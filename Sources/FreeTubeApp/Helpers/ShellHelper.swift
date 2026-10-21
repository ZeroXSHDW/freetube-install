import Foundation

enum ShellError: Error, LocalizedError {
    case commandNotFound(String)
    case executionFailed(Int32, String)
    case outputDecodingFailed

    var errorDescription: String? {
        switch self {
        case .commandNotFound(let cmd):
            return "Command not found: \(cmd)"
        case .executionFailed(let code, let output):
            return "Command failed with code \(code): \(output)"
        case .outputDecodingFailed:
            return "Failed to decode command output"
        }
    }
}

struct ShellHelper {
    /// Runs an executable by absolute path and returns its stdout.
    @discardableResult
    static func run(_ command: String, arguments: [String] = [],
                    environment: [String: String] = [:]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command)
        process.arguments = arguments

        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            environment.forEach { env[$0.key] = $0.value }
            process.environment = env
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            throw ShellError.commandNotFound(command)
        }

        process.waitUntilExit()

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            throw ShellError.executionFailed(process.terminationStatus, stderr)
        }

        guard let output = String(data: stdoutData, encoding: .utf8) else {
            throw ShellError.outputDecodingFailed
        }

        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolves a command name (or keeps an absolute path) to an absolute
    /// executable path, scanning Homebrew and standard directories first.
    static func resolveExecutable(_ name: String) -> String? {
        if name.contains("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? name : nil
        }
        let dirs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin",
                    "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        for dir in dirs {
            let path = "\(dir)/\(name)"
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        if let which = try? run("/usr/bin/which", arguments: [name]),
           !which.isEmpty, FileManager.default.isExecutableFile(atPath: which) {
            return which
        }
        return nil
    }

    /// Runs a command by name, resolving it against standard directories.
    @discardableResult
    static func runNamed(_ name: String, arguments: [String] = []) throws -> String {
        guard let path = resolveExecutable(name) else {
            throw ShellError.commandNotFound(name)
        }
        return try run(path, arguments: arguments)
    }

    /// Runs a command asynchronously with callbacks for completion.
    static func runAsync(_ command: String, arguments: [String] = [],
                         onOutput: @escaping (String) -> Void,
                         onCompletion: @escaping (Int32) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let output = try run(command, arguments: arguments)
                output.split(separator: "\n", omittingEmptySubsequences: false).forEach { line in
                    DispatchQueue.main.async {
                        onOutput(String(line))
                    }
                }
                DispatchQueue.main.async {
                    onCompletion(0)
                }
            } catch let error as ShellError {
                DispatchQueue.main.async {
                    onOutput(error.errorDescription ?? "Unknown error")
                    onCompletion(1)
                }
            } catch {
                DispatchQueue.main.async {
                    onOutput(error.localizedDescription)
                    onCompletion(1)
                }
            }
        }
    }

    static func commandExists(_ command: String) -> Bool {
        resolveExecutable(command) != nil
    }

    static func runOptional(_ command: String, arguments: [String] = []) -> String? {
        guard let path = resolveExecutable(command) else { return nil }
        return try? run(path, arguments: arguments)
    }
}
