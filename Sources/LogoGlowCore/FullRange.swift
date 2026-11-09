// SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech>
// SPDX-License-Identifier: GPL-2.0-only

import Foundation

/// Removes (or restores) the ambient-light clamp on logo brightness.
///
/// corebrightnessd only loads its lux restriction tables at startup, from root's
/// `com.apple.CoreBrightness` preferences, so changing them takes an admin shell: write or
/// delete the tables, then restart the daemon (launchd relaunches it).
public enum FullRange {
    public static let minNits: Double = 0
    /// Highest output in Apple's default tables.
    public static let maxNits: Double = 1000

    public enum Action: Sendable {
        case unlock
        /// Deleting the keys returns corebrightnessd to its built-in tables.
        case restore

        public var command: String {
            switch self {
            case .unlock:
                [
                    defaultsWrite(LogoBacklight.Key.minRestriction, .constant(minNits)),
                    defaultsWrite(LogoBacklight.Key.maxRestriction, .constant(maxNits)),
                    restartDaemon,
                ].joined(separator: " && ")
            case .restore:
                [LogoBacklight.Key.minRestriction, LogoBacklight.Key.maxRestriction]
                    .map { "/usr/bin/defaults delete \(domain) \($0) 2>/dev/null" }
                    .joined(separator: "; ")
                    + "; " + restartDaemon
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case succeeded
        /// The user dismissed the password prompt.
        case cancelled
        case failed(String)
    }

    /// Runs `action` as root after the standard macOS password prompt.
    public static func run(_ action: Action) async -> Outcome {
        let script = adminAppleScript(for: action.command)
        return await Task.detached { runOSAScript(script) }.value
    }

    /// Commands are built only from constants, so no escaping is needed beyond a check.
    static func adminAppleScript(for command: String) -> String {
        precondition(!command.contains("\"") && !command.contains("\\"), "command needs AppleScript escaping")
        return "do shell script \"\(command)\" with administrator privileges"
    }

    private static let domain = "com.apple.CoreBrightness"
    private static let restartDaemon = "/usr/bin/killall corebrightnessd"

    private static func defaultsWrite(_ key: String, _ mapping: NitsMapping) -> String {
        // An XML value keeps the numbers typed as reals; old-style syntax would store strings.
        let rows = mapping.points.map { "<array><real>\($0.input)</real><real>\($0.output)</real></array>" }
        return "/usr/bin/defaults write \(domain) \(key) '<array>\(rows.joined())</array>'"
    }

    private static func runOSAScript(_ script: String) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let stderr = Pipe()
        process.standardError = stderr
        process.standardOutput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return .failed(error.localizedDescription)
        }
        let message = String(decoding: stderr.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .succeeded }
        // AppleScript's "User canceled." error.
        if message.contains("(-128)") { return .cancelled }
        return .failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
