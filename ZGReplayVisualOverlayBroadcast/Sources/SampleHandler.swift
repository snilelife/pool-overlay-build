import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ImageIO
import ReplayKit
import UIKit
import UniformTypeIdentifiers

final class SampleHandler: RPBroadcastSampleHandler {
    private let analyzer = FrameAnalyzer()
    private let previewWriter = PreviewFrameWriter()
    private var writer: AnnotatedMovieWriter?
    private var lastOverlay: OverlayModel?
    private var frameCount = 0
    private var writerCreationFailed = false
    private var lastWriterError: String?

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        frameCount = 0
        writer = nil
        lastOverlay = nil
        writerCreationFailed = false
        lastWriterError = nil
        try? FileManager.default.removeItem(at: Shared.containerURL.appendingPathComponent("ZGAnnotatedReplay.mov"))
        try? FileManager.default.removeItem(at: Shared.containerURL.appendingPathComponent("ZGPreviewFrame.jpg"))
        Shared.pasteboard?.setData(Data(), forPasteboardType: Shared.pasteboardOverlayKey)
        Shared.pasteboard?.setData(Data(), forPasteboardType: Shared.pasteboardPreviewKey)
        Shared.pasteboard?.setData(Data(), forPasteboardType: Shared.pasteboardPreviewTimestampKey)
        writeState(OverlayModel.empty(note: "broadcast started"), status: "started")
    }

    override func broadcastPaused() {
        writeState(lastOverlay ?? OverlayModel.empty(note: "broadcast paused"), status: "paused")
    }

    override func broadcastResumed() {
        writeState(lastOverlay ?? OverlayModel.empty(note: "broadcast resumed"), status: "resumed")
    }

    override func broadcastFinished() {
        writer?.finish()
        writeState(lastOverlay ?? OverlayModel.empty(note: "broadcast finished"), status: "finished")
        writer = nil
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        frameCount += 1
        let settings = BroadcastSettings.load()
        var overlay: OverlayModel

        if !settings.scannerEnabled {
            if frameCount == 1 || frameCount % 30 == 0 {
                var stopped = lastOverlay ?? OverlayModel.empty(note: "scanner stopped")
                stopped.timestamp = Date().timeIntervalSince1970
                stopped.note = settings.holdScanResult ? "scanner stopped - holding last scan" : "scanner stopped"
                stopped.scene = stopped.table.width > 0 ? "scan_paused" : "scanner_stopped"
                writeState(stopped, status: "scanner stopped")
                if !settings.holdScanResult {
                    previewWriter.write(sampleBuffer, overlay: .empty(note: "scanner stopped"), minimumInterval: 0.25)
                }
            }
            return
        }

        // Fast mode scans about 15 times/second on a 60fps stream while the live preview keeps flowing.
        let analysisInterval: Int
        if settings.predictionStyle >= 2 {
            analysisInterval = settings.fastScanMode ? 5 : 12
        } else if settings.predictionStyle == 0 {
            analysisInterval = settings.fastScanMode ? 3 : 8
        } else {
            analysisInterval = settings.fastScanMode ? 4 : 10
        }
        if frameCount == 1 || frameCount % analysisInterval == 0 || lastOverlay == nil {
            let analyzed = analyzer.makeOverlay(from: sampleBuffer, settings: settings)
            if shouldHoldLastGameplayOverlay(insteadOf: analyzed, settings: settings), var held = lastOverlay {
                held.timestamp = Date().timeIntervalSince1970
                held.note = "holding last gameplay scan while screen is changing"
                overlay = held
            } else {
                overlay = analyzed
                lastOverlay = overlay
            }
            writeState(overlay, status: "running")
        } else {
            overlay = lastOverlay ?? analyzer.makeOverlay(from: sampleBuffer, settings: settings)
        }

        previewWriter.write(
            sampleBuffer,
            overlay: settings.predictionEnabled ? overlay : .empty(note: "prediction disabled"),
            minimumInterval: settings.fastScanMode ? 0.10 : 0.20
        )

        guard settings.recordAnnotatedVideo else { return }

        if writer == nil,
           !writerCreationFailed,
           let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            let width = CVPixelBufferGetWidth(imageBuffer)
            let height = CVPixelBufferGetHeight(imageBuffer)
            let output = Shared.containerURL.appendingPathComponent("ZGAnnotatedReplay.mov")
            do {
                writer = try AnnotatedMovieWriter(outputURL: output, width: width, height: height)
            } catch {
                writerCreationFailed = true
                lastWriterError = error.localizedDescription
                Shared.defaults.set(error.localizedDescription, forKey: "broadcastWriterError")
                Shared.defaults.set("failed to create writer", forKey: "broadcastWriterStatus")
                Shared.defaults.synchronize()
            }
        }

        writer?.append(sampleBuffer, overlay: settings.predictionEnabled ? overlay : .empty(note: "prediction disabled"))
        if frameCount % 30 == 0 {
            writeDiagnostics(status: "running", overlay: overlay)
        }
    }

    private func shouldHoldLastGameplayOverlay(insteadOf overlay: OverlayModel, settings: BroadcastSettings) -> Bool {
        guard settings.holdScanResult,
              overlay.scene != "gameplay_table",
              let previous = lastOverlay,
              previous.scene == "gameplay_table",
              previous.table.width > 0,
              previous.table.height > 0 else { return false }
        return Date().timeIntervalSince1970 - previous.timestamp <= settings.clampedHoldSeconds
    }

    private func writeState(_ overlay: OverlayModel, status: String) {
        let url = Shared.containerURL.appendingPathComponent("zg_overlay_state.json")
        guard let data = try? JSONEncoder.pretty.encode(overlay) else { return }
        try? data.write(to: url, options: .atomic)
        Shared.pasteboard?.setData(data, forPasteboardType: Shared.pasteboardOverlayKey)
        RelayClient.postState(data)
        writeDiagnostics(status: status, overlay: overlay)
    }

    private func writeDiagnostics(status: String, overlay: OverlayModel) {
        let replayURL = Shared.containerURL.appendingPathComponent("ZGAnnotatedReplay.mov")
        let previewURL = Shared.containerURL.appendingPathComponent("ZGPreviewFrame.jpg")
        let defaults = Shared.defaults
        defaults.set(status, forKey: "broadcastStatus")
        defaults.set(Date().timeIntervalSince1970, forKey: "broadcastLastEvent")
        defaults.set(frameCount, forKey: "broadcastFrameCount")
        defaults.set(overlay.note, forKey: "broadcastLastNote")
        defaults.set(overlay.scene, forKey: "broadcastScene")
        defaults.set(overlay.tableConfidence, forKey: "broadcastTableConfidence")
        defaults.set(overlay.detectedBalls, forKey: "broadcastDetectedBalls")
        defaults.set(overlay.lines.count, forKey: "broadcastLineCount")
        defaults.set(FileManager.default.fileExists(atPath: replayURL.path), forKey: "broadcastReplayAvailable")
        defaults.set(FileManager.default.fileExists(atPath: previewURL.path), forKey: "broadcastPreviewFrameAvailable")
        defaults.set(writerCreationFailed ? "failed to create writer" : (writer?.statusText ?? "not recording"), forKey: "broadcastWriterStatus")

        if let error = lastWriterError ?? writer?.errorDescription {
            defaults.set(error, forKey: "broadcastWriterError")
        } else {
            defaults.removeObject(forKey: "broadcastWriterError")
        }

        defaults.synchronize()
    }
}

private enum Shared {
    static let appGroupID = "group.com.snilelife.zgreplayvisualoverlay"
    static let pasteboardName = "com.snilelife.zgreplayvisualoverlay.shared"
    static let pasteboardOverlayKey = "zg_overlay_state_json"
    static let pasteboardPreviewKey = "zg_preview_frame_jpeg"
    static let pasteboardPreviewTimestampKey = "zg_preview_frame_timestamp"
    /// Optional fallback bridge when App Group signing is broken.
    /// Must match ZGShared.relayBaseURL in the main app target.
    static let relayBaseURL = "https://zg-overlay-relay-2.onrender.com"
    static let relayStreamKey = "zg-default"

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    static var pasteboard: UIPasteboard? {
        UIPasteboard(name: UIPasteboard.Name(pasteboardName), create: true)
    }
}

private enum RelayClient {
    static func postState(_ data: Data) {
        post(data, path: "/push/\(Shared.relayStreamKey)/state", contentType: "application/json")
    }

    static func postFrame(_ data: Data) {
        post(data, path: "/push/\(Shared.relayStreamKey)/frame", contentType: "image/jpeg")
    }

    private static func post(_ data: Data, path: String, contentType: String) {
        guard let url = endpoint(path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 2.5
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.httpBody = data
        URLSession.shared.dataTask(with: request).resume()
    }

    private static func endpoint(_ path: String) -> URL? {
        let raw = Shared.relayBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        let base = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
        return URL(string: base + path)
    }
}

private struct BroadcastSettings {
    var scannerEnabled: Bool
    var holdScanResult: Bool
    var predictionEnabled: Bool
    var keepLine: Bool
    var manualPocket: Bool
    var showSideLines: Bool
    var recordAnnotatedVideo: Bool
    var showDetectedBalls: Bool
    var showGhostBall: Bool
    var fastScanMode: Bool
    var lineLength: Double
    var holdScanSeconds: Double
    var maxBounces: Int
    var selectedPocket: Int
    var scanRoute: Int
    var predictionStyle: Int

    var clampedHoldSeconds: Double {
        min(30.0, max(2.0, holdScanSeconds))
    }

    static func load() -> BroadcastSettings {
        let defaults = Shared.defaults
        let hasSavedSettings = defaults.object(forKey: "predictionEnabled") != nil
        return BroadcastSettings(
            scannerEnabled: defaults.object(forKey: "scannerEnabled") == nil ? true : defaults.bool(forKey: "scannerEnabled"),
            holdScanResult: defaults.object(forKey: "holdScanResult") == nil ? true : defaults.bool(forKey: "holdScanResult"),
            predictionEnabled: hasSavedSettings ? defaults.bool(forKey: "predictionEnabled") : true,
            keepLine: hasSavedSettings ? defaults.bool(forKey: "keepLine") : true,
            manualPocket: defaults.bool(forKey: "manualPocket"),
            showSideLines: hasSavedSettings ? defaults.bool(forKey: "showSideLines") : true,
            recordAnnotatedVideo: hasSavedSettings ? defaults.bool(forKey: "recordAnnotatedVideo") : true,
            showDetectedBalls: hasSavedSettings ? defaults.bool(forKey: "showDetectedBalls") : true,
            showGhostBall: hasSavedSettings ? defaults.bool(forKey: "showGhostBall") : true,
            fastScanMode: defaults.object(forKey: "fastScanMode") == nil ? true : defaults.bool(forKey: "fastScanMode"),
            lineLength: defaults.object(forKey: "lineLength") as? Double ?? 0.86,
            holdScanSeconds: defaults.object(forKey: "holdScanSeconds") as? Double ?? 8.0,
            maxBounces: defaults.object(forKey: "maxBounces") as? Int ?? 3,
            selectedPocket: defaults.object(forKey: "selectedPocket") as? Int ?? 1,
            scanRoute: defaults.object(forKey: "scanRoute") as? Int ?? 0,
            predictionStyle: defaults.object(forKey: "predictionStyle") as? Int ?? 1
        )
    }
}

private struct OverlayModel: Codable {
    var timestamp: Double
    var note: String
    var scene: String
    var tableConfidence: Double
    var table: OverlayRect
    var lines: [OverlayLine]
    var circles: [OverlayCircle]
    var detectedBalls: Int
    var selectedPocket: Int

    static func empty(note: String) -> OverlayModel {
        OverlayModel(
            timestamp: Date().timeIntervalSince1970,
            note: note,
            scene: "unknown",
            tableConfidence: 0,
            table: OverlayRect(x: 0, y: 0, width: 0, height: 0),
            lines: [],
            circles: [],
            detectedBalls: 0,
            selectedPocket: 0
        )
    }
}

private struct OverlayRect: Codable { var x: Double; var y: Double; var width: Double; var height: Double }
private struct OverlayLine: Codable { var startX: Double; var startY: Double; var endX: Double; var endY: Double; var red: Double; var green: Double; var blue: Double; var alpha: Double; var width: Double }
private struct OverlayCircle: Codable { var x: Double; var y: Double; var radius: Double; var red: Double; var green: Double; var blue: Double; var alpha: Double; var width: Double }

private struct BallCandidate {
    var center: CGPoint
    var radius: Double
    var score: Double
    var isCueLike: Bool
}

private struct ShotChoice {
    var cue: CGPoint
    var object: CGPoint
    var pocket: CGPoint
    var ghost: CGPoint
    var score: Double
    var pocketIndex: Int
}

private struct TableDetection {
    var rect: CGRect
    var scene: String
    var confidence: Double
    var greenHits: Int
    var sampledPixels: Int
    var pocketHits: Int

    var isGameplay: Bool {
        scene == "gameplay_table" && confidence >= 0.54 && pocketHits >= 3
    }
}

private struct Accum {
    var sumX = 0.0
    var sumY = 0.0
    var weight = 0.0
    var count = 0
    mutating func add(x: Int, y: Int, weight w: Double) {
        sumX += Double(x) * w
        sumY += Double(y) * w
        weight += w
        count += 1
    }
    var center: CGPoint { CGPoint(x: sumX / max(0.001, weight), y: sumY / max(0.001, weight)) }
}

private final class FrameAnalyzer {
    private let ciContext = CIContext(options: nil)
    private var stableTable: CGRect?

    func makeOverlay(from sampleBuffer: CMSampleBuffer, settings: BroadcastSettings) -> OverlayModel {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .empty(note: "no video buffer")
        }

        let analysisBuffer = makeBGRAIfNeeded(sourceBuffer) ?? sourceBuffer
        let width = Double(CVPixelBufferGetWidth(analysisBuffer))
        let height = Double(CVPixelBufferGetHeight(analysisBuffer))
        let tableDetection = detectTable(in: analysisBuffer, width: width, height: height)
        let table = tableDetection.rect
        let route = max(0, min(settings.scanRoute, 3))

        guard tableDetection.isGameplay else {
            return OverlayModel(
                timestamp: Date().timeIntervalSince1970,
                note: "scene=\(tableDetection.scene), table confidence=\(String(format: "%.2f", tableDetection.confidence)), pockets=\(tableDetection.pocketHits). Waiting for a top-down gameplay table.",
                scene: tableDetection.scene,
                tableConfidence: tableDetection.confidence,
                table: OverlayRect(x: table.minX, y: table.minY, width: table.width, height: table.height),
                lines: [],
                circles: [],
                detectedBalls: 0,
                selectedPocket: 0
            )
        }

        let cue = findCueBall(in: analysisBuffer, table: table) ?? CGPoint(x: table.minX + table.width * 0.24, y: table.midY)
        let balls = findBallCandidates(in: analysisBuffer, table: table, cue: cue)
        let pockets = pocketPoints(table: table)
        let pocketIndex = max(0, min(settings.selectedPocket, pockets.count - 1))
        let choice = route == 1 || route == 3 ? nil : chooseShot(cue: cue, balls: balls, pockets: pockets, settings: settings)
        let aimPath = route == 2 || route == 3 ? [] : findAimPath(in: analysisBuffer, cue: cue, table: table, maxBounces: settings.maxBounces)
        let style = max(0, min(settings.predictionStyle, 2))

        var lines: [OverlayLine] = []
        var circles: [OverlayCircle] = []
        let ballRadius = max(8.0, table.width * 0.018)

        if settings.predictionEnabled {
            if style >= 2 {
                for pocket in pockets {
                    circles.append(circle(pocket, radius: max(10, table.width * 0.016), color: (0.08, 0.95, 1.0, 0.46), width: 2.0))
                }
            }

            if aimPath.count >= 2 {
                for index in 0..<max(0, aimPath.count - 1) {
                    addStyledLine(
                        aimPath[index],
                        aimPath[index + 1],
                        color: index == 0 ? (1, 1, 1, 0.96) : (0.18, 0.88, 1.0, 0.74),
                        width: index == 0 ? (style >= 2 ? 4.2 : style == 1 ? 3.4 : 2.7) : (style >= 2 ? 2.8 : 2.0),
                        style: style,
                        lines: &lines
                    )
                }

                if style >= 2, let choice {
                    addStyledLine(choice.object, choice.pocket, color: (0.12, 0.92, 1.0, 0.70), width: 2.4, style: style, lines: &lines)
                    circles.append(circle(choice.ghost, radius: ballRadius, color: (1.0, 0.84, 0.10, 0.92), width: 2.6))
                }
            } else if let choice {
                addStyledLine(choice.cue, choice.ghost, color: (1, 1, 1, 0.94), width: style >= 2 ? 4.0 : style == 1 ? 3.2 : 2.7, style: style, lines: &lines)
                addStyledLine(choice.object, choice.pocket, color: (0.10, 0.86, 1.0, 0.88), width: style >= 2 ? 3.1 : 2.4, style: style, lines: &lines)

                if style >= 2 {
                    addStyledLine(choice.ghost, choice.object, color: (1.0, 0.84, 0.10, 0.78), width: 2.0, style: style, lines: &lines)
                }

                if settings.showGhostBall {
                    circles.append(circle(choice.ghost, radius: ballRadius, color: (1.0, 0.84, 0.10, 0.96), width: style >= 2 ? 3.2 : 2.6))
                    if style >= 2 {
                        circles.append(circle(choice.object, radius: ballRadius * 1.18, color: (0.10, 0.86, 1.0, 0.66), width: 2.2))
                    }
                }

                if style >= 1 {
                    let after = cueAfterHitPath(cue: choice.cue, ghost: choice.ghost, object: choice.object, table: table, count: settings.maxBounces)
                    for index in 0..<max(0, after.count - 1) {
                        addStyledLine(after[index], after[index + 1], color: (0.70, 1.00, 0.12, 0.70), width: style >= 2 ? 2.5 : 2.0, style: style, lines: &lines)
                    }
                }

                if style >= 2 {
                    for guide in bankGuides(from: choice.object, to: choice.pocket, table: table).prefix(3) {
                        guard guide.count == 3 else { continue }
                        addStyledLine(guide[0], guide[1], color: (0.72, 0.40, 1.0, 0.36), width: 1.8, style: style, lines: &lines)
                        addStyledLine(guide[1], guide[2], color: (0.72, 0.40, 1.0, 0.36), width: 1.8, style: style, lines: &lines)
                    }
                }
            } else {
                let targetPocket = settings.manualPocket ? pockets[pocketIndex] : nearestPocket(to: cue, pockets: pockets)
                let aimEnd = clamp(point(from: cue, toward: targetPocket, distance: hypot(table.width, table.height) * settings.lineLength), to: table)
                addStyledLine(cue, aimEnd, color: (1, 1, 1, 0.92), width: style >= 2 ? 3.8 : style == 1 ? 3.0 : 2.6, style: style, lines: &lines)
                if style >= 1 {
                    addStyledLine(aimEnd, targetPocket, color: (0.15, 0.82, 1.0, 0.82), width: style >= 2 ? 2.8 : 2.2, style: style, lines: &lines)
                }
            }

            if settings.showSideLines {
                let sideAlpha = style >= 2 ? 0.26 : 0.18
                lines.append(line(CGPoint(x: table.minX, y: table.midY), CGPoint(x: table.maxX, y: table.midY), color: (1.0, 0.86, 0.18, sideAlpha), width: style >= 2 ? 1.4 : 1.0))
                lines.append(line(CGPoint(x: table.midX, y: table.minY), CGPoint(x: table.midX, y: table.maxY), color: (1.0, 0.86, 0.18, sideAlpha), width: style >= 2 ? 1.4 : 1.0))
            }

            if aimPath.isEmpty && route != 1 && style >= 1 {
                let bounceStart = choice?.cue ?? cue
                let bounceTarget = choice?.pocket ?? pockets[pocketIndex]
                let bounces = bouncePath(start: bounceStart, toward: bounceTarget, table: table, count: settings.maxBounces)
                for index in 0..<max(0, bounces.count - 1) {
                    addStyledLine(bounces[index], bounces[index + 1], color: (0.45, 0.40, 1.0, style >= 2 ? 0.58 : 0.42), width: style >= 2 ? 1.9 : 1.5, style: style, lines: &lines)
                }
            }

            circles.append(circle(cue, radius: ballRadius, color: (1, 1, 1, 0.96), width: style >= 2 ? 3.6 : 2.8))
            let selected = choice?.pocket ?? pockets[pocketIndex]
            circles.append(circle(selected, radius: max(13, table.width * (style >= 2 ? 0.030 : 0.023)), color: (0.1, 0.88, 1.0, 0.94), width: style >= 2 ? 4.2 : 3.0))

            if settings.showDetectedBalls {
                let maxBallMarkers = style >= 2 ? 16 : style == 1 ? 10 : 6
                for ball in balls.prefix(maxBallMarkers) {
                    circles.append(circle(ball.center, radius: ball.radius, color: ball.isCueLike ? (1, 1, 1, 0.75) : (1.0, 0.20, 0.20, style >= 2 ? 0.70 : 0.54), width: style >= 2 ? 2.2 : 1.7))
                }
            }
        }

        let note: String
        if !aimPath.isEmpty {
            note = "route=\(routeName(route)), style=\(styleName(style)), scene=gameplay_table, aim guide=ok, balls=\(balls.count), confidence=\(String(format: "%.2f", tableDetection.confidence))"
        } else if choice != nil {
            note = "route=\(routeName(route)), style=\(styleName(style)), scene=gameplay_table, table=ok, balls=\(balls.count), shot candidate=ok, confidence=\(String(format: "%.2f", tableDetection.confidence))"
        } else {
            note = "route=\(routeName(route)), style=\(styleName(style)), scene=gameplay_table, fallback: table=ok, balls=\(balls.count), confidence=\(String(format: "%.2f", tableDetection.confidence))"
        }

        return OverlayModel(
            timestamp: Date().timeIntervalSince1970,
            note: note,
            scene: tableDetection.scene,
            tableConfidence: tableDetection.confidence,
            table: OverlayRect(x: table.minX, y: table.minY, width: table.width, height: table.height),
            lines: lines,
            circles: circles,
            detectedBalls: balls.count,
            selectedPocket: choice?.pocketIndex ?? pocketIndex
        )
    }

    private func makeBGRAIfNeeded(_ buffer: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(buffer)
        if format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB { return buffer }

        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        var out: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as CFDictionary,
            &out
        )
        guard let out else { return nil }
        ciContext.render(CIImage(cvPixelBuffer: buffer), to: out)
        return out
    }

    private func detectTable(in pixelBuffer: CVPixelBuffer, width: Double, height: Double) -> TableDetection {
        let landscape = width >= height
        let fallback = landscape
            ? CGRect(x: width * 0.17, y: height * 0.16, width: width * 0.66, height: height * 0.70)
            : CGRect(x: width * 0.19, y: height * 0.16, width: width * 0.62, height: height * 0.68)

        guard let reader = PixelReader(pixelBuffer: pixelBuffer) else {
            return TableDetection(rect: fallback, scene: "unknown", confidence: 0, greenHits: 0, sampledPixels: 0, pocketHits: 0)
        }
        let search = landscape
            ? CGRect(x: width * 0.10, y: height * 0.08, width: width * 0.80, height: height * 0.86)
            : CGRect(x: width * 0.08, y: height * 0.20, width: width * 0.84, height: height * 0.62)

        var minX = Int(width), minY = Int(height), maxX = 0, maxY = 0
        var greenHits = 0
        var sampledPixels = 0
        let step = 8
        reader.withLockedBuffer {
            for y in stride(from: max(0, Int(search.minY)), through: min(Int(height) - 1, Int(search.maxY)), by: step) {
                for x in stride(from: max(0, Int(search.minX)), through: min(Int(width) - 1, Int(search.maxX)), by: step) {
                    sampledPixels += 1
                    let rgb = reader.rgbAt(x: x, y: y)
                    if isGreenCloth(rgb) {
                        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); greenHits += 1
                    }
                }
            }
        }

        let greenRatio = Double(greenHits) / Double(max(1, sampledPixels))
        let screen = CGRect(x: 0, y: 0, width: width, height: height)
        let detected: CGRect
        if greenHits > 120 {
            let greenRect = CGRect(x: Double(minX), y: Double(minY), width: Double(maxX - minX), height: Double(maxY - minY))
            detected = greenRect
                .insetBy(dx: -max(18, greenRect.width * 0.055), dy: -max(18, greenRect.height * 0.075))
                .intersection(screen)
        } else {
            detected = fallback
        }

        let aspect = detected.width / max(1.0, detected.height)
        let areaRatio = detected.width * detected.height / max(1.0, width * height)
        let aspectScore = clamp01(1.0 - abs(aspect - 2.0) / 0.85)
        let areaScore = clamp01(1.0 - abs(areaRatio - 0.46) / 0.34)

        var pocketHits = 0
        reader.withLockedBuffer {
            pocketHits = countPocketHits(reader: reader, table: detected)
        }
        let pocketScore = Double(pocketHits) / 6.0
        var finalRect = detected
        var confidence = clamp01(greenRatio * 2.25 + pocketScore * 0.46 + aspectScore * 0.24 + areaScore * 0.18)

        var scene: String
        if confidence >= 0.54 && pocketHits >= 3 && greenRatio > 0.10 {
            scene = "gameplay_table"
        } else if greenRatio > 0.08 || pocketHits >= 2 {
            scene = "partial_table_or_transition"
        } else {
            scene = "lobby_menu"
        }

        if scene == "gameplay_table" {
            if let stableTable, rectsAreClose(stableTable, finalRect, screen: screen) {
                finalRect = blend(previous: stableTable, current: finalRect, currentWeight: 0.42)
            }
            stableTable = finalRect
        } else if let stableTable, scene == "partial_table_or_transition" {
            finalRect = stableTable
            confidence = max(confidence, 0.50)
        }

        return TableDetection(rect: finalRect, scene: scene, confidence: confidence, greenHits: greenHits, sampledPixels: sampledPixels, pocketHits: pocketHits)
    }

    private func isGreenCloth(_ rgb: RGB) -> Bool {
        rgb.green > 64 &&
        rgb.green > rgb.red * 1.12 &&
        rgb.green > rgb.blue * 1.03 &&
        rgb.luma > 45 &&
        rgb.luma < 205 &&
        rgb.saturation > 28
    }

    private func rectsAreClose(_ a: CGRect, _ b: CGRect, screen: CGRect) -> Bool {
        let screenDiagonal = hypot(screen.width, screen.height)
        let centerDistance = hypot(a.midX - b.midX, a.midY - b.midY)
        let sizeDelta = abs(a.width - b.width) + abs(a.height - b.height)
        return centerDistance < screenDiagonal * 0.045 && sizeDelta < screenDiagonal * 0.11
    }

    private func blend(previous: CGRect, current: CGRect, currentWeight: CGFloat) -> CGRect {
        let oldWeight = 1.0 - currentWeight
        return CGRect(
            x: previous.minX * oldWeight + current.minX * currentWeight,
            y: previous.minY * oldWeight + current.minY * currentWeight,
            width: previous.width * oldWeight + current.width * currentWeight,
            height: previous.height * oldWeight + current.height * currentWeight
        )
    }

    private func countPocketHits(reader: PixelReader, table: CGRect) -> Int {
        let points = pocketPoints(table: table)
        let radius = max(16, min(table.width, table.height) * 0.060)
        var hits = 0

        for point in points {
            var dark = 0
            var total = 0
            for y in stride(from: Int(point.y - radius), through: Int(point.y + radius), by: 4) {
                for x in stride(from: Int(point.x - radius), through: Int(point.x + radius), by: 4) {
                    let dx = CGFloat(x) - point.x
                    let dy = CGFloat(y) - point.y
                    guard dx * dx + dy * dy <= radius * radius else { continue }
                    let rgb = reader.rgbAt(x: x, y: y)
                    total += 1
                    if rgb.luma < 55 && rgb.saturation < 105 {
                        dark += 1
                    }
                }
            }
            if total > 0 && Double(dark) / Double(total) > 0.14 {
                hits += 1
            }
        }

        return hits
    }

    private func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }

    private func routeName(_ route: Int) -> String {
        switch route {
        case 1: return "guide_lock"
        case 2: return "ball_geometry"
        case 3: return "corner_lock"
        default: return "auto_hybrid"
        }
    }

    private func styleName(_ style: Int) -> String {
        switch style {
        case 0: return "simple"
        case 2: return "pro_video"
        default: return "advanced"
        }
    }

    private func addStyledLine(
        _ start: CGPoint,
        _ end: CGPoint,
        color: (Double, Double, Double, Double),
        width: Double,
        style: Int,
        lines: inout [OverlayLine]
    ) {
        if style >= 2 {
            lines.append(line(start, end, color: (color.0, color.1, color.2, color.3 * 0.20), width: width * 3.1))
            lines.append(line(start, end, color: (color.0, color.1, color.2, color.3 * 0.34), width: width * 1.85))
        }
        lines.append(line(start, end, color: color, width: width))
    }

    private func bankGuides(from object: CGPoint, to pocket: CGPoint, table: CGRect) -> [[CGPoint]] {
        var guides: [[CGPoint]] = []
        if let top = railGuide(from: object, to: pocket, rail: .top, table: table) { guides.append(top) }
        if let bottom = railGuide(from: object, to: pocket, rail: .bottom, table: table) { guides.append(bottom) }
        if let left = railGuide(from: object, to: pocket, rail: .left, table: table) { guides.append(left) }
        if let right = railGuide(from: object, to: pocket, rail: .right, table: table) { guides.append(right) }

        return guides.sorted {
            guideLength($0) < guideLength($1)
        }
    }

    private enum Rail { case top, bottom, left, right }

    private func railGuide(from object: CGPoint, to pocket: CGPoint, rail: Rail, table: CGRect) -> [CGPoint]? {
        let mirror: CGPoint
        switch rail {
        case .top:
            mirror = CGPoint(x: pocket.x, y: table.minY * 2 - pocket.y)
        case .bottom:
            mirror = CGPoint(x: pocket.x, y: table.maxY * 2 - pocket.y)
        case .left:
            mirror = CGPoint(x: table.minX * 2 - pocket.x, y: pocket.y)
        case .right:
            mirror = CGPoint(x: table.maxX * 2 - pocket.x, y: pocket.y)
        }

        let dx = mirror.x - object.x
        let dy = mirror.y - object.y
        let t: CGFloat
        switch rail {
        case .top:
            guard abs(dy) > 0.001 else { return nil }
            t = (table.minY - object.y) / dy
        case .bottom:
            guard abs(dy) > 0.001 else { return nil }
            t = (table.maxY - object.y) / dy
        case .left:
            guard abs(dx) > 0.001 else { return nil }
            t = (table.minX - object.x) / dx
        case .right:
            guard abs(dx) > 0.001 else { return nil }
            t = (table.maxX - object.x) / dx
        }

        guard t > 0.05 && t < 0.95 else { return nil }
        let railPoint = CGPoint(x: object.x + dx * t, y: object.y + dy * t)
        guard table.insetBy(dx: -2, dy: -2).contains(railPoint) else { return nil }
        return [object, railPoint, pocket]
    }

    private func guideLength(_ guide: [CGPoint]) -> CGFloat {
        guard guide.count == 3 else { return .greatestFiniteMagnitude }
        return hypot(guide[1].x - guide[0].x, guide[1].y - guide[0].y) +
            hypot(guide[2].x - guide[1].x, guide[2].y - guide[1].y)
    }

    private func findCueBall(in pixelBuffer: CVPixelBuffer, table: CGRect) -> CGPoint? {
        guard let reader = PixelReader(pixelBuffer: pixelBuffer) else { return nil }
        var bins: [String: Accum] = [:]
        let binSize = max(18, Int(table.width / 28.0))
        let inner = table.insetBy(dx: table.width * 0.035, dy: table.height * 0.05)

        reader.withLockedBuffer {
            for y in stride(from: max(0, Int(inner.minY)), through: min(reader.height - 1, Int(inner.maxY)), by: 4) {
                for x in stride(from: max(0, Int(inner.minX)), through: min(reader.width - 1, Int(inner.maxX)), by: 4) {
                    let rgb = reader.rgbAt(x: x, y: y)
                    if rgb.luma > 186 && rgb.saturation < 65 {
                        let key = "\(x / binSize),\(y / binSize)"
                        var acc = bins[key] ?? Accum()
                        acc.add(x: x, y: y, weight: max(1.0, rgb.luma - 176.0))
                        bins[key] = acc
                    }
                }
            }
        }

        guard let best = bins.values.max(by: { $0.weight < $1.weight }), best.weight > 260 else { return nil }
        return best.center
    }

    private func findBallCandidates(in pixelBuffer: CVPixelBuffer, table: CGRect, cue: CGPoint) -> [BallCandidate] {
        guard let reader = PixelReader(pixelBuffer: pixelBuffer) else { return [] }
        var bins: [String: Accum] = [:]
        let ballRadius = max(8.0, table.width * 0.018)
        let binSize = max(16, Int(ballRadius * 2.2))
        let inner = table.insetBy(dx: ballRadius * 1.3, dy: ballRadius * 1.3)

        reader.withLockedBuffer {
            for y in stride(from: max(0, Int(inner.minY)), through: min(reader.height - 1, Int(inner.maxY)), by: 5) {
                for x in stride(from: max(0, Int(inner.minX)), through: min(reader.width - 1, Int(inner.maxX)), by: 5) {
                    let rgb = reader.rgbAt(x: x, y: y)
                    let isWhite = rgb.luma > 186 && rgb.saturation < 65
                    let isColored = rgb.saturation > 54 && rgb.luma > 38 && rgb.luma < 238
                    let isBlackBall = rgb.luma > 18 && rgb.luma < 58 && rgb.saturation < 45
                    if isWhite || isColored || isBlackBall {
                        let key = "\(x / binSize),\(y / binSize)"
                        var acc = bins[key] ?? Accum()
                        let w = isWhite ? 0.7 : max(1.0, rgb.saturation / 18.0)
                        acc.add(x: x, y: y, weight: w)
                        bins[key] = acc
                    }
                }
            }
        }

        var raw = bins.values
            .filter { $0.count >= 3 }
            .map { acc -> BallCandidate in
                let center = acc.center
                let isCueLike = hypot(center.x - cue.x, center.y - cue.y) < ballRadius * 2.2
                return BallCandidate(center: center, radius: ballRadius, score: acc.weight, isCueLike: isCueLike)
            }
            .sorted { $0.score > $1.score }

        var kept: [BallCandidate] = []
        for ball in raw {
            if kept.allSatisfy({ hypot($0.center.x - ball.center.x, $0.center.y - ball.center.y) > ballRadius * 2.0 }) {
                kept.append(ball)
            }
            if kept.count >= 14 { break }
        }
        raw.removeAll()
        return kept
    }

    private func chooseShot(cue: CGPoint, balls: [BallCandidate], pockets: [CGPoint], settings: BroadcastSettings) -> ShotChoice? {
        let objectBalls = balls.filter { !$0.isCueLike && hypot($0.center.x - cue.x, $0.center.y - cue.y) > $0.radius * 2.5 }
        guard !objectBalls.isEmpty else { return nil }

        let pocketIndexes: [Int] = settings.manualPocket ? [max(0, min(settings.selectedPocket, pockets.count - 1))] : Array(0..<pockets.count)
        var best: ShotChoice?

        for ball in objectBalls {
            for pi in pocketIndexes {
                let pocket = pockets[pi]
                let dx = pocket.x - ball.center.x
                let dy = pocket.y - ball.center.y
                let objectToPocket = max(0.001, hypot(dx, dy))
                let ux = dx / objectToPocket
                let uy = dy / objectToPocket
                let ghost = CGPoint(x: ball.center.x - ux * ball.radius * 2.0, y: ball.center.y - uy * ball.radius * 2.0)
                let cueToGhost = hypot(ghost.x - cue.x, ghost.y - cue.y)
                let directness = abs(cross(a: CGPoint(x: ghost.x - cue.x, y: ghost.y - cue.y), b: CGPoint(x: ball.center.x - cue.x, y: ball.center.y - cue.y))) / max(1.0, cueToGhost)
                let score = cueToGhost + objectToPocket * 0.62 + directness * 4.0 - ball.score * 0.02
                let candidate = ShotChoice(cue: cue, object: ball.center, pocket: pocket, ghost: ghost, score: score, pocketIndex: pi)
                if best == nil || candidate.score < best!.score { best = candidate }
            }
        }
        return best
    }

    private func findAimPath(in pixelBuffer: CVPixelBuffer, cue: CGPoint, table: CGRect, maxBounces: Int) -> [CGPoint] {
        guard let reader = PixelReader(pixelBuffer: pixelBuffer) else { return [] }

        let ballRadius = max(8.0, Double(table.width) * 0.018)
        let maxDistance = Double(hypot(table.width, table.height))
        let tableWithTolerance = table.insetBy(dx: -6, dy: -6)
        var bestAngle: Double?
        var bestScore = 0.0

        reader.withLockedBuffer {
            for degrees in stride(from: 0, to: 360, by: 3) {
                let angle = Double(degrees) * Double.pi / 180.0
                let ux = CGFloat(cos(angle))
                let uy = CGFloat(sin(angle))
                var score = 0.0
                var streak = 0.0
                var samples = 0

                for distance in stride(from: ballRadius * 2.35, through: maxDistance, by: max(5.0, ballRadius * 0.34)) {
                    let point = CGPoint(x: cue.x + CGFloat(distance) * ux, y: cue.y + CGFloat(distance) * uy)
                    guard tableWithTolerance.contains(point) else { break }
                    samples += 1

                    if guideLineHit(reader: reader, point: point, ux: ux, uy: uy) {
                        streak = min(streak + 1.0, 8.0)
                        score += 2.0 + streak * 0.75
                    } else {
                        streak = max(0.0, streak - 1.5)
                    }
                }

                if samples >= 10 && score > bestScore {
                    bestScore = score
                    bestAngle = angle
                }
            }
        }

        guard let bestAngle, bestScore > 28.0 else { return [] }
        let ux = CGFloat(cos(bestAngle))
        let uy = CGFloat(sin(bestAngle))
        let target = CGPoint(x: cue.x + CGFloat(maxDistance * 1.6) * ux, y: cue.y + CGFloat(maxDistance * 1.6) * uy)
        return bouncePath(start: cue, toward: target, table: table, count: max(1, maxBounces + 1))
    }

    private func guideLineHit(reader: PixelReader, point: CGPoint, ux: CGFloat, uy: CGFloat) -> Bool {
        let nx = -uy
        let ny = ux
        var hits = 0

        for offset in [-3.0, 0.0, 3.0] {
            let sample = CGPoint(x: point.x + CGFloat(offset) * nx, y: point.y + CGFloat(offset) * ny)
            let rgb = reader.rgbAt(x: Int(sample.x.rounded()), y: Int(sample.y.rounded()))
            let whiteGuide = rgb.luma > 142 && rgb.saturation < 95
            let paleGuide = rgb.luma > 118 && rgb.saturation < 58
            if whiteGuide || paleGuide {
                hits += 1
            }
        }

        return hits >= 2
    }

    private func cross(a: CGPoint, b: CGPoint) -> Double { Double(a.x * b.y - a.y * b.x) }

    private func pocketPoints(table: CGRect) -> [CGPoint] {
        [
            CGPoint(x: table.minX, y: table.minY),
            CGPoint(x: table.midX, y: table.minY),
            CGPoint(x: table.maxX, y: table.minY),
            CGPoint(x: table.minX, y: table.maxY),
            CGPoint(x: table.midX, y: table.maxY),
            CGPoint(x: table.maxX, y: table.maxY)
        ]
    }

    private func nearestPocket(to point: CGPoint, pockets: [CGPoint]) -> CGPoint {
        pockets.min { hypot($0.x - point.x, $0.y - point.y) < hypot($1.x - point.x, $1.y - point.y) } ?? pockets[0]
    }

    private func point(from start: CGPoint, toward end: CGPoint, distance: Double) -> CGPoint {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(0.001, hypot(dx, dy))
        return CGPoint(x: start.x + dx / length * distance, y: start.y + dy / length * distance)
    }

    private func clamp(_ p: CGPoint, to rect: CGRect) -> CGPoint {
        CGPoint(x: min(max(p.x, rect.minX), rect.maxX), y: min(max(p.y, rect.minY), rect.maxY))
    }

    private func cueAfterHitPath(cue: CGPoint, ghost: CGPoint, object: CGPoint, table: CGRect, count: Int) -> [CGPoint] {
        let incoming = CGPoint(x: ghost.x - cue.x, y: ghost.y - cue.y)
        let normal = CGPoint(x: object.x - ghost.x, y: object.y - ghost.y)
        let nl = max(0.001, hypot(normal.x, normal.y))
        let nx = normal.x / nl
        let ny = normal.y / nl
        let dot = incoming.x * nx + incoming.y * ny
        let tangent = CGPoint(x: incoming.x - dot * nx, y: incoming.y - dot * ny)
        let end = CGPoint(x: ghost.x + tangent.x, y: ghost.y + tangent.y)
        return bouncePath(start: ghost, toward: end, table: table, count: max(1, count))
    }

    private func bouncePath(start: CGPoint, toward target: CGPoint, table: CGRect, count: Int) -> [CGPoint] {
        guard count > 0 else { return [] }
        var points = [start]
        var current = start
        var vx = target.x - start.x
        var vy = target.y - start.y
        let length = max(0.001, hypot(vx, vy))
        vx /= length; vy /= length

        for _ in 0..<count {
            let tx = vx > 0 ? (table.maxX - current.x) / vx : (table.minX - current.x) / vx
            let ty = vy > 0 ? (table.maxY - current.y) / vy : (table.minY - current.y) / vy
            let t = max(0.001, min(abs(tx), abs(ty)))
            let next = CGPoint(x: current.x + vx * t, y: current.y + vy * t)
            points.append(next)
            if abs(next.x - table.minX) < 1 || abs(next.x - table.maxX) < 1 { vx = -vx }
            if abs(next.y - table.minY) < 1 || abs(next.y - table.maxY) < 1 { vy = -vy }
            current = next
        }
        return points
    }

    private func line(_ start: CGPoint, _ end: CGPoint, color: (Double, Double, Double, Double), width: Double) -> OverlayLine {
        OverlayLine(startX: start.x, startY: start.y, endX: end.x, endY: end.y, red: color.0, green: color.1, blue: color.2, alpha: color.3, width: width)
    }

    private func circle(_ center: CGPoint, radius: Double, color: (Double, Double, Double, Double), width: Double) -> OverlayCircle {
        OverlayCircle(x: center.x, y: center.y, radius: radius, red: color.0, green: color.1, blue: color.2, alpha: color.3, width: width)
    }
}

private struct RGB {
    var red: Double
    var green: Double
    var blue: Double
    var luma: Double { 0.2126 * red + 0.7152 * green + 0.0722 * blue }
    var saturation: Double { max(red, max(green, blue)) - min(red, min(green, blue)) }
}

private final class PixelReader {
    let width: Int
    let height: Int
    private let format: OSType
    private let pixelBuffer: CVPixelBuffer
    private var bytes: UnsafeMutablePointer<UInt8>?
    private var rowBytes: Int = 0

    init?(pixelBuffer: CVPixelBuffer) {
        self.format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA || format == kCVPixelFormatType_32ARGB else { return nil }
        self.pixelBuffer = pixelBuffer
        self.width = CVPixelBufferGetWidth(pixelBuffer)
        self.height = CVPixelBufferGetHeight(pixelBuffer)
    }

    func withLockedBuffer(_ block: () -> Void) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        bytes = CVPixelBufferGetBaseAddress(pixelBuffer)?.assumingMemoryBound(to: UInt8.self)
        rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        block()
        bytes = nil
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
    }

    func rgbAt(x: Int, y: Int) -> RGB {
        guard let bytes else { return RGB(red: 0, green: 0, blue: 0) }
        let safeX = min(max(0, x), width - 1)
        let safeY = min(max(0, y), height - 1)
        let offset = safeY * rowBytes + safeX * 4
        if format == kCVPixelFormatType_32BGRA {
            return RGB(red: Double(bytes[offset + 2]), green: Double(bytes[offset + 1]), blue: Double(bytes[offset]))
        }
        return RGB(red: Double(bytes[offset + 1]), green: Double(bytes[offset + 2]), blue: Double(bytes[offset + 3]))
    }
}

private final class AnnotatedMovieWriter {
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let ciContext = CIContext()
    private var didStart = false

    init(outputURL: URL, width: Int, height: Int) throws {
        writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 4_000_000,
                    AVVideoExpectedSourceFrameRateKey: 30
                ]
            ]
        )
        input.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
        )
        if writer.canAdd(input) { writer.add(input) }
    }

    func append(_ sampleBuffer: CMSampleBuffer, overlay: OverlayModel) {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if !didStart {
            writer.startWriting()
            writer.startSession(atSourceTime: presentationTime)
            didStart = true
        }
        guard input.isReadyForMoreMediaData, writer.status == .writing, let pool = adaptor.pixelBufferPool else { return }
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &outputBuffer)
        guard let outputBuffer else { return }
        ciContext.render(CIImage(cvPixelBuffer: imageBuffer), to: outputBuffer)
        OverlayFrameDrawer.draw(overlay: overlay, into: outputBuffer)
        adaptor.append(outputBuffer, withPresentationTime: presentationTime)
    }

    func finish() {
        guard didStart, writer.status == .writing else { return }
        input.markAsFinished()
        writer.finishWriting {}
    }

    var statusText: String {
        switch writer.status {
        case .unknown:
            return didStart ? "unknown" : "waiting for first frame"
        case .writing:
            return "writing"
        case .completed:
            return "completed"
        case .failed:
            return "failed"
        case .cancelled:
            return "cancelled"
        @unknown default:
            return "unknown future status"
        }
    }

    var errorDescription: String? {
        writer.error?.localizedDescription
    }
}

private final class PreviewFrameWriter {
    private let ciContext = CIContext()
    private var lastWrite = Date.distantPast

    func write(_ sampleBuffer: CMSampleBuffer, overlay: OverlayModel, minimumInterval: TimeInterval) {
        guard Date().timeIntervalSince(lastWrite) > minimumInterval,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastWrite = Date()

        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        var outputBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            [
                kCVPixelBufferCGImageCompatibilityKey as String: true,
                kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ] as CFDictionary,
            &outputBuffer
        )
        guard let outputBuffer else { return }

        ciContext.render(CIImage(cvPixelBuffer: imageBuffer), to: outputBuffer)
        OverlayFrameDrawer.draw(overlay: overlay, into: outputBuffer)

        let ciImage = CIImage(cvPixelBuffer: outputBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: CGRect(x: 0, y: 0, width: width, height: height)) else { return }

        let outputURL = Shared.containerURL.appendingPathComponent("ZGPreviewFrame.jpg")
        let tempURL = Shared.containerURL.appendingPathComponent("ZGPreviewFrame.tmp.jpg")
        guard let destination = CGImageDestinationCreateWithURL(tempURL as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        let options = [kCGImageDestinationLossyCompressionQuality as String: 0.72] as CFDictionary
        CGImageDestinationAddImage(destination, cgImage, options)
        guard CGImageDestinationFinalize(destination) else { return }
        try? FileManager.default.removeItem(at: outputURL)
        try? FileManager.default.moveItem(at: tempURL, to: outputURL)
        if let data = try? Data(contentsOf: outputURL) {
            Shared.pasteboard?.setData(data, forPasteboardType: Shared.pasteboardPreviewKey)
            RelayClient.postFrame(data)
            if let timestampData = "\(Date().timeIntervalSince1970)".data(using: .utf8) {
                Shared.pasteboard?.setData(timestampData, forPasteboardType: Shared.pasteboardPreviewTimestampKey)
            }
        }
    }
}

private enum OverlayFrameDrawer {
    static func draw(overlay: OverlayModel, into pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(data: base, width: width, height: height, bitsPerComponent: 8, bytesPerRow: rowBytes, space: colorSpace, bitmapInfo: bitmapInfo) else { return }
        context.setLineCap(.round)
        context.setLineJoin(.round)

        if overlay.table.width > 0 && overlay.table.height > 0 {
            context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
            context.setLineWidth(1.2)
            context.stroke(CGRect(x: overlay.table.x, y: overlay.table.y, width: overlay.table.width, height: overlay.table.height))
        }

        for line in overlay.lines {
            context.setStrokeColor(CGColor(red: line.red, green: line.green, blue: line.blue, alpha: line.alpha))
            context.setLineWidth(CGFloat(line.width))
            context.move(to: CGPoint(x: line.startX, y: line.startY))
            context.addLine(to: CGPoint(x: line.endX, y: line.endY))
            context.strokePath()
        }
        for circle in overlay.circles {
            context.setStrokeColor(CGColor(red: circle.red, green: circle.green, blue: circle.blue, alpha: circle.alpha))
            context.setLineWidth(CGFloat(circle.width))
            context.strokeEllipse(in: CGRect(x: circle.x - circle.radius, y: circle.y - circle.radius, width: circle.radius * 2, height: circle.radius * 2))
        }
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
