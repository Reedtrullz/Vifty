#if DEBUG
import AppKit
import CryptoKit
import Darwin
import Foundation

enum ViftyReviewFileHash {
    static func sha256(at url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return sha256(data)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum ViftyReviewCanonicalRequest {
    static func sha256<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ViftyReviewFileHash.sha256(try encoder.encode(value))
    }
}

struct ViftyReviewScreenshotObservation: Codable, Equatable, Sendable {
    var method: String
    var artifactPath: String
    var sha256: String
    var pointWidth: Int
    var pointHeight: Int
    var pixelWidth: Int
    var pixelHeight: Int
    var backingScaleFactor: Double
}

enum ViftyReviewPNGWriterError: Error, Equatable, LocalizedError {
    case hiddenWindow
    case wrongWindow
    case emptyBounds
    case invalidScale
    case bitmapUnavailable(String)
    case dimensionMismatch(String)
    case captureToolUnavailable
    case captureTimedOut
    case captureFailed(Int32)
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .hiddenWindow:
            "The UI review PNG target window is not visible."
        case .wrongWindow:
            "The UI review PNG content view is not attached to the observed window."
        case .emptyBounds:
            "The UI review PNG content view has empty or non-finite bounds."
        case .invalidScale:
            "The UI review PNG target has an invalid backing scale."
        case .bitmapUnavailable(let detail):
            "The native macOS window capture is unreadable: \(detail)"
        case .dimensionMismatch(let detail):
            "The UI review PNG geometry is invalid: \(detail)"
        case .captureToolUnavailable:
            "The native macOS window capture tool is unavailable."
        case .captureTimedOut:
            "The native macOS window capture timed out."
        case .captureFailed(let status):
            "The native macOS window capture failed with exit status \(status)."
        case .pngEncodingFailed:
            "AppKit could not encode the UI review capture as PNG."
        }
    }
}

@MainActor
enum ViftyReviewPNGWriter {
    typealias NativeWindowCapture = (NSWindow, URL) throws -> Void

    static func capture(
        contentView: NSView,
        window: NSWindow,
        to url: URL,
        nativeWindowCapture: NativeWindowCapture? = nil
    ) throws -> ViftyReviewScreenshotObservation {
        guard window.isVisible else {
            throw ViftyReviewPNGWriterError.hiddenWindow
        }
        guard contentView.window === window else {
            throw ViftyReviewPNGWriterError.wrongWindow
        }

        window.displayIfNeeded()
        contentView.layoutSubtreeIfNeeded()
        contentView.displayIfNeeded()

        let contentBounds = contentView
            .convert(window.contentLayoutRect, from: nil)
            .intersection(contentView.bounds)
        guard contentBounds.width.isFinite,
              contentBounds.height.isFinite,
              contentBounds.width > 0,
              contentBounds.height > 0 else {
            throw ViftyReviewPNGWriterError.emptyBounds
        }
        let scale = window.backingScaleFactor
        guard scale.isFinite, scale > 0, scale <= 4 else {
            throw ViftyReviewPNGWriterError.invalidScale
        }

        let pointWidth = Int(contentBounds.width.rounded())
        let pointHeight = Int(contentBounds.height.rounded())
        let expectedPixelWidth = Int((Double(pointWidth) * scale).rounded())
        let expectedPixelHeight = Int((Double(pointHeight) * scale).rounded())
        let expectedFrameWidth = Int((window.frame.width * scale).rounded())
        let expectedFrameHeight = Int((window.frame.height * scale).rounded())
        guard pointWidth > 0,
              pointHeight > 0,
              expectedFrameWidth > 0,
              expectedFrameHeight > 0 else {
            throw ViftyReviewPNGWriterError.dimensionMismatch(
                "the observed content or frame dimensions are not positive"
            )
        }

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let rawURL = url.deletingLastPathComponent().appendingPathComponent(
            "window-capture-\(UUID().uuidString).png"
        )
        defer {
            try? FileManager.default.removeItem(at: rawURL)
        }
        try (nativeWindowCapture ?? captureNativeWindow)(window, rawURL)

        guard let rawData = try? Data(contentsOf: rawURL) else {
            throw ViftyReviewPNGWriterError.bitmapUnavailable(
                "capture tool returned success without writing \(rawURL.lastPathComponent)"
            )
        }
        guard let rawBitmap = NSBitmapImageRep(data: rawData),
              let rawImage = rawBitmap.cgImage else {
            throw ViftyReviewPNGWriterError.bitmapUnavailable(
                "captured file contains \(rawData.count) bytes but AppKit cannot decode it"
            )
        }
        let horizontalFramePadding = rawBitmap.pixelsWide - expectedFrameWidth
        let verticalFramePadding = rawBitmap.pixelsHigh - expectedFrameHeight
        let maximumFramePadding = Int((2 * scale).rounded())
        guard horizontalFramePadding >= 0,
              horizontalFramePadding <= maximumFramePadding,
              horizontalFramePadding.isMultiple(of: 2),
              verticalFramePadding >= 0,
              verticalFramePadding <= maximumFramePadding,
              verticalFramePadding.isMultiple(of: 2) else {
            throw ViftyReviewPNGWriterError.dimensionMismatch(
                "captured frame is \(rawBitmap.pixelsWide)x\(rawBitmap.pixelsHigh) pixels; "
                    + "expected \(expectedFrameWidth)x\(expectedFrameHeight) with at most "
                    + "\(maximumFramePadding) pixels of symmetric border padding per axis"
            )
        }

        let layout = window.contentLayoutRect
        let cropX = horizontalFramePadding / 2
            + Int((layout.minX * scale).rounded())
        let cropY = verticalFramePadding / 2
            + Int(((window.frame.height - layout.maxY) * scale).rounded())
        guard cropX >= 0,
              cropY >= 0,
              cropX + expectedPixelWidth <= rawBitmap.pixelsWide,
              cropY + expectedPixelHeight <= rawBitmap.pixelsHigh else {
            throw ViftyReviewPNGWriterError.dimensionMismatch(
                "content crop (\(cropX),\(cropY),\(expectedPixelWidth),\(expectedPixelHeight)) "
                    + "escapes captured frame \(rawBitmap.pixelsWide)x\(rawBitmap.pixelsHigh)"
            )
        }
        guard let croppedImage = rawImage.cropping(to: CGRect(
            x: cropX,
            y: cropY,
            width: expectedPixelWidth,
            height: expectedPixelHeight
        )) else {
            throw ViftyReviewPNGWriterError.dimensionMismatch(
                "Core Graphics rejected the validated content crop"
            )
        }
        let bitmap = NSBitmapImageRep(cgImage: croppedImage)
        bitmap.size = contentBounds.size
        guard bitmap.pixelsWide == expectedPixelWidth,
              bitmap.pixelsHigh == expectedPixelHeight else {
            throw ViftyReviewPNGWriterError.dimensionMismatch(
                "cropped bitmap is \(bitmap.pixelsWide)x\(bitmap.pixelsHigh) pixels; "
                    + "expected \(expectedPixelWidth)x\(expectedPixelHeight)"
            )
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ViftyReviewPNGWriterError.pngEncodingFailed
        }

        try png.write(to: url, options: .atomic)
        let persistedSHA256 = try ViftyReviewFileHash.sha256(at: url)

        return ViftyReviewScreenshotObservation(
            method: "native-window-screencapture-crop",
            artifactPath: url.path,
            sha256: persistedSHA256,
            pointWidth: pointWidth,
            pointHeight: pointHeight,
            pixelWidth: bitmap.pixelsWide,
            pixelHeight: bitmap.pixelsHigh,
            backingScaleFactor: scale
        )
    }

    private static func captureNativeWindow(_ window: NSWindow, to url: URL) throws {
        let captureTool = URL(fileURLWithPath: "/usr/sbin/screencapture")
        let attributes = try? FileManager.default.attributesOfItem(atPath: captureTool.path)
        let ownerID = (attributes?[.ownerAccountID] as? NSNumber)?.uint32Value
        let permissions = (attributes?[.posixPermissions] as? NSNumber)?.uint16Value
        guard attributes?[.type] as? FileAttributeType == .typeRegular,
              ownerID == 0,
              let permissions,
              permissions & 0o022 == 0,
              FileManager.default.isExecutableFile(atPath: captureTool.path) else {
            throw ViftyReviewPNGWriterError.captureToolUnavailable
        }

        let process = Process()
        let completion = DispatchSemaphore(value: 0)
        process.executableURL = captureTool
        process.arguments = [
            "-x",
            "-o",
            "-l", String(window.windowNumber),
            url.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.standardError
        process.terminationHandler = { _ in completion.signal() }
        do {
            try process.run()
        } catch {
            throw ViftyReviewPNGWriterError.captureToolUnavailable
        }
        guard completion.wait(timeout: .now() + 10) == .success else {
            stopTimedOutCaptureProcess(process, completion: completion)
            throw ViftyReviewPNGWriterError.captureTimedOut
        }
        guard process.terminationStatus == 0 else {
            throw ViftyReviewPNGWriterError.captureFailed(process.terminationStatus)
        }
    }

    static func stopTimedOutCaptureProcess(
        _ process: Process,
        completion: DispatchSemaphore,
        terminationGracePeriod: DispatchTimeInterval = .seconds(1)
    ) {
        guard process.isRunning else { return }

        process.terminate()
        guard completion.wait(timeout: .now() + terminationGracePeriod) != .success else {
            return
        }

        if process.isRunning {
            _ = Darwin.kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
    }
}
#endif
