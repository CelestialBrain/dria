//
//  CrashReporter.swift
//  dria
//
//  Catches uncaught NSExceptions and POSIX signals (SIGSEGV, SIGABRT, etc.),
//  writes a human-readable log to ~/Library/Logs/dria/crash-<timestamp>.log,
//  then chains to the default handler so macOS still writes its DiagnosticReport.
//
//  Not a full symbolicated crash reporter (those need mach exception ports
//  and a separate process). This is the "industry minimum" — enough to know
//  WHAT crashed, when, where in app code, on the next launch.
//

import Foundation
import Darwin

enum CrashReporter {
    static let directoryPath: String = {
        let dir = NSHomeDirectory() + "/Library/Logs/dria"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir
    }()

    static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }()

    /// Install handlers. Call once, early in app launch (before UI).
    static func install() {
        installExceptionHandler()
        installSignalHandlers()
    }

    // MARK: - List + retrieve

    /// Returns recent log files (crash + hang) newest first.
    static func recentLogs(limit: Int = 20) -> [URL] {
        let url = URL(fileURLWithPath: directoryPath)
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return entries
            .filter { $0.lastPathComponent.hasSuffix(".log") }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r
            }
            .prefix(limit)
            .map { $0 }
    }

    /// Best-effort path for a new log file with the given category.
    static func newLogPath(category: String) -> String {
        let ts = Self.timestamp()
        return "\(directoryPath)/\(category)-\(ts).log"
    }

    static func timestamp() -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: Date())
    }

    // MARK: - NSException

    private static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let path = CrashReporter.newLogPath(category: "crash")
            let lines = [
                "[dria crash log] uncaught NSException",
                "Date: \(Date())",
                "Version: \(CrashReporter.appVersion)",
                "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)",
                "",
                "Name: \(exception.name.rawValue)",
                "Reason: \(exception.reason ?? "—")",
                "User info: \(exception.userInfo ?? [:])",
                "",
                "Call stack symbols:",
                exception.callStackSymbols.joined(separator: "\n"),
                "",
                "Call stack return addresses:",
                exception.callStackReturnAddresses.map { $0.stringValue }.joined(separator: " "),
            ]
            let body = lines.joined(separator: "\n")
            try? body.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - POSIX signals

    /// Signals we want to catch. Skipping SIGKILL/SIGSTOP (can't), SIGPIPE (noisy).
    private static let catchSignals: [Int32] = [SIGSEGV, SIGABRT, SIGBUS, SIGILL, SIGFPE, SIGTRAP]

    /// Pre-allocated alternate stack so SIGSEGV from stack overflow can still
    /// invoke our handler instead of compounding the fault. Kept alive for
    /// the lifetime of the process — DO NOT free this pointer.
    private static let altStackSize: Int = max(Int(MINSIGSTKSZ), 64 * 1024)
    nonisolated(unsafe) private static let altStackPtr: UnsafeMutableRawPointer = {
        let p = UnsafeMutableRawPointer.allocate(byteCount: altStackSize, alignment: 16)
        var ss = stack_t()
        ss.ss_sp = p
        ss.ss_size = altStackSize
        ss.ss_flags = 0
        _ = sigaltstack(&ss, nil)
        return p
    }()

    private static func installSignalHandlers() {
        // Force the alt-stack lazy init.
        _ = altStackPtr

        var sa = sigaction()
        sa.__sigaction_u.__sa_sigaction = { signo, _, _ in
            // Signal handlers should be async-signal-safe. We violate this
            // pragmatically (Swift String formatting, file I/O) — same as
            // what KSCrash/PLCrashReporter do in their simple paths. The
            // alternative is no log at all.
            let path = CrashReporter.newLogPath(category: "crash")
            let name = CrashReporter.name(for: signo)
            var body = "[dria crash log] fatal signal \(signo) (\(name))\n"
            body += "Date: \(Date())\n"
            body += "Version: \(CrashReporter.appVersion)\n"
            body += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n\n"
            body += "Backtrace:\n"
            for frame in Thread.callStackSymbols { body += frame + "\n" }
            _ = try? body.write(toFile: path, atomically: true, encoding: .utf8)

            // Reset to default and re-raise so macOS writes its own report.
            // Use signal() here only because we're about to exit anyway.
            signal(signo, SIG_DFL)
            raise(signo)
        }
        // SA_SIGINFO so we use the three-arg handler form; SA_ONSTACK so we
        // run on our pre-allocated alternate stack (critical for stack overflow);
        // SA_RESETHAND so we naturally chain to the default after first hit.
        sa.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND
        sigemptyset(&sa.sa_mask)

        for sig in catchSignals {
            var prev = sigaction()
            _ = sigaction(sig, &sa, &prev)
        }
    }

    private static func name(for sig: Int32) -> String {
        switch sig {
        case SIGSEGV: return "SIGSEGV"
        case SIGABRT: return "SIGABRT"
        case SIGBUS:  return "SIGBUS"
        case SIGILL:  return "SIGILL"
        case SIGFPE:  return "SIGFPE"
        case SIGTRAP: return "SIGTRAP"
        default:      return "UNKNOWN"
        }
    }
}
