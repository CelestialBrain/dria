//
//  HangWatchdog.swift
//  dria
//
//  Monitors main-thread responsiveness. Background timer pings main; if
//  main doesn't ack within N seconds, we log a hang (with a real main-thread
//  stack from `/usr/bin/sample`) and — if the hang exceeds the fatal
//  threshold — deliberately abort so macOS writes a real crash report.
//
//  Long-operation API: legitimate workloads that block main (cold-start
//  embedding load, large KB indexing, slow Vertex token mint, large-PDF
//  OCR) wrap themselves in `withLongOperation(_:)` so the watchdog raises
//  the bar instead of crashing on a real piece of work.
//

import Foundation

final class HangWatchdog: @unchecked Sendable {
    /// Warn + write a log if main is unresponsive longer than this.
    private let warnThreshold: TimeInterval = 5.0
    /// Force a fatal abort (crash report) if main is unresponsive longer than this
    /// AND no long-operation is in flight.
    private let abortThreshold: TimeInterval = 60.0
    /// Soft "extended" threshold during a long-operation. We never abort while
    /// a named operation is in flight, but we still log if it goes truly silly.
    private let longOpExtendedLogThreshold: TimeInterval = 90.0
    private let pingInterval: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "dria.hangwatchdog", qos: .utility)
    private var timer: DispatchSourceTimer?

    private var lastPingSent: TimeInterval = 0
    private var lastPingAck: TimeInterval = 0
    private var pingToken: UInt64 = 0
    private var ackedToken: UInt64 = 0
    private var loggedThisHang = false
    private var lastWallClock = Date().timeIntervalSince1970

    /// Long-operation stack. Multiple may overlap (re-entrant).
    /// Protected by `opsLock` to allow `begin`/`end` from any thread.
    private let opsLock = NSLock()
    private var activeOps: [(id: UInt64, name: String, startedAt: TimeInterval)] = []
    private var nextOpId: UInt64 = 1

    func start() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        t.setEventHandler { [weak self] in
            self?.tick()
        }
        timer = t
        let now = monotonic()
        lastPingSent = now
        lastPingAck = now
        t.resume()
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    // MARK: - Long operation API

    /// Begin a named long operation. Returns a token to pair with `endLongOperation`.
    /// Use `withLongOperation(_:)` whenever you can — it's exception-safe.
    @discardableResult
    func beginLongOperation(_ name: String) -> UInt64 {
        opsLock.lock()
        defer { opsLock.unlock() }
        let id = nextOpId
        nextOpId += 1
        activeOps.append((id: id, name: name, startedAt: monotonic()))
        return id
    }

    func endLongOperation(_ id: UInt64) {
        opsLock.lock()
        defer { opsLock.unlock() }
        activeOps.removeAll { $0.id == id }
    }

    /// Scoped helper — preferred entry point for async paths.
    func withLongOperation<T>(_ name: String, _ body: () async throws -> T) async rethrows -> T {
        let id = beginLongOperation(name)
        defer { endLongOperation(id) }
        return try await body()
    }

    private func activeOpsSnapshot() -> [(id: UInt64, name: String, startedAt: TimeInterval)] {
        opsLock.lock()
        defer { opsLock.unlock() }
        return activeOps
    }

    private func anyOpActive() -> Bool {
        opsLock.lock()
        defer { opsLock.unlock() }
        return !activeOps.isEmpty
    }

    // MARK: - Tick

    private func tick() {
        let now = monotonic()
        let wall = Date().timeIntervalSince1970
        let wallDelta = wall - lastWallClock
        lastWallClock = wall

        // Sleep/wake detection: large wall jump vs monotonic ⇒ machine slept.
        if wallDelta > pingInterval * 4 {
            lastPingSent = now
            lastPingAck = now
            pingToken = 0
            ackedToken = 0
            loggedThisHang = false
            return
        }

        if pingToken > ackedToken {
            let stuck = now - lastPingSent
            let opActive = anyOpActive()

            // Truly long stuck-during-long-op: log once for visibility, never abort.
            if opActive && stuck >= longOpExtendedLogThreshold && !loggedThisHang {
                logHang(seconds: stuck, kind: .longOpExtended)
                loggedThisHang = true
                return
            }

            // Fatal threshold: abort only if no long-operation is in flight.
            if stuck >= abortThreshold {
                if opActive {
                    if !loggedThisHang {
                        logHang(seconds: stuck, kind: .warnDuringOp)
                        loggedThisHang = true
                    }
                    return
                }
                logHang(seconds: stuck, kind: .fatal)
                fatalError("dria HangWatchdog: main thread unresponsive for \(Int(stuck))s — aborting")
            }

            // Warn threshold: log once per hang.
            if stuck >= warnThreshold && !loggedThisHang {
                logHang(seconds: stuck, kind: opActive ? .warnDuringOp : .warn)
                loggedThisHang = true
            }
            return
        }

        // Send a new ping.
        pingToken += 1
        let token = pingToken
        lastPingSent = now
        loggedThisHang = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.queue.async {
                self.ackedToken = max(self.ackedToken, token)
                self.lastPingAck = self.monotonic()
            }
        }
    }

    private func monotonic() -> TimeInterval {
        var ts = timespec()
        clock_gettime(CLOCK_UPTIME_RAW, &ts)
        return TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000
    }

    // MARK: - Logging

    private enum HangKind {
        case warn               // generic warn, no long-op
        case warnDuringOp       // hang while a long-op is in flight
        case longOpExtended     // op exceeded the soft "this is really slow" threshold
        case fatal              // about to abort
    }

    private func logHang(seconds: TimeInterval, kind: HangKind) {
        let label: String
        switch kind {
        case .warn:             label = "WARN"
        case .warnDuringOp:     label = "WARN (long-op active)"
        case .longOpExtended:   label = "WARN (long-op extended)"
        case .fatal:            label = "FATAL"
        }
        let opsSnapshot = activeOpsSnapshot()
        let opsDesc = opsSnapshot.isEmpty
            ? "(none)"
            : opsSnapshot.map { "\($0.name) for \(Int(monotonic() - $0.startedAt))s" }.joined(separator: ", ")

        let path = CrashReporter.newLogPath(category: "hang")
        var body = "[dria hang log] \(label) main thread unresponsive\n"
        body += "Date: \(Date())\n"
        body += "Version: \(CrashReporter.appVersion)\n"
        body += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        body += "Hang duration: \(String(format: "%.2f", seconds))s\n"
        body += "Active long-operations: \(opsDesc)\n\n"
        body += "Background-thread backtrace (watchdog):\n"
        for frame in Thread.callStackSymbols { body += frame + "\n" }
        try? body.write(toFile: path, atomically: true, encoding: .utf8)

        // Real main-thread stack via /usr/bin/sample — runs in a separate
        // process so it can read our hung main thread.
        captureSampleAsync(category: "hang-sample")
    }

    /// Fire `/usr/bin/sample` against our own PID for 1s and write its output
    /// alongside the hang log. Runs asynchronously so we don't block the
    /// watchdog tick. Falls back silently if `sample` isn't available.
    private func captureSampleAsync(category: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let path = CrashReporter.newLogPath(category: category)
        DispatchQueue.global(qos: .utility).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            task.arguments = [String(pid), "1", "-file", path, "-mayDie"]
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                // sample not available or denied — leave watchdog log only.
            }
        }
    }
}
