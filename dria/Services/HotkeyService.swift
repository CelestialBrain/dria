//
//  HotkeyService.swift
//  dria
//

import AppKit
import Carbon

// MARK: - Hotkey Binding Model

struct HotkeyBinding: Codable, Equatable, Hashable {
    let keyCode: UInt32
    let label: String  // Human-readable key name

    static let key1 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_1), label: "1")
    static let key2 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_2), label: "2")
    static let key3 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_3), label: "3")
    static let key4 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_4), label: "4")
    static let key5 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_5), label: "5")
    static let key6 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_6), label: "6")
    static let key7 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_7), label: "7")
    static let key8 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_8), label: "8")
    static let key9 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_9), label: "9")
    static let key0 = HotkeyBinding(keyCode: UInt32(kVK_ANSI_0), label: "0")
    static let space = HotkeyBinding(keyCode: UInt32(kVK_Space), label: "Space")
    static let keyQ = HotkeyBinding(keyCode: UInt32(kVK_ANSI_Q), label: "Q")
    static let keyW = HotkeyBinding(keyCode: UInt32(kVK_ANSI_W), label: "W")
    static let keyE = HotkeyBinding(keyCode: UInt32(kVK_ANSI_E), label: "E")
    static let keyR = HotkeyBinding(keyCode: UInt32(kVK_ANSI_R), label: "R")
    static let keyS = HotkeyBinding(keyCode: UInt32(kVK_ANSI_S), label: "S")
    static let keyD = HotkeyBinding(keyCode: UInt32(kVK_ANSI_D), label: "D")

    static let leftArrow = HotkeyBinding(keyCode: UInt32(kVK_LeftArrow), label: "←")
    static let rightArrow = HotkeyBinding(keyCode: UInt32(kVK_RightArrow), label: "→")

    static let allOptions: [HotkeyBinding] = [
        .key0, .key1, .key2, .key3, .key4, .key5, .key6, .key7, .key8, .key9,
        .space, .leftArrow, .rightArrow,
        .keyQ, .keyW, .keyE, .keyR, .keyS, .keyD,
    ]

    var displayName: String { "⌘⌥\(label)" }
}

struct HotkeyConfig: Codable {
    var capture: HotkeyBinding     // Default: ⌘⌥1
    var sendToAI: HotkeyBinding    // Default: ⌘⌥2
    var inlineChat: HotkeyBinding  // Default: ⌘⌥3
    var cycleMode: HotkeyBinding   // Default: ⌘⌥0
    var abort: HotkeyBinding       // Default: ⌘⌥←
    var hoverCapture: HotkeyBinding // Default: ⌘⌥4 — capture around cursor + send
    var askExcelCell: HotkeyBinding // Default: ⌘⌥E — read Excel selection, write answer below

    static let defaults = HotkeyConfig(
        capture: .key1,
        sendToAI: .key2,
        inlineChat: .key3,
        cycleMode: .key0,
        abort: .leftArrow,
        hoverCapture: .key4,
        askExcelCell: .keyE
    )

    // Custom decoder so users who saved a config before askExcelCell existed
    // keep their other bindings instead of being reset to defaults.
    enum CodingKeys: String, CodingKey {
        case capture, sendToAI, inlineChat, cycleMode, abort, hoverCapture, askExcelCell
    }

    init(capture: HotkeyBinding, sendToAI: HotkeyBinding, inlineChat: HotkeyBinding,
         cycleMode: HotkeyBinding, abort: HotkeyBinding, hoverCapture: HotkeyBinding,
         askExcelCell: HotkeyBinding) {
        self.capture = capture
        self.sendToAI = sendToAI
        self.inlineChat = inlineChat
        self.cycleMode = cycleMode
        self.abort = abort
        self.hoverCapture = hoverCapture
        self.askExcelCell = askExcelCell
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.capture       = try c.decodeIfPresent(HotkeyBinding.self, forKey: .capture)       ?? Self.defaults.capture
        self.sendToAI      = try c.decodeIfPresent(HotkeyBinding.self, forKey: .sendToAI)      ?? Self.defaults.sendToAI
        self.inlineChat    = try c.decodeIfPresent(HotkeyBinding.self, forKey: .inlineChat)    ?? Self.defaults.inlineChat
        self.cycleMode     = try c.decodeIfPresent(HotkeyBinding.self, forKey: .cycleMode)     ?? Self.defaults.cycleMode
        self.abort         = try c.decodeIfPresent(HotkeyBinding.self, forKey: .abort)         ?? Self.defaults.abort
        self.hoverCapture  = try c.decodeIfPresent(HotkeyBinding.self, forKey: .hoverCapture)  ?? Self.defaults.hoverCapture
        self.askExcelCell  = try c.decodeIfPresent(HotkeyBinding.self, forKey: .askExcelCell)  ?? Self.defaults.askExcelCell
    }

    static func load() -> HotkeyConfig {
        guard let data = UserDefaults.standard.data(forKey: "hotkeyConfig"),
              let config = try? JSONDecoder().decode(HotkeyConfig.self, from: data) else {
            return .defaults
        }
        return config
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "hotkeyConfig")
        }
    }
}

// MARK: - Hotkey Service

private var hotkeyServiceInstance: HotkeyService?

private func hotkeyHandler(nextHandler: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    var hotKeyID = EventHotKeyID()
    let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard err == noErr else { return OSStatus(eventNotHandledErr) }

    Task { @MainActor in
        switch hotKeyID.id {
        case 1: hotkeyServiceInstance?.onScreenshot?()
        case 2: hotkeyServiceInstance?.onSendToAI?()
        case 3: hotkeyServiceInstance?.onOpenPopover?()
        case 4: hotkeyServiceInstance?.onToggleMode?()
        case 5: hotkeyServiceInstance?.onAbort?()
        case 6: hotkeyServiceInstance?.onHoverCapture?()
        case 7: hotkeyServiceInstance?.onAskExcelCell?()
        default: break
        }
    }
    return noErr
}

@MainActor
final class HotkeyService {
    var onScreenshot: (() -> Void)?
    var onSendToAI: (() -> Void)?
    var onOpenPopover: (() -> Void)?
    var onToggleMode: (() -> Void)?
    var onAbort: (() -> Void)?
    var onHoverCapture: (() -> Void)?
    var onAskExcelCell: (() -> Void)?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var eventHandlerRef: EventHandlerRef?

    func register() {
        // Unregister existing first
        unregister()
        hotkeyServiceInstance = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            return hotkeyHandler(nextHandler: nil, event: event, userData: nil)
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventType, nil, &eventHandlerRef)

        let sig = OSType(0x44524941) // "DRIA"
        let config = HotkeyConfig.load()
        let mods = UInt32(cmdKey | optionKey)

        func reg(_ keyCode: UInt32, _ id: UInt32) {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(keyCode, mods,
                                EventHotKeyID(signature: sig, id: id),
                                GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }

        reg(config.capture.keyCode, 1)         // Capture
        reg(config.sendToAI.keyCode, 2)        // Send to AI
        reg(config.inlineChat.keyCode, 3)      // Inline chat
        reg(config.cycleMode.keyCode, 4)       // Cycle mode
        reg(config.abort.keyCode, 5)           // Abort
        reg(config.hoverCapture.keyCode, 6)    // Hover capture + send
        reg(config.askExcelCell.keyCode, 7)    // Ask Excel cell
    }

    func unregister() {
        for ref in hotKeyRefs { if let ref { UnregisterEventHotKey(ref) } }
        hotKeyRefs.removeAll()
        if let handler = eventHandlerRef { RemoveEventHandler(handler); eventHandlerRef = nil }
        hotkeyServiceInstance = nil
    }

    /// Re-register with updated config
    func reloadBindings() {
        register()
    }
}
