import AppKit
import SwiftUI

private enum EditorPanel: String, CaseIterable, Identifiable {
    case clip = "Clip"
    case prelude = "Prelude"
    case score = "Score"
    case log = "Log"

    var id: String { rawValue }
}

struct ContentView: View {
    private let laneLabelWidth: CGFloat = 188
    private let baseBarWidth: CGFloat = 88
    private let barGap: CGFloat = 6
    private let laneHeight: CGFloat = 64

    @StateObject private var model = AppViewModel()
    @State private var editorPanel: EditorPanel = .clip
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            HSplitView {
                trackListPane
                    .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
                timelinePane
                    .frame(minWidth: 700)
                editorPane
                    .frame(minWidth: 380, idealWidth: 430)
            }
        }
        .frame(minWidth: 1320, minHeight: 780)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.82)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var topBar: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                transportBadge
                transportControls
                cycleDesk
                timelineDesk
                snapDesk
                projectDesk
                Spacer(minLength: 0)
                sessionStatusDesk
            }

            HStack(spacing: 8) {
                TextField("Project", text: model.projectBinding(\.name))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)

                TextField("ChucK Path", text: model.chuckPathBinding())
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        model.refreshEngineStatus()
                    }

                Button("Detect") {
                    model.autoDetectBinary()
                }
                .buttonStyle(.bordered)

                Button("Test Audio") {
                    model.testEngine()
                }
                .buttonStyle(.bordered)

                Picker("Preset", selection: $model.selectedPreset) {
                    ForEach(PresetLibrary.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                Button("Load") {
                    model.loadPreset()
                }
                .buttonStyle(.bordered)

                Button("Reset") {
                    model.resetProject()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor).opacity(0.9),
                    Color(nsColor: .underPageBackgroundColor).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var trackListPane: some View {
        VStack(spacing: 0) {
            paneHeader("Tracks") {
                HStack(spacing: 8) {
                    Button("+ Track") { model.addTrack() }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("n", modifiers: [.command])
                    Button("- Track") { model.removeSelectedTrack() }
                        .buttonStyle(.borderless)
                        .disabled(model.selectedTrackID == nil)
                        .keyboardShortcut(.delete, modifiers: [.command])
                }
                .font(.system(size: 11, weight: .semibold))
            }

            List {
                ForEach(model.project.tracks) { track in
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            model.selectTrack(track.id)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(trackIsAudible(track) ? Color.accentColor : .gray.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                Text(track.name)
                                    .fontWeight(track.id == model.selectedTrackID ? .semibold : .regular)
                                Spacer()
                                if track.solo {
                                    Text("S")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.yellow)
                                }
                                if !track.enabled {
                                    Text("M")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundStyle(.red)
                                }
                                Text("\(track.clips.count)")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)

                        ForEach(track.clips) { clip in
                            Button {
                                model.selectClip(trackID: track.id, clipID: clip.id)
                            } label: {
                                HStack(spacing: 6) {
                                    Rectangle()
                                        .fill(model.selectedClipIDs.contains(clip.id) ? Color.accentColor : Color.secondary.opacity(0.25))
                                        .frame(width: 3, height: 14)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(clip.name)
                                            .lineLimit(1)
                                        Text("\(formattedClipStart(clip)) · \(formattedClipLength(clip))")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 16)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.sidebar)
        }
    }

    private var timelinePane: some View {
        VStack(spacing: 0) {
            paneHeader("Arrangement") {
                HStack(spacing: 8) {
                    if model.selectedTrackID != nil {
                        Button("+ Clip") { model.addClip() }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("n", modifiers: [.command, .option])
                        Button("- Clip") { model.removeSelectedClip() }
                            .buttonStyle(.borderless)
                            .disabled(model.selectedClipID == nil)
                            .keyboardShortcut(.delete, modifiers: [.option])
                        Button("←") { model.nudgeSelectedClips(bySteps: -model.snapMode.unitSteps) }
                            .buttonStyle(.borderless)
                            .disabled(model.selectedClipIDs.isEmpty)
                            .keyboardShortcut(.leftArrow, modifiers: [.option])
                        Button("→") { model.nudgeSelectedClips(bySteps: model.snapMode.unitSteps) }
                            .buttonStyle(.borderless)
                            .disabled(model.selectedClipIDs.isEmpty)
                            .keyboardShortcut(.rightArrow, modifiers: [.option])
                        Button("↑") { model.moveSelectedClipsBetweenTracks(-1) }
                            .buttonStyle(.borderless)
                            .disabled(model.selectedClipIDs.isEmpty)
                            .keyboardShortcut(.upArrow, modifiers: [.option])
                        Button("↓") { model.moveSelectedClipsBetweenTracks(1) }
                            .buttonStyle(.borderless)
                            .disabled(model.selectedClipIDs.isEmpty)
                            .keyboardShortcut(.downArrow, modifiers: [.option])
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }

            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(model.project.tracks) { track in
                                trackLane(track)
                            }
                        } header: {
                            timelinePinnedHeader
                        }
                    }
                    .padding(12)
                    .overlay(alignment: .topLeading) {
                        if let marqueeRect {
                            Rectangle()
                                .fill(Color.accentColor.opacity(0.12))
                                .overlay(
                                    Rectangle()
                                        .stroke(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                )
                                .frame(width: marqueeRect.width, height: marqueeRect.height)
                                .offset(x: marqueeRect.minX, y: marqueeRect.minY)
                        }
                    }
                }
                .background(
                    LinearGradient(
                        colors: [
                            Color(nsColor: .textBackgroundColor).opacity(0.42),
                            Color(nsColor: .controlBackgroundColor).opacity(0.58)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .onAppear {
                    scrollToVisibleBar(using: proxy, animated: false)
                }
                .onChange(of: currentBarAnchor) { _, _ in
                    scrollToVisibleBar(using: proxy, animated: model.isPlaying)
                }
                .onChange(of: model.project.master.loopBars) { _, _ in
                    scrollToVisibleBar(using: proxy, animated: false)
                }
                .onChange(of: model.timelineZoom) { _, _ in
                    scrollToVisibleBar(using: proxy, animated: false)
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 10)
                        .onChanged { value in
                            if NSEvent.modifierFlags.contains(.command) {
                                if marqueeStart == nil {
                                    marqueeStart = value.startLocation
                                }
                                marqueeCurrent = value.location
                            }
                        }
                        .onEnded { _ in
                            if marqueeStart != nil {
                                applyMarqueeSelection()
                            }
                            marqueeStart = nil
                            marqueeCurrent = nil
                        }
                )
            }
        }
    }

    private var timelinePinnedHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            scrubStrip
                .padding(.bottom, 8)
            overviewStrip
                .padding(.bottom, 8)
            barRuler
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor).opacity(0.96),
                    Color(nsColor: .controlBackgroundColor).opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var editorPane: some View {
        VStack(spacing: 0) {
            paneHeader("Editor") {
                Picker("", selection: $editorPanel) {
                    ForEach(EditorPanel.allCases) { panel in
                        Text(panel.rawValue).tag(panel)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            VStack(alignment: .leading, spacing: 8) {
                if editorPanel == .clip {
                    clipInspector
                } else if editorPanel == .prelude {
                    editorBlock(title: "Session Prelude", text: model.projectBinding(\.prelude))
                } else if editorPanel == .score {
                    editorBlock(title: "Compiled Score", text: .constant(model.compiledCode), editable: false)
                } else {
                    logView
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var clipInspector: some View {
        Group {
            if model.selectedTrackIndex != nil, model.selectedClipIndex != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Clip Name", text: model.selectedClipBinding(\.name, fallback: ""))
                            .textFieldStyle(.roundedBorder)
                        compactIntField("Start 16th", value: model.selectedClipBinding(\.startStep, fallback: 0), width: 72)
                        compactIntField("Len 16th", value: model.selectedClipBinding(\.lengthSteps, fallback: 1), width: 72)
                    }

                    HStack(spacing: 8) {
                        TextField("Track Name", text: model.selectedTrackBinding(\.name, fallback: ""))
                            .textFieldStyle(.roundedBorder)
                        Toggle("On", isOn: model.selectedTrackBinding(\.enabled, fallback: true))
                            .toggleStyle(.checkbox)
                    }

                    selectedTrackTimingStrip

                    editorBlock(title: "Clip Code", text: model.selectedClipBinding(\.code, fallback: ""))
                }
            } else if model.selectedTrackIndex != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("Track Name", text: model.selectedTrackBinding(\.name, fallback: ""))
                            .textFieldStyle(.roundedBorder)
                        Toggle("On", isOn: model.selectedTrackBinding(\.enabled, fallback: true))
                            .toggleStyle(.checkbox)
                        Toggle("Solo", isOn: model.selectedTrackBinding(\.solo, fallback: false))
                            .toggleStyle(.checkbox)
                    }

                    selectedTrackTimingStrip

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Track")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Select a clip to edit its ChucK region. Tempo ratio and meter apply to every clip on this track.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }
            } else {
                ContentUnavailableView("No Track Selected", systemImage: "timeline.selection")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedTrackTimingStrip: some View {
        HStack(spacing: 8) {
            compactNumberField("Tempo x", value: model.selectedTrackBinding(\.tempoRatio, fallback: 1.0), width: 76, precision: 3)
            compactIntField("Beats", value: model.selectedTrackBinding(\.timeSignatureTop, fallback: 4), width: 58)
            compactTimeSignatureBottomPicker(
                title: "Unit",
                value: model.selectedTrackBinding(\.timeSignatureBottom, fallback: 4),
                width: 72
            )
            Spacer(minLength: 0)
            if let track = selectedTrack {
                Text("Local pulse: \(formattedTempoRatio(track.tempoRatio)) · \(track.timeSignatureTop)/\(track.timeSignatureBottom)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var barRuler: some View {
        HStack(spacing: 6) {
            Text("")
                .frame(width: laneLabelWidth)
            ZStack(alignment: .topLeading) {
                HStack(spacing: barGap) {
                    ForEach(1...model.project.master.loopBars, id: \.self) { bar in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(bar)")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(bar == currentBarAnchor ? .primary : .secondary)
                            Rectangle()
                                .fill(rulerBarFill(bar))
                                .frame(height: 2)
                        }
                        .frame(width: barWidth, alignment: .leading)
                        .id(barID(bar))
                    }
                }

                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: cycleOverlayWidth, height: 22)
                    .offset(x: cycleOverlayX, y: -1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let span = model.project.master.cycleEndBar - model.project.master.cycleStartBar
                                let proposedStart = rulerBarIndex(for: cycleOverlayX + value.translation.width)
                                let clampedStart = min(
                                    max(1, proposedStart),
                                    max(1, model.project.master.loopBars - span)
                                )
                                model.setCycleRange(start: clampedStart, end: clampedStart + span)
                            }
                    )

                cycleHandle
                    .frame(height: 22)
                    .offset(x: cycleOverlayX, y: -1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let bar = rulerBarIndex(for: cycleOverlayX + value.translation.width)
                                model.setCycleRange(start: min(bar, model.project.master.cycleEndBar))
                            }
                    )

                cycleHandle
                    .frame(height: 22)
                    .offset(x: cycleOverlayX + cycleOverlayWidth - cycleHandleWidth, y: -1)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let bar = rulerBarIndex(for: cycleOverlayX + cycleOverlayWidth + value.translation.width)
                                model.setCycleRange(end: max(bar, model.project.master.cycleStartBar))
                            }
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        model.setTransportBarPosition(snappedTransportPosition(barPosition(for: value.location.x)))
                    }
            )
        }
    }

    private var overviewStrip: some View {
        HStack(spacing: 6) {
            Text("Overview")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: laneLabelWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.secondary.opacity(0.08))

                    overviewBarGrid(width: geometry.size.width)

                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(
                            width: overviewCycleWidth(width: geometry.size.width),
                            height: 30
                        )
                        .offset(x: overviewCycleX(width: geometry.size.width), y: 3)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let span = model.project.master.cycleEndBar - model.project.master.cycleStartBar
                                    let proposedStart = overviewBarIndex(
                                        for: overviewCycleX(width: geometry.size.width) + value.translation.width,
                                        width: geometry.size.width
                                    )
                                    let clampedStart = min(
                                        max(1, proposedStart),
                                        max(1, model.project.master.loopBars - span)
                                    )
                                    model.setCycleRange(start: clampedStart, end: clampedStart + span)
                                }
                        )

                    cycleHandle
                        .offset(x: overviewCycleX(width: geometry.size.width), y: 3)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let bar = overviewBarIndex(
                                        for: overviewCycleX(width: geometry.size.width) + value.translation.width,
                                        width: geometry.size.width
                                    )
                                    model.setCycleRange(start: min(bar, model.project.master.cycleEndBar))
                                }
                        )

                    cycleHandle
                        .offset(
                            x: overviewCycleX(width: geometry.size.width) + overviewCycleWidth(width: geometry.size.width) - cycleHandleWidth,
                            y: 3
                        )
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    let bar = overviewBarIndex(
                                        for: overviewCycleX(width: geometry.size.width) + overviewCycleWidth(width: geometry.size.width) + value.translation.width,
                                        width: geometry.size.width
                                    )
                                    model.setCycleRange(end: max(bar, model.project.master.cycleStartBar))
                                }
                        )

                    ForEach(model.project.tracks) { track in
                        ForEach(track.clips) { clip in
                            let overviewWidth = max(4, geometry.size.width * CGFloat(clip.lengthSteps) / CGFloat(max(1, model.project.master.loopBars * 16)))
                            let overviewX = geometry.size.width * CGFloat(clip.startStep) / CGFloat(max(1, model.project.master.loopBars * 16))
                            let overviewFill = clipFill(track: track, selected: model.selectedClipIDs.contains(clip.id), audible: trackIsAudible(track)).opacity(0.9)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(overviewFill)
                                .frame(
                                    width: overviewWidth,
                                    height: 8
                                )
                                .offset(
                                    x: overviewX,
                                    y: CGFloat(10 + (trackRowIndex(track) % 3) * 10)
                                )
                        }
                    }

                    Rectangle()
                        .fill(Color.white.opacity(0.95))
                        .frame(width: 2)
                        .offset(x: overviewPlayheadX(width: geometry.size.width))
                        .shadow(color: .accentColor.opacity(0.35), radius: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            let clampedX = min(max(0, value.location.x), geometry.size.width)
                            let ratio = geometry.size.width > 0 ? clampedX / geometry.size.width : 0
                            let position = 1.0 + Double(ratio) * Double(max(1, model.project.master.loopBars))
                            model.setTransportBarPosition(snappedTransportPosition(position))
                        }
                )
            }
            .frame(height: 36)
        }
    }

    private var scrubStrip: some View {
        HStack(spacing: 6) {
            Text("Scrub")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: laneLabelWidth, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.black.opacity(0.18))
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: max(2, scrubPlayheadX(width: geometry.size.width)))
                    Rectangle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: 2)
                        .offset(x: scrubPlayheadX(width: geometry.size.width))
                        .shadow(color: .accentColor.opacity(0.35), radius: 2)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let clampedX = min(max(0, value.location.x), geometry.size.width)
                            let ratio = geometry.size.width > 0 ? clampedX / geometry.size.width : 0
                            let position = 1.0 + Double(ratio) * Double(max(1, model.project.master.loopBars))
                            model.setTransportBarPosition(snappedTransportPosition(position))
                        }
                )
            }
            .frame(height: 18)
        }
    }

    private func trackLane(_ track: Track) -> some View {
        HStack(alignment: .top, spacing: 6) {
            trackHeader(track)
            .frame(width: laneLabelWidth, alignment: .leading)

            ZStack(alignment: .topLeading) {
                HStack(spacing: barGap) {
                    ForEach(1...model.project.master.loopBars, id: \.self) { bar in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(bar % 4 == 1 ? Color.white.opacity(0.08) : Color.white.opacity(0.038))
                            .frame(width: barWidth, height: laneHeight)
                    }
                }

                HStack(spacing: barGap) {
                    ForEach(1..<model.project.master.loopBars, id: \.self) { bar in
                        Rectangle()
                            .fill(bar % 4 == 0 ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                            .frame(width: 1, height: laneHeight)
                            .offset(x: CGFloat(bar) * (barWidth + barGap) - barGap / 2)
                    }
                }

                ForEach(1...model.project.master.loopBars, id: \.self) { bar in
                    ForEach(1..<4, id: \.self) { subdivision in
                        Rectangle()
                            .fill(Color.white.opacity(0.045))
                            .frame(width: 1, height: laneHeight)
                            .offset(x: xForSubdivision(bar: bar, subdivision: subdivision))
                    }
                }

                localTrackGrid(track)

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.98), Color.accentColor.opacity(0.72)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 2, height: laneHeight + 14)
                    .shadow(color: .accentColor.opacity(0.55), radius: 6)
                    .offset(x: playheadX, y: -5)

                ForEach(track.clips) { clip in
                    clipBlock(track: track, clip: clip)
                }
            }
            .frame(width: timelineWidth, height: laneHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(trackLaneBackground(track))
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        model.setTransportBarPosition(snappedTransportPosition(barPosition(for: value.location.x)))
                    }
            )
        }
    }

    @ViewBuilder
    private func localTrackGrid(_ track: Track) -> some View {
        let beatLines = trackBeatLinePositions(track)
        let barLines = trackBarLinePositions(track)

        ForEach(Array(beatLines.enumerated()), id: \.offset) { _, x in
            Rectangle()
                .fill(Color.cyan.opacity(0.16))
                .frame(width: 1, height: laneHeight)
                .offset(x: x)
        }

        ForEach(Array(barLines.enumerated()), id: \.offset) { index, x in
            Rectangle()
                .fill(Color.cyan.opacity(0.46))
                .frame(width: 2, height: laneHeight)
                .offset(x: x - 0.5)

            Text("|\(index + 1)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.cyan.opacity(0.78))
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(Color.black.opacity(0.22), in: Capsule())
                .offset(x: min(max(0, x + 4), max(0, timelineWidth - 28)), y: 2)
        }
    }

    private func clipBlock(track: Track, clip: ClipRegion) -> some View {
        let clipWidth = widthForClip(clip)
        let isSelected = model.selectedClipIDs.contains(clip.id)
        let isAudible = trackIsAudible(track)
        return ZStack(alignment: .trailing) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.name)
                    .lineLimit(1)
                    .font(.system(size: 11, weight: .semibold))
                Text(formattedClipLength(clip))
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: clipWidth, height: 48, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(clipFill(track: track, selected: isSelected, audible: isAudible))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.white.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(isSelected ? Color.white : (isAudible ? Color.primary : Color.secondary))

            Rectangle()
                .fill(Color.primary.opacity(0.35))
                .frame(width: 6, height: 24)
                .padding(.trailing, 2)
                .gesture(
                    DragGesture()
                        .onEnded { value in
                            let deltaSteps = Int(round(value.translation.width / pixelsPerStep))
                            model.resizeClip(trackID: track.id, clipID: clip.id, lengthSteps: clip.lengthSteps + deltaSteps)
                        }
                )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectClip(trackID: track.id, clipID: clip.id)
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    let deltaSteps = Int(round(value.translation.width / pixelsPerStep))
                    let trackShift = Int(round(value.translation.height / (laneHeight + 10)))
                    let shouldDuplicate = NSEvent.modifierFlags.contains(.option)
                    model.moveClip(
                        trackID: track.id,
                        clipID: clip.id,
                        startStep: clip.startStep + deltaSteps,
                        targetTrackOffset: trackShift,
                        duplicate: shouldDuplicate
                    )
                }
        )
        .offset(x: xForClip(clip), y: 6)
    }

    private func editorBlock(title: String, text: Binding<String>, editable: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if editable {
                TextEditor(text: text)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var transportBadge: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("ChuckDAW")
                .font(.system(size: 18, weight: .bold, design: .rounded))
            Text("ARRANGE")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 120, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var transportControls: some View {
        HStack(spacing: 8) {
            Button(model.isPlaying ? "Re-run" : "Start") {
                model.startPlayback()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])

            Button("Stop") {
                model.stopPlayback()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(".", modifiers: [.command])

            Button("Compile") {
                model.compile()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("b", modifiers: [.command])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var cycleDesk: some View {
        HStack(spacing: 10) {
            compactIntField("Loop", value: model.masterBinding(\.loopBars), width: 56)
            compactIntField("Cycle In", value: cycleStartBinding, width: 62)
            compactIntField("Cycle Out", value: cycleEndBinding, width: 62)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var timelineDesk: some View {
        HStack(spacing: 10) {
            compactNumberField("BPM", value: model.masterBinding(\.bpm), width: 60, precision: 0)
            compactNumberField("Gain", value: model.masterBinding(\.gain), width: 60, precision: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Follow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Toggle("", isOn: $model.followPlayhead)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.84, anchor: .leading)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Slider(value: $model.timelineZoom, in: 0.65...1.85)
                    .frame(width: 110)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var projectDesk: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Position")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(logicBarDisplay)
                .font(.system(size: 21, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green.opacity(0.95))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: 148, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.86))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var sessionStatusDesk: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 6) {
                tag("\(model.stats.activeTracks) tracks")
                tag("\(model.stats.activeClips) clips")
                tag(model.engineStatus == "Binary found" ? "engine ok" : "engine missing")
            }
            Text(model.isPlaying ? "Rolling" : "Stopped")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(model.isPlaying ? Color.green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private var snapDesk: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Snap")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: $model.snapMode) {
                ForEach(TimelineSnapMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(transportPanelFill, in: RoundedRectangle(cornerRadius: 12))
    }

    private func trackHeader(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(trackHeaderDot(track))
                    .frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("\(formattedTempoRatio(track.tempoRatio)) · \(track.timeSignatureTop)/\(track.timeSignatureBottom) · \(track.clips.count) clips")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(track.solo ? "S" : (!track.enabled ? "M" : ""))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(track.solo ? .yellow : .red)
            }

            HStack(spacing: 6) {
                smallTrackButton("M", active: !track.enabled, accent: .red) {
                    model.toggleTrackEnabled(track.id)
                }
                smallTrackButton("S", active: track.solo, accent: .yellow) {
                    model.toggleTrackSolo(track.id)
                }
                Spacer(minLength: 0)
                Text(trackIsAudible(track) ? "live" : "off")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(trackIsAudible(track) ? Color.green.opacity(0.85) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(trackHeaderBackground(track))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var logView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(model.logMessages, id: \.self) { line in
                    Text(line)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func paneHeader<Content: View>(_ title: String, @ViewBuilder trailing: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func compactNumberField(_ title: String, value: Binding<Double>, width: CGFloat, precision: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number.precision(.fractionLength(precision)))
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func compactIntField(_ title: String, value: Binding<Int>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
    }

    private func compactTimeSignatureBottomPicker(title: String, value: Binding<Int>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker("", selection: value) {
                ForEach([1, 2, 4, 8, 16], id: \.self) { denominator in
                    Text("\(denominator)").tag(denominator)
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
    }

    private func smallTrackButton(_ title: String, active: Bool, accent: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .frame(width: 22, height: 18)
                .background(active ? accent.opacity(0.92) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(active ? Color.black.opacity(0.8) : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private var cycleHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.accentColor.opacity(0.9))
            .frame(width: cycleHandleWidth, height: 30)
            .overlay {
                Capsule()
                    .fill(Color.white.opacity(0.7))
                    .frame(width: 2, height: 14)
            }
    }

    private var timelineWidth: CGFloat {
        CGFloat(model.project.master.loopBars) * barWidth + CGFloat(max(0, model.project.master.loopBars - 1)) * barGap
    }

    private var cycleOverlayX: CGFloat {
        CGFloat(model.project.master.cycleStartBar - 1) * (barWidth + barGap)
    }

    private var cycleOverlayWidth: CGFloat {
        CGFloat(max(1, model.project.master.cycleEndBar - model.project.master.cycleStartBar + 1)) * barWidth
            + CGFloat(max(0, model.project.master.cycleEndBar - model.project.master.cycleStartBar)) * barGap
    }

    private var barWidth: CGFloat {
        baseBarWidth * model.timelineZoom
    }

    private var playheadX: CGFloat {
        CGFloat((model.transportBarPosition - 1.0) * 16.0) * pixelsPerStep
    }

    private var currentBarAnchor: Int {
        min(model.project.master.loopBars, max(1, Int(floor(model.transportBarPosition))))
    }

    private var currentBarDisplay: String {
        String(format: "%.2f", model.transportBarPosition)
    }

    private var marqueeRect: CGRect? {
        guard let marqueeStart, let marqueeCurrent else { return nil }
        return CGRect(
            x: min(marqueeStart.x, marqueeCurrent.x),
            y: min(marqueeStart.y, marqueeCurrent.y),
            width: abs(marqueeCurrent.x - marqueeStart.x),
            height: abs(marqueeCurrent.y - marqueeStart.y)
        )
    }

    private var logicBarDisplay: String {
        let wholeBar = Int(floor(model.transportBarPosition))
        let beatProgress = model.transportBarPosition - Double(wholeBar)
        let beat = min(4, max(1, Int(floor(beatProgress * 4.0)) + 1))
        let subBeat = min(16, max(1, Int(floor((beatProgress * 16.0).truncatingRemainder(dividingBy: 4.0) * 4.0)) + 1))
        return "\(wholeBar).\(beat).\(subBeat)"
    }

    private func xForClip(_ clip: ClipRegion) -> CGFloat {
        CGFloat(clip.startStep) * pixelsPerStep
    }

    private func xForSubdivision(bar: Int, subdivision: Int) -> CGFloat {
        let step = barWidth + barGap
        let baseX = CGFloat(bar - 1) * step
        return baseX + (CGFloat(subdivision) * (barWidth / 4.0))
    }

    private func applyMarqueeSelection() {
        guard let marqueeRect else { return }
        let contentTop = CGFloat(12)
        let lanesTop = contentTop + 10 + 22 + 10
        var selected: Set<UUID> = []

        for (trackIndex, track) in model.project.tracks.enumerated() {
            let laneY = lanesTop + CGFloat(trackIndex) * (laneHeight + 10)
            for clip in track.clips {
                let clipRect = CGRect(
                    x: contentTop + laneLabelWidth + 6 + xForClip(clip),
                    y: laneY + 6,
                    width: widthForClip(clip),
                    height: 48
                )
                if marqueeRect.intersects(clipRect) {
                    selected.insert(clip.id)
                }
            }
        }

        model.selectClips(selected)
    }

    private func widthForClip(_ clip: ClipRegion) -> CGFloat {
        CGFloat(max(1, clip.lengthSteps)) * pixelsPerStep
    }

    private func barPosition(for x: CGFloat) -> Double {
        let step = barWidth + barGap
        let clampedX = min(max(0, x), timelineWidth)
        return 1.0 + Double(clampedX / step)
    }

    private func snappedTransportPosition(_ position: Double) -> Double {
        let unit = model.snapMode.unitBars
        let base = 1.0
        let snapped = (round((position - base) / unit) * unit) + base
        return min(max(Double(model.project.master.cycleStartBar), snapped), Double(model.project.master.cycleEndBar) + 0.999)
    }

    private func rulerBarIndex(for x: CGFloat) -> Int {
        min(model.project.master.loopBars, max(1, Int(floor(barPosition(for: x)))))
    }

    private var pixelsPerStep: CGFloat {
        (barWidth + barGap) / 16.0
    }

    private func formattedClipStart(_ clip: ClipRegion) -> String {
        let bar = (clip.startStep / 16) + 1
        let beat = ((clip.startStep % 16) / 4) + 1
        let sixteenth = (clip.startStep % 4) + 1
        return "\(bar).\(beat).\(sixteenth)"
    }

    private func formattedClipLength(_ clip: ClipRegion) -> String {
        if clip.lengthSteps % 16 == 0 {
            let bars = clip.lengthSteps / 16
            return bars == 1 ? "1 bar" : "\(bars) bars"
        }
        return "\(clip.lengthSteps)/16"
    }

    private func formattedTempoRatio(_ ratio: Double) -> String {
        if abs(ratio.rounded() - ratio) < 0.0001 {
            return "x\(Int(ratio.rounded()))"
        }
        return String(format: "x%.3f", ratio)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    private func trackBeatLengthInMasterSteps(_ track: Track) -> Double {
        let ratio = max(0.125, track.tempoRatio)
        let denominator = Double(max(1, track.timeSignatureBottom))
        return 16.0 / (denominator * ratio)
    }

    private func trackBarLengthInMasterSteps(_ track: Track) -> Double {
        Double(max(1, track.timeSignatureTop)) * trackBeatLengthInMasterSteps(track)
    }

    private func trackBeatLinePositions(_ track: Track) -> [CGFloat] {
        let beatLength = trackBeatLengthInMasterSteps(track)
        guard beatLength > 0 else { return [] }

        let maxSteps = Double(model.project.master.loopBars * 16)
        var lines: [CGFloat] = []
        var step = beatLength
        while step < maxSteps - 0.001 {
            lines.append(CGFloat(step) * pixelsPerStep)
            step += beatLength
        }
        return lines
    }

    private func trackBarLinePositions(_ track: Track) -> [CGFloat] {
        let barLength = trackBarLengthInMasterSteps(track)
        guard barLength > 0 else { return [] }

        let maxSteps = Double(model.project.master.loopBars * 16)
        var lines: [CGFloat] = [0]
        var step = barLength
        while step < maxSteps - 0.001 {
            lines.append(CGFloat(step) * pixelsPerStep)
            step += barLength
        }
        return lines
    }

    private func barID(_ bar: Int) -> String {
        "bar-\(bar)"
    }

    private func scrollToVisibleBar(using proxy: ScrollViewProxy, animated: Bool) {
        guard model.followPlayhead else { return }
        let targetBar = min(model.project.master.loopBars, max(1, currentBarAnchor + followLookAheadBars))
        let anchor = UnitPoint(x: 0.28, y: 0.5)
        if animated {
            withAnimation(.easeOut(duration: 0.18)) {
                proxy.scrollTo(barID(targetBar), anchor: anchor)
            }
        } else {
            proxy.scrollTo(barID(targetBar), anchor: anchor)
        }
    }

    private func trackIsAudible(_ track: Track) -> Bool {
        let anySolo = model.project.tracks.contains(where: \.solo)
        if anySolo {
            return track.enabled && track.solo
        }
        return track.enabled
    }

    private func clipFill(track: Track, selected: Bool, audible: Bool) -> Color {
        if selected {
            return .accentColor.opacity(0.88)
        }
        if !audible {
            return .gray.opacity(0.14)
        }
        if track.solo {
            return .yellow.opacity(0.38)
        }
        return .blue.opacity(0.20)
    }

    private func trackLaneBackground(_ track: Track) -> Color {
        if track.solo {
            return Color.yellow.opacity(0.06)
        }
        if !track.enabled {
            return Color.gray.opacity(0.08)
        }
        return Color.black.opacity(0.14)
    }

    private func trackHeaderBackground(_ track: Track) -> Color {
        if track.solo {
            return Color.yellow.opacity(0.12)
        }
        if !track.enabled {
            return Color.gray.opacity(0.12)
        }
        return Color.black.opacity(0.18)
    }

    private func trackHeaderDot(_ track: Track) -> Color {
        if track.solo {
            return .yellow
        }
        return trackIsAudible(track) ? .green : .gray
    }

    private var cycleStartBinding: Binding<Int> {
        Binding(
            get: { model.project.master.cycleStartBar },
            set: { model.setCycleRange(start: $0) }
        )
    }

    private var cycleEndBinding: Binding<Int> {
        Binding(
            get: { model.project.master.cycleEndBar },
            set: { model.setCycleRange(end: $0) }
        )
    }

    private func rulerBarFill(_ bar: Int) -> Color {
        if bar == currentBarAnchor {
            return Color.accentColor.opacity(0.7)
        }
        if bar >= model.project.master.cycleStartBar && bar <= model.project.master.cycleEndBar {
            return Color.accentColor.opacity(0.32)
        }
        return Color.secondary.opacity(0.18)
    }

    private func overviewPlayheadX(width: CGFloat) -> CGFloat {
        let ratio = max(0, min(1, CGFloat(model.transportBarPosition - 1.0) / CGFloat(max(1, model.project.master.loopBars))))
        return ratio * width
    }

    private func scrubPlayheadX(width: CGFloat) -> CGFloat {
        let ratio = max(0, min(1, CGFloat(model.transportBarPosition - 1.0) / CGFloat(max(1, model.project.master.loopBars))))
        return ratio * width
    }

    private func overviewCycleX(width: CGFloat) -> CGFloat {
        width * CGFloat(model.project.master.cycleStartBar - 1) / CGFloat(max(1, model.project.master.loopBars))
    }

    private func overviewCycleWidth(width: CGFloat) -> CGFloat {
        width * CGFloat(max(1, model.project.master.cycleEndBar - model.project.master.cycleStartBar + 1)) / CGFloat(max(1, model.project.master.loopBars))
    }

    private func overviewBarIndex(for x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 1 }
        let normalized = min(max(0, x), width)
        let ratio = normalized / width
        let bar = Int(floor(ratio * CGFloat(max(1, model.project.master.loopBars)))) + 1
        return min(model.project.master.loopBars, max(1, bar))
    }

    @ViewBuilder
    private func overviewBarGrid(width: CGFloat) -> some View {
        let loopBars = max(1, model.project.master.loopBars)
        ZStack(alignment: .leading) {
            ForEach(0...loopBars, id: \.self) { index in
                Rectangle()
                    .fill(index % 4 == 0 ? Color.secondary.opacity(0.2) : Color.secondary.opacity(0.1))
                    .frame(width: 1)
                    .offset(x: width * CGFloat(index) / CGFloat(loopBars))
            }
        }
    }

    private func trackRowIndex(_ track: Track) -> Int {
        model.project.tracks.firstIndex(where: { $0.id == track.id }) ?? 0
    }

    private var followLookAheadBars: Int {
        max(1, Int(round(4 / max(0.65, model.timelineZoom))))
    }

    private var cycleHandleWidth: CGFloat {
        8
    }

    private var transportPanelFill: some ShapeStyle {
        LinearGradient(
            colors: [
                Color.white.opacity(0.16),
                Color.black.opacity(0.08)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var selectedTrack: Track? {
        guard let selectedTrackID = model.selectedTrackID else { return nil }
        return model.project.tracks.first(where: { $0.id == selectedTrackID })
    }
}
