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

                // Scale down for AI — use CGImage (thread-safe, no lockFocus)
                let maxWidth: CGFloat = 1600
                let scale = min(maxWidth / original.size.width, 1.0)
                let finalImage: NSImage
                if scale >= 1.0 {
                    finalImage = original
                } else {
                    guard let cgImage = original.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                        continuation.resume(returning: (original, nil))
                        return
                    }
                    let newW = Int(CGFloat(cgImage.width) * scale)
                    let newH = Int(CGFloat(cgImage.height) * scale)
                    guard let ctx = CGContext(data: nil, width: newW, height: newH,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                        continuation.resume(returning: (original, nil))
                        return
                    }
                    ctx.interpolationQuality = .high
                    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: newW, height: newH))
                    if let scaled = ctx.makeImage() {
                        finalImage = NSImage(cgImage: scaled, size: NSSize(width: newW, height: newH))
                    } else {
                        finalImage = original
                    }
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

        // Create marked image using CGContext (thread-safe, no lockFocus)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
        let w = cgImage.width, h = cgImage.height
        guard let ctx = CGContext(data: nil, width: w, height: h,
                                   bitsPerComponent: 8, bytesPerRow: 0,
                                   space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }

        // Draw original
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Convert cursor point to CGImage coordinates (CGImage is top-left origin flipped)
        let cx = cursorPoint.x * CGFloat(w) / imageSize.width
        let cy = (imageSize.height - cursorPoint.y) * CGFloat(h) / imageSize.height // flip Y
        let r = radius * CGFloat(w) / imageSize.width
        let lw = lineWidth * CGFloat(w) / imageSize.width
        let cl = crosshairLength * CGFloat(w) / imageSize.width

        // Draw red circle + crosshair
        ctx.setStrokeColor(CGColor(red: 1, green: 0, blue: 0, alpha: 0.9))
        ctx.setLineWidth(lw)
        ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        ctx.move(to: CGPoint(x: cx - cl, y: cy))
        ctx.addLine(to: CGPoint(x: cx + cl, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - cl))
        ctx.addLine(to: CGPoint(x: cx, y: cy + cl))
        ctx.strokePath()

        guard let result = ctx.makeImage() else { return image }
        return NSImage(cgImage: result, size: imageSize)
    }

    /// Capture region around cursor — invisible, no UI, instant
    /// Captures a ~800x600 area centered on the mouse cursor
    func captureAroundCursor(width: CGFloat = 800, height: CGFloat = 600) async -> (image: NSImage?, error: String?) {
        let tempFile = NSTemporaryDirectory() + "dria_hover_\(UUID().uuidString).png"

        // Get mouse position
        guard let mouseLocation = CGEvent(source: nil)?.location else {
            return (nil, "Could not get mouse position")
        }

        // Calculate capture rect centered on cursor
        guard let mainScreen = NSScreen.main else {
            return (nil, "No main screen")
        }
        let screenFrame = mainScreen.frame

        let x = max(0, mouseLocation.x - width / 2)
        let y = max(0, mouseLocation.y - height / 2)
        let w = min(width, screenFrame.width - x)
        let h = min(height, screenFrame.height - y)
        let rect = "-R\(Int(x)),\(Int(y)),\(Int(w)),\(Int(h))"

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = ["-x", rect, tempFile]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice

                do {
                    try process.run()
                    process.waitUntilExit()
                } catch {
                    continuation.resume(returning: (nil, "screencapture failed: \(error.localizedDescription)"))
                    return
                }

                guard process.terminationStatus == 0,
                      FileManager.default.fileExists(atPath: tempFile),
                      let image = NSImage(contentsOfFile: tempFile) else {
                    continuation.resume(returning: (nil, "Hover capture failed — grant Screen Recording permission"))
                    return
                }

                try? FileManager.default.removeItem(atPath: tempFile)
                continuation.resume(returning: (image, nil))
            }
        }
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
