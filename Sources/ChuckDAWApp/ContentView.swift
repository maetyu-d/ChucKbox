import AppKit
import SwiftUI

private enum EditorPanel: String, CaseIterable, Identifiable {
    case clip = "Clip"
    case prelude = "Prelude"
    case score = "Score"
    case log = "Log"

    var id: String { rawValue }
}

private struct ArrangementSplitContainer<Left: View, Center: View, Right: View>: NSViewRepresentable {
    let left: Left
    let center: Center
    let right: Right

    func makeCoordinator() -> Coordinator {
        Coordinator(left: NSHostingView(rootView: left), center: NSHostingView(rootView: center), right: NSHostingView(rootView: right))
    }

    func makeNSView(context: Context) -> WideDividerSplitView {
        let splitView = WideDividerSplitView()
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autosaveName = "ChuckDAWArrangementSplit"

        let leftHost = context.coordinator.leftHost
        leftHost.frame = NSRect(x: 0, y: 0, width: 280, height: 800)
        let centerHost = context.coordinator.centerHost
        centerHost.frame = NSRect(x: 0, y: 0, width: 820, height: 800)
        let rightHost = context.coordinator.rightHost
        rightHost.frame = NSRect(x: 0, y: 0, width: 520, height: 800)

        [leftHost, centerHost, rightHost].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            splitView.addArrangedSubview($0)
        }

        NSLayoutConstraint.activate([
            leftHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 0),
            centerHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 420),
            rightHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 0)
        ])

        return splitView
    }

    func updateNSView(_ splitView: WideDividerSplitView, context: Context) {
        context.coordinator.leftHost.rootView = left
        context.coordinator.centerHost.rootView = center
        context.coordinator.rightHost.rootView = right
    }

    final class Coordinator {
        let leftHost: NSHostingView<Left>
        let centerHost: NSHostingView<Center>
        let rightHost: NSHostingView<Right>

        init(left: NSHostingView<Left>, center: NSHostingView<Center>, right: NSHostingView<Right>) {
            self.leftHost = left
            self.centerHost = center
            self.rightHost = right
        }
    }
}

private final class WideDividerSplitView: NSSplitView {
    override var dividerThickness: CGFloat { 14 }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let clickedDividerIndex = dividerIndexForPoint(point)

        if event.clickCount == 2, clickedDividerIndex != -1 {
            cyclePaneWidth(forDividerAt: clickedDividerIndex)
            return
        }

        super.mouseDown(with: event)
    }

    override func drawDivider(in rect: NSRect) {
        let railRect = rect.insetBy(dx: 5.5, dy: 0)
        NSColor.separatorColor.withAlphaComponent(0.9).setFill()
        NSBezierPath(roundedRect: railRect, xRadius: 3, yRadius: 3).fill()

        let gripSize = NSSize(width: 4, height: 34)
        let gripRect = NSRect(
            x: rect.midX - gripSize.width / 2,
            y: rect.midY - gripSize.height / 2,
            width: gripSize.width,
            height: gripSize.height
        )
        NSColor.controlAccentColor.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: gripRect, xRadius: 2, yRadius: 2).fill()
    }

    private func cyclePaneWidth(forDividerAt dividerIndex: Int) {
        guard isVertical, dividerIndex >= 0, dividerIndex < arrangedSubviews.count - 1 else { return }
        let availableWidth = bounds.width
        guard availableWidth > 0 else { return }

        let targets: [CGFloat] = [0.0, 0.25, 0.5].map { availableWidth * $0 }

        if dividerIndex == 0 {
            let currentWidth = arrangedSubviews[0].frame.width
            let nextWidth = nextTarget(from: currentWidth, targets: targets)
            setPosition(nextWidth, ofDividerAt: dividerIndex)
        } else {
            let currentWidth = arrangedSubviews[dividerIndex + 1].frame.width
            let nextWidth = nextTarget(from: currentWidth, targets: targets)
            let dividerPosition = max(0, availableWidth - dividerThickness - nextWidth)
            setPosition(dividerPosition, ofDividerAt: dividerIndex)
        }

        adjustSubviews()
    }

    private func nextTarget(from currentWidth: CGFloat, targets: [CGFloat]) -> CGFloat {
        let tolerance: CGFloat = 18
        if let currentIndex = targets.firstIndex(where: { abs($0 - currentWidth) <= tolerance }) {
            return targets[(currentIndex + 1) % targets.count]
        }
        return targets.min(by: { abs($0 - currentWidth) < abs($1 - currentWidth) }) ?? currentWidth
    }

    private func dividerIndexForPoint(_ point: NSPoint) -> Int {
        guard arrangedSubviews.count > 1 else { return -1 }
        for index in 0..<(arrangedSubviews.count - 1) {
            let leadingFrame = arrangedSubviews[index].frame
            let dividerRect = NSRect(
                x: leadingFrame.maxX,
                y: 0,
                width: dividerThickness,
                height: bounds.height
            )
            if dividerRect.contains(point) {
                return index
            }
        }
        return -1
    }
}

struct ContentView: View {
    private let laneLabelWidth: CGFloat = 188
    private let baseBarWidth: CGFloat = 88
    private let barGap: CGFloat = 6
    private let laneHeight: CGFloat = 64
    private let mixerStripHeight: CGFloat = 525

    @EnvironmentObject private var model: AppViewModel
    @State private var editorPanel: EditorPanel = .clip
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if model.isMixerVisible {
                mixerWorkspace
            } else {
                arrangementWorkspace
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
        .background(
            EmptyView()
        )
        .animation(.easeInOut(duration: 0.18), value: model.isMixerVisible)
    }

    private var arrangementWorkspace: some View {
        ArrangementSplitContainer(
            left: trackListPane
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 420),
            center: timelinePane
                .frame(minWidth: 560)
                .layoutPriority(1),
            right: editorPane
                .frame(minWidth: 360, idealWidth: 520, maxWidth: .infinity)
                .layoutPriority(0.35)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
    }

    private var mixerWorkspace: some View {
        mixerPane
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
    }

    private var topBar: some View {
        VStack(spacing: 6) {
            compactTransportRow
            compactSessionRow
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor).opacity(0.95),
                    Color(nsColor: .controlBackgroundColor).opacity(0.88)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var compactTransportRow: some View {
        HStack(alignment: .center, spacing: 10) {
            compactIdentity
            compactTransportButtons
            compactTimingStrip
            compactSnapStrip
            compactNavigationStrip
            Spacer(minLength: 10)
            compactMonitorStrip
        }
        .frame(height: 36)
    }

    private var compactSessionRow: some View {
        HStack(spacing: 10) {
            TextField("Project", text: model.projectBinding(\.name))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)

            Picker("Preset", selection: $model.selectedPreset) {
                ForEach(PresetLibrary.allCases) { preset in
                    Text(preset.rawValue).tag(preset)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Button("Load") {
                model.loadPreset()
            }
            .buttonStyle(.bordered)

            Button("Reset") {
                model.resetProject()
            }
            .buttonStyle(.bordered)

            Button(model.isMixerVisible ? "Hide Mixer" : "Mixer") {
                model.toggleMixerVisibility()
            }
            .buttonStyle(.bordered)

            SettingsLink {
                Text("Settings…")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 0)
        }
        .controlSize(.small)
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

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.project.tracks) { track in
                        sidebarTrackCard(track)
                    }
                }
                .padding(10)
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .textBackgroundColor).opacity(0.74),
                        Color(nsColor: .controlBackgroundColor).opacity(0.44)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
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

            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView([.horizontal, .vertical]) {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            timelinePinnedHeader

                            ForEach(model.project.tracks) { track in
                                trackLane(track)
                                if let renderedAudio = track.renderedAudio {
                                    renderedAudioLane(track: track, renderedAudio: renderedAudio)
                                }
                            }
                        }
                        .frame(minWidth: geometry.size.width, minHeight: geometry.size.height, alignment: .topLeading)
                        .contentShape(Rectangle())
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
    }

    private var timelinePinnedHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Timeline")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: laneLabelWidth, alignment: .leading)

                HStack(spacing: 6) {
                    headerPill(logicBarDisplay, tint: Color.green.opacity(0.16))
                    headerPill("Cycle \(model.project.master.cycleStartBar)-\(model.project.master.cycleEndBar)", tint: Color.secondary.opacity(0.10))
                    if let primaryFollowTrack, usesIndependentTrackPlayheads {
                        headerPill("\(primaryFollowTrack.name) \(localPlayheadDisplay(for: primaryFollowTrack))", tint: Color.orange.opacity(0.14))
                    }
                }
            }

            barRuler
        }
        .padding(.vertical, 4)
        .frame(height: 42, alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) {
            Divider()
        }
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .textBackgroundColor).opacity(0.985),
                    Color(nsColor: .controlBackgroundColor).opacity(0.95)
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

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if editorPanel == .clip {
                        clipInspector
                    } else if editorPanel == .prelude {
                        editorBlock(title: "Session Prelude", text: model.projectBinding(\.prelude))
                            .frame(minHeight: 360)
                    } else if editorPanel == .score {
                        editorBlock(title: "Compiled Score", text: .constant(model.compiledCode), editable: false)
                            .frame(minHeight: 360)
                    } else {
                        logView
                            .frame(minHeight: 360)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .textBackgroundColor).opacity(0.78),
                        Color(nsColor: .controlBackgroundColor).opacity(0.46)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var mixerPane: some View {
        VStack(spacing: 0) {
            paneHeader("Mixer") {
                HStack(spacing: 8) {
                    Text("Tab hides")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    miniStatus("\(model.project.tracks.count + model.project.buses.count + 1) strips")
                }
            }

            GeometryReader { geometry in
                let stripCount = max(1, model.project.tracks.count + 1)
                let horizontalPadding: CGFloat = 36
                let stripSpacing: CGFloat = 14
                let availableWidth = max(0, geometry.size.width - horizontalPadding - (CGFloat(stripCount - 1) * stripSpacing))
                let stripWidth = max(108, min(164, availableWidth / CGFloat(stripCount)))
                let stripHeight = max(560, geometry.size.height - 28)
                let controlHeight = max(260, min(360, stripHeight * 0.42))

                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(model.project.tracks) { track in
                            mixerChannelStrip(
                                track,
                                width: stripWidth,
                                stripHeight: stripHeight,
                                controlHeight: controlHeight
                            )
                        }
                        ForEach(model.project.buses) { bus in
                            busChannelStrip(
                                bus,
                                width: stripWidth,
                                stripHeight: stripHeight,
                                controlHeight: controlHeight
                            )
                        }
                        masterChannelStrip(
                            width: max(stripWidth, 118),
                            stripHeight: stripHeight,
                            controlHeight: controlHeight
                        )
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
                    .frame(
                        minWidth: geometry.size.width,
                        minHeight: geometry.size.height,
                        alignment: .topLeading
                    )
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(nsColor: .controlBackgroundColor).opacity(0.92),
                        Color.black.opacity(0.34)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var clipInspector: some View {
        Group {
            if model.selectedTrackIndex != nil, model.selectedClipIndex != nil {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorCard(title: "Clip") {
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
                        }
                    }

                    inspectorCard(title: "Track Insert") {
                        editorBlock(title: "Track Insert Code", text: model.selectedTrackBinding(\.effectCode, fallback: "trackIn => trackOut;"))
                    }

                    inspectorCard(title: "Track Devices") {
                        if let track = selectedTrack {
                            deviceSlotRack(
                                slots: track.deviceSlots,
                                loadAction: { model.loadDeviceSlotForSelectedTrack() },
                                toggleAction: { model.toggleTrackDeviceSlot($0) },
                                moveUpAction: { model.moveTrackDeviceSlot($0, by: -1) },
                                moveDownAction: { model.moveTrackDeviceSlot($0, by: 1) },
                                removeAction: { model.removeTrackDeviceSlot($0) }
                            )
                        }
                    }

                    inspectorCard(title: "Code") {
                        editorBlock(title: "Clip Code", text: model.selectedClipBinding(\.code, fallback: ""))
                    }
                }
            } else if model.selectedTrackIndex != nil {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorCard(title: "Track") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Track Name", text: model.selectedTrackBinding(\.name, fallback: ""))
                                    .textFieldStyle(.roundedBorder)
                                Toggle("On", isOn: model.selectedTrackBinding(\.enabled, fallback: true))
                                    .toggleStyle(.checkbox)
                                Toggle("Solo", isOn: model.selectedTrackBinding(\.solo, fallback: false))
                                    .toggleStyle(.checkbox)
                            }

                            selectedTrackTimingStrip

                            Text("Select a clip to edit its ChucK region. Tempo ratio and meter apply to every clip on this track.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    inspectorCard(title: "Track Insert") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Use `trackIn` and `trackOut` inside the insert code.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            editorBlock(title: "Track Insert Code", text: model.selectedTrackBinding(\.effectCode, fallback: "trackIn => trackOut;"))
                                .frame(minHeight: 180)
                        }
                    }

                    inspectorCard(title: "Track Devices") {
                        if let track = selectedTrack {
                            deviceSlotRack(
                                slots: track.deviceSlots,
                                loadAction: { model.loadDeviceSlotForSelectedTrack() },
                                toggleAction: { model.toggleTrackDeviceSlot($0) },
                                moveUpAction: { model.moveTrackDeviceSlot($0, by: -1) },
                                moveDownAction: { model.moveTrackDeviceSlot($0, by: 1) },
                                removeAction: { model.removeTrackDeviceSlot($0) }
                            )
                        }
                    }

                    Spacer(minLength: 0)
                }
            } else if model.selectedBusIndex != nil {
                VStack(alignment: .leading, spacing: 10) {
                    inspectorCard(title: "Bus") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Bus Name", text: model.selectedBusBinding(\.name, fallback: ""))
                                .textFieldStyle(.roundedBorder)

                            HStack(spacing: 8) {
                                compactNumberField("Gain", value: model.selectedBusBinding(\.gain, fallback: 1.0), width: 76, precision: 2)
                                compactNumberField("Pan", value: model.selectedBusBinding(\.pan, fallback: 0.0), width: 76, precision: 2)
                                Spacer(minLength: 0)
                            }

                            Text("Use `busIn` and `busOut` inside the bus effect code.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }

                    inspectorCard(title: "Bus FX Code") {
                        editorBlock(title: "Bus Effect", text: model.selectedBusBinding(\.effectCode, fallback: "busIn => busOut;"))
                    }

                    inspectorCard(title: "Bus Devices") {
                        if let bus = selectedBus {
                            deviceSlotRack(
                                slots: bus.deviceSlots,
                                loadAction: { model.loadDeviceSlotForSelectedBus() },
                                toggleAction: { model.toggleBusDeviceSlot($0) },
                                moveUpAction: { model.moveBusDeviceSlot($0, by: -1) },
                                moveDownAction: { model.moveBusDeviceSlot($0, by: 1) },
                                removeAction: { model.removeBusDeviceSlot($0) }
                            )
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Track Selected", systemImage: "timeline.selection")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var selectedTrackTimingStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                compactNumberField("Tempo x", value: model.selectedTrackBinding(\.tempoRatio, fallback: 1.0), width: 76, precision: 3)
                compactIntField("Beats", value: model.selectedTrackBinding(\.timeSignatureTop, fallback: 4), width: 58)
                compactTimeSignatureBottomPicker(
                    title: "Unit",
                    value: model.selectedTrackBinding(\.timeSignatureBottom, fallback: 4),
                    width: 72
                )
                if let track = selectedTrack {
                    compactBusRoutePicker(
                        title: "Out",
                        selection: model.trackOutputBusBinding(track.id),
                        width: 110
                    )
                }
                Spacer(minLength: 0)
                if let track = selectedTrack {
                    Text("Local pulse: \(formattedTempoRatio(track.tempoRatio)) · \(track.timeSignatureTop)/\(track.timeSignatureBottom) · \(routeLabel(for: track))")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            if let track = selectedTrack, !model.project.buses.isEmpty {
                HStack(spacing: 8) {
                    ForEach(model.project.buses) { bus in
                        compactNumberField(
                            "Send \(bus.name)",
                            value: model.trackSendLevelBinding(track.id, busID: bus.id),
                            width: 84,
                            precision: 2
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func sidebarTrackCard(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                model.selectTrack(track.id)
            } label: {
                HStack(spacing: 8) {
                    Circle()
                        .fill(trackHeaderDot(track))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text("\(formattedTempoRatio(track.tempoRatio)) · \(track.timeSignatureTop)/\(track.timeSignatureBottom)")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if track.solo {
                        headerPill("S", tint: Color.yellow.opacity(0.22))
                    }
                    if !track.enabled {
                        headerPill("M", tint: Color.red.opacity(0.18))
                    }
                    Text("\(track.clips.count)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            VStack(spacing: 4) {
                ForEach(track.clips) { clip in
                    Button {
                        model.selectClip(trackID: track.id, clipID: clip.id)
                    } label: {
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(model.selectedClipIDs.contains(clip.id) ? Color.accentColor : Color.secondary.opacity(0.18))
                                .frame(width: 4, height: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(clip.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .lineLimit(1)
                                Text("\(formattedClipStart(clip)) · \(formattedClipLength(clip))")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(model.selectedClipIDs.contains(clip.id) ? Color.accentColor.opacity(0.12) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(sidebarTrackBackground(track))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(track.id == model.selectedTrackID ? Color.accentColor.opacity(0.32) : Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private func inspectorCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
            )
        )
    }

    private func deviceSlotRack(
        slots: [DeviceSlot],
        loadAction: @escaping () -> Void,
        toggleAction: @escaping (UUID) -> Void,
        moveUpAction: @escaping (UUID) -> Void,
        moveDownAction: @escaping (UUID) -> Void,
        removeAction: @escaping (UUID) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button("Load Device", action: loadAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Text("\(slots.count) slot\(slots.count == 1 ? "" : "s")")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            if slots.isEmpty {
                Text("Load `.ck` files that use `deviceIn` and `deviceOut`.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(Array(slots.enumerated()), id: \.element.id) { entry in
                        let slot = entry.element
                        HStack(spacing: 8) {
                            Button(slot.isEnabled ? "On" : "Off") {
                                toggleAction(slot.id)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .frame(width: 28, height: 18)
                            .background((slot.isEnabled ? Color.green.opacity(0.18) : Color.white.opacity(0.08)), in: RoundedRectangle(cornerRadius: 4))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(slot.name)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)
                                Text(URL(fileURLWithPath: slot.filePath).lastPathComponent)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Button("↑") { moveUpAction(slot.id) }
                                .buttonStyle(.borderless)
                                .disabled(entry.offset == 0)
                            Button("↓") { moveDownAction(slot.id) }
                                .buttonStyle(.borderless)
                                .disabled(entry.offset == slots.count - 1)
                            Button("Show") { model.revealDeviceFile(slot.filePath) }
                                .buttonStyle(.borderless)
                            Button("Remove") { removeAction(slot.id) }
                                .buttonStyle(.borderless)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 7)
                        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
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

                if usesIndependentTrackPlayheads, let primaryFollowTrack {
                    Rectangle()
                        .fill(Color.orange.opacity(0.95))
                        .frame(width: 2, height: 18)
                        .offset(x: lanePlayheadX(for: primaryFollowTrack), y: 2)
                        .shadow(color: Color.orange.opacity(0.42), radius: 3)

                    Text("T1")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.95))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color.black.opacity(0.25), in: Capsule())
                        .offset(x: min(max(0, lanePlayheadX(for: primaryFollowTrack) + 4), max(0, timelineWidth - 24)), y: -10)
                }

                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.10))
                    .frame(width: cycleOverlayWidth, height: 18)
                    .offset(x: cycleOverlayX, y: 2)
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
                    .frame(height: 18)
                    .offset(x: cycleOverlayX, y: 2)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let bar = rulerBarIndex(for: cycleOverlayX + value.translation.width)
                                model.setCycleRange(start: min(bar, model.project.master.cycleEndBar))
                            }
                    )

                cycleHandle
                    .frame(height: 18)
                    .offset(x: cycleOverlayX + cycleOverlayWidth - cycleHandleWidth, y: 2)
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
        .frame(height: 22, alignment: .top)
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
                    .fill(playheadFill(for: track))
                    .frame(width: 2, height: laneHeight + 14)
                    .shadow(color: playheadShadowColor(for: track), radius: 6)
                    .offset(x: lanePlayheadX(for: track), y: -5)

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

    private func renderedAudioLane(track: Track, renderedAudio: RenderedTrackAudio) -> some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(Color.orange.opacity(0.92))
                        .frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(track.name) Print")
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                        Text(renderedAudio.filePath.components(separatedBy: "/").last ?? "render.wav")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    headerPill(track.useRenderedAudio ? "Audio Live" : "Audio", tint: track.useRenderedAudio ? Color.orange.opacity(0.24) : Color.orange.opacity(0.16))
                }

                HStack(spacing: 6) {
                    Button("Open") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: renderedAudio.filePath)])
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .frame(width: 34, height: 18)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))

                    Text(String(format: "%.2fs", renderedAudio.durationSeconds))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)

                    Button(track.useRenderedAudio ? "Using Print" : "Use Print") {
                        model.toggleTrackRenderedAudio(track.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .frame(width: 64, height: 18)
                    .background(
                        (track.useRenderedAudio ? Color.orange.opacity(0.22) : Color.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .frame(width: laneLabelWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )

            renderedWaveformBlock(track: track, renderedAudio: renderedAudio)
        }
    }

    private func renderedWaveformBlock(track: Track, renderedAudio: RenderedTrackAudio) -> some View {
        let waveform = renderedAudio.waveform.isEmpty ? Array(repeating: Float(0.12), count: 96) : renderedAudio.waveform
        let clipWidth = CGFloat(max(1, renderedAudio.lengthSteps)) * pixelsPerStep
        let startX = CGFloat(max(0, renderedAudio.startStep)) * pixelsPerStep
        let barWidth = max(1, clipWidth / CGFloat(max(1, waveform.count)) - 1)

        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.16))

            RoundedRectangle(cornerRadius: 8)
                .fill(track.useRenderedAudio ? Color.orange.opacity(0.14) : Color.orange.opacity(0.08))
                .frame(width: clipWidth, height: 60)
                .offset(x: startX)

            HStack(alignment: .center, spacing: 1) {
                ForEach(Array(waveform.enumerated()), id: \.offset) { entry in
                    let sample = CGFloat(entry.element)
                    let sampleHeight = max(4, 46 * sample)
                    Capsule()
                        .fill(Color.orange.opacity(0.92))
                        .frame(width: barWidth, height: sampleHeight)
                }
            }
            .padding(.horizontal, 8)
            .frame(width: clipWidth, height: 60, alignment: .leading)
            .offset(x: startX)

            Rectangle()
                .fill(playheadFill(for: track))
                .frame(width: 2, height: 70)
                .shadow(color: playheadShadowColor(for: track), radius: 6)
                .offset(x: lanePlayheadX(for: track), y: -5)

            Text("Rendered Audio")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.18), in: Capsule())
                .offset(x: startX + 8, y: 6)
        }
        .frame(width: timelineWidth, height: 60, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(track.useRenderedAudio ? Color.orange.opacity(0.34) : Color.orange.opacity(0.18), lineWidth: 1)
                )
        )
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
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
        )
    }

    private var transportIdentity: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(model.project.name.isEmpty ? "ChuckDAW" : model.project.name)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("Arrangement")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 210, alignment: .leading)
    }

    private var transportButtons: some View {
        HStack(spacing: 8) {
            Button(model.isPlaying ? "Re-run" : "Start") {
                model.startPlayback()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.space, modifiers: [])
            .frame(width: 74)

            Button("Stop") {
                model.stopPlayback()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(".", modifiers: [.command])
            .frame(width: 66)

            Button("Compile") {
                model.compile()
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("b", modifiers: [.command])
            .frame(width: 76)
        }
        .controlSize(.large)
    }

    private var transportTimingCluster: some View {
        HStack(alignment: .top, spacing: 10) {
            compactNumberField("BPM", value: model.masterBinding(\.bpm), width: 60, precision: 0)
            compactNumberField("Gain", value: model.masterBinding(\.gain), width: 60, precision: 2)
            compactIntField("Loop", value: model.masterBinding(\.loopBars), width: 54)
            compactIntField("In", value: cycleStartBinding, width: 52)
            compactIntField("Out", value: cycleEndBinding, width: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text("Snap")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Picker("", selection: $model.snapMode) {
                    ForEach(TimelineSnapMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
            }
        }
        .frame(width: 430, alignment: .leading)
    }

    private var transportNavigationCluster: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Follow")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Toggle("", isOn: $model.followPlayhead)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.84, anchor: .leading)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Zoom")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Slider(value: $model.timelineZoom, in: 0.65...1.85)
                    .frame(width: 96)
            }
        }
        .frame(width: 156, alignment: .leading)
    }

    private var transportReadoutCluster: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(logicBarDisplay)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.green.opacity(0.95))
            HStack(spacing: 6) {
                headerPill("Master", tint: Color.green.opacity(0.14))
                if let primaryFollowTrack, usesIndependentTrackPlayheads {
                    headerPill("Track 1 \(localPlayheadDisplay(for: primaryFollowTrack))", tint: Color.orange.opacity(0.16))
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(width: 140, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.88))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var transportStatusCluster: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                monitorMetric(value: "\(model.stats.activeTracks)", label: "Tracks")
                monitorMetric(value: "\(model.stats.activeClips)", label: "Clips")
            }

            HStack(spacing: 8) {
                monitorStatusPill(
                    model.engineStatus == "Binary found" ? "Engine OK" : "Engine Missing",
                    tint: model.engineStatus == "Binary found" ? Color.green.opacity(0.18) : Color.red.opacity(0.18)
                )
                monitorStatusPill(
                    model.isPlaying ? "Rolling" : "Stopped",
                    tint: model.isPlaying ? Color.green.opacity(0.18) : Color.white.opacity(0.10)
                )
            }
        }
        .frame(width: 150, alignment: .leading)
    }

    private var transportMonitorCluster: some View {
        HStack(alignment: .center, spacing: 14) {
            transportReadoutCluster
            transportStatusCluster
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 344, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private var compactIdentity: some View {
        HStack(spacing: 6) {
            Text(model.project.name.isEmpty ? "ChuckDAW" : model.project.name)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .lineLimit(1)
            Text("Arrange")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(width: 134, alignment: .leading)
    }

    private var compactTransportButtons: some View {
        HStack(spacing: 6) {
            Button(model.isPlaying ? "Re-run" : "Start") {
                model.startPlayback()
            }
            .buttonStyle(.borderedProminent)
            .frame(width: 58)

            Button("Stop") {
                model.stopPlayback()
            }
            .buttonStyle(.bordered)
            .frame(width: 50)

            Button("Compile") {
                model.compile()
            }
            .buttonStyle(.bordered)
            .frame(width: 62)
        }
        .controlSize(.small)
    }

    private var compactTimingStrip: some View {
        HStack(spacing: 8) {
            compactNumberField("BPM", value: model.masterBinding(\.bpm), width: 44, precision: 0)
            compactNumberField("Gain", value: model.masterGainLiveBinding(), width: 48, precision: 2)
            compactIntField("Loop", value: model.masterBinding(\.loopBars), width: 40)
            compactIntField("In", value: cycleStartBinding, width: 36)
            compactIntField("Out", value: cycleEndBinding, width: 36)
        }
    }

    private var compactSnapStrip: some View {
        HStack(spacing: 6) {
            Picker("", selection: $model.snapMode) {
                ForEach(TimelineSnapMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 132)
        }
    }

    private var compactNavigationStrip: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                Text("Follow")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Toggle("", isOn: $model.followPlayhead)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .scaleEffect(0.75)
            }

            HStack(spacing: 5) {
                Text("Zoom")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Slider(value: $model.timelineZoom, in: 0.65...1.85)
                    .frame(width: 60)
            }
        }
        .frame(width: 144, alignment: .leading)
    }

    private var compactMonitorStrip: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(logicBarDisplay)
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.95))
                Text("Master")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.green.opacity(0.55))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.black.opacity(0.84))
            )

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    miniStatus("\(model.stats.activeTracks)T")
                    miniStatus("\(model.stats.activeClips)C")
                }
                miniStatus(model.isPlaying ? "Playing" : "Stopped")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private func miniStatus(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.4), in: Capsule())
    }

    private func trackHeader(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(trackHeaderDot(track))
                    .frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.name)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text("clips \(track.clips.count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text(trackIndexLabel(for: track))
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                smallTrackButton("M", active: !track.enabled, accent: .red) {
                    model.toggleTrackEnabled(track.id)
                }
                smallTrackButton("S", active: track.solo, accent: .yellow) {
                    model.toggleTrackSolo(track.id)
                }
                Button(track.renderedAudio == nil ? "Bnc" : "Reb") {
                    model.renderTrackAudio(track.id)
                }
                .buttonStyle(.plain)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .frame(width: 28, height: 18)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 4))
                if track.renderedAudio != nil {
                    Button(track.useRenderedAudio ? "Prt" : "Src") {
                        model.toggleTrackRenderedAudio(track.id)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .frame(width: 28, height: 18)
                    .background(
                        (track.useRenderedAudio ? Color.orange.opacity(0.22) : Color.white.opacity(0.08)),
                        in: RoundedRectangle(cornerRadius: 4)
                    )
                }
                Spacer(minLength: 0)
                headerPill(formattedTempoRatio(track.tempoRatio), tint: Color.secondary.opacity(0.10))
                headerPill("\(track.timeSignatureTop)/\(track.timeSignatureBottom)", tint: Color.secondary.opacity(0.10))
                headerPill(routeShortLabel(for: track), tint: Color.orange.opacity(0.12))
            }

            HStack(spacing: 6) {
                Text(trackIsAudible(track) ? "live" : "off")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(trackIsAudible(track) ? Color.green.opacity(0.85) : .secondary)
                Spacer(minLength: 0)
                Text(localPlayheadDisplay(for: track))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(primaryFollowTrack?.id == track.id && usesIndependentTrackPlayheads ? Color.orange.opacity(0.95) : .secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(trackHeaderBackground(track))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.72),
                    Color.white.opacity(0.46)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func mixerChannelStrip(_ track: Track, width: CGFloat, stripHeight: CGFloat, controlHeight: CGFloat) -> some View {
        let gainBinding = model.trackGainLiveBinding(track.id)
        let panBinding = model.trackPanLiveBinding(track.id)

        return VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text(trackIndexLabel(for: track))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Spacer()
                    Text(track.name)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                Text("Read")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.18))
                    )

                mixerPanKnob(value: panBinding.wrappedValue)

                Slider(value: panBinding, in: -1.0...1.0)
                    .controlSize(.mini)

                HStack(spacing: 4) {
                    mixerValueBox(String(format: "%+.1f", panBinding.wrappedValue * 50.0), tint: Color.yellow.opacity(0.9))
                    mixerValueBox(String(format: "%.2f", gainBinding.wrappedValue), tint: Color.white.opacity(0.9))
                }

                Text(routeLabel(for: track))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                mixerMeter(level: mixerLevel(for: track), height: controlHeight - 22)
                mixerFader(value: gainBinding, height: controlHeight)
            }
            .frame(height: controlHeight, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 10)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    smallTrackButton("M", active: !track.enabled, accent: .red) {
                        model.toggleTrackEnabled(track.id)
                    }
                    smallTrackButton("S", active: track.solo, accent: .yellow) {
                        model.toggleTrackSolo(track.id)
                    }
                }

                VStack(spacing: 2) {
                    Text(formattedTempoRatio(track.tempoRatio))
                    Text("\(track.timeSignatureTop)/\(track.timeSignatureBottom)")
                }
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: width, height: stripHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(track.id == model.selectedTrackID ? Color.white.opacity(0.16) : Color.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(track.id == model.selectedTrackID ? Color.accentColor.opacity(0.38) : Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            model.selectTrack(track.id)
        }
    }

    private func busChannelStrip(_ bus: Bus, width: CGFloat, stripHeight: CGFloat, controlHeight: CGFloat) -> some View {
        let gainBinding = model.busGainLiveBinding(bus.id)
        let panBinding = model.busPanLiveBinding(bus.id)

        return VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text("BUS")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Spacer()
                    Text(bus.name)
                        .font(.system(size: 10, weight: .bold))
                        .lineLimit(1)
                }

                Text("Aux Return")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.cyan.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.cyan.opacity(0.16))
                    )

                mixerPanKnob(value: panBinding.wrappedValue)

                Slider(value: panBinding, in: -1.0...1.0)
                    .controlSize(.mini)

                HStack(spacing: 4) {
                    mixerValueBox(String(format: "%+.1f", panBinding.wrappedValue * 50.0), tint: Color.yellow.opacity(0.9))
                    mixerValueBox(String(format: "%.2f", gainBinding.wrappedValue), tint: Color.white.opacity(0.9))
                }

                Text("Feeds from tracks")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 6))
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                mixerMeter(level: busMixerLevel(for: bus), height: controlHeight - 22)
                mixerFader(value: gainBinding, range: 0.0...1.5, height: controlHeight)
            }
            .frame(height: controlHeight, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 10)

            Text("to Master")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: width, height: stripHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.cyan.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.cyan.opacity(0.18), lineWidth: 1)
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            model.selectBus(bus.id)
        }
    }

    private func masterChannelStrip(width: CGFloat, stripHeight: CGFloat, controlHeight: CGFloat) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 10) {
                HStack {
                    Text("MST")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.orange.opacity(0.9))
                    Spacer()
                    Text("Master")
                        .font(.system(size: 10, weight: .bold))
                }

                Text(model.isPlaying ? "Output" : "Idle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.green.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.green.opacity(0.18))
                    )

                mixerPanKnob(value: 0)

                HStack(spacing: 4) {
                    mixerValueBox("0.0", tint: Color.yellow.opacity(0.9))
                    mixerValueBox(String(format: "%.2f", model.project.master.gain), tint: Color.white.opacity(0.9))
                }
            }
            .frame(maxWidth: .infinity)

            Spacer(minLength: 10)

            HStack(alignment: .bottom, spacing: 14) {
                mixerMeter(level: masterMixerLevel, height: controlHeight - 22)
                mixerFader(value: model.masterGainLiveBinding(), range: 0.0...1.5, height: controlHeight)
            }
            .frame(height: controlHeight, alignment: .bottom)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 14)
            .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))

            Spacer(minLength: 10)

            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    monitorStatusPill(model.engineStatus == "Binary found" ? "OK" : "MISS", tint: model.engineStatus == "Binary found" ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                    monitorStatusPill(model.isPlaying ? "RUN" : "STOP", tint: model.isPlaying ? Color.green.opacity(0.18) : Color.white.opacity(0.08))
                }

                Text("BPM \(Int(model.project.master.bpm.rounded()))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(width: width, height: stripHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private func mixerPanKnob(value: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0.125, to: 0.125 + (0.75 * abs(value)))
                .stroke(value >= 0 ? Color.green.opacity(0.9) : Color.orange.opacity(0.9), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(value >= 0 ? -135 : 135))
            Text(value == 0 ? "C" : (value > 0 ? "R" : "L"))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(.primary)
        }
        .frame(width: 52, height: 52)
    }

    private func mixerValueBox(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.34), in: RoundedRectangle(cornerRadius: 4))
    }

    private func mixerMeter(level: Double, height: CGFloat) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.black.opacity(0.56))
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.95), Color.green.opacity(0.75)],
                                startPoint: .bottom,
                                endPoint: .top
                            )
                        )
                        .frame(height: geometry.size.height * max(0.02, level))
                }
            }
        }
        .frame(width: 18, height: height)
        .overlay(alignment: .leading) {
            VStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { index in
                    Spacer(minLength: 0)
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 18, height: 1)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func mixerFader(value: Binding<Double>, range: ClosedRange<Double> = 0.0...1.25, height: CGFloat) -> some View {
        GeometryReader { geometry in
            let trackWidth: CGFloat = 12
            let thumbSize = CGSize(width: 20, height: 28)
            let usableHeight = max(1, geometry.size.height - thumbSize.height)
            let normalized = CGFloat((value.wrappedValue - range.lowerBound) / (range.upperBound - range.lowerBound))
            let clamped = min(max(normalized, 0), 1)
            let thumbY = usableHeight * (1 - clamped)

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.16))
                    .frame(width: trackWidth)

                VStack(spacing: 0) {
                    Spacer(minLength: thumbY + thumbSize.height / 2)
                    Capsule()
                        .fill(Color.accentColor.opacity(0.95))
                        .frame(width: 8)
                }

                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.98))
                    .frame(width: thumbSize.width, height: thumbSize.height)
                    .shadow(color: Color.black.opacity(0.18), radius: 3, y: 1)
                    .offset(y: thumbY)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let position = min(max(0, gesture.location.y - thumbSize.height / 2), usableHeight)
                        let newNormalized = 1 - (position / usableHeight)
                        let newValue = range.lowerBound + Double(newNormalized) * (range.upperBound - range.lowerBound)
                        value.wrappedValue = min(max(range.lowerBound, newValue), range.upperBound)
                    }
            )
        }
        .frame(width: 26, height: height)
    }

    private func compactNumberField(_ title: String, value: Binding<Double>, width: CGFloat, precision: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            TextField("", value: value, format: .number.precision(.fractionLength(precision)))
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
    }

    private func compactIntField(_ title: String, value: Binding<Int>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            TextField("", value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
    }

    private func compactTimeSignatureBottomPicker(title: String, value: Binding<Int>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: value) {
                ForEach([1, 2, 4, 8, 16], id: \.self) { denominator in
                    Text("\(denominator)").tag(denominator)
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
    }

    private func compactBusRoutePicker(title: String, selection: Binding<UUID?>, width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Picker("", selection: selection) {
                Text("Master").tag(UUID?.none)
                ForEach(model.project.buses) { bus in
                    Text(bus.name).tag(UUID?.some(bus.id))
                }
            }
            .labelsHidden()
            .frame(width: width)
        }
        .frame(width: width, alignment: .leading)
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .fixedSize()
    }

    private func monitorMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.94))
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }

    private func monitorStatusPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(Color.white.opacity(0.92))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(tint, in: Capsule())
            .fixedSize()
    }

    private func transportSubsection<Content: View>(
        title: String,
        width: CGFloat? = nil,
        fill: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(width: width, alignment: .leading)
        .frame(maxWidth: fill ? .infinity : nil, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.32))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.34), lineWidth: 1)
                )
        )
    }

    private var transportDeckBackground: some ShapeStyle {
        LinearGradient(
            colors: [
                Color(nsColor: .textBackgroundColor).opacity(0.92),
                Color(nsColor: .controlBackgroundColor).opacity(0.78)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func headerPill(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint, in: Capsule())
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

    private var followBarAnchor: Int {
        if usesIndependentTrackPlayheads, let firstTrack = model.project.tracks.first {
            return barAnchor(forX: lanePlayheadX(for: firstTrack))
        }
        return currentBarAnchor
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
        let targetBar = min(model.project.master.loopBars, max(1, followBarAnchor + followLookAheadBars))
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

    private func sidebarTrackBackground(_ track: Track) -> Color {
        if track.id == model.selectedTrackID {
            return Color.accentColor.opacity(0.08)
        }
        if track.solo {
            return Color.yellow.opacity(0.05)
        }
        if !track.enabled {
            return Color.gray.opacity(0.06)
        }
        return Color.black.opacity(0.10)
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

    private func trackIndexLabel(for track: Track) -> String {
        if let index = model.project.tracks.firstIndex(where: { $0.id == track.id }) {
            return "T\(index + 1)"
        }
        return "T"
    }

    private func routeLabel(for track: Track) -> String {
        if let outputBusID = track.outputBusID,
           let bus = model.project.buses.first(where: { $0.id == outputBusID }) {
            return "Out \(bus.name)"
        }
        return "Out Master"
    }

    private func routeShortLabel(for track: Track) -> String {
        if let outputBusID = track.outputBusID,
           let bus = model.project.buses.first(where: { $0.id == outputBusID }) {
            return bus.name
        }
        return "Master"
    }

    private func mixerLevel(for track: Track) -> Double {
        guard model.isPlaying, trackIsAudible(track) else { return 0.0 }
        let active = track.clips.contains { clip in
            currentTransportStep >= clip.startStep && currentTransportStep < (clip.startStep + clip.lengthSteps)
        }
        guard active else { return 0.06 }

        let trackIndex = Double(trackRowIndex(track) + 1)
        let time = Date().timeIntervalSinceReferenceDate
        let bpmFactor = max(1.4, model.project.master.bpm / 42.0)
        let fastPulse = (sin((time * bpmFactor * 5.8) + trackIndex * 0.9) + 1.0) * 0.5
        let microPulse = (sin((time * bpmFactor * 13.0) + trackIndex * 2.1) + 1.0) * 0.5
        let clipWeight = min(1.0, Double(max(1, track.clips.count)) / 4.0)
        let gainWeight = min(1.0, track.gain / 1.25)
        let level = 0.16 + fastPulse * 0.42 + microPulse * 0.18 + gainWeight * 0.16 + clipWeight * 0.08
        return min(1.0, level)
    }

    private func busMixerLevel(for bus: Bus) -> Double {
        guard model.isPlaying else { return 0.0 }
        let routedTracks = model.project.tracks.filter { track in
            track.outputBusID == bus.id && trackIsAudible(track)
        }
        guard !routedTracks.isEmpty else { return 0.03 }
        let average = routedTracks.map(mixerLevel(for:)).reduce(0, +) / Double(routedTracks.count)
        return min(1.0, average * bus.gain)
    }

    private var masterMixerLevel: Double {
        guard model.isPlaying else { return 0.0 }
        let masterTracks = model.project.tracks.filter { $0.outputBusID == nil && trackIsAudible($0) }
        let directTrackAverage = masterTracks.isEmpty ? 0.0 : (masterTracks.map(mixerLevel(for:)).reduce(0, +) / Double(masterTracks.count))
        let activeBuses = model.project.buses.filter { bus in
            model.project.tracks.contains { $0.outputBusID == bus.id && trackIsAudible($0) }
        }
        let busAverage = activeBuses.isEmpty ? 0.0 : (activeBuses.map(busMixerLevel(for:)).reduce(0, +) / Double(activeBuses.count))
        let combined = max(directTrackAverage, busAverage * 0.96)
        return min(1.0, max(0.04, combined) * model.project.master.gain)
    }

    private var currentTransportStep: Int {
        let raw = Int(floor((model.transportBarPosition - 1.0) * 16.0))
        return min(model.project.master.cycleEndBar * 16 - 1, max((model.project.master.cycleStartBar - 1) * 16, raw))
    }

    private func lanePlayheadX(for track: Track) -> CGFloat {
        if usesIndependentTrackPlayheads {
            let cycleStartSteps = Double((model.project.master.cycleStartBar - 1) * 16)
            let cycleLengthSteps = Double(max(16, (model.project.master.cycleEndBar - model.project.master.cycleStartBar + 1) * 16))
            let masterStepPosition = ((model.transportBarPosition - 1.0) * 16.0) - cycleStartSteps
            let wrappedTrackSteps = (masterStepPosition * max(0.125, track.tempoRatio))
                .truncatingRemainder(dividingBy: cycleLengthSteps)
            let normalizedTrackSteps = wrappedTrackSteps >= 0 ? wrappedTrackSteps : wrappedTrackSteps + cycleLengthSteps
            return CGFloat(normalizedTrackSteps) * pixelsPerStep
        }
        return playheadX
    }

    private var primaryFollowTrack: Track? {
        model.project.tracks.first
    }

    private func localPlayheadDisplay(for track: Track) -> String {
        let masterBeatsFromCycleStart = max(0, (model.transportBarPosition - Double(model.project.master.cycleStartBar)) * 4.0)
        let localQuarterBeats = masterBeatsFromCycleStart * max(0.125, track.tempoRatio)
        let beatsPerLocalBar = Double(track.timeSignatureTop) * (4.0 / Double(max(1, track.timeSignatureBottom)))
        guard beatsPerLocalBar > 0 else { return "1.1.1" }

        let localBarFloat = localQuarterBeats / beatsPerLocalBar
        let localBar = Int(floor(localBarFloat)) + 1
        let beatWithinBarFloat = (localBarFloat - floor(localBarFloat)) * beatsPerLocalBar
        let localBeat = Int(floor(beatWithinBarFloat)) + 1
        let sixteenthWithinBeat = Int(floor((beatWithinBarFloat - floor(beatWithinBarFloat)) * 4.0)) + 1
        return "\(localBar).\(max(1, localBeat)).\(min(4, max(1, sixteenthWithinBeat)))"
    }

    private func barAnchor(forX x: CGFloat) -> Int {
        let step = barWidth + barGap
        guard step > 0 else { return 1 }
        let bar = Int(floor(x / step)) + 1
        return min(model.project.master.loopBars, max(1, bar))
    }

    private var usesIndependentTrackPlayheads: Bool {
        let audibleTracks = model.project.tracks.filter { trackIsAudible($0) }
        guard let firstTrack = audibleTracks.first else { return false }
        return audibleTracks.dropFirst().contains { abs($0.tempoRatio - firstTrack.tempoRatio) > 0.0001 }
    }

    private func overviewTrackPlayheadX(track: Track, width: CGFloat) -> CGFloat {
        let ratio = timelineWidth > 0 ? lanePlayheadX(for: track) / timelineWidth : 0
        return width * ratio
    }

    private func scrubTrackPlayheadX(track: Track, width: CGFloat) -> CGFloat {
        let ratio = timelineWidth > 0 ? lanePlayheadX(for: track) / timelineWidth : 0
        return width * ratio
    }

    private func playheadFill(for track: Track) -> LinearGradient {
        if usesIndependentTrackPlayheads {
            let isTrackOne = model.project.tracks.first?.id == track.id
            let top = isTrackOne ? Color.orange.opacity(0.98) : Color.cyan.opacity(0.95)
            let bottom = isTrackOne ? Color.red.opacity(0.76) : Color.blue.opacity(0.72)
            return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
        }
        return LinearGradient(
            colors: [Color.white.opacity(0.98), Color.accentColor.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func playheadShadowColor(for track: Track) -> Color {
        if usesIndependentTrackPlayheads {
            return (model.project.tracks.first?.id == track.id ? Color.orange : Color.cyan).opacity(0.55)
        }
        return Color.accentColor.opacity(0.55)
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

    private var selectedBus: Bus? {
        guard let selectedBusID = model.selectedBusID else { return nil }
        return model.project.buses.first(where: { $0.id == selectedBusID })
    }
}
