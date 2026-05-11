//
//  HangWatchdog.swift
//  dria
//
//  Monitors main-thread responsiveness. Industry-standard approach:
//  background timer pings main; if main doesn't ack within N seconds,
//  log a hang. If the hang exceeds a longer threshold, deliberately
//  abort so macOS writes a real crash report — better than letting the
//  user kill a zombie at 100% CPU.
//

import Foundation

final class HangWatchdog: @unchecked Sendable {
    /// Warn + write a log if main is unresponsive longer than this.
    private let warnThreshold: TimeInterval = 3.0
    /// Force a fatal abort (crash report) if main is unresponsive longer than this.
    /// Set high enough that legitimate workloads (large screenshots, big OCR) don't trip it.
    private let abortThreshold: TimeInterval = 20.0
    /// How often to ping main.
    private let pingInterval: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "dria.hangwatchdog", qos: .utility)
    private var timer: DispatchSourceTimer?

    /// Last time we asked main to ack (CACurrentMediaTime — monotonic, sleep-aware).
    private var lastPingSent: TimeInterval = 0
    /// Last time main acked us.
    private var lastPingAck: TimeInterval = 0
    /// Token incremented per ping; main acks by setting `ackedToken = pingToken`.
    private var pingToken: UInt64 = 0
    private var ackedToken: UInt64 = 0
    /// Have we already logged the current hang? Avoid repeat logs while still stuck.
    private var loggedThisHang = false
    /// Last wall-clock so we can detect sleep (large jumps in wall time vs monotonic).
    private var lastWallClock = Date().timeIntervalSince1970

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

    private func tick() {
        let now = monotonic()
        let wall = Date().timeIntervalSince1970
        let wallDelta = wall - lastWallClock
        lastWallClock = wall

        // Sleep/wake detection: if wall jumped much more than monotonic, machine slept.
        // Reset bookkeeping and skip this tick.
        if wallDelta > pingInterval * 4 {
            lastPingSent = now
            lastPingAck = now
            pingToken = 0
            ackedToken = 0
            loggedThisHang = false
            return
        }

        // If a previous ping is outstanding, evaluate it.
        if pingToken > ackedToken {
            let stuck = now - lastPingSent
            if stuck >= abortThreshold {
                logHang(seconds: stuck, fatal: true)
                // Deliberately crash so macOS writes a diagnostic report.
                fatalError("dria HangWatchdog: main thread unresponsive for \(Int(stuck))s — aborting")
            }
            if stuck >= warnThreshold && !loggedThisHang {
                logHang(seconds: stuck, fatal: false)
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
        // CACurrentMediaTime equivalent without importing QuartzCore.
        var ts = timespec()
        clock_gettime(CLOCK_UPTIME_RAW, &ts)
        return TimeInterval(ts.tv_sec) + TimeInterval(ts.tv_nsec) / 1_000_000_000
    }

    private func logHang(seconds: TimeInterval, fatal: Bool) {
        let kind = fatal ? "FATAL" : "warn"
        let path = CrashReporter.newLogPath(category: "hang")
        var body = "[dria hang log] \(kind) main thread unresponsive\n"
        body += "Date: \(Date())\n"
        body += "Version: \(CrashReporter.appVersion)\n"
        body += "macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        body += "Hang duration: \(String(format: "%.2f", seconds))s\n\n"
        body += "Background-thread backtrace (watchdog):\n"
        for frame in Thread.callStackSymbols { body += frame + "\n" }
        body += "\nNote: main thread is stuck; getting its stack from another\n"
        body += "thread requires mach exception ports. If this happens often,\n"
        body += "run `sample <pid> 2 -mayDie` against the dria process.\n"
        try? body.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
