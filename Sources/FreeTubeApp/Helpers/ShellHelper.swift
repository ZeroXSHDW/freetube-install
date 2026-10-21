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
    /// Runs a shell command and returns its stdout.
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

    /// Runs a command asynchronously with a callback for output lines.
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
        return FileManager.default.isExecutableFile(atPath: command)
            || run("which", arguments: [command]) != nil
    }

    static func runOptional(_ command: String, arguments: [String] = []) -> String? {
        try? run(command, arguments: arguments)
    }
}
