import Darwin
import Foundation

private let pendingMark = "\u{2813}"
private let doneMark = "\u{2714}\u{FE0E}"
private let frames = [
    "\u{2813}", "\u{280B}", "\u{2819}", "\u{281A}", "\u{2816}",
    "\u{2846}", "\u{28C4}", "\u{28E0}", "\u{28B0}", "\u{2832}",
]

private struct SpinnerError: Error {
    let message: String
    let code: Int32
}

private func usage(scriptName: String) {
    print(
        """
        USAGE:
          \(scriptName) --message <text> --output <file> -- <command> [args...]
          \(scriptName) --message <text> --spin-only
          \(scriptName) --message <text> --pending
          \(scriptName) --message <text> --done
          \(scriptName) -h|--help

        OPTIONS:
          --message <text>  Text to show next to the spinner.
          --output <file>   File that receives combined stdout and stderr.
          --spin-only       Show the spinner until this process is stopped.
          --pending         Print a pending progress row and exit.
          --done            Print a completed progress row.
          -h, --help        Show this help text.

        ENVIRONMENT:
          SCRIPT_COLOUR     Set to off, false, or 0 to disable colour.
        """,
    )
}

private func colourEnabled() -> Bool {
    switch ProcessInfo.processInfo.environment["SCRIPT_COLOUR"] ?? "" {
    case "off", "OFF", "false", "FALSE", "0":
        false
    default:
        isatty(STDOUT_FILENO) == 1
    }
}

private func coloured(_ text: String, code: String) -> String {
    guard colourEnabled() else { return text }
    return "\u{001B}[\(code)m\(text)\u{001B}[0m"
}

private func printPending(_ message: String) {
    print("\(coloured(pendingMark, code: "38;5;63")) \(message)")
}

private func printDone(_ message: String) {
    print("\(coloured(doneMark, code: "32")) \(message)")
}

private func clearLine() {
    guard isatty(STDOUT_FILENO) == 1 else { return }
    print("\r\u{001B}[K", terminator: "")
    fflush(stdout)
}

private func spin(message: String) -> Never {
    signal(SIGTERM) { _ in Foundation.exit(0) }
    signal(SIGINT) { _ in Foundation.exit(0) }

    if isatty(STDOUT_FILENO) != 1 {
        printPending(message)
        while true {
            usleep(100_000)
        }
    }

    var index = 0
    while true {
        let frame = coloured(frames[index % frames.count], code: "38;5;63")
        print("\r\(frame) \(message)", terminator: "")
        fflush(stdout)
        index += 1
        usleep(100_000)
    }
}

private func runCommand(message: String, outputFile: String, command: [String]) throws -> Int32 {
    FileManager.default.createFile(atPath: outputFile, contents: nil)
    let output = try FileHandle(forWritingTo: URL(fileURLWithPath: outputFile))
    defer { try? output.close() }

    printPending(message)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = command
    process.standardOutput = output
    process.standardError = output
    try process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

private func main() throws -> Int32 {
    let scriptName = URL(fileURLWithPath: CommandLine.arguments.first ?? "mac-spinner").lastPathComponent
    var args = Array(CommandLine.arguments.dropFirst())
    var message = ""
    var outputFile = ""
    var mode = "run"

    while let arg = args.first {
        args.removeFirst()
        switch arg {
        case "--message":
            guard let value = args.first else {
                throw SpinnerError(message: "missing value for --message", code: 2)
            }
            message = value
            args.removeFirst()
        case "--output":
            guard let value = args.first else {
                throw SpinnerError(message: "missing value for --output", code: 2)
            }
            outputFile = value
            args.removeFirst()
        case "--spin-only":
            mode = "spin"
        case "--pending":
            mode = "pending"
        case "--done":
            mode = "done"
        case "--":
            if mode == "run" {
                break
            }
        case "-h", "--help":
            usage(scriptName: scriptName)
            return 0
        default:
            throw SpinnerError(message: "unknown argument: \(arg)", code: 2)
        }

        if arg == "--" {
            break
        }
    }

    guard !message.isEmpty else {
        throw SpinnerError(message: "missing --message", code: 2)
    }

    switch mode {
    case "pending":
        guard args.isEmpty else {
            throw SpinnerError(message: "--pending does not accept a command", code: 2)
        }
        printPending(message)
        return 0
    case "done":
        guard args.isEmpty else {
            throw SpinnerError(message: "--done does not accept a command", code: 2)
        }
        printDone(message)
        return 0
    case "spin":
        guard args.isEmpty else {
            throw SpinnerError(message: "--spin-only does not accept a command", code: 2)
        }
        spin(message: message)
    default:
        guard !outputFile.isEmpty else {
            throw SpinnerError(message: "missing --output", code: 2)
        }
        guard !args.isEmpty else {
            throw SpinnerError(message: "missing command after --", code: 2)
        }
        return try runCommand(message: message, outputFile: outputFile, command: args)
    }
}

do {
    let status = try main()
    Foundation.exit(status)
} catch let error as SpinnerError {
    fputs("ERROR: \(error.message)\n", stderr)
    usage(scriptName: URL(fileURLWithPath: CommandLine.arguments.first ?? "mac-spinner").lastPathComponent)
    Foundation.exit(error.code)
} catch {
    fputs("ERROR: \(error)\n", stderr)
    Foundation.exit(1)
}
