//
//  ScreenCaptureService.swift
//  dria
//
//  Uses /usr/sbin/screencapture CLI tool — no per-app Screen Recording permission needed.
//  The system screencapture binary has its own blanket permission.
//

import AppKit
import CoreGraphics

struct ScreenCaptureService {
    /// Silent full-screen capture — uses screencapture CLI (no TCC prompt per build)
    func captureSilent() async -> (image: NSImage?, error: String?) {
        let tempFile = NSTemporaryDirectory() + "dria_\(UUID().uuidString).png"

        // Capture mouse position BEFORE screencapture runs (it may move the cursor)
        let mouseLocation = CGEvent(source: nil)?.location

        // Run screencapture asynchronously to not block
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", "-C", tempFile] // -x no sound, -C capture cursor
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: (nil, "screencapture failed: \(error.localizedDescription)"))
                    return
                }

                guard process.terminationStatus == 0 else {
                    continuation.resume(returning: (nil, "screencapture exit code \(process.terminationStatus)"))
                    return
                }

                guard FileManager.default.fileExists(atPath: tempFile),
                      let original = NSImage(contentsOfFile: tempFile) else {
                    continuation.resume(returning: (nil, "Screenshot file not created — grant Screen Recording to Terminal in System Settings"))
                    return
                }

                // Clean up
                try? FileManager.default.removeItem(atPath: tempFile)

                // Scale down for AI
                let maxWidth: CGFloat = 1600
                let scale = min(maxWidth / original.size.width, 1.0)
                let finalImage: NSImage
                if scale >= 1.0 {
                    finalImage = original
                } else {
                    let newSize = NSSize(width: original.size.width * scale, height: original.size.height * scale)
                    let resized = NSImage(size: newSize)
                    resized.lockFocus()
                    original.draw(in: NSRect(origin: .zero, size: newSize),
                                  from: NSRect(origin: .zero, size: original.size),
                                  operation: .copy, fraction: 1.0)
                    resized.unlockFocus()
                    finalImage = resized
                }

                continuation.resume(returning: (finalImage, nil))
            }
        }
    }

    /// Draw a red circle with crosshair at the cursor position on the image
    func markCursorPosition(on image: NSImage) -> NSImage {
        guard let mouseLocation = CGEvent(source: nil)?.location else { return image }

        let imageSize = image.size
        guard imageSize.width > 0 && imageSize.height > 0 else { return image }

        // Get main screen info for coordinate conversion
        guard let mainScreen = NSScreen.main else { return image }
        let screenFrame = mainScreen.frame

        // Convert screen coordinates (origin top-left for CGEvent) to image coordinates
        // CGEvent uses top-left origin; image uses bottom-left origin
        let scaleX = imageSize.width / screenFrame.width
        let scaleY = imageSize.height / screenFrame.height

        // CGEvent.location is in global display coordinates (top-left origin)
        let imgX = mouseLocation.x * scaleX
        let imgY = mouseLocation.y * scaleY  // CGEvent already top-left, image draw is bottom-left

        // Flip Y for NSImage coordinate system (bottom-left origin)
        let cursorPoint = NSPoint(x: imgX, y: imageSize.height - imgY)

        // Calculate radius: 1.5% of image size, min 12px
        let avgDimension = (imageSize.width + imageSize.height) / 2.0
        let radius = max(avgDimension * 0.015, 12.0)

        // Line width: 25% of radius, min 2px
        let lineWidth = max(radius * 0.25, 2.0)

        // Crosshair line length: 1.8x radius
        let crosshairLength = radius * 1.8

        // Create the marked image
        let markedImage = NSImage(size: imageSize)
        markedImage.lockFocus()

        // Draw original image
        image.draw(in: NSRect(origin: .zero, size: imageSize),
                   from: NSRect(origin: .zero, size: imageSize),
                   operation: .copy, fraction: 1.0)

        // Set color: red with 0.9 alpha
        let markerColor = NSColor.red.withAlphaComponent(0.9)
        markerColor.setStroke()

        // Draw circle
        let circleRect = NSRect(
            x: cursorPoint.x - radius,
            y: cursorPoint.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let circlePath = NSBezierPath(ovalIn: circleRect)
        circlePath.lineWidth = lineWidth
        circlePath.stroke()

        // Draw crosshair lines through the circle
        let horizontalLine = NSBezierPath()
        horizontalLine.move(to: NSPoint(x: cursorPoint.x - crosshairLength, y: cursorPoint.y))
        horizontalLine.line(to: NSPoint(x: cursorPoint.x + crosshairLength, y: cursorPoint.y))
        horizontalLine.lineWidth = lineWidth
        horizontalLine.stroke()

        let verticalLine = NSBezierPath()
        verticalLine.move(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y - crosshairLength))
        verticalLine.line(to: NSPoint(x: cursorPoint.x, y: cursorPoint.y + crosshairLength))
        verticalLine.lineWidth = lineWidth
        verticalLine.stroke()

        markedImage.unlockFocus()
        return markedImage
    }

    /// Interactive screen capture (user selects area) — saves to file to avoid Clop interception
    func captureInteractive() async -> NSImage? {
        let tempFile = NSTemporaryDirectory() + "dria_select_\(UUID().uuidString).png"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-i", "-x", tempFile] // -i interactive, -x no sound, save to file (not clipboard)
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                // User cancelled selection
                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tempFile),
                      let image = NSImage(contentsOfFile: tempFile) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Clean up temp file
                try? FileManager.default.removeItem(atPath: tempFile)

                continuation.resume(returning: image)
            }
        }
    }
}
