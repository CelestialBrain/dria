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

struct ExcelWorkbookContext {
    let bookName: String
    let sheetName: String
    let selectionAddress: String     // e.g. "B3" or "B3:C5"
    let selectionValue: String
    let usedRows: Int                // total used rows
    let usedCols: Int                // total used cols
    let includedRows: Int            // rows actually fetched
    let includedCols: Int            // cols actually fetched
    let tsv: String                  // TAB-separated values, top-left of used range
}

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

    /// Read the workbook context: book name, active sheet, used-range
    /// dimensions, and a TSV-formatted slice of the top-left of the used
    /// range up to `maxRows × maxCols`. AppleScript on Mac Excel happily
    /// returns Sub-range values as a list-of-lists; we truncate aggressively
    /// to keep the prompt under control.
    static func workbookContext(maxRows: Int = 100, maxCols: Int = 26) -> ExcelWorkbookContext? {
        let script = """
        tell application "Microsoft Excel"
            try
                if not (exists active workbook) then return ""
                set ws to active sheet of active workbook
                set bookName to name of active workbook
                set sheetName to name of ws
                set sel to selection
                set selAddr to get address sel local form false external form false
                set rawVal to value of sel
                set selVal to ""
                if rawVal is not missing value then set selVal to rawVal as text

                set usedRng to used range of ws
                set rTotal to count of rows of usedRng
                set cTotal to count of columns of usedRng

                set rInc to rTotal
                if rInc > \(maxRows) then set rInc to \(maxRows)
                set cInc to cTotal
                if cInc > \(maxCols) then set cInc to \(maxCols)

                -- Anchor at the first row/column of the used range so we don't
                -- start from an arbitrary offset.
                set firstRowIx to first row index of usedRng
                set firstColIx to first column index of usedRng
                set lastRowIx to firstRowIx + rInc - 1
                set lastColIx to firstColIx + cInc - 1

                set topLeft to cell firstRowIx column firstColIx of ws
                set bottomRight to cell lastRowIx column lastColIx of ws
                set targetRng to range (get address topLeft) & ":" & (get address bottomRight) of ws
                set vals to value of targetRng

                -- Build TSV with a header line of metadata.
                set tsvLines to {}
                if rInc = 1 and cInc = 1 then
                    -- Single cell: vals is the scalar, wrap it.
                    set cellTxt to ""
                    if vals is not missing value then set cellTxt to vals as text
                    set end of tsvLines to cellTxt
                else if rInc = 1 then
                    -- Single row: vals is a flat list.
                    set rowTxt to ""
                    repeat with i from 1 to count of vals
                        set v to item i of vals
                        set vt to ""
                        if v is not missing value then set vt to v as text
                        if i > 1 then set rowTxt to rowTxt & tab
                        set rowTxt to rowTxt & vt
                    end repeat
                    set end of tsvLines to rowTxt
                else if cInc = 1 then
                    -- Single column: vals is a list of scalars.
                    repeat with i from 1 to count of vals
                        set v to item i of vals
                        set vt to ""
                        if v is not missing value then set vt to v as text
                        set end of tsvLines to vt
                    end repeat
                else
                    -- Matrix: list of rows.
                    repeat with i from 1 to count of vals
                        set rowList to item i of vals
                        set rowTxt to ""
                        repeat with j from 1 to count of rowList
                            set v to item j of rowList
                            set vt to ""
                            if v is not missing value then set vt to v as text
                            if j > 1 then set rowTxt to rowTxt & tab
                            set rowTxt to rowTxt & vt
                        end repeat
                        set end of tsvLines to rowTxt
                    end repeat
                end if

                set AppleScript's text item delimiters to linefeed
                set tsvBody to tsvLines as text
                set AppleScript's text item delimiters to ""

                return bookName & "\\n" & sheetName & "\\n" & selAddr & "\\n" & selVal & "\\n" ¬
                    & (rTotal as text) & "\\n" & (cTotal as text) & "\\n" ¬
                    & (rInc as text) & "\\n" & (cInc as text) & "\\n---TSV---\\n" & tsvBody
            on error errMsg
                return "err:" & errMsg
            end try
        end tell
        """
        guard let raw = runScript(script), !raw.hasPrefix("err:") else { return nil }
        let parts = raw.components(separatedBy: "\n---TSV---\n")
        guard parts.count == 2 else { return nil }
        let header = parts[0].components(separatedBy: "\n")
        guard header.count >= 8 else { return nil }
        return ExcelWorkbookContext(
            bookName: header[0],
            sheetName: header[1],
            selectionAddress: header[2],
            selectionValue: header[3],
            usedRows: Int(header[4]) ?? 0,
            usedCols: Int(header[5]) ?? 0,
            includedRows: Int(header[6]) ?? 0,
            includedCols: Int(header[7]) ?? 0,
            tsv: parts[1]
        )
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
