import Foundation

struct MasterSettings: Codable, Equatable {
    var bpm: Double
    var gain: Double
    var loopBars: Int
    var cycleStartBar: Int
    var cycleEndBar: Int

    init(bpm: Double, gain: Double, loopBars: Int, cycleStartBar: Int = 1, cycleEndBar: Int? = nil) {
        self.bpm = bpm
        self.gain = gain
        self.loopBars = loopBars
        self.cycleStartBar = cycleStartBar
        self.cycleEndBar = cycleEndBar ?? loopBars
    }

    enum CodingKeys: String, CodingKey {
        case bpm
        case gain
        case loopBars
        case cycleStartBar
        case cycleEndBar
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bpm = try container.decode(Double.self, forKey: .bpm)
        gain = try container.decode(Double.self, forKey: .gain)
        loopBars = try container.decode(Int.self, forKey: .loopBars)
        cycleStartBar = try container.decodeIfPresent(Int.self, forKey: .cycleStartBar) ?? 1
        cycleEndBar = try container.decodeIfPresent(Int.self, forKey: .cycleEndBar) ?? loopBars
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bpm, forKey: .bpm)
        try container.encode(gain, forKey: .gain)
        try container.encode(loopBars, forKey: .loopBars)
        try container.encode(cycleStartBar, forKey: .cycleStartBar)
        try container.encode(cycleEndBar, forKey: .cycleEndBar)
    }
}

struct ClipRegion: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var startStep: Int
    var lengthSteps: Int
    var code: String

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case startStep
        case lengthSteps
        case startBar
        case lengthBars
        case code
    }

    init(id: UUID, name: String, startStep: Int, lengthSteps: Int, code: String) {
        self.id = id
        self.name = name
        self.startStep = startStep
        self.lengthSteps = lengthSteps
        self.code = code
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        if let startStep = try container.decodeIfPresent(Int.self, forKey: .startStep) {
            self.startStep = startStep
        } else {
            let legacyStartBar = try container.decodeIfPresent(Int.self, forKey: .startBar) ?? 1
            self.startStep = max(0, (legacyStartBar - 1) * 16)
        }
        if let lengthSteps = try container.decodeIfPresent(Int.self, forKey: .lengthSteps) {
            self.lengthSteps = lengthSteps
        } else {
            let legacyLengthBars = try container.decodeIfPresent(Int.self, forKey: .lengthBars) ?? 1
            self.lengthSteps = max(1, legacyLengthBars * 16)
        }
        code = try container.decode(String.self, forKey: .code)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(startStep, forKey: .startStep)
        try container.encode(lengthSteps, forKey: .lengthSteps)
        try container.encode(code, forKey: .code)
    }
}

struct RenderedTrackAudio: Codable, Equatable {
    var filePath: String
    var startStep: Int
    var lengthSteps: Int
    var durationSeconds: Double
    var waveform: [Float]
}

struct DeviceSlot: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var filePath: String
    var isEnabled: Bool

    init(id: UUID = UUID(), name: String, filePath: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.filePath = filePath
        self.isEnabled = isEnabled
    }
}

struct Bus: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var gain: Double
    var pan: Double
    var deviceSlots: [DeviceSlot]
    var effectCode: String

    init(id: UUID, name: String, gain: Double = 1.0, pan: Double = 0.0, deviceSlots: [DeviceSlot] = [], effectCode: String = "busIn => busOut;") {
        self.id = id
        self.name = name
        self.gain = gain
        self.pan = pan
        self.deviceSlots = deviceSlots
        self.effectCode = effectCode
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case gain
        case pan
        case deviceSlots
        case effectCode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 1.0
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0.0
        deviceSlots = try container.decodeIfPresent([DeviceSlot].self, forKey: .deviceSlots) ?? []
        effectCode = try container.decodeIfPresent(String.self, forKey: .effectCode) ?? "busIn => busOut;"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(gain, forKey: .gain)
        try container.encode(pan, forKey: .pan)
        try container.encode(deviceSlots, forKey: .deviceSlots)
        try container.encode(effectCode, forKey: .effectCode)
    }
}

struct BusSend: Codable, Equatable {
    var busID: UUID
    var level: Double
}

struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var enabled: Bool
    var solo: Bool
    var gain: Double
    var pan: Double
    var deviceSlots: [DeviceSlot]
    var effectCode: String
    var outputBusID: UUID?
    var sends: [BusSend]
    var tempoRatio: Double
    var timeSignatureTop: Int
    var timeSignatureBottom: Int
    var renderedAudio: RenderedTrackAudio?
    var useRenderedAudio: Bool
    var clips: [ClipRegion]

    init(
        id: UUID,
        name: String,
        enabled: Bool,
        solo: Bool = false,
        gain: Double = 1.0,
        pan: Double = 0.0,
        deviceSlots: [DeviceSlot] = [],
        effectCode: String = "trackIn => trackOut;",
        outputBusID: UUID? = nil,
        sends: [BusSend] = [],
        tempoRatio: Double = 1.0,
        timeSignatureTop: Int = 4,
        timeSignatureBottom: Int = 4,
        renderedAudio: RenderedTrackAudio? = nil,
        useRenderedAudio: Bool = false,
        clips: [ClipRegion]
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.solo = solo
        self.gain = gain
        self.pan = pan
        self.deviceSlots = deviceSlots
        self.effectCode = effectCode
        self.outputBusID = outputBusID
        self.sends = sends
        self.tempoRatio = tempoRatio
        self.timeSignatureTop = timeSignatureTop
        self.timeSignatureBottom = timeSignatureBottom
        self.renderedAudio = renderedAudio
        self.useRenderedAudio = useRenderedAudio
        self.clips = clips
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case enabled
        case solo
        case gain
        case pan
        case deviceSlots
        case effectCode
        case outputBusID
        case sends
        case tempoRatio
        case timeSignatureTop
        case timeSignatureBottom
        case renderedAudio
        case useRenderedAudio
        case clips
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        solo = try container.decodeIfPresent(Bool.self, forKey: .solo) ?? false
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 1.0
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0.0
        deviceSlots = try container.decodeIfPresent([DeviceSlot].self, forKey: .deviceSlots) ?? []
        effectCode = try container.decodeIfPresent(String.self, forKey: .effectCode) ?? "trackIn => trackOut;"
        outputBusID = try container.decodeIfPresent(UUID.self, forKey: .outputBusID)
        sends = try container.decodeIfPresent([BusSend].self, forKey: .sends) ?? []
        tempoRatio = try container.decodeIfPresent(Double.self, forKey: .tempoRatio) ?? 1.0
        timeSignatureTop = try container.decodeIfPresent(Int.self, forKey: .timeSignatureTop) ?? 4
        timeSignatureBottom = try container.decodeIfPresent(Int.self, forKey: .timeSignatureBottom) ?? 4
        renderedAudio = try container.decodeIfPresent(RenderedTrackAudio.self, forKey: .renderedAudio)
        useRenderedAudio = try container.decodeIfPresent(Bool.self, forKey: .useRenderedAudio) ?? false
        clips = try container.decodeIfPresent([ClipRegion].self, forKey: .clips) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(solo, forKey: .solo)
        try container.encode(gain, forKey: .gain)
        try container.encode(pan, forKey: .pan)
        try container.encode(deviceSlots, forKey: .deviceSlots)
        try container.encode(effectCode, forKey: .effectCode)
        try container.encodeIfPresent(outputBusID, forKey: .outputBusID)
        try container.encode(sends, forKey: .sends)
        try container.encode(tempoRatio, forKey: .tempoRatio)
        try container.encode(timeSignatureTop, forKey: .timeSignatureTop)
        try container.encode(timeSignatureBottom, forKey: .timeSignatureBottom)
        try container.encodeIfPresent(renderedAudio, forKey: .renderedAudio)
        try container.encode(useRenderedAudio, forKey: .useRenderedAudio)
        try container.encode(clips, forKey: .clips)
    }
}

struct Project: Codable, Equatable {
    var name: String
    var master: MasterSettings
    var prelude: String
    var buses: [Bus]
    var tracks: [Track]

    enum CodingKeys: String, CodingKey {
        case name
        case master
        case prelude
        case buses
        case tracks
    }

    init(name: String, master: MasterSettings, prelude: String, buses: [Bus], tracks: [Track]) {
        self.name = name
        self.master = master
        self.prelude = prelude
        self.buses = buses
        self.tracks = tracks
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        master = try container.decode(MasterSettings.self, forKey: .master)
        prelude = try container.decode(String.self, forKey: .prelude)
        buses = try container.decodeIfPresent([Bus].self, forKey: .buses) ?? Project.defaultBuses()
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(master, forKey: .master)
        try container.encode(prelude, forKey: .prelude)
        try container.encode(buses, forKey: .buses)
        try container.encode(tracks, forKey: .tracks)
    }
}

struct SavedState: Codable {
    var project: Project
    var chuckPath: String
}

enum PresetLibrary: String, CaseIterable, Identifiable {
    case codeTape = "Code Tape"
    case logicGhost = "Logic Ghost"
    case transportStudy = "Transport Study"

    var id: String { rawValue }

    func build() -> Project {
        switch self {
        case .codeTape:
            return .defaultProject()
        case .logicGhost:
            return Project(
                name: rawValue,
                master: .init(bpm: 118, gain: 0.85, loopBars: 16),
                prelude: Project.defaultPrelude,
                buses: Project.defaultBuses(),
                tracks: [
                    Track.make(
                        name: "Kick Script",
                        clips: [
                            ClipRegion.make(name: "Four Floor", startBar: 1, lengthBars: 4, code: ClipTemplates.kickLoop),
                            ClipRegion.make(name: "Drop", startBar: 9, lengthBars: 8, code: ClipTemplates.heavyKickLoop)
                        ]
                    ),
                    Track.make(
                        name: "Bass Script",
                        clips: [
                            ClipRegion.make(name: "Root Riff", startBar: 1, lengthBars: 8, code: ClipTemplates.bassRiff),
                            ClipRegion.make(name: "Climb", startBar: 9, lengthBars: 8, code: ClipTemplates.bassClimb)
                        ]
                    ),
                    Track.make(
                        name: "Texture Script",
                        clips: [
                            ClipRegion.make(name: "Glass Bed", startBar: 5, lengthBars: 8, code: ClipTemplates.glassPad)
                        ]
                    )
                ]
            ).normalized()
        case .transportStudy:
            return Project(
                name: rawValue,
                master: .init(bpm: 92, gain: 0.9, loopBars: 12),
                prelude: Project.defaultPrelude,
                buses: Project.defaultBuses(),
                tracks: [
                    Track.make(
                        name: "Scene A",
                        clips: [
                            ClipRegion.make(name: "Intro Tone", startBar: 1, lengthBars: 2, code: ClipTemplates.introTone),
                            ClipRegion.make(name: "Mid Pulse", startBar: 4, lengthBars: 4, code: ClipTemplates.pulseMotif),
                            ClipRegion.make(name: "End Noise", startBar: 10, lengthBars: 2, code: ClipTemplates.noiseTail)
                        ]
                    ),
                    Track.make(
                        name: "Scene B",
                        clips: [
                            ClipRegion.make(name: "Chord Slice", startBar: 3, lengthBars: 3, code: ClipTemplates.chordSlice),
                            ClipRegion.make(name: "Arp Slice", startBar: 7, lengthBars: 3, code: ClipTemplates.arpSlice)
                        ]
                    )
                ]
            ).normalized()
        }
    }
}

extension Project {
    static let defaultPrelude = """
    // Global ChucK code for the whole session goes here.
    // Each clip runs when the transport reaches its region.
    // Inside a clip snippet you can use:
    // - regionDur
    // - regionEnd
    // - bar
    // - beat
    """

    static func defaultProject() -> Project {
        Project(
            name: "Code Tape",
            master: .init(bpm: 110, gain: 0.85, loopBars: 16),
            prelude: defaultPrelude,
            buses: defaultBuses(),
            tracks: [
                Track.make(
                    name: "Drums",
                    clips: [
                        ClipRegion.make(name: "Kick", startBar: 1, lengthBars: 4, code: ClipTemplates.kickLoop),
                        ClipRegion.make(name: "Hats", startBar: 5, lengthBars: 4, code: ClipTemplates.hatLoop),
                        ClipRegion.make(name: "Break", startBar: 9, lengthBars: 8, code: ClipTemplates.breakLoop)
                    ]
                ),
                Track.make(
                    name: "Bass",
                    clips: [
                        ClipRegion.make(name: "Bassline A", startBar: 1, lengthBars: 8, code: ClipTemplates.bassRiff),
                        ClipRegion.make(name: "Bassline B", startBar: 9, lengthBars: 8, code: ClipTemplates.bassClimb)
                    ]
                ),
                Track.make(
                    name: "Atmos",
                    clips: [
                        ClipRegion.make(name: "Pad", startBar: 3, lengthBars: 10, code: ClipTemplates.glassPad)
                    ]
                )
            ]
        ).normalized()
    }

    func normalized() -> Project {
        TimelineCompiler.normalize(self)
    }

    static func defaultBuses() -> [Bus] {
        [
            Bus(id: UUID(), name: "Bus A"),
            Bus(id: UUID(), name: "Bus B")
        ]
    }
}

extension Track {
    static func make(name: String, clips: [ClipRegion] = []) -> Track {
        Track(
            id: UUID(),
            name: name,
            enabled: true,
            solo: false,
            gain: 1.0,
            pan: 0.0,
            deviceSlots: [],
            effectCode: "trackIn => trackOut;",
            outputBusID: nil,
            sends: [],
            tempoRatio: 1.0,
            timeSignatureTop: 4,
            timeSignatureBottom: 4,
            renderedAudio: nil,
            useRenderedAudio: false,
            clips: clips
        )
    }
}

extension ClipRegion {
    static func make(name: String, startBar: Int, lengthBars: Int, code: String) -> ClipRegion {
        ClipRegion(
            id: UUID(),
            name: name,
            startStep: max(0, (startBar - 1) * 16),
            lengthSteps: max(1, lengthBars * 16),
            code: code
        )
    }

    static func make(name: String, startStep: Int, lengthSteps: Int, code: String) -> ClipRegion {
        ClipRegion(
            id: UUID(),
            name: name,
            startStep: startStep,
            lengthSteps: lengthSteps,
            code: code
        )
    }
}

enum ClipTemplates {
    static let kickLoop = """
    SndBuf buf => Gain g => dac;
    PROJECT_ROOT + "/Vendor/chuck/examples/data/kick.wav" => buf.read;
    0.8 => g.gain;
    while (now < regionEnd)
    {
        0 => buf.pos;
        1 * beat => now;
    }
    """

    static let heavyKickLoop = """
    SndBuf buf => Gain g => LPF f => dac;
    PROJECT_ROOT + "/Vendor/chuck/examples/data/kick.wav" => buf.read;
    0.95 => g.gain;
    900 => f.freq;
    while (now < regionEnd)
    {
        0 => buf.pos;
        0.5 * beat => now;
        0 => buf.pos;
        1.5 * beat => now;
    }
    """

    static let hatLoop = """
    Noise n => HPF h => ADSR e => dac;
    9000 => h.freq;
    e.set(2::ms, 10::ms, 0.0, 20::ms);
    while (now < regionEnd)
    {
        0.08 => n.gain;
        e.keyOn();
        40::ms => now;
        e.keyOff();
        0.5 * beat - 40::ms => now;
    }
    """

    static let breakLoop = """
    while (now < regionEnd)
    {
        Noise n => BPF f => ADSR e => dac;
        Std.rand2f(1400, 4000) => f.freq;
        3 => f.Q;
        e.set(4::ms, 30::ms, 0.0, 60::ms);
        0.12 => n.gain;
        e.keyOn();
        90::ms => now;
        e.keyOff();
        0.25 * beat => now;
    }
    """

    static let bassRiff = """
    SawOsc s => LPF f => ADSR e => dac;
    700 => f.freq;
    e.set(8::ms, 50::ms, 0.2, 70::ms);
    [36, 36, 43, 39] @=> int notes[];
    0 => int i;
    while (now < regionEnd)
    {
        Std.mtof(notes[i % notes.cap()]) => s.freq;
        0.18 => s.gain;
        e.keyOn();
        0.45 * beat => now;
        e.keyOff();
        0.55 * beat => now;
        i++;
    }
    """

    static let bassClimb = """
    TriOsc s => LPF f => ADSR e => dac;
    1100 => f.freq;
    e.set(5::ms, 70::ms, 0.18, 90::ms);
    [36, 39, 43, 46, 48, 46, 43, 39] @=> int notes[];
    0 => int i;
    while (now < regionEnd)
    {
        Std.mtof(notes[i % notes.cap()]) => s.freq;
        0.16 => s.gain;
        e.keyOn();
        0.5 * beat => now;
        e.keyOff();
        0.5 * beat => now;
        i++;
    }
    """

    static let glassPad = """
    TriOsc a => Gain mix => JCRev r => dac;
    SinOsc b => mix;
    0.18 => r.mix;
    [60, 64, 67] @=> int chord[];
    0.05 => mix.gain;
    for (0 => int i; i < chord.cap(); i++)
    {
        Std.mtof(chord[i]) => a.freq;
        Std.mtof(chord[i] + 12) => b.freq;
    }
    regionDur => now;
    """

    static let introTone = """
    SinOsc s => dac;
    330 => s.freq;
    0.12 => s.gain;
    regionDur => now;
    """

    static let pulseMotif = """
    while (now < regionEnd)
    {
        SinOsc s => ADSR e => dac;
        Std.rand2f(220, 660) => s.freq;
        e.set(5::ms, 20::ms, 0.0, 60::ms);
        0.12 => s.gain;
        e.keyOn();
        80::ms => now;
        e.keyOff();
        0.5 * beat => now;
    }
    """

    static let noiseTail = """
    Noise n => LPF f => dac;
    1400 => f.freq;
    0.03 => n.gain;
    regionDur => now;
    """

    static let chordSlice = """
    [60, 65, 69] @=> int chord[];
    for (0 => int i; i < chord.cap(); i++)
    {
        SawOsc s => ADSR e => dac;
        Std.mtof(chord[i]) => s.freq;
        0.07 => s.gain;
        e.set(10::ms, 100::ms, 0.0, 200::ms);
        e.keyOn();
        0.8 * beat => now;
        e.keyOff();
    }
    regionDur => now;
    """

    static let arpSlice = """
    [72, 76, 79, 84] @=> int notes[];
    0 => int i;
    while (now < regionEnd)
    {
        TriOsc s => ADSR e => dac;
        Std.mtof(notes[i % notes.cap()]) => s.freq;
        0.09 => s.gain;
        e.set(3::ms, 20::ms, 0.0, 50::ms);
        e.keyOn();
        90::ms => now;
        e.keyOff();
        0.25 * beat => now;
        i++;
    }
    """
}
