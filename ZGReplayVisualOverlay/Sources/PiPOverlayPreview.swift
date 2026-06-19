import AVFoundation
import AVKit
import CoreMedia
import ImageIO
import SwiftUI
import UIKit

final class PiPOverlayPreviewController: NSObject, ObservableObject {
    @Published private(set) var isSupported = AVPictureInPictureController.isPictureInPictureSupported()
    @Published private(set) var isPossible = false
    @Published private(set) var isActive = false
    @Published private(set) var statusText = "PiP preview idle"

    let displayLayer = AVSampleBufferDisplayLayer()

    private var pipController: AVPictureInPictureController?
    private var pipPossibleObservation: NSKeyValueObservation?
    private var timer: Timer?
    private var frameIndex: Int64 = 0
    private let renderSize = CGSize(width: 960, height: 540)

    override init() {
        super.init()
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = UIColor.black.cgColor
        configureAudioSession()
        configurePictureInPictureIfNeeded()
        startRendering()
    }

    deinit {
        timer?.invalidate()
        pipPossibleObservation?.invalidate()
    }

    func toggle() {
        if isActive {
            stopPictureInPicture()
        } else {
            startPictureInPicture()
        }
    }

    func startPictureInPicture() {
        configureAudioSession()
        configurePictureInPictureIfNeeded()
        renderNow()

        guard let pipController else {
            statusText = "PiP is not available on this device."
            return
        }

        guard pipController.isPictureInPicturePossible else {
            statusText = "PiP is preparing. Try again in a moment."
            pipController.invalidatePlaybackState()
            return
        }

        pipController.startPictureInPicture()
    }

    func stopPictureInPicture() {
        pipController?.stopPictureInPicture()
    }

    func renderNow() {
        guard let sampleBuffer = makeSampleBuffer() else { return }
        if displayLayer.status == .failed {
            displayLayer.flush()
        }
        displayLayer.enqueue(sampleBuffer)
    }

    private func configurePictureInPictureIfNeeded() {
        guard pipController == nil else { return }
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            statusText = "PiP is not supported on this device."
            isSupported = false
            return
        }

        let source = AVPictureInPictureController.ContentSource(
            sampleBufferDisplayLayer: displayLayer,
            playbackDelegate: self
        )
        let controller = AVPictureInPictureController(contentSource: source)
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        pipPossibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] controller, _ in
            DispatchQueue.main.async {
                self?.isPossible = controller.isPictureInPicturePossible
                if controller.isPictureInPicturePossible, self?.isActive == false {
                    self?.statusText = "PiP preview ready."
                }
            }
        }
        pipController = controller
    }

    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            statusText = "Audio session warning: \(error.localizedDescription)"
        }
    }

    private func startRendering() {
        timer?.invalidate()
        renderNow()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.renderNow()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func makeSampleBuffer() -> CMSampleBuffer? {
        let overlay = loadLatestOverlay()
        guard let image = renderImage(overlay: overlay),
              let pixelBuffer = makePixelBuffer(from: image),
              let formatDescription = makeFormatDescription(for: pixelBuffer) else {
            return nil
        }

        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 30),
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )

        if let sampleBuffer,
           let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           CFArrayGetCount(attachments) > 0 {
            let rawDictionary = CFArrayGetValueAtIndex(attachments, 0)
            let dictionary = unsafeBitCast(rawDictionary, to: CFMutableDictionary.self)
            CFDictionarySetValue(
                dictionary,
                Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
            )
        }

        return sampleBuffer
    }

    private func loadLatestOverlay() -> PiPOverlayModel? {
        let url = ZGShared.sharedContainerURL().appendingPathComponent("zg_overlay_state.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PiPOverlayModel.self, from: data)
    }

    private func renderImage(overlay: PiPOverlayModel?) -> CGImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: renderSize, format: format)
        let image = renderer.image { context in
            let rect = CGRect(origin: .zero, size: renderSize)
            color(red: 0.015, green: 0.02, blue: 0.03, alpha: 1).setFill()
            context.fill(rect)

            if let previewImage = loadLatestPreviewImage() {
                draw(image: previewImage, in: rect)
                drawLiveBadge(in: rect, overlay: overlay)
                return
            }

            drawHeader(in: rect, overlay: overlay)

            guard let overlay, overlay.table.width > 0, overlay.table.height > 0 else {
                drawWaitingState(in: rect)
                return
            }

            let tableFrame = CGRect(x: 90, y: 104, width: 780, height: 330)
            color(red: 0.02, green: 0.18, blue: 0.16, alpha: 1).setFill()
            UIBezierPath(roundedRect: tableFrame, cornerRadius: 26).fill()
            UIColor(white: 1, alpha: 0.18).setStroke()
            let border = UIBezierPath(roundedRect: tableFrame, cornerRadius: 26)
            border.lineWidth = 3
            border.stroke()
            drawPockets(in: tableFrame)

            let transform = PiPTableTransform(source: overlay.table.cgRect, destination: tableFrame.insetBy(dx: 28, dy: 28))

            for (index, line) in overlay.lines.enumerated() {
                let path = UIBezierPath()
                path.move(to: transform.map(CGPoint(x: line.startX, y: line.startY)))
                path.addLine(to: transform.map(CGPoint(x: line.endX, y: line.endY)))
                if index == 0 {
                    UIColor.white.withAlphaComponent(0.96).setStroke()
                    path.lineWidth = max(4, CGFloat(line.width) * 1.9)
                } else {
                    color(red: line.red, green: line.green, blue: line.blue, alpha: max(0.26, line.alpha)).setStroke()
                    path.lineWidth = max(2.6, CGFloat(line.width) * 1.55)
                }
                path.lineCapStyle = .round
                path.stroke()
            }

            for circle in overlay.circles {
                let center = transform.map(CGPoint(x: circle.x, y: circle.y))
                let radius = max(5, CGFloat(circle.radius) * transform.scale)
                let path = UIBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                color(red: circle.red, green: circle.green, blue: circle.blue, alpha: max(0.20, circle.alpha)).setStroke()
                path.lineWidth = max(2, CGFloat(circle.width) * 1.5)
                path.stroke()
            }

            drawFooter(in: rect, overlay: overlay)
        }
        return image.cgImage
    }

    private func loadLatestPreviewImage() -> CGImage? {
        let url = ZGShared.sharedContainerURL().appendingPathComponent("ZGPreviewFrame.jpg")
        guard FileManager.default.fileExists(atPath: url.path),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private func draw(image: CGImage, in rect: CGRect) {
        let imageSize = CGSize(width: image.width, height: image.height)
        let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width * 0.5,
            y: rect.midY - drawSize.height * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
        UIImage(cgImage: image).draw(in: drawRect)
    }

    private func drawLiveBadge(in rect: CGRect, overlay: PiPOverlayModel?) {
        let badge = CGRect(x: 18, y: 16, width: 214, height: 46)
        UIColor.black.withAlphaComponent(0.68).setFill()
        UIBezierPath(roundedRect: badge, cornerRadius: 16).fill()

        let label = overlay.map { "\($0.scene.uppercased()) \(Int($0.tableConfidence * 100))%" } ?? "LIVE SCAN"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .heavy),
            .foregroundColor: color(red: 0.18, green: 0.90, blue: 1.0, alpha: 1)
        ]
        NSString(string: label).draw(at: CGPoint(x: 34, y: 28), withAttributes: attributes)
    }

    private func drawHeader(in rect: CGRect, overlay: PiPOverlayModel?) {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 32, weight: .black),
            .foregroundColor: UIColor.white
        ]
        NSString(string: "ZG LIVE").draw(at: CGPoint(x: 34, y: 28), withAttributes: titleAttributes)

        let state: String
        if let overlay {
            state = "\(overlay.scene.uppercased())  \(Int(overlay.tableConfidence * 100))%"
        } else {
            state = "WAITING FOR SCAN"
        }
        let stateAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .semibold),
            .foregroundColor: color(red: 0.20, green: 0.88, blue: 1.0, alpha: 1)
        ]
        NSString(string: state).draw(at: CGPoint(x: 34, y: 70), withAttributes: stateAttributes)
    }

    private func drawWaitingState(in rect: CGRect) {
        let box = CGRect(x: 120, y: 136, width: 720, height: 276)
        UIColor.white.withAlphaComponent(0.06).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 28).fill()

        let message = ZGShared.appGroupReady
            ? "Start a broadcast to feed live scan data into this floating preview."
            : "App Group is not available. The recorder cannot send scan frames to this preview until signing keeps the App Group entitlement."
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.74),
            .paragraphStyle: centeredParagraph()
        ]
        NSString(string: message)
            .draw(in: box.insetBy(dx: 44, dy: 92), withAttributes: attributes)
    }

    private func drawFooter(in rect: CGRect, overlay: PiPOverlayModel) {
        let footer = "BALLS \(overlay.detectedBalls)  LINES \(overlay.lines.count)  POCKET \(overlay.selectedPocket + 1)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 18, weight: .heavy),
            .foregroundColor: UIColor.white.withAlphaComponent(0.80),
            .paragraphStyle: centeredParagraph()
        ]
        NSString(string: footer).draw(in: CGRect(x: 24, y: 488, width: 912, height: 32), withAttributes: attributes)
    }

    private func drawPockets(in tableFrame: CGRect) {
        let pocketPoints = [
            CGPoint(x: tableFrame.minX, y: tableFrame.minY),
            CGPoint(x: tableFrame.midX, y: tableFrame.minY),
            CGPoint(x: tableFrame.maxX, y: tableFrame.minY),
            CGPoint(x: tableFrame.minX, y: tableFrame.maxY),
            CGPoint(x: tableFrame.midX, y: tableFrame.maxY),
            CGPoint(x: tableFrame.maxX, y: tableFrame.maxY)
        ]

        for point in pocketPoints {
            let outer = UIBezierPath(ovalIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34))
            color(red: 1.0, green: 0.08, blue: 0.08, alpha: 0.90).setStroke()
            outer.lineWidth = 4
            outer.stroke()

            let inner = UIBezierPath(ovalIn: CGRect(x: point.x - 11, y: point.y - 11, width: 22, height: 22))
            UIColor.black.setFill()
            inner.fill()
        }
    }

    private func centeredParagraph() -> NSMutableParagraphStyle {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return paragraph
    }

    private func makePixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(renderSize.width),
            Int(renderSize.height),
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let context = CGContext(
            data: baseAddress,
            width: Int(renderSize.width),
            height: Int(renderSize.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        )
        context?.draw(image, in: CGRect(origin: .zero, size: renderSize))
        return pixelBuffer
    }

    private func makeFormatDescription(for pixelBuffer: CVPixelBuffer) -> CMVideoFormatDescription? {
        var formatDescription: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        return formatDescription
    }

    private func color(red: Double, green: Double, blue: Double, alpha: Double) -> UIColor {
        UIColor(red: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}

extension PiPOverlayPreviewController: AVPictureInPictureControllerDelegate {
    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        statusText = "Starting floating PiP preview..."
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = true
        statusText = "Floating PiP preview active."
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        isActive = false
        statusText = "PiP preview stopped."
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        isActive = false
        statusText = "PiP failed: \(error.localizedDescription)"
    }
}

extension PiPOverlayPreviewController: AVPictureInPictureSampleBufferPlaybackDelegate {
    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        statusText = playing ? "Floating PiP preview active." : "PiP preview paused."
        pictureInPictureController.invalidatePlaybackState()
    }

    func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        CMTimeRange(start: .zero, duration: .positiveInfinity)
    }

    func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        false
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        renderNow()
    }

    func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        completionHandler()
    }

    func pictureInPictureControllerShouldProhibitBackgroundAudioPlayback(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        true
    }
}

struct PiPOverlayPreviewSurface: UIViewRepresentable {
    @ObservedObject var controller: PiPOverlayPreviewController

    func makeUIView(context: Context) -> PiPOverlayPreviewHostView {
        let view = PiPOverlayPreviewHostView()
        view.displayLayer = controller.displayLayer
        controller.renderNow()
        return view
    }

    func updateUIView(_ uiView: PiPOverlayPreviewHostView, context: Context) {
        uiView.displayLayer = controller.displayLayer
    }
}

final class PiPOverlayPreviewHostView: UIView {
    var displayLayer: AVSampleBufferDisplayLayer? {
        didSet {
            oldValue?.removeFromSuperlayer()
            if let displayLayer {
                layer.addSublayer(displayLayer)
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        layer.cornerRadius = 14
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        layer.cornerRadius = 14
        layer.masksToBounds = true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        displayLayer?.frame = bounds
    }
}

private struct PiPOverlayModel: Decodable {
    var timestamp: Double
    var note: String
    var scene: String
    var tableConfidence: Double
    var table: PiPOverlayRect
    var lines: [PiPOverlayLine]
    var circles: [PiPOverlayCircle]
    var detectedBalls: Int
    var selectedPocket: Int

    private enum CodingKeys: String, CodingKey {
        case timestamp, note, scene, tableConfidence, table, lines, circles, detectedBalls, selectedPocket
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        timestamp = try container.decodeIfPresent(Double.self, forKey: .timestamp) ?? Date().timeIntervalSince1970
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
        scene = try container.decodeIfPresent(String.self, forKey: .scene) ?? "unknown"
        tableConfidence = try container.decodeIfPresent(Double.self, forKey: .tableConfidence) ?? 0
        table = try container.decode(PiPOverlayRect.self, forKey: .table)
        lines = try container.decodeIfPresent([PiPOverlayLine].self, forKey: .lines) ?? []
        circles = try container.decodeIfPresent([PiPOverlayCircle].self, forKey: .circles) ?? []
        detectedBalls = try container.decodeIfPresent(Int.self, forKey: .detectedBalls) ?? 0
        selectedPocket = try container.decodeIfPresent(Int.self, forKey: .selectedPocket) ?? 0
    }
}

private struct PiPOverlayRect: Decodable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private struct PiPOverlayLine: Decodable {
    var startX: Double
    var startY: Double
    var endX: Double
    var endY: Double
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var width: Double
}

private struct PiPOverlayCircle: Decodable {
    var x: Double
    var y: Double
    var radius: Double
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    var width: Double
}

private struct PiPTableTransform {
    var source: CGRect
    var destination: CGRect
    var scale: CGFloat
    private var xOffset: CGFloat
    private var yOffset: CGFloat

    init(source: CGRect, destination: CGRect) {
        self.source = source
        self.destination = destination
        let scaleX = destination.width / max(1, source.width)
        let scaleY = destination.height / max(1, source.height)
        scale = min(scaleX, scaleY)
        let fittedWidth = source.width * scale
        let fittedHeight = source.height * scale
        xOffset = destination.minX + (destination.width - fittedWidth) * 0.5
        yOffset = destination.minY + (destination.height - fittedHeight) * 0.5
    }

    func map(_ point: CGPoint) -> CGPoint {
        CGPoint(
            x: xOffset + (point.x - source.minX) * scale,
            y: yOffset + (point.y - source.minY) * scale
        )
    }
}
