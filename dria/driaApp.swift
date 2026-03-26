//
//  driaApp.swift
//  dria
//
//  Created by Prince Wagan on 3/9/26.
//

import SwiftUI

@main
struct driaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!

    // Marquee
    private var marqueeTimer: Timer?
    private var marqueeFullText: String = ""
    private var marqueeShortAnswer: String = "" // Short answer for copy
    private var marqueeOffset: Int = 0
    private let marqueeSpeed: TimeInterval = 0.12
    private var isShowingMarquee = false
    private var isMarqueeAnswer = false
    private var autoDismissTimer: Timer?

    // Floating input panel
    private var inputPanel: NSPanel?
    private var inputField: NSTextField?
    private var isTypingInline = false

    // Current AI task for abort
    private var currentAITask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        popover = NSPopover()
        popover.contentSize = NSSize(width: 420, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView()
                .environment(appState)
        )

        // Standard NSStatusItem — compatible with Ice, Bartender, Hidden Bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = Self.menuBarImage(for: appState.activeMode)
            button.imagePosition = .imageLeading
            button.action = #selector(statusItemClicked)
            button.target = self
        }

        appState.onMarqueeUpdate = { [weak self] text in
            guard let self else { return }
            guard let text else {
                self.stopMarquee()
                self.setIconColor(.labelColor)
                return
            }

            if text.hasPrefix("📸") {
                self.setIconColor(.systemYellow) // Captured — ready to send
                self.resetIconColorAfter(3)
            } else if text.hasPrefix("🔄") {
                self.setIconColor(.systemBlue) // Processing
            } else if text.hasPrefix("⚠️") {
                self.setIconColor(.systemRed) // Error
                self.resetIconColorAfter(3)
            } else if text.hasPrefix("📚") || text.hasPrefix("📋") {
                self.setIconColor(.systemCyan) // Mode/detection
                self.resetIconColorAfter(2)
            } else if text.hasPrefix("✅") || text.hasPrefix("✋") {
                self.setIconColor(.systemGreen)
                self.resetIconColorAfter(2)
            } else {
                // AI answer — show in marquee + green icon
                self.setIconColor(.systemGreen)
                self.startMarquee(text)
            }
        }

        appState.onModeChanged = { [weak self] mode in
            self?.statusItem.button?.image = Self.menuBarImage(for: mode)
        }

        appState.onIconColorChange = { [weak self] color in
            guard let self else { return }
            switch color {
            case "red": self.setIconColor(.systemRed)
            case "yellow": self.setIconColor(.systemYellow)
            case "blue": self.setIconColor(.systemBlue)
            case "green": self.setIconColor(.systemGreen)
            case "reset": self.setIconColor(.labelColor)
            default: self.setIconColor(.labelColor)
            }
        }

        appState.onOpenPopover = { [weak self] in
            self?.showInlineInput()
        }

        appState.onAbort = { [weak self] in
            self?.abortCurrentRequest()
        }

        appState.onAITaskStarted = { [weak self] task in
            self?.currentAITask = task
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        marqueeTimer?.invalidate()
        autoDismissTimer?.invalidate()
        iconColorTimer?.invalidate()
        currentAITask?.cancel()
        hideInlineInput()
        appState.cleanup()
    }

    // MARK: - Abort

    private func abortCurrentRequest() {
        currentAITask?.cancel()
        currentAITask = nil
        appState.isProcessing = false
        appState.isStreaming = false
        stopMarquee()
        setIconColor(.systemOrange)
        resetIconColorAfter(2)
    }

    // MARK: - Inline Text Input

    private func showInlineInput() {
        if isTypingInline {
            hideInlineInput()
            return
        }

        stopMarquee()
        isTypingInline = true

        guard let button = statusItem.button,
              let buttonWindow = button.window else { return }

        let buttonRect = buttonWindow.frame
        let panelWidth: CGFloat = 400
        let panelHeight: CGFloat = 36
        let panelX = buttonRect.midX - panelWidth / 2
        let panelY = buttonRect.minY - panelHeight - 4

        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true

        let field = NSTextField(frame: NSRect(x: 8, y: 6, width: panelWidth - 16, height: 24))
        let hasImage = appState.capturedImage != nil
        field.placeholderString = hasImage
            ? "📸 Screenshot ready — type a question, Enter to send"
            : "Ask DRIA (\(appState.activeMode.name))... Enter=send Esc=close"
        field.font = NSFont.systemFont(ofSize: 13)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(inlineFieldSubmitted)

        let container = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: panelHeight))
        container.material = .hudWindow
        container.blendingMode = .behindWindow
        container.state = .active
        container.wantsLayer = true
        container.layer?.cornerRadius = 10
        container.addSubview(field)

        panel.contentView = container
        panel.makeKeyAndOrderFront(nil)

        self.inputPanel = panel
        self.inputField = field

        NSApp.activate(ignoringOtherApps: true)
        panel.makeFirstResponder(field)
    }

    private func hideInlineInput() {
        inputPanel?.orderOut(nil)
        inputPanel = nil
        inputField = nil
        isTypingInline = false
    }

    @objc private func inlineFieldSubmitted() {
        guard let text = inputField?.stringValue, !text.isEmpty else {
            hideInlineInput()
            return
        }

        let question = text
        hideInlineInput()

        if appState.capturedImage != nil {
            let task = Task { await appState.sendCapturedWithQuestion(question) }
            currentAITask = task
        } else {
            appState.currentQuestion = question
            let task = Task {
                await appState.submitQuestion()
                if !appState.currentResponse.isEmpty {
                    let clean = appState.currentResponse
                        .replacingOccurrences(of: "\n", with: " · ")
                        .replacingOccurrences(of: "  ", with: " ")
                    appState.onMarqueeUpdate?(clean)
                }
            }
            currentAITask = task
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            hideInlineInput()
            return true
        }
        return false
    }

    // MARK: - Toggle Popover

    private func togglePopover() {
        if appState.lockPopover { return }

        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func statusItemClicked() {
        if isTypingInline { return }

        if isShowingMarquee && isMarqueeAnswer {
            // Copy short or full answer based on user setting
            let copyText: String
            switch appState.copyMode {
            case "short":
                copyText = marqueeShortAnswer.isEmpty ? marqueeFullText : marqueeShortAnswer
            case "full":
                // Get the full response from the last assistant message
                copyText = appState.chatHistory.last(where: { $0.role == .assistant })?.content ?? marqueeFullText
            default: // "marquee" — copy exactly what's in the marquee
                copyText = marqueeFullText
            }
            let clean = copyText.trimmingCharacters(in: CharacterSet.whitespaces)
            if !clean.isEmpty {
                appState.clipboard.skipNextChange = true
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(clean, forType: .string)
                setButtonText("✓ Copied!")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    self?.stopMarquee()
                }
            }
            return
        }
        if isShowingMarquee {
            stopMarquee()
            return
        }

        togglePopover()
    }

    // MARK: - Icon Color Status

    private var iconColorTimer: Timer?

    private func setIconColor(_ color: NSColor) {
        guard let button = statusItem.button else { return }
        if color == .labelColor {
            button.image = Self.menuBarImage(for: appState.activeMode)
        } else {
            // Tint the current icon with color
            if let base = Self.menuBarImage(for: appState.activeMode) {
                let tinted = NSImage(size: base.size, flipped: false) { rect in
                    base.draw(in: rect)
                    color.withAlphaComponent(0.9).set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.isTemplate = false
                button.image = tinted
            }
        }
    }

    /// Returns custom DRIA icon for General mode, SF Symbol for specific modes
    private static func menuBarImage(for mode: StudyMode) -> NSImage? {
        if mode.iconName == "sparkles" || mode.id == StudyMode.general.id {
            // Use custom DRIA icon for General/default mode
            let img = NSImage(named: "MenuBarIcon")
            img?.isTemplate = true
            return img
        }
        // Use SF Symbol for specific modes
        let img = NSImage(systemSymbolName: mode.iconName, accessibilityDescription: mode.name)
        img?.isTemplate = true
        return img
    }

    private func resetIconColorAfter(_ seconds: TimeInterval) {
        iconColorTimer?.invalidate()
        iconColorTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.setIconColor(.labelColor)
        }
    }

    // MARK: - Marquee (standard button API — Ice/Bartender compatible)

    private var marqueeVisibleChars: Int { appState.marqueeWidth }
    private var marqueeOpacity: CGFloat { CGFloat(appState.marqueeOpacity) }

    private func setButtonText(_ text: String) {
        guard let button = statusItem.button else { return }
        button.attributedTitle = NSAttributedString(
            string: " \(text)",
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor.labelColor.withAlphaComponent(marqueeOpacity),
            ]
        )
    }

    private func startMarquee(_ text: String) {
        if isTypingInline { hideInlineInput() }

        marqueeTimer?.invalidate()
        marqueeTimer = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil

        marqueeShortAnswer = text // Store the short/marquee version
        marqueeFullText = "  \(text)  "
        marqueeOffset = 0
        isShowingMarquee = true

        let isStatus = text.hasPrefix("📸") || text.hasPrefix("⚠️") || text.hasPrefix("🔄")
            || text.hasPrefix("📚") || text.hasPrefix("📋") || text.hasPrefix("✅") || text.hasPrefix("✋")
        isMarqueeAnswer = !isStatus

        // Show text immediately
        setButtonText(String(text.prefix(marqueeVisibleChars)))

        // Start scrolling if text is longer than visible area
        if marqueeFullText.count > marqueeVisibleChars {
            marqueeTimer = Timer.scheduledTimer(withTimeInterval: marqueeSpeed, repeats: true) { [weak self] timer in
                guard let self else { timer.invalidate(); return }
                self.advanceMarquee()
            }
        }

        // Auto-dismiss status messages after 3s
        if isStatus {
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                guard let self, !self.isMarqueeAnswer else { return }
                self.stopMarquee()
            }
        }
    }

    private func advanceMarquee() {
        marqueeOffset += 1
        if marqueeOffset >= marqueeFullText.count { marqueeOffset = 0 }
        updateMarqueeDisplay()
    }

    private func updateMarqueeDisplay() {
        let text = marqueeFullText
        guard !text.isEmpty else { return }
        let visibleCount = marqueeVisibleChars
        let start = text.index(text.startIndex, offsetBy: marqueeOffset % text.count)
        var visible = ""
        var idx = start
        for _ in 0..<min(visibleCount, text.count) {
            if idx == text.endIndex { idx = text.startIndex }
            visible.append(text[idx])
            idx = text.index(after: idx)
        }
        setButtonText(visible)
    }

    private func stopMarquee() {
        marqueeTimer?.invalidate()
        marqueeTimer = nil
        autoDismissTimer?.invalidate()
        autoDismissTimer = nil
        iconColorTimer?.invalidate()
        iconColorTimer = nil
        marqueeFullText = ""
        marqueeOffset = 0
        isShowingMarquee = false
        isMarqueeAnswer = false
        statusItem.button?.title = ""
        statusItem.button?.attributedTitle = NSAttributedString(string: "")
        statusItem.button?.font = nil
        setIconColor(.labelColor)
    }
}
