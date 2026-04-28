import Foundation
import SwiftUI

enum TimelineSnapMode: String, CaseIterable, Identifiable {
    case bar = "Bars"
    case beat = "Beats"
    case sixteenth = "1/16"

    var id: String { rawValue }

    var unitBars: Double {
        switch self {
        case .bar:
            return 1.0
        case .beat:
            return 0.25
        case .sixteenth:
            return 0.0625
        }
    }

    var unitSteps: Int {
        switch self {
        case .bar: return 16
        case .beat: return 4
        case .sixteenth: return 1
        }
    }
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var project: Project
    @Published var selectedTrackID: UUID?
    @Published var selectedClipID: UUID?
    @Published var selectedClipIDs: Set<UUID> = []
    @Published var compiledCode: String = ""
    @Published var logMessages: [String] = ["ChuckDAW ready."]
    @Published var chuckPath: String
    @Published var isPlaying = false
    @Published var selectedPreset: PresetLibrary = .codeTape
    @Published var engineStatus: String
    @Published var transportBarPosition: Double = 1.0
    @Published var followPlayhead = true
    @Published var timelineZoom: Double = 1.0
    @Published var snapMode: TimelineSnapMode = .bar

    private let processManager = ChuckProcessManager()
    private var transportStartDate: Date?
    private var transportTimer: Timer?

    init() {
        let stored = Self.loadSavedState()
        let initialProject = TimelineCompiler.normalize(stored?.project ?? Project.defaultProject())
        let initialChuckPath = stored?.chuckPath ?? Self.defaultChuckPath()
        self.project = initialProject
        self.selectedTrackID = initialProject.tracks.first?.id
        self.selectedClipID = initialProject.tracks.first?.clips.first?.id
        self.selectedClipIDs = initialProject.tracks.first?.clips.first.map { [$0.id] } ?? []
        self.chuckPath = initialChuckPath
        self.engineStatus = Self.describeBinary(at: initialChuckPath)
        compile()
    }

    var stats: ProjectStats {
        TimelineCompiler.stats(for: project)
    }

    var selectedTrackIndex: Int? {
        project.tracks.firstIndex(where: { $0.id == selectedTrackID })
    }

    var selectedClipIndex: Int? {
        guard let trackIndex = selectedTrackIndex else { return nil }
        return project.tracks[trackIndex].clips.firstIndex(where: { $0.id == selectedClipID })
    }

    func projectBinding<Value>(_ keyPath: WritableKeyPath<Project, Value>) -> Binding<Value> {
        Binding(
            get: { self.project[keyPath: keyPath] },
            set: { newValue in
                self.project[keyPath: keyPath] = newValue
                self.projectDidChange()
            }
        )
    }

    func masterBinding<Value>(_ keyPath: WritableKeyPath<MasterSettings, Value>) -> Binding<Value> {
        Binding(
            get: { self.project.master[keyPath: keyPath] },
            set: { newValue in
                self.project.master[keyPath: keyPath] = newValue
                self.projectDidChange()
            }
        )
    }

    func chuckPathBinding() -> Binding<String> {
        Binding(
            get: { self.chuckPath },
            set: { newValue in
                self.chuckPath = newValue
                self.engineStatus = Self.describeBinary(at: newValue)
                self.saveState()
            }
        )
    }

    func selectedTrackBinding<Value>(_ keyPath: WritableKeyPath<Track, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                guard let trackIndex = self.selectedTrackIndex else { return fallback }
                return self.project.tracks[trackIndex][keyPath: keyPath]
            },
            set: { newValue in
                guard let trackIndex = self.selectedTrackIndex else { return }
                self.project.tracks[trackIndex][keyPath: keyPath] = newValue
                self.projectDidChange()
            }
        )
    }

    func selectedClipBinding<Value>(_ keyPath: WritableKeyPath<ClipRegion, Value>, fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                guard let trackIndex = self.selectedTrackIndex, let clipIndex = self.selectedClipIndex else { return fallback }
                return self.project.tracks[trackIndex].clips[clipIndex][keyPath: keyPath]
            },
            set: { newValue in
                guard let trackIndex = self.selectedTrackIndex, let clipIndex = self.selectedClipIndex else { return }
                self.project.tracks[trackIndex].clips[clipIndex][keyPath: keyPath] = newValue
                self.projectDidChange()
            }
        )
    }

    func addTrack() {
        let track = Track.make(name: "Track \(project.tracks.count + 1)")
        project.tracks.append(track)
        selectedTrackID = track.id
        selectedClipID = nil
        selectedClipIDs = []
        projectDidChange()
    }

    func removeSelectedTrack() {
        guard let currentSelectedTrackID = selectedTrackID,
              let index = project.tracks.firstIndex(where: { $0.id == currentSelectedTrackID }) else { return }
        project.tracks.remove(at: index)
        self.selectedTrackID = project.tracks.first?.id
        selectedClipID = project.tracks.first?.clips.first?.id
        selectedClipIDs = project.tracks.first?.clips.first.map { [$0.id] } ?? []
        projectDidChange()
    }

    func addClip() {
        guard let trackIndex = selectedTrackIndex else { return }
        let nextStart = project.tracks[trackIndex].clips.map { $0.startStep + $0.lengthSteps }.max() ?? 0
        let clip = ClipRegion.make(name: "Clip \(project.tracks[trackIndex].clips.count + 1)", startStep: nextStart, lengthSteps: 16, code: "regionDur => now;")
        project.tracks[trackIndex].clips.append(clip)
        selectedClipID = clip.id
        selectedClipIDs = [clip.id]
        projectDidChange()
    }

    func moveClip(trackID: UUID, clipID: UUID, startStep: Int) {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = project.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else { return }
        let track = project.tracks[trackIndex]
        let clip = track.clips[clipIndex]
        let maxStart = maximumStartStep(for: clip, on: track)
        let minStart = minimumStartStep(for: clip, on: track)
        project.tracks[trackIndex].clips[clipIndex].startStep = min(max(minStart, startStep), maxStart)
        projectDidChange()
    }

    func moveClip(trackID: UUID, clipID: UUID, startStep: Int, targetTrackOffset: Int, duplicate: Bool) {
        if !duplicate, selectedClipIDs.contains(clipID), selectedClipIDs.count > 1 {
            moveSelectedClips(primaryTrackID: trackID, primaryClipID: clipID, startStep: startStep, duplicate: false)
            return
        }
        guard let sourceTrackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              let sourceClipIndex = project.tracks[sourceTrackIndex].clips.firstIndex(where: { $0.id == clipID }) else { return }

        let targetTrackIndex = min(
            max(0, sourceTrackIndex + targetTrackOffset),
            max(0, project.tracks.count - 1)
        )

        let originalClip = project.tracks[sourceTrackIndex].clips[sourceClipIndex]
        var destinationClip = originalClip
        if duplicate {
            destinationClip.id = UUID()
            destinationClip.name = uniqueClipName(
                basedOn: originalClip.name,
                in: project.tracks[targetTrackIndex]
            )
        } else if sourceTrackIndex != targetTrackIndex {
            project.tracks[sourceTrackIndex].clips.remove(at: sourceClipIndex)
        }

        let destinationTrack = project.tracks[targetTrackIndex]
        let proposedStart = boundedStartStep(for: destinationClip, on: destinationTrack, proposed: startStep)
        destinationClip.startStep = proposedStart

        if duplicate || sourceTrackIndex != targetTrackIndex {
            project.tracks[targetTrackIndex].clips.append(destinationClip)
            project.tracks[targetTrackIndex].clips.sort { lhs, rhs in
                if lhs.startStep == rhs.startStep {
                    return lhs.name < rhs.name
                }
                return lhs.startStep < rhs.startStep
            }
            selectedTrackID = project.tracks[targetTrackIndex].id
            selectedClipID = destinationClip.id
            selectedClipIDs = [destinationClip.id]
        } else {
            project.tracks[targetTrackIndex].clips[sourceClipIndex].startStep = proposedStart
            selectedClipIDs = [clipID]
        }

        projectDidChange()
    }

    func resizeClip(trackID: UUID, clipID: UUID, lengthSteps: Int) {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }),
              let clipIndex = project.tracks[trackIndex].clips.firstIndex(where: { $0.id == clipID }) else { return }
        let track = project.tracks[trackIndex]
        let clip = track.clips[clipIndex]
        let maxLength = maximumLengthSteps(for: clip, on: track)
        project.tracks[trackIndex].clips[clipIndex].lengthSteps = min(max(1, lengthSteps), maxLength)
        projectDidChange()
    }

    func removeSelectedClip() {
        if selectedClipIDs.count > 1 {
            removeSelectedClips()
            return
        }
        guard let trackIndex = selectedTrackIndex, let clipIndex = selectedClipIndex else { return }
        project.tracks[trackIndex].clips.remove(at: clipIndex)
        selectedClipID = project.tracks[trackIndex].clips.first?.id
        selectedClipIDs = project.tracks[trackIndex].clips.first.map { [$0.id] } ?? []
        projectDidChange()
    }

    func selectTrack(_ trackID: UUID) {
        selectedTrackID = trackID
        if let track = project.tracks.first(where: { $0.id == trackID }) {
            selectedClipID = track.clips.first?.id
            selectedClipIDs = track.clips.first.map { [$0.id] } ?? []
        } else {
            selectedClipID = nil
            selectedClipIDs = []
        }
    }

    func selectClip(trackID: UUID, clipID: UUID) {
        selectedTrackID = trackID
        selectedClipID = clipID
        selectedClipIDs = [clipID]
    }

    func selectClips(_ clipIDs: Set<UUID>) {
        selectedClipIDs = clipIDs
        if let first = project.tracks
            .flatMap(\.clips)
            .first(where: { clipIDs.contains($0.id) }) {
            selectedClipID = first.id
            if let track = project.tracks.first(where: { $0.clips.contains(where: { $0.id == first.id }) }) {
                selectedTrackID = track.id
            }
        } else {
            selectedClipID = nil
        }
    }

    func removeSelectedClips() {
        guard !selectedClipIDs.isEmpty else { return }
        let ids = selectedClipIDs
        for trackIndex in project.tracks.indices {
            project.tracks[trackIndex].clips.removeAll { ids.contains($0.id) }
        }
        selectedClipID = nil
        selectedClipIDs = []
        if let firstTrackWithClip = project.tracks.first(where: { !$0.clips.isEmpty }),
           let firstClip = firstTrackWithClip.clips.first {
            selectedTrackID = firstTrackWithClip.id
            selectedClipID = firstClip.id
            selectedClipIDs = [firstClip.id]
        }
        projectDidChange()
    }

    func nudgeSelectedClips(bySteps deltaSteps: Int) {
        guard !selectedClipIDs.isEmpty, deltaSteps != 0 else { return }
        moveSelectedClipsBy(deltaSteps: deltaSteps, trackOffset: 0)
    }

    func moveSelectedClipsBetweenTracks(_ offset: Int) {
        guard !selectedClipIDs.isEmpty, offset != 0 else { return }
        moveSelectedClipsBy(deltaSteps: 0, trackOffset: offset)
    }

    func toggleTrackEnabled(_ trackID: UUID) {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[trackIndex].enabled.toggle()
        projectDidChange()
    }

    func toggleTrackSolo(_ trackID: UUID) {
        guard let trackIndex = project.tracks.firstIndex(where: { $0.id == trackID }) else { return }
        project.tracks[trackIndex].solo.toggle()
        projectDidChange()
    }

    func loadPreset() {
        project = selectedPreset.build()
        selectedTrackID = project.tracks.first?.id
        selectedClipID = project.tracks.first?.clips.first?.id
        selectedClipIDs = project.tracks.first?.clips.first.map { [$0.id] } ?? []
        transportBarPosition = Double(project.master.cycleStartBar)
        projectDidChange()
        pushLog("Loaded preset \(selectedPreset.rawValue).")
    }

    func resetProject() {
        project = Project.defaultProject()
        selectedTrackID = project.tracks.first?.id
        selectedClipID = project.tracks.first?.clips.first?.id
        selectedClipIDs = project.tracks.first?.clips.first.map { [$0.id] } ?? []
        transportBarPosition = Double(project.master.cycleStartBar)
        projectDidChange()
        pushLog("Project reset.")
    }

    func compile() {
        compiledCode = TimelineCompiler.buildChuckProgram(project: project, projectRoot: projectRootPath, startStep: currentTransportStep)
        saveState()
    }

    func startPlayback() {
        compile()
        let startStep = currentTransportStep
        Task { [weak self] in
            await self?.performStartPlayback(startStep: startStep)
        }
    }

    func stopPlayback() {
        isPlaying = false
        stopTransportClock(resetPosition: false)

        pushLog("Transport stopped.")
        Task { [weak self] in
            await self?.performStopPlayback()
        }
    }

    func panicKillAllAudio() {
        isPlaying = false
        stopTransportClock(resetPosition: false)
        pushLog("Panic stop requested.")

        Task { [weak self] in
            await self?.performPanicKillAllAudio()
        }
    }

    func autoDetectBinary() {
        let path = Self.defaultChuckPath()
        chuckPath = path
        engineStatus = Self.describeBinary(at: path)
        saveState()
        pushLog("Using ChucK binary at \(path)")
    }

    func refreshEngineStatus() {
        engineStatus = Self.describeBinary(at: chuckPath)
        saveState()
    }

    func testEngine() {
        let testPatch = """
        SinOsc osc => dac;
        660 => osc.freq;
        0.18 => osc.gain;
        220::ms => now;
        """

        Task { [weak self] in
            await self?.performTestEngine(testPatch: testPatch)
        }
    }

    func pushLog(_ message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let timestamp = Self.timestampFormatter.string(from: Date())
        logMessages.insert("[\(timestamp)] \(trimmed)", at: 0)
        logMessages = Array(logMessages.prefix(40))
    }

    func setTransportBarPosition(_ position: Double) {
        transportBarPosition = min(max(Double(project.master.cycleStartBar), position), Double(project.master.cycleEndBar) + 0.999)
        if isPlaying {
            let secondsPerBar = (60.0 / project.master.bpm) * 4.0
            transportStartDate = Date().addingTimeInterval(-((transportBarPosition - Double(project.master.cycleStartBar)) * secondsPerBar))
            let startStep = currentTransportStep
            Task { [weak self] in
                await self?.performReloadPersistentSession(startStep: startStep)
            }
        }
    }

    func setCycleRange(start: Int? = nil, end: Int? = nil) {
        if let start {
            project.master.cycleStartBar = start
        }
        if let end {
            project.master.cycleEndBar = end
        }
        projectDidChange()
        if transportBarPosition < Double(project.master.cycleStartBar) || transportBarPosition > Double(project.master.cycleEndBar) + 0.999 {
            transportBarPosition = Double(project.master.cycleStartBar)
        }
    }

    private func projectDidChange() {
        project = TimelineCompiler.normalize(project)
        compile()
        if isPlaying {
            let startStep = currentTransportStep
            Task { [weak self] in
                await self?.performReloadPersistentSession(startStep: startStep)
            }
        }
    }

    private func startTransportClock() {
        stopTransportClock(resetPosition: false)
        let secondsPerBar = (60.0 / project.master.bpm) * 4.0
        transportStartDate = Date().addingTimeInterval(-((transportBarPosition - Double(project.master.cycleStartBar)) * secondsPerBar))
        transportTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTransportPosition()
            }
        }
    }

    private func stopTransportClock(resetPosition: Bool) {
        transportTimer?.invalidate()
        transportTimer = nil
        transportStartDate = nil
        if resetPosition {
            transportBarPosition = 1
        }
    }

    private func updateTransportPosition() {
        guard let transportStartDate else { return }
        let elapsed = Date().timeIntervalSince(transportStartDate)
        let secondsPerBar = (60.0 / project.master.bpm) * 4.0
        let cycleLength = max(1, project.master.cycleEndBar - project.master.cycleStartBar + 1)
        let loopDuration = secondsPerBar * Double(cycleLength)
        guard loopDuration > 0 else {
            transportBarPosition = Double(project.master.cycleStartBar)
            return
        }
        let looped = elapsed.truncatingRemainder(dividingBy: loopDuration)
        transportBarPosition = Double(project.master.cycleStartBar) + (looped / secondsPerBar)
    }

    private func minimumStartStep(for clip: ClipRegion, on track: Track) -> Int {
        let previousClipEnd = track.clips
            .filter { $0.id != clip.id && $0.startStep < clip.startStep }
            .map { $0.startStep + $0.lengthSteps }
            .max() ?? 0
        return max(0, previousClipEnd)
    }

    private func maximumStartStep(for clip: ClipRegion, on track: Track) -> Int {
        let nextClipStart = track.clips
            .filter { $0.id != clip.id && $0.startStep > clip.startStep }
            .map(\.startStep)
            .min() ?? totalTimelineSteps
        let byLoop = totalTimelineSteps - clip.lengthSteps
        let byNeighbor = nextClipStart - clip.lengthSteps
        return max(0, min(byLoop, byNeighbor))
    }

    private func maximumLengthSteps(for clip: ClipRegion, on track: Track) -> Int {
        let nextClipStart = track.clips
            .filter { $0.id != clip.id && $0.startStep > clip.startStep }
            .map(\.startStep)
            .min() ?? totalTimelineSteps
        let byLoop = totalTimelineSteps - clip.startStep
        let byNeighbor = nextClipStart - clip.startStep
        return max(1, min(byLoop, byNeighbor))
    }

    private func boundedStartStep(for clip: ClipRegion, on track: Track, proposed: Int) -> Int {
        let maxStart = maximumStartStep(for: clip, on: track)
        let minStart = minimumStartStep(for: clip, on: track)
        return min(max(minStart, proposed), maxStart)
    }

    private func uniqueClipName(basedOn baseName: String, in track: Track) -> String {
        let existing = Set(track.clips.map(\.name))
        guard existing.contains(baseName) else { return baseName }
        var suffix = 2
        while existing.contains("\(baseName) \(suffix)") {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func moveSelectedClips(primaryTrackID: UUID, primaryClipID: UUID, startStep: Int, duplicate: Bool) {
        guard let primaryTrackIndex = project.tracks.firstIndex(where: { $0.id == primaryTrackID }),
              let primaryClip = project.tracks[primaryTrackIndex].clips.first(where: { $0.id == primaryClipID }) else { return }

        let deltaSteps = startStep - primaryClip.startStep
        moveSelectedClipsBy(deltaSteps: deltaSteps, trackOffset: 0)
        selectedClipID = primaryClipID
    }

    private func moveSelectedClipsBy(deltaSteps: Int, trackOffset: Int) {
        let ids = selectedClipIDs
        guard !ids.isEmpty else { return }

        var movedSelections: [(trackIndex: Int, clipID: UUID)] = []

        for sourceTrackIndex in project.tracks.indices {
            let matchingClips = project.tracks[sourceTrackIndex].clips.filter { ids.contains($0.id) }
            guard !matchingClips.isEmpty else { continue }

            for clip in matchingClips {
                let targetTrackIndex = min(
                    max(0, sourceTrackIndex + trackOffset),
                    max(0, project.tracks.count - 1)
                )

                if sourceTrackIndex == targetTrackIndex {
                    guard let clipIndex = project.tracks[sourceTrackIndex].clips.firstIndex(where: { $0.id == clip.id }) else { continue }
                    let proposed = clip.startStep + deltaSteps
                    let bounded = boundedStartStep(for: clip, on: project.tracks[sourceTrackIndex], proposed: proposed)
                    project.tracks[sourceTrackIndex].clips[clipIndex].startStep = bounded
                    movedSelections.append((trackIndex: sourceTrackIndex, clipID: clip.id))
                } else {
                    guard let clipIndex = project.tracks[sourceTrackIndex].clips.firstIndex(where: { $0.id == clip.id }) else { continue }
                    project.tracks[sourceTrackIndex].clips.remove(at: clipIndex)
                    let destinationTrack = project.tracks[targetTrackIndex]
                    var movedClip = clip
                    let proposed = clip.startStep + deltaSteps
                    movedClip.startStep = boundedStartStep(for: movedClip, on: destinationTrack, proposed: proposed)
                    project.tracks[targetTrackIndex].clips.append(movedClip)
                    movedSelections.append((trackIndex: targetTrackIndex, clipID: movedClip.id))
                }
            }
        }

        for trackIndex in project.tracks.indices {
            project.tracks[trackIndex].clips.sort {
                if $0.startStep == $1.startStep { return $0.name < $1.name }
                return $0.startStep < $1.startStep
            }
        }

        selectedClipIDs = Set(movedSelections.map(\.clipID))
        if let first = movedSelections.first {
            selectedTrackID = project.tracks[first.trackIndex].id
            selectedClipID = first.clipID
        }
        projectDidChange()
    }

    private func saveState() {
        do {
            let state = SavedState(project: project, chuckPath: chuckPath)
            let data = try JSONEncoder().encode(state)
            try data.write(to: Self.saveURL, options: .atomic)
        } catch {
            pushLog("Autosave failed: \(error.localizedDescription)")
        }
    }

    private static func loadSavedState() -> SavedState? {
        guard let data = try? Data(contentsOf: saveURL) else { return nil }
        return try? JSONDecoder().decode(SavedState.self, from: data)
    }

    private static func defaultChuckPath() -> String {
        let candidates = [
            Bundle.main.bundleURL
                .deletingLastPathComponent()
                .appendingPathComponent("Vendor/chuck/src/chuck")
                .path,
            "/opt/homebrew/bin/chuck",
            "/usr/local/bin/chuck",
            "\(FileManager.default.currentDirectoryPath)/Vendor/chuck/src/chuck"
        ]
        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) ?? candidates[0]
    }

    private static let saveURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folder = appSupport.appendingPathComponent("ChuckDAW", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("state.json")
    }()

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static func describeBinary(at path: String) -> String {
        FileManager.default.fileExists(atPath: path) ? "Binary found" : "Binary not found"
    }

    private var currentTransportStep: Int {
        let raw = Int(floor((transportBarPosition - 1.0) * 16.0))
        return min(project.master.cycleEndBar * 16 - 1, max((project.master.cycleStartBar - 1) * 16, raw))
    }

    private func reloadPersistentSession(startStep: Int) async throws {
        let liveCode = TimelineCompiler.buildChuckProgram(project: project, projectRoot: projectRootPath, startStep: startStep)
        compiledCode = liveCode
        let chuckPath = self.chuckPath
        let processManager = self.processManager
        try await runBlockingProcessWork {
            try processManager.ensureLoopRunning(chuckPath: chuckPath) { [weak self] message in
                Task { @MainActor in
                    self?.pushLog(message)
                }
            }
            try processManager.removeAllShreds(chuckPath: chuckPath) { [weak self] message in
                Task { @MainActor in
                    self?.pushLog(message)
                }
            }
            try processManager.addShred(code: liveCode, chuckPath: chuckPath, name: "session-controller") { [weak self] message in
                Task { @MainActor in
                    self?.pushLog(message)
                }
            }
        }
    }

    private var projectRootPath: String {
        let vendorSuffix = "/Vendor/chuck/src/chuck"
        if chuckPath.hasSuffix(vendorSuffix) {
            let root = String(chuckPath.dropLast(vendorSuffix.count))
            if FileManager.default.fileExists(atPath: root + "/Vendor/chuck/examples/data") {
                return root
            }
        }

        let candidates = [
            FileManager.default.currentDirectoryPath,
            Bundle.main.bundleURL.deletingLastPathComponent().path
        ]

        return candidates.first {
            FileManager.default.fileExists(atPath: $0 + "/Vendor/chuck/examples/data")
        } ?? FileManager.default.currentDirectoryPath
    }

    private func performStartPlayback(startStep: Int) async {
        do {
            try await reloadPersistentSession(startStep: startStep)
            isPlaying = true
            startTransportClock()
            pushLog("Transport started in persistent engine mode.")
        } catch {
            pushLog(error.localizedDescription)
        }
    }

    private func performStopPlayback() async {
        let chuckPath = self.chuckPath
        let processManager = self.processManager
        do {
            try await runBlockingProcessWork {
                try processManager.stop { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
                try processManager.removeAllShreds(chuckPath: chuckPath) { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
                try processManager.exitLoop(chuckPath: chuckPath) { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
                processManager.shutdownLoop { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
            }
        } catch {
            pushLog(error.localizedDescription)
        }
    }

    private func performPanicKillAllAudio() async {
        let processManager = self.processManager
        do {
            try await runBlockingProcessWork {
                try processManager.forceKillAllChuckAudio { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
            }
        } catch {
            pushLog(error.localizedDescription)
        }
    }

    private func performTestEngine(testPatch: String) async {
        let chuckPath = self.chuckPath
        let processManager = self.processManager
        do {
            try await runBlockingProcessWork {
                try processManager.play(code: testPatch, chuckPath: chuckPath) { [weak self] message in
                    Task { @MainActor in
                        self?.pushLog(message)
                    }
                }
            }
            isPlaying = true
            pushLog("Running short audio engine test.")

            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(400))
                self?.isPlaying = false
            }
        } catch {
            pushLog(error.localizedDescription)
        }
    }

    private func performReloadPersistentSession(startStep: Int) async {
        do {
            try await reloadPersistentSession(startStep: startStep)
        } catch {
            pushLog(error.localizedDescription)
        }
    }

    private var totalTimelineSteps: Int {
        project.master.loopBars * 16
    }

    private func runBlockingProcessWork(_ work: @Sendable @escaping () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
