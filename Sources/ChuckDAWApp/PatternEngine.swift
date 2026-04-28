import Foundation

struct ProjectStats {
    let activeTracks: Int
    let activeClips: Int
}

enum TimelineCompiler {
    static func normalize(_ project: Project) -> Project {
        var project = project
        project.master.bpm = clamp(project.master.bpm, 40, 240)
        project.master.gain = clamp(project.master.gain, 0.05, 1.25)
        project.master.loopBars = max(1, project.master.loopBars)
        project.master.cycleStartBar = clamp(project.master.cycleStartBar, 1, project.master.loopBars)
        project.master.cycleEndBar = clamp(project.master.cycleEndBar, project.master.cycleStartBar, project.master.loopBars)
        if project.buses.isEmpty {
            project.buses = Project.defaultBuses()
        }
        project.buses = project.buses.map { bus in
            var bus = bus
            bus.gain = clamp(bus.gain, 0.0, 1.5)
            bus.pan = clamp(bus.pan, -1.0, 1.0)
            bus.deviceSlots = bus.deviceSlots.map { slot in
                var slot = slot
                if slot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    slot.name = URL(fileURLWithPath: slot.filePath).deletingPathExtension().lastPathComponent
                }
                return slot
            }
            if bus.effectCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                bus.effectCode = "busIn => busOut;"
            }
            return bus
        }
        let validBusIDs = Set(project.buses.map(\.id))

        project.tracks = project.tracks.map { track in
            var track = track
            track.gain = clamp(track.gain, 0.0, 1.5)
            track.pan = clamp(track.pan, -1.0, 1.0)
            track.deviceSlots = track.deviceSlots.map { slot in
                var slot = slot
                if slot.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    slot.name = URL(fileURLWithPath: slot.filePath).deletingPathExtension().lastPathComponent
                }
                return slot
            }
            if track.effectCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                track.effectCode = "trackIn => trackOut;"
            }
            if let outputBusID = track.outputBusID, !validBusIDs.contains(outputBusID) {
                track.outputBusID = nil
            }
            track.sends = track.sends
                .filter { validBusIDs.contains($0.busID) }
                .map { send in
                    var send = send
                    send.level = clamp(send.level, 0.0, 1.5)
                    return send
                }
            track.tempoRatio = clamp(track.tempoRatio, 0.125, 8.0)
            track.timeSignatureTop = clamp(track.timeSignatureTop, 1, 15)
            track.timeSignatureBottom = snapDenominator(track.timeSignatureBottom)
            if let renderedAudio = track.renderedAudio,
               !FileManager.default.fileExists(atPath: renderedAudio.filePath) {
                track.renderedAudio = nil
                track.useRenderedAudio = false
            }
            track.clips = track.clips
                .map { clip in
                    var clip = clip
                    clip.startStep = max(0, clip.startStep)
                    clip.lengthSteps = max(1, clip.lengthSteps)
                    if clip.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        clip.code = "regionDur => now;"
                    }
                    clip.code = migrateDurationSyntax(in: clip.code)
                    clip.code = migrateLegacyClipBodies(in: clip.code)
                    return clip
                }
                .sorted { lhs, rhs in
                    if lhs.startStep == rhs.startStep {
                        return lhs.name < rhs.name
                    }
                    return lhs.startStep < rhs.startStep
                }
            return track
        }
        return project
    }

    static func stats(for project: Project) -> ProjectStats {
        let audibleTracks = playbackTracks(for: project)
        let activeTracks = audibleTracks.count
        let activeClips = audibleTracks
            .reduce(0) { partial, track in
                if track.useRenderedAudio && track.renderedAudio != nil {
                    return partial + 1
                }
                return partial + track.clips.count
            }
        return ProjectStats(activeTracks: activeTracks, activeClips: activeClips)
    }

    static func buildChuckProgram(project: Project, projectRoot: String, startStep: Int = 0) -> String {
        let project = normalize(project)
        let cycleStartStep = (project.master.cycleStartBar - 1) * 16
        let cycleEndStepExclusive = project.master.cycleEndBar * 16
        let normalizedStartStep = min(cycleEndStepExclusive - 1, max(cycleStartStep, startStep))
        let enabledTracks = playbackTracks(for: project)
        let busIndexByID = Dictionary(uniqueKeysWithValues: project.buses.enumerated().map { ($0.element.id, $0.offset) })
        let mixStateDeclarations = enabledTracks.enumerated().map { index, _ in
            """
                static float trackGain_\(index);
                static float trackPan_\(index);
            """
        }.joined(separator: "\n")
        let sendMixStateDeclarations = enabledTracks.enumerated().flatMap { trackIndex, _ in
            project.buses.enumerated().map { busIndex, _ in
                "    static float trackSend_\(trackIndex)_\(busIndex);"
            }
        }.joined(separator: "\n")
        let busMixStateDeclarations = project.buses.enumerated().map { index, _ in
            """
                static float busGain_\(index);
                static float busPan_\(index);
            """
        }.joined(separator: "\n")
        let mixStateInitializers = enabledTracks.enumerated().map { index, track in
            let sendMap = Dictionary(uniqueKeysWithValues: track.sends.map { ($0.busID, $0.level) })
            let sendLines = project.buses.enumerated().map { busIndex, bus in
                "\(format(sendMap[bus.id] ?? 0.0)) => ChuckDAWMix.trackSend_\(index)_\(busIndex);"
            }.joined(separator: "\n")
            return """
            \(format(track.gain)) => ChuckDAWMix.trackGain_\(index);
            \(format(track.pan)) => ChuckDAWMix.trackPan_\(index);
            \(sendLines)
            """
        }.joined(separator: "\n")
        let busMixStateInitializers = project.buses.enumerated().map { index, bus in
            """
            \(format(bus.gain)) => ChuckDAWMix.busGain_\(index);
            \(format(bus.pan)) => ChuckDAWMix.busPan_\(index);
            """
        }.joined(separator: "\n")
        let auxBusConfig = project.buses.enumerated().map { index, bus in
            let effectCode = bus.effectCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let slotChain = buildDeviceSlotChain(slotPrefix: "bus_\(index)", slots: bus.deviceSlots, sourceNode: "busSource_\(index)", destinationNode: "busPreFX_\(index)")
            let lines = [
                "Gain busSource_\(index);",
                "Gain busPreFX_\(index);",
                "Gain busProcessed_\(index);",
                slotChain,
                "fun void initBusFX_\(index)()",
                "{",
                "    Gain busIn;",
                "    Gain busOut;",
                "    busPreFX_\(index) => busIn;",
                indent(effectCode, spaces: 4),
                "    busOut => busProcessed_\(index);",
                "}",
                "initBusFX_\(index)();",
                "Gain busProcessed_\(index) => Gain busTrim_\(index) => Pan2 busPan_\(index) => master;",
                "1.0 => busSource_\(index).gain;",
                "\(format(bus.gain)) => busTrim_\(index).gain;",
                "\(format(bus.pan)) => busPan_\(index).pan;"
            ]
            return lines.joined(separator: "\n")
        }.joined(separator: "\n")
        let trackBusConfig = enabledTracks.enumerated().map { index, track in
            let destinationBus = track.outputBusID.flatMap { busIndexByID[$0] }.map { "busSource_\($0)" } ?? "master"
            let sendConfig = project.buses.enumerated().map { busIndex, _ in
                "trackTrim_\(index) => Gain trackSendGain_\(index)_\(busIndex) => busSource_\(busIndex);"
            }.joined(separator: "\n")
            let insertCode = track.effectCode.trimmingCharacters(in: .whitespacesAndNewlines)
            let slotChain = buildDeviceSlotChain(slotPrefix: "track_\(index)", slots: track.deviceSlots, sourceNode: "trackInput_\(index)", destinationNode: "trackPreFX_\(index)")
            let trackInsertLines = [
                "Gain trackInput_\(index);",
                "Gain trackPreFX_\(index);",
                "Gain trackProcessed_\(index);",
                slotChain,
                "fun void initTrackInsert_\(index)()",
                "{",
                "    Gain trackIn;",
                "    Gain trackOut;",
                "    trackPreFX_\(index) => trackIn;",
                indent(insertCode, spaces: 4),
                "    trackOut => trackProcessed_\(index);",
                "}",
                "initTrackInsert_\(index)();",
                "Gain trackProcessed_\(index) => Gain trackTrim_\(index) => Pan2 trackPan_\(index) => \(destinationBus);",
                "1.0 => trackInput_\(index).gain;",
                "\(format(track.gain)) => trackTrim_\(index).gain;",
                "\(format(track.pan)) => trackPan_\(index).pan;",
                sendConfig
            ]
            return """
            \(trackInsertLines.joined(separator: "\n"))
            """
        }.joined(separator: "\n")
        let trackBusControllers = enabledTracks.enumerated().map { index, _ in
            let sendControlLines = project.buses.enumerated().map { busIndex, _ in
                "        ChuckDAWMix.trackSend_\(index)_\(busIndex) => trackSendGain_\(index)_\(busIndex).gain;"
            }.joined(separator: "\n")
            return """
            fun void trackBusControl_\(index)()
            {
                while (true)
                {
                    ChuckDAWMix.trackGain_\(index) => trackTrim_\(index).gain;
                    ChuckDAWMix.trackPan_\(index) => trackPan_\(index).pan;
            \(sendControlLines)
                    10::ms => now;
                }
            }
            spork ~ trackBusControl_\(index)();
            """
        }.joined(separator: "\n")
        let busControllers = project.buses.enumerated().map { index, _ in
            """
            fun void auxBusControl_\(index)()
            {
                while (true)
                {
                    ChuckDAWMix.busGain_\(index) => busTrim_\(index).gain;
                    ChuckDAWMix.busPan_\(index) => busPan_\(index).pan;
                    10::ms => now;
                }
            }
            spork ~ auxBusControl_\(index)();
            """
        }.joined(separator: "\n")
        let globals = """
        Gain master => dac;
        \(format(project.master.gain)) => master.gain;
        public class ChuckDAWMix
        {
            static float masterGain;
        \(mixStateDeclarations)
        \(sendMixStateDeclarations)
        \(busMixStateDeclarations)
        }
        \(format(project.master.gain)) => ChuckDAWMix.masterGain;
        \(mixStateInitializers)
        \(busMixStateInitializers)
        \(auxBusConfig)
        \(trackBusConfig)
        fun void masterBusControl()
        {
            while (true)
            {
                ChuckDAWMix.masterGain => master.gain;
                10::ms => now;
            }
        }
        spork ~ masterBusControl();
        \(trackBusControllers)
        \(busControllers)
        \(format(project.master.bpm)) => float BPM;
        \(project.master.loopBars) => int LOOP_BARS;
        \(project.master.cycleStartBar) => int CYCLE_START;
        \(project.master.cycleEndBar) => int CYCLE_END;
        \(cycleStartStep) => int CYCLE_START_STEP;
        \(cycleEndStepExclusive) => int CYCLE_END_STEP_EXCLUSIVE;
        \(normalizedStartStep) => int START_STEP;
        "\(escapeString(projectRoot))" => string PROJECT_ROOT;
        (60.0 / BPM)::second => dur beat;
        beat / 4 => dur sixteenth;
        beat * 4 => dur bar;
        (CYCLE_END - CYCLE_START + 1) * bar => dur loopDur;

        fun void releaseVoice(ADSR env, dur wait)
        {
            wait => now;
            env.keyOff();
        }
        """

        let scheduleItems = enabledTracks.enumerated().flatMap { index, track in
            buildScheduleItems(for: track, busIndex: index)
        }

        let clipFunctions = scheduleItems.enumerated().map { index, item in
            switch item.kind {
            case .clip(let clip):
                return buildClipCode(trackName: item.track.name, clip: clip, track: item.track, index: index, outputBus: "trackInput_\(item.busIndex)")
            case .rendered(let renderedAudio):
                return buildRenderedPlaybackCode(trackName: item.track.name, renderedAudio: renderedAudio, index: index, outputBus: "trackInput_\(item.busIndex)")
            }
        }.joined(separator: "\n\n")

        let scheduleCases = scheduleItems.enumerated().map { index, item in
            """
                    if (currentStep == \(item.startStep))
                    {
                        spork ~ region_\(index)(); // \(item.track.name) / \(item.name)
                    }
            """
        }.joined(separator: "\n")

        return """
        \(globals)

        \(project.prelude.trimmingCharacters(in: .whitespacesAndNewlines))

        \(clipFunctions)

        while (true)
        {
            START_STEP => int currentStep;
            while (currentStep < CYCLE_END_STEP_EXCLUSIVE)
            {
        \(scheduleCases)
                sixteenth => now;
                currentStep++;
            }
            CYCLE_START_STEP => START_STEP;
        }
        """
    }

    private struct ScheduleItem {
        enum Kind {
            case clip(ClipRegion)
            case rendered(RenderedTrackAudio)
        }

        let track: Track
        let busIndex: Int
        let name: String
        let startStep: Int
        let kind: Kind
    }

    private static func buildScheduleItems(for track: Track, busIndex: Int) -> [ScheduleItem] {
        if track.useRenderedAudio, let renderedAudio = track.renderedAudio {
            return [
                ScheduleItem(
                    track: track,
                    busIndex: busIndex,
                    name: "\(track.name) Print",
                    startStep: renderedAudio.startStep,
                    kind: .rendered(renderedAudio)
                )
            ]
        }

        return track.clips.map { clip in
            ScheduleItem(track: track, busIndex: busIndex, name: clip.name, startStep: clip.startStep, kind: .clip(clip))
        }
    }

    static func buildClipRuntimeScript(project: Project, trackName: String, clip: ClipRegion, projectRoot: String) -> String {
        let project = normalize(project)
        return """
        \(format(project.master.bpm)) => float BPM;
        \(format(project.master.gain)) => float MASTER_GAIN;
        "\(escapeString(projectRoot))" => string PROJECT_ROOT;
        (60.0 / BPM)::second => dur beat;
        beat / 4 => dur sixteenth;
        beat * 4 => dur bar;

        fun void releaseVoice(ADSR env, dur wait)
        {
            wait => now;
            env.keyOff();
        }

        \(project.prelude.trimmingCharacters(in: .whitespacesAndNewlines))

        \(clip.lengthSteps) * sixteenth => dur regionDur;
        now + regionDur => time regionEnd;
        <<< "clip.start", "\(escapeString(trackName))", "\(escapeString(clip.name))" >>>;
        \(clip.code.trimmingCharacters(in: .whitespacesAndNewlines))
        """
    }

    static func buildTrackRenderProgram(project: Project, trackID: UUID, outputPath: String, projectRoot: String) -> String? {
        let project = normalize(project)
        guard let track = project.tracks.first(where: { $0.id == trackID }) else { return nil }

        let cycleStartStep = (project.master.cycleStartBar - 1) * 16
        let cycleEndStepExclusive = project.master.cycleEndBar * 16
        let trackInsertCode = track.effectCode.trimmingCharacters(in: .whitespacesAndNewlines)
        let slotChain = buildDeviceSlotChain(slotPrefix: "render_track", slots: track.deviceSlots, sourceNode: "renderTrackInput", destinationNode: "renderTrackPreFX")
        let globals = """
        Gain renderTrackInput;
        Gain renderTrackPreFX;
        Gain renderTrackProcessed;
        \(slotChain)
        fun void initRenderTrackInsert()
        {
            Gain trackIn;
            Gain trackOut;
            renderTrackPreFX => trackIn;
        \(indent(trackInsertCode, spaces: 8))
            trackOut => renderTrackProcessed;
        }
        initRenderTrackInsert();
        Gain renderTrackProcessed => Gain renderTrackGain => Pan2 renderPan => dac;
        dac => Gain renderTap => WvOut2 recorder => blackhole;
        "\(escapeString(outputPath))" => recorder.wavFilename;
        1.0 => renderTrackInput.gain;
        1.0 => renderTrackGain.gain;
        0.0 => renderPan.pan;
        \(format(project.master.bpm)) => float BPM;
        \(project.master.loopBars) => int LOOP_BARS;
        \(project.master.cycleStartBar) => int CYCLE_START;
        \(project.master.cycleEndBar) => int CYCLE_END;
        \(cycleStartStep) => int CYCLE_START_STEP;
        \(cycleEndStepExclusive) => int CYCLE_END_STEP_EXCLUSIVE;
        "\(escapeString(projectRoot))" => string PROJECT_ROOT;
        (60.0 / BPM)::second => dur beat;
        beat / 4 => dur sixteenth;
        beat * 4 => dur bar;

        fun void releaseVoice(ADSR env, dur wait)
        {
            wait => now;
            env.keyOff();
        }
        """

        let clipFunctions = track.clips.enumerated().map { index, clip in
            buildRenderClipCode(trackName: track.name, clip: clip, track: track, index: index)
        }.joined(separator: "\n\n")

        let scheduleCases = track.clips.enumerated().map { index, clip in
            """
                    if (currentStep == \(clip.startStep))
                    {
                        spork ~ region_\(index)(); // \(track.name) / \(clip.name)
                    }
            """
        }.joined(separator: "\n")

        return """
        \(globals)

        \(project.prelude.trimmingCharacters(in: .whitespacesAndNewlines))

        \(clipFunctions)

        CYCLE_START_STEP => int currentStep;
        while (currentStep < CYCLE_END_STEP_EXCLUSIVE)
        {
        \(scheduleCases)
            sixteenth => now;
            currentStep++;
        }

        bar => now;
        recorder.closeFile();
        me.exit();
        """
    }

    static func buildMixerStateUpdateProgram(project: Project) -> String {
        let project = normalize(project)
        let enabledTracks = playbackTracks(for: project)
        let assignments = enabledTracks.enumerated().map { index, track in
            let sendMap = Dictionary(uniqueKeysWithValues: track.sends.map { ($0.busID, $0.level) })
            let sendAssignments = project.buses.enumerated().map { busIndex, bus in
                "\(format(sendMap[bus.id] ?? 0.0)) => ChuckDAWMix.trackSend_\(index)_\(busIndex);"
            }.joined(separator: "\n")
            return """
            \(format(track.gain)) => ChuckDAWMix.trackGain_\(index);
            \(format(track.pan)) => ChuckDAWMix.trackPan_\(index);
            \(sendAssignments)
            """
        }.joined(separator: "\n")
        let busAssignments = project.buses.enumerated().map { index, bus in
            """
            \(format(bus.gain)) => ChuckDAWMix.busGain_\(index);
            \(format(bus.pan)) => ChuckDAWMix.busPan_\(index);
            """
        }.joined(separator: "\n")

        return """
        \(format(project.master.gain)) => ChuckDAWMix.masterGain;
        \(assignments)
        \(busAssignments)
        me.exit();
        """
    }

    private static func buildClipCode(trackName: String, clip: ClipRegion, track: Track, index: Int, outputBus: String) -> String {
        let routedCode = rerouteClipOutput(clip.code.trimmingCharacters(in: .whitespacesAndNewlines), busName: outputBus)
        return """
        // \(trackName) :: \(clip.name)
        fun void region_\(index)()
        {
            beat => dur masterBeat;
            bar => dur masterBar;
            sixteenth => dur masterSixteenth;
            \(format(track.tempoRatio)) => float trackTempoRatio;
            \(track.timeSignatureTop) => int trackBeatsPerBar;
            \(track.timeSignatureBottom) => int trackBeatUnit;
            (masterBeat * (4.0 / trackBeatUnit)) / trackTempoRatio => dur beat;
            beat * trackBeatsPerBar => dur bar;
            beat / 4 => dur sixteenth;
            \(clip.lengthSteps) * masterSixteenth => dur regionDur;
            now + regionDur => time regionEnd;
        \(indent(routedCode, spaces: 4))
        }
        """
    }

    private static func buildRenderClipCode(trackName: String, clip: ClipRegion, track: Track, index: Int) -> String {
        let routedCode = rerouteClipCodeForRender(clip.code.trimmingCharacters(in: .whitespacesAndNewlines))
        return """
        // \(trackName) :: \(clip.name)
        fun void region_\(index)()
        {
            beat => dur masterBeat;
            bar => dur masterBar;
            sixteenth => dur masterSixteenth;
            \(format(track.tempoRatio)) => float trackTempoRatio;
            \(track.timeSignatureTop) => int trackBeatsPerBar;
            \(track.timeSignatureBottom) => int trackBeatUnit;
            (masterBeat * (4.0 / trackBeatUnit)) / trackTempoRatio => dur beat;
            beat * trackBeatsPerBar => dur bar;
            beat / 4 => dur sixteenth;
            \(clip.lengthSteps) * masterSixteenth => dur regionDur;
            now + regionDur => time regionEnd;
        \(indent(routedCode, spaces: 4))
        }
        """
    }

    private static func buildRenderedPlaybackCode(trackName: String, renderedAudio: RenderedTrackAudio, index: Int, outputBus: String) -> String {
        """
        // \(trackName) :: rendered audio
        fun void region_\(index)()
        {
            SndBuf2 buf => Gain clipGain => \(outputBus);
            "\(escapeString(renderedAudio.filePath))" => buf.read;
            1.0 => clipGain.gain;
            0 => buf.pos;
            0 => buf.loop;
            \(renderedAudio.lengthSteps) * sixteenth => dur regionDur;
            regionDur => now;
        }
        """
    }

    private static func clamp<T: Comparable>(_ value: T, _ minimum: T, _ maximum: T) -> T {
        min(maximum, max(minimum, value))
    }

    private static func snapDenominator(_ value: Int) -> Int {
        let allowed = [1, 2, 4, 8, 16]
        return allowed.min(by: { abs($0 - value) < abs($1 - value) }) ?? 4
    }

    private static func playbackTracks(for project: Project) -> [Track] {
        let enabledTracks = project.tracks.filter(\.enabled)
        let soloTracks = enabledTracks.filter(\.solo)
        return soloTracks.isEmpty ? enabledTracks : soloTracks
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    private static func indent(_ text: String, spaces: Int) -> String {
        let padding = String(repeating: " ", count: spaces)
        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { padding + $0 }
            .joined(separator: "\n")
    }

    private static func escapeString(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func rerouteClipOutput(_ text: String, busName: String) -> String {
        text.replacingOccurrences(
            of: #"=>\s*dac"#,
            with: "=> \(busName)",
            options: .regularExpression
        )
    }

    private static func rerouteClipCodeForRender(_ text: String) -> String {
        rerouteClipOutput(text, busName: "renderTrackInput")
    }

    private static func buildDeviceSlotChain(slotPrefix: String, slots: [DeviceSlot], sourceNode: String, destinationNode: String) -> String {
        let activeSlots = slots.filter(\.isEnabled)
        guard !activeSlots.isEmpty else {
            return "\(sourceNode) => \(destinationNode);"
        }

        var lines: [String] = []
        var currentSource = sourceNode

        for (index, slot) in activeSlots.enumerated() {
            let deviceCode = loadDeviceSlotCode(from: slot.filePath)
            let slotIn = "\(slotPrefix)_slotIn_\(index)"
            let slotOut = "\(slotPrefix)_slotOut_\(index)"
            let initName = "init_\(slotPrefix)_slot_\(index)"
            lines.append("Gain \(slotIn);")
            lines.append("Gain \(slotOut);")
            lines.append("fun void \(initName)()")
            lines.append("{")
            lines.append("    Gain deviceIn;")
            lines.append("    Gain deviceOut;")
            lines.append("    \(slotIn) => deviceIn;")
            lines.append(indent(deviceCode, spaces: 4))
            lines.append("    deviceOut => \(slotOut);")
            lines.append("}")
            lines.append("\(currentSource) => \(slotIn);")
            lines.append("\(initName)();")
            currentSource = slotOut
        }

        lines.append("\(currentSource) => \(destinationNode);")
        return lines.joined(separator: "\n")
    }

    private static func loadDeviceSlotCode(from filePath: String) -> String {
        guard let text = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return "deviceIn => deviceOut;"
        }

        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return "deviceIn => deviceOut;"
        }

        return rerouteClipOutput(normalized, busName: "deviceOut")
    }

    private static func migrateDurationSyntax(in text: String) -> String {
        text
            .replacingOccurrences(of: "0.25::beat", with: "0.25 * beat")
            .replacingOccurrences(of: "0.45::beat", with: "0.45 * beat")
            .replacingOccurrences(of: "0.5::beat", with: "0.5 * beat")
            .replacingOccurrences(of: "0.55::beat", with: "0.55 * beat")
            .replacingOccurrences(of: "0.8::beat", with: "0.8 * beat")
            .replacingOccurrences(of: "1::beat", with: "1 * beat")
            .replacingOccurrences(of: "1.5::beat", with: "1.5 * beat")
    }

    private static func migrateLegacyClipBodies(in text: String) -> String {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let legacyChordSlice = """
        [60, 65, 69] @=> int chord[];
        for (0 => int i; i < chord.cap(); i++)
        {
            SawOsc s => ADSR e => dac;
            Std.mtof(chord[i]) => s.freq;
            0.07 => s.gain;
            e.set(10::ms, 100::ms, 0.0, 200::ms);
            e.keyOn();
            spork ~ releaseVoice(e, 0.8 * beat);
        }
        regionDur => now;
        """

        let brokenNestedChordSlice = """
        fun void chordVoice(int midi, dur hold)
        {
            SawOsc s => ADSR e => dac;
            Std.mtof(midi) => s.freq;
            0.07 => s.gain;
            e.set(10::ms, 100::ms, 0.0, 200::ms);
            e.keyOn();
            hold => now;
            e.keyOff();
            200::ms => now;
        }
        
        [60, 65, 69] @=> int chord[];
        for (0 => int i; i < chord.cap(); i++)
        {
            spork ~ chordVoice(chord[i], 0.8 * beat);
        }
        regionDur => now;
        """

        let migratedText = text.replacingOccurrences(
            of: "me.dir() + \"/Vendor/chuck/examples/data/",
            with: "PROJECT_ROOT + \"/Vendor/chuck/examples/data/"
        )

        if normalized == legacyChordSlice.trimmingCharacters(in: .whitespacesAndNewlines)
            || normalized == brokenNestedChordSlice.trimmingCharacters(in: .whitespacesAndNewlines) {
            return ClipTemplates.chordSlice
        }

        return migratedText
    }
}
