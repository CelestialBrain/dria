//
//  ExcelScript.swift
//  dria
//
//  AppleScript bridge to Microsoft Excel. Lets dria read the selected cell
//  and write a result back without an Office add-in — bypasses Microsoft's
//  Mac sideload restrictions entirely.
//
//  First use will trigger macOS Automation permission ("dria.app wants
//  permission to control Microsoft Excel"). User must grant it once.
//

import AppKit
import Foundation

enum ExcelScript {
    /// True if Excel is the current frontmost app.
    static func isFrontmost() -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        return front.bundleIdentifier == "com.microsoft.Excel"
    }

    /// Read the text content of the selected cell. Returns nil if Excel
    /// isn't running, nothing is selected, or the cell is empty.
    static func selectedCellText() -> String? {
        let script = """
        tell application "Microsoft Excel"
            try
                if not (exists active workbook) then return ""
                set sel to selection
                if sel is missing value then return ""
                set v to value of sel
                if v is missing value then return ""
                return v as text
            on error
                return ""
            end try
        end tell
        """
        guard let result = runScript(script) else { return nil }
        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Write `text` into the cell directly below the current selection.
    /// Returns true on success.
    @discardableResult
    static func writeBelowSelection(_ text: String) -> Bool {
        // Escape backslashes and double-quotes for AppleScript string literal.
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Microsoft Excel"
            try
                set sel to selection
                set r to first row index of sel
                set c to first column index of sel
                set targetCell to cell (r + 1) column c of active sheet of active workbook
                set value of targetCell to "\(escaped)"
                return "ok"
            on error errMsg
                return "err:" & errMsg
            end try
        end tell
        """
        guard let result = runScript(script) else { return false }
        return result.hasPrefix("ok")
    }

    /// Write `text` directly into the currently selected cell (overwrites).
    @discardableResult
    static func writeIntoSelection(_ text: String) -> Bool {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Microsoft Excel"
            try
                set value of selection to "\(escaped)"
                return "ok"
            on error errMsg
                return "err:" & errMsg
            end try
        end tell
        """
        guard let result = runScript(script) else { return false }
        return result.hasPrefix("ok")
    }

    // MARK: - Run

    private static func runScript(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorDict: NSDictionary?
        let result = script.executeAndReturnError(&errorDict)
        if let errorDict {
            let num = errorDict[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 = "Not authorised to send Apple events" — TCC denial.
            if num == -1743 {
                NSLog("[dria-excel] Automation permission denied. Grant access in System Settings → Privacy → Automation.")
            } else {
                NSLog("[dria-excel] script error: \(errorDict)")
            }
            return nil
        }
        return result.stringValue
    }
}
