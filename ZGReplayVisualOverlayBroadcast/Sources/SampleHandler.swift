import AVFoundation
import CoreGraphics
import CoreImage
import CoreMedia
import Foundation
import ReplayKit

final class SampleHandler: RPBroadcastSampleHandler {
    private let analyzer = FrameAnalyzer()
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
        let overlay: OverlayModel

        // Keep extension CPU safer: analyze about 5 times/second on a 60fps stream.
        if frameCount == 1 || frameCount % 12 == 0 || lastOverlay == nil {
            overlay = analyzer.makeOverlay(from: sampleBuffer, settings: settings)
            lastOverlay = overlay
            writeState(overlay, status: "running")
        } else {
            overlay = lastOverlay ?? analyzer.makeOverlay(from: sampleBuffer, settings: settings)
        }

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

    private func writeState(_ overlay: OverlayModel, status: String) {
        let url = Shared.containerURL.appendingPathComponent("zg_overlay_state.json")
        guard let data = try? JSONEncoder.pretty.encode(overlay) else { return }
        try? data.write(to: url, options: .atomic)
        writeDiagnostics(status: status, overlay: overlay)
    }

    private func writeDiagnostics(status: String, overlay: OverlayModel) {
        let replayURL = Shared.containerURL.appendingPathComponent("ZGAnnotatedReplay.mov")
        let defaults = Shared.defaults
        defaults.set(status, forKey: "broadcastStatus")
        defaults.set(Date().timeIntervalSince1970, forKey: "broadcastLastEvent")
        defaults.set(frameCount, forKey: "broadcastFrameCount")
        defaults.set(overlay.note, forKey: "broadcastLastNote")
        defaults.set(overlay.detectedBalls, forKey: "broadcastDetectedBalls")
        defaults.set(overlay.lines.count, forKey: "broadcastLineCount")
        defaults.set(FileManager.default.fileExists(atPath: replayURL.path), forKey: "broadcastReplayAvailable")
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

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) {
            return url
        }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    }

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}

private struct BroadcastSettings {
    var predictionEnabled: Bool
    var keepLine: Bool
    var manualPocket: Bool
    var showSideLines: Bool
    var recordAnnotatedVideo: Bool
    var showDetectedBalls: Bool
    var showGhostBall: Bool
    var lineLength: Double
    var maxBounces: Int
    var selectedPocket: Int

    static func load() -> BroadcastSettings {
        let defaults = Shared.defaults
        let hasSavedSettings = defaults.object(forKey: "predictionEnabled") != nil
        return BroadcastSettings(
            predictionEnabled: hasSavedSettings ? defaults.bool(forKey: "predictionEnabled") : true,
            keepLine: hasSavedSettings ? defaults.bool(forKey: "keepLine") : true,
            manualPocket: defaults.bool(forKey: "manualPocket"),
            showSideLines: hasSavedSettings ? defaults.bool(forKey: "showSideLines") : true,
            recordAnnotatedVideo: hasSavedSettings ? defaults.bool(forKey: "recordAnnotatedVideo") : true,
            showDetectedBalls: hasSavedSettings ? defaults.bool(forKey: "showDetectedBalls") : true,
            showGhostBall: hasSavedSettings ? defaults.bool(forKey: "showGhostBall") : true,
            lineLength: defaults.object(forKey: "lineLength") as? Double ?? 0.86,
            maxBounces: defaults.object(forKey: "maxBounces") as? Int ?? 3,
            selectedPocket: defaults.object(forKey: "selectedPocket") as? Int ?? 1
        )
    }
}

private struct OverlayModel: Codable {
    var timestamp: Double
    var note: String
    var table: OverlayRect
    var lines: [OverlayLine]
    var circles: [OverlayCircle]
    var detectedBalls: Int
    var selectedPocket: Int

    static func empty(note: String) -> OverlayModel {
        OverlayModel(
            timestamp: Date().timeIntervalSince1970,
            note: note,
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

    func makeOverlay(from sampleBuffer: CMSampleBuffer, settings: BroadcastSettings) -> OverlayModel {
        guard let sourceBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return .empty(note: "no video buffer")
        }

        let analysisBuffer = makeBGRAIfNeeded(sourceBuffer) ?? sourceBuffer
        let width = Double(CVPixelBufferGetWidth(analysisBuffer))
        let height = Double(CVPixelBufferGetHeight(analysisBuffer))
        let table = detectTableRect(in: analysisBuffer, width: width, height: height)

        let cue = findCueBall(in: analysisBuffer, table: table) ?? CGPoint(x: table.minX + table.width * 0.24, y: table.midY)
        let balls = findBallCandidates(in: analysisBuffer, table: table, cue: cue)
        let pockets = pocketPoints(table: table)
        let pocketIndex = max(0, min(settings.selectedPocket, pockets.count - 1))
        let choice = chooseShot(cue: cue, balls: balls, pockets: pockets, settings: settings)

        var lines: [OverlayLine] = []
        var circles: [OverlayCircle] = []
        let ballRadius = max(8.0, table.width * 0.018)

        if settings.predictionEnabled {
            if let choice {
                lines.append(line(choice.cue, choice.ghost, color: (1, 1, 1, 0.94), width: 3.2))
                lines.append(line(choice.object, choice.pocket, color: (0.10, 0.86, 1.0, 0.88), width: 2.6))

                if settings.showGhostBall {
                    circles.append(circle(choice.ghost, radius: ballRadius, color: (1.0, 0.84, 0.10, 0.96), width: 2.6))
                }

                let after = cueAfterHitPath(cue: choice.cue, ghost: choice.ghost, object: choice.object, table: table, count: settings.maxBounces)
                for index in 0..<max(0, after.count - 1) {
                    lines.append(line(after[index], after[index + 1], color: (0.70, 1.00, 0.12, 0.70), width: 2.0))
                }
            } else {
                let targetPocket = settings.manualPocket ? pockets[pocketIndex] : nearestPocket(to: cue, pockets: pockets)
                let aimEnd = clamp(point(from: cue, toward: targetPocket, distance: hypot(table.width, table.height) * settings.lineLength), to: table)
                lines.append(line(cue, aimEnd, color: (1, 1, 1, 0.92), width: 3.0))
                lines.append(line(aimEnd, targetPocket, color: (0.15, 0.82, 1.0, 0.82), width: 2.4))
            }

            if settings.showSideLines {
                lines.append(line(CGPoint(x: table.minX, y: table.midY), CGPoint(x: table.maxX, y: table.midY), color: (1.0, 0.86, 0.18, 0.30), width: 1.2))
                lines.append(line(CGPoint(x: table.midX, y: table.minY), CGPoint(x: table.midX, y: table.maxY), color: (1.0, 0.86, 0.18, 0.30), width: 1.2))
            }

            let bounceStart = choice?.cue ?? cue
            let bounceTarget = choice?.pocket ?? pockets[pocketIndex]
            let bounces = bouncePath(start: bounceStart, toward: bounceTarget, table: table, count: settings.maxBounces)
            for index in 0..<max(0, bounces.count - 1) {
                lines.append(line(bounces[index], bounces[index + 1], color: (0.45, 0.40, 1.0, 0.50), width: 1.5))
            }

            circles.append(circle(cue, radius: ballRadius, color: (1, 1, 1, 0.96), width: 2.8))
            let selected = choice?.pocket ?? pockets[pocketIndex]
            circles.append(circle(selected, radius: max(13, table.width * 0.023), color: (0.1, 0.88, 1.0, 0.94), width: 3.0))

            if settings.showDetectedBalls {
                for ball in balls.prefix(10) {
                    circles.append(circle(ball.center, radius: ball.radius, color: ball.isCueLike ? (1, 1, 1, 0.75) : (1.0, 0.20, 0.20, 0.62), width: 1.8))
                }
            }
        }

        let note: String
        if choice != nil {
            note = "visual scan: table=ok, balls=\(balls.count), shot candidate=ok"
        } else {
            note = "visual scan fallback: table=ok, balls=\(balls.count), no strong object-ball candidate"
        }

        return OverlayModel(
            timestamp: Date().timeIntervalSince1970,
            note: note,
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

    private func detectTableRect(in pixelBuffer: CVPixelBuffer, width: Double, height: Double) -> CGRect {
        let landscape = width >= height
        let fallback = landscape
            ? CGRect(x: width * 0.145, y: height * 0.205, width: width * 0.710, height: height * 0.585)
            : CGRect(x: width * 0.095, y: height * 0.365, width: width * 0.810, height: height * 0.260)

        guard let reader = PixelReader(pixelBuffer: pixelBuffer) else { return fallback }
        let search = landscape
            ? CGRect(x: width * 0.05, y: height * 0.10, width: width * 0.90, height: height * 0.78)
            : CGRect(x: width * 0.04, y: height * 0.28, width: width * 0.92, height: height * 0.46)

        var minX = Int(width), minY = Int(height), maxX = 0, maxY = 0, hits = 0
        let step = 12
        reader.withLockedBuffer {
            for y in stride(from: max(0, Int(search.minY)), through: min(Int(height) - 1, Int(search.maxY)), by: step) {
                for x in stride(from: max(0, Int(search.minX)), through: min(Int(width) - 1, Int(search.maxX)), by: step) {
                    let rgb = reader.rgbAt(x: x, y: y)
                    let luma = rgb.luma
                    let sat = rgb.saturation
                    // Pool cloth is usually saturated blue/green/dark gray; skip black bars and bright HUD.
                    if luma > 28 && luma < 185 && sat > 18 {
                        minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y); hits += 1
                    }
                }
            }
        }

        guard hits > 80 else { return fallback }
        let detected = CGRect(x: Double(minX), y: Double(minY), width: Double(maxX - minX), height: Double(maxY - minY)).insetBy(dx: -20, dy: -12)
        let aspect = detected.width / max(1.0, detected.height)
        if detected.width > width * 0.45 && detected.height > height * 0.16 && aspect > 1.25 {
            return detected.intersection(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return fallback
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
        draw(overlay: overlay, into: outputBuffer)
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

    private func draw(overlay: OverlayModel, into pixelBuffer: CVPixelBuffer) {
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

        // Draw table calibration rectangle first.
        context.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
        context.setLineWidth(1.2)
        context.stroke(CGRect(x: overlay.table.x, y: overlay.table.y, width: overlay.table.width, height: overlay.table.height))

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
