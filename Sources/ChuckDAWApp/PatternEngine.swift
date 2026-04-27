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

        project.tracks = project.tracks.map { track in
            var track = track
            track.tempoRatio = clamp(track.tempoRatio, 0.125, 8.0)
            track.timeSignatureTop = clamp(track.timeSignatureTop, 1, 15)
            track.timeSignatureBottom = snapDenominator(track.timeSignatureBottom)
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
            .reduce(0) { $0 + $1.clips.count }
        return ProjectStats(activeTracks: activeTracks, activeClips: activeClips)
    }

    static func buildChuckProgram(project: Project, projectRoot: String, startStep: Int = 0) -> String {
        let project = normalize(project)
        let cycleStartStep = (project.master.cycleStartBar - 1) * 16
        let cycleEndStepExclusive = project.master.cycleEndBar * 16
        let normalizedStartStep = min(cycleEndStepExclusive - 1, max(cycleStartStep, startStep))
        let globals = """
        Gain master => dac;
        \(format(project.master.gain)) => master.gain;
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

        let enabledTracks = playbackTracks(for: project)
        let allClips = enabledTracks.flatMap { track in
            track.clips.map { (track: track, clip: $0) }
        }

        let clipFunctions = allClips.enumerated().map { index, item in
            buildClipCode(trackName: item.track.name, clip: item.clip, track: item.track, index: index)
        }.joined(separator: "\n\n")

        let scheduleCases = allClips.enumerated().map { index, item in
            """
                    if (currentStep == \(item.clip.startStep))
                    {
                        spork ~ region_\(index)(); // \(item.track.name) / \(item.clip.name)
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

    private static func buildClipCode(trackName: String, clip: ClipRegion, track: Track, index: Int) -> String {
        """
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
        \(indent(clip.code.trimmingCharacters(in: .whitespacesAndNewlines), spaces: 4))
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
