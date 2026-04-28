import Foundation

enum ChuckProcessError: LocalizedError {
    case binaryNotFound
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound:
            return "Set the path to a local chuck binary before starting playback."
        case .commandFailed(let message):
            return message
        }
    }
}

final class ChuckProcessManager: @unchecked Sendable {
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var scriptURL: URL?
    private var loopProcess: Process?
    private var loopStdoutPipe: Pipe?
    private var loopStderrPipe: Pipe?
    private let controlPort: Int = Int.random(in: 8900...9800)

    struct RenderResult {
        let outputURL: URL
    }

    func play(code: String, chuckPath: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        try stop(onOutput: onOutput)

        let binaryURL = URL(fileURLWithPath: chuckPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw ChuckProcessError.binaryNotFound
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ChuckDAW", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let scriptURL = tempDirectory.appendingPathComponent("session.ck")
        try code.write(to: scriptURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = [scriptURL.path]
        process.currentDirectoryURL = tempDirectory

        let stdout = Pipe()
        let stderr = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                onOutput(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                onOutput(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                onOutput("chuck process ended.")
            }
        }

        try process.run()
        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.scriptURL = scriptURL
        onOutput("Running \(binaryURL.path)")
    }

    func stop(onOutput: @escaping @Sendable (String) -> Void) throws {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil

        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
            onOutput("Playback stopped.")
        }
        self.process = nil
    }

    func renderTrackToFile(code: String, chuckPath: String, outputURL: URL, onOutput: @escaping @Sendable (String) -> Void) throws -> RenderResult {
        let binaryURL = URL(fileURLWithPath: chuckPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw ChuckProcessError.binaryNotFound
        }

        let tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("ChuckDAW-Renders", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        let scriptURL = tempDirectory.appendingPathComponent("render-\(UUID().uuidString).ck")
        try code.write(to: scriptURL, atomically: true, encoding: .utf8)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--silent", scriptURL.path]
        process.currentDirectoryURL = tempDirectory

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            onOutput(output)
        }

        guard process.terminationStatus == 0 else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "ChucK could not render the track." : output)
        }
        guard FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ChuckProcessError.commandFailed("The track render finished, but no audio file was produced.")
        }

        onOutput("Rendered audio file \(outputURL.lastPathComponent).")
        return RenderResult(outputURL: outputURL)
    }

    func ensureLoopRunning(chuckPath: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        if let loopProcess, loopProcess.isRunning {
            return
        }

        let binaryURL = URL(fileURLWithPath: chuckPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw ChuckProcessError.binaryNotFound
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--port:\(controlPort)", "--loop"]

        let stdout = Pipe()
        let stderr = Pipe()
        stdout.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                onOutput(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                onOutput(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { _ in
            DispatchQueue.main.async {
                onOutput("persistent chuck engine ended.")
            }
        }

        try process.run()
        self.loopProcess = process
        self.loopStdoutPipe = stdout
        self.loopStderrPipe = stderr
        onOutput("Persistent chuck engine online on port \(controlPort).")
        Thread.sleep(forTimeInterval: 0.2)
    }

    func addShred(code: String, chuckPath: String, name: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        try ensureLoopRunning(chuckPath: chuckPath, onOutput: onOutput)

        let runtimeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChuckDAW-Persistent", isDirectory: true)
        try FileManager.default.createDirectory(at: runtimeDirectory, withIntermediateDirectories: true)
        let filename = "\(safeFilename(name))-\(UUID().uuidString).ck"
        let fileURL = runtimeDirectory.appendingPathComponent(filename)
        try code.write(to: fileURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chuckPath)
        process.arguments = ["--port:\(controlPort)", "+", fileURL.path]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            onOutput(output)
        }
        guard process.terminationStatus == 0 else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "ChucK could not add the live session." : output)
        }
    }

    func removeAllShreds(chuckPath: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        try ensureLoopRunning(chuckPath: chuckPath, onOutput: onOutput)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chuckPath)
        process.arguments = ["--port:\(controlPort)", "--remove.all"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            onOutput(output)
        }
        guard process.terminationStatus == 0 else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "ChucK could not clear the live session." : output)
        }
    }

    func exitLoop(chuckPath: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        guard loopProcess != nil else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: chuckPath)
        process.arguments = ["--port:\(controlPort)", "--exit"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !output.isEmpty {
            onOutput(output)
        }
        guard process.terminationStatus == 0 else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "ChucK could not exit the live engine." : output)
        }
    }

    func shutdownLoop(onOutput: @escaping @Sendable (String) -> Void) {
        loopStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        loopStderrPipe?.fileHandleForReading.readabilityHandler = nil
        loopStdoutPipe = nil
        loopStderrPipe = nil

        if let loopProcess, loopProcess.isRunning {
            loopProcess.terminate()
            loopProcess.waitUntilExit()
            onOutput("Persistent audio engine stopped.")
        }
        self.loopProcess = nil
    }

    func forceKillAllChuckAudio(onOutput: @escaping @Sendable (String) -> Void) throws {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        loopStdoutPipe?.fileHandleForReading.readabilityHandler = nil
        loopStderrPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        stderrPipe = nil
        loopStdoutPipe = nil
        loopStderrPipe = nil
        process = nil
        loopProcess = nil

        let pkill = Process()
        pkill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        pkill.arguments = ["-9", "-x", "chuck"]

        let outputPipe = Pipe()
        pkill.standardOutput = outputPipe
        pkill.standardError = outputPipe

        try pkill.run()
        pkill.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if !output.isEmpty {
            onOutput(output)
        }

        // pkill returns 1 when no processes matched, which is acceptable for panic-stop.
        if pkill.terminationStatus == 0 {
            onOutput("Panic stop: all ChucK audio was killed.")
        } else if pkill.terminationStatus == 1 {
            onOutput("Panic stop: no running ChucK processes were found.")
        } else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "Panic stop failed." : output)
        }
    }

    func terminateManagedChuckProcesses(chuckPath: String, onOutput: @escaping @Sendable (String) -> Void) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,command="]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        let managedPIDs = output
            .split(separator: "\n")
            .compactMap { line -> Int? in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return nil }
                let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace)
                guard parts.count == 2, let pid = Int(parts[0]) else { return nil }
                let command = String(parts[1])
                guard command.contains(chuckPath) else { return nil }
                let isManaged = command.contains("--loop")
                    || command.contains("ChuckDAW")
                    || command.contains("ChuckDAW-Persistent")
                    || command.contains("session.ck")
                    || command.contains("debug.ck")
                return isManaged ? pid : nil
            }

        guard !managedPIDs.isEmpty else { return }

        for pid in managedPIDs {
            kill(pid_t(pid), SIGTERM)
        }

        Thread.sleep(forTimeInterval: 0.15)

        for pid in managedPIDs {
            if kill(pid_t(pid), 0) == 0 {
                kill(pid_t(pid), SIGKILL)
            }
        }

        onOutput("Cleaned up \(managedPIDs.count) managed ChucK process(es).")
    }

    func probeBinary(at chuckPath: String) throws -> String {
        let binaryURL = URL(fileURLWithPath: chuckPath)
        guard FileManager.default.fileExists(atPath: binaryURL.path) else {
            throw ChuckProcessError.binaryNotFound
        }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = ["--version"]

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard process.terminationStatus == 0 else {
            throw ChuckProcessError.commandFailed(output.isEmpty ? "ChucK probe failed." : output)
        }

        return output
    }

    private func safeFilename(_ text: String) -> String {
        let allowed = text.map { character -> Character in
            if character.isLetter || character.isNumber || character == "-" || character == "_" {
                return character
            }
            return "-"
        }
        return String(allowed)
    }
}
