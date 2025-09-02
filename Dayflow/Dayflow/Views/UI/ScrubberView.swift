//
//  ScrubberView.swift
//  Dayflow
//
//  Minimal custom scrubber with baseline, draggable playhead, time chip,
//  and filmstrip thumbnails generated from the video.
//

import SwiftUI
import AVFoundation
import AppKit

// MARK: - Filmstrip Generator (lightweight cache)
final class FilmstripGenerator {
    static let shared = FilmstripGenerator()

    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.dayflow.filmstripgen"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    private let syncQueue = DispatchQueue(label: "com.dayflow.filmstripgen.sync")
    private var cache: [String: [NSImage]] = [:]
    private var inflight: [String: [(Int, [NSImage]) -> Void]] = [:]

    private init() {}

    func generate(url: URL, frameCount: Int, targetHeight: CGFloat, completion: @escaping (Int, [NSImage]) -> Void) {
        // Key by file path + mtime + parameters
        let key = Self.cacheKey(for: url, frameCount: frameCount, targetHeight: targetHeight)

        if let images = syncQueue.sync(execute: { cache[key] }) {
            completion(frameCount, images)
            return
        }

        var shouldStart = false
        syncQueue.sync {
            if var callbacks = inflight[key] {
                callbacks.append(completion)
                inflight[key] = callbacks
            } else {
                inflight[key] = [completion]
                shouldStart = true
            }
        }

        guard shouldStart else { return }

        queue.addOperation { [weak self] in
            guard let self = self else { return }
            let asset = AVAsset(url: url)
            guard asset.isPlayable else {
                self.finish(key: key, frameCount: frameCount, images: [])
                return
            }

            let duration = CMTimeGetSeconds(asset.duration)
            if duration.isNaN || duration.isInfinite || duration <= 0 {
                self.finish(key: key, frameCount: frameCount, images: [])
                return
            }

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            // Set a reasonable maximum size for thumbnails
            let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0
            generator.maximumSize = CGSize(width: targetHeight * 16/9 * scale, height: targetHeight * scale)

            // Evenly spaced times across duration (avoid 0 exactly)
            let step = duration / Double(frameCount)
            let times: [NSValue] = (0..<frameCount).map { i in
                let t = max(0.001, Double(i) * step + step * 0.5)
                return NSValue(time: CMTime(seconds: t, preferredTimescale: 600))
            }
            var indexMap: [Int64: Int] = [:]
            for (i, v) in times.enumerated() {
                indexMap[v.timeValue.value] = i
            }

            var images: [NSImage] = Array(repeating: NSImage(), count: frameCount)
            var produced = 0
            let group = DispatchGroup()

            // Use generateCGImagesAsynchronously for better throughput
            generator.generateCGImagesAsynchronously(forTimes: times) { requestedTime, cg, actualTime, result, error in
                if let cg = cg, result == .succeeded {
                    let index = indexMap[requestedTime.value] ?? Int((CMTimeGetSeconds(actualTime) / duration * Double(frameCount)).clamped(to: 0.0, Double(frameCount - 1)))
                    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    if index >= 0 && index < images.count {
                        images[index] = image
                    }
                }
                produced += 1
                if produced == frameCount {
                    self.syncQueue.sync {
                        self.cache[key] = images
                    }
                    self.finish(key: key, frameCount: frameCount, images: images)
                }
            }
        }
    }

    private func finish(key: String, frameCount: Int, images: [NSImage]) {
        var callbacks: [(Int, [NSImage]) -> Void] = []
        syncQueue.sync {
            callbacks = inflight[key] ?? []
            inflight.removeValue(forKey: key)
        }
        DispatchQueue.main.async {
            callbacks.forEach { $0(frameCount, images) }
        }
    }

    private static func cacheKey(for url: URL, frameCount: Int, targetHeight: CGFloat) -> String {
        var mtimeString = "-"
        if url.isFileURL, let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date {
            mtimeString = String(Int(mtime.timeIntervalSince1970))
        }
        return "\(url.absoluteString)|m:\(mtimeString)|n:\(frameCount)|h:\(Int(targetHeight.rounded()))"
    }
}

// MARK: - Scrubber View
struct ScrubberView: View {
    let url: URL
    let duration: Double
    let currentTime: Double
    let onSeek: (Double) -> Void
    let onScrubStateChange: (Bool) -> Void
    var absoluteStart: Date? = nil
    var absoluteEnd: Date? = nil

    @State private var images: [NSImage] = []
    @State private var isDragging: Bool = false

    private let frameCount = 12
    private let baselineHeight: CGFloat = 10
    private let playheadDiameter: CGFloat = 12
    private let filmstripHeight: CGFloat = 64
    private let spacingBetween: CGFloat = 10
    private let aspect: CGFloat = 16.0/9.0
    private let zoom: CGFloat = 1.2 // 20% zoom

    var body: some View {
        GeometryReader { outer in
            ZStack(alignment: .topLeading) {
                VStack(spacing: spacingBetween) {
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            // Baseline track
                            Capsule()
                                .fill(Color.white.opacity(0.25))
                                .frame(height: 4)
                                .offset(y: (baselineHeight - 4) / 2)

                    // Playhead + time chip
                    let x = xFor(time: currentTime, width: geometry.size.width)
                    Group {
                        // Time chip above playhead
                        Text(timeLabel(for: currentTime))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                            .offset(x: x - 24, y: -24)

                        Circle()
                            .fill(Color.white)
                            .frame(width: playheadDiameter, height: playheadDiameter)
                            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
                            .offset(x: x - playheadDiameter/2, y: (baselineHeight - playheadDiameter)/2)
                    }
                }
                .frame(height: baselineHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDragging { isDragging = true; onScrubStateChange(true) }
                            let pct = max(0, min(1, value.location.x / geometry.size.width))
                            onSeek(pct * max(duration, 0.0001))
                        }
                        .onEnded { value in
                            isDragging = false
                            onScrubStateChange(false)
                        }
                )
                }
                    .frame(height: baselineHeight + 10)

                // Filmstrip
                let tileWidth = filmstripHeight * aspect
                let columnsNeeded = max(1, Int(ceil(outer.size.width / tileWidth)))
                HStack(spacing: 0) {
                    if images.count == columnsNeeded {
                        ForEach(0..<images.count, id: \.self) { idx in
                            Image(nsImage: images[idx])
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .scaleEffect(zoom, anchor: .center)
                                .frame(width: tileWidth, height: filmstripHeight)
                                .clipped()
                        }
                    } else if images.isEmpty {
                        // Lightweight placeholders while generating
                        ForEach(0..<columnsNeeded, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: tileWidth, height: filmstripHeight)
                        }
                    } else {
                        // If counts mismatch (resize), prefer newly computed count as placeholders
                        ForEach(0..<columnsNeeded, id: \.self) { i in
                            let img: NSImage? = i < images.count ? images[i] : nil
                            Group {
                                if let img = img {
                                    Image(nsImage: img)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .scaleEffect(zoom, anchor: .center)
                                } else {
                                    Rectangle().fill(Color.white.opacity(0.08))
                                }
                            }
                            .frame(width: tileWidth, height: filmstripHeight)
                            .clipped()
                        }
                    }
                }
                .frame(width: outer.size.width, alignment: .leading)
                .clipped()
                .onChange(of: columnsNeeded) { newValue in
                    generateFilmstripIfNeeded(count: newValue)
                }
                .onAppear {
                    generateFilmstripIfNeeded(count: columnsNeeded)
                }
            }

                // Vertical playhead line overlay (from just under the dot through filmstrip)
                GeometryReader { geometry in
                    let x = xFor(time: currentTime, width: geometry.size.width)
                    let topOffset = baselineHeight / 2 + playheadDiameter / 2 + 1
                    let totalHeight = baselineHeight + spacingBetween + filmstripHeight
                    let lineHeight = max(0, totalHeight - topOffset)

                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.white)
                        .frame(width: 3, height: lineHeight)
                        .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 0)
                        .offset(x: x - 1.5, y: topOffset)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { isDragging = true; onScrubStateChange(true) }
                        let pct = max(0, min(1, value.location.x / outer.size.width))
                        onSeek(pct * max(duration, 0.0001))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onScrubStateChange(false)
                    }
            )
        }
        .onAppear { /* filmstrip generation handled above */ }
    }

    private func xFor(time: Double, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        return CGFloat(time / duration) * width
    }

    private func timeLabel(for time: Double) -> String {
        if let start = absoluteStart, let end = absoluteEnd, duration > 0 {
            let total = end.timeIntervalSince(start)
            let pct = max(0, min(1, time / duration))
            let absolute = start.addingTimeInterval(total * pct)
            let fmt = DateFormatter()
            fmt.dateFormat = "h:mm a"
            return fmt.string(from: absolute)
        } else {
            let mins = Int(time) / 60
            let secs = Int(time) % 60
            return String(format: "%d:%02d", mins, secs)
        }
    }

    private func generateFilmstripIfNeeded(count: Int) {
        guard count > 0 else { return }
        FilmstripGenerator.shared.generate(url: url, frameCount: count, targetHeight: filmstripHeight) { producedCount, imgs in
            // Only set if counts match current expectation to avoid race during resizes
            self.images = imgs
        }
    }
}

private extension Comparable {
    func clamped(to lower: Self, _ upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}
