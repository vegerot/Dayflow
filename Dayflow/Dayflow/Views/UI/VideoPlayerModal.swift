//
//  VideoPlayerModal.swift
//  Dayflow
//
//  Custom video timeline player with activity segments
//

import SwiftUI
import AVKit

// MARK: - Custom Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Data Models
struct VideoSegment: Identifiable {
    let id = UUID()
    let title: String
    let startTime: Double // in seconds
    let endTime: Double
    let color: Color
    let activityType: ActivityType
    
    var duration: Double {
        endTime - startTime
    }
    
    var durationString: String {
        let minutes = Int(duration / 60)
        let seconds = Int(duration) % 60
        return minutes > 0 ? "\(minutes) min" : "\(seconds) sec"
    }
}

enum ActivityType {
    case brainstorming
    case browsing
    case coding
    case email
    case meeting
    case breaks
    case other(String)
    
    var color: Color {
        switch self {
        case .brainstorming, .coding:
            return Color.orange
        case .browsing:
            return Color.red
        case .email, .meeting:
            return Color.blue
        case .breaks:
            return Color.yellow
        case .other:
            return Color.gray
        }
    }
}

// MARK: - View Model
class VideoPlayerViewModel: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 1
    @Published var isPlaying: Bool = false
    @Published var playbackSpeed: Float = 1.0
    @Published var currentSegment: VideoSegment?
    @Published var segments: [VideoSegment] = []
    @Published var isDragging: Bool = false
    @Published var hoverTime: Double? = nil
    @Published var timelineOffset: CGFloat = 0
    
    var player: AVPlayer?
    private var timeObserver: Any?
    
    func setupPlayer(url: URL) {
        player = AVPlayer(url: url)
        
        // Get video duration
        player?.currentItem?.asset.loadValuesAsynchronously(forKeys: ["duration"]) { [weak self] in
            guard let duration = self?.player?.currentItem?.asset.duration else { return }
            DispatchQueue.main.async {
                self?.duration = CMTimeGetSeconds(duration)
                self?.loadSegments()
            }
        }
        
        // Observe playback time
        let interval = CMTime(seconds: 0.03, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self, !self.isDragging else { return }
            self.currentTime = CMTimeGetSeconds(time)
            self.updateCurrentSegment()
        }
    }
    
    func cleanup() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        player?.pause()
        player = nil
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
            player?.rate = playbackSpeed
        }
        isPlaying.toggle()
    }
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = time
        updateCurrentSegment()
    }
    
    func setPlaybackSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player?.rate = speed
        }
    }
    
    private func updateCurrentSegment() {
        currentSegment = segments.first { segment in
            currentTime >= segment.startTime && currentTime < segment.endTime
        }
    }
    
    private func loadSegments() {
        // Dummy data for now
        segments = [
            VideoSegment(title: "Brainstorming with Chat GPT", startTime: 0, endTime: 420, color: .orange, activityType: .brainstorming),
            VideoSegment(title: "Browsing TripAdvisor", startTime: 420, endTime: 660, color: .red, activityType: .browsing),
            VideoSegment(title: "Comparing flights", startTime: 660, endTime: 780, color: .blue, activityType: .other("travel")),
            VideoSegment(title: "Break", startTime: 780, endTime: 840, color: .yellow, activityType: .breaks),
            VideoSegment(title: "Email responses", startTime: 840, endTime: 1020, color: .blue, activityType: .email),
            VideoSegment(title: "Coding session", startTime: 1020, endTime: 1680, color: .orange, activityType: .coding),
            VideoSegment(title: "Research", startTime: 1680, endTime: 1980, color: .orange, activityType: .brainstorming),
            VideoSegment(title: "Planning", startTime: 1980, endTime: duration, color: .blue, activityType: .other("planning"))
        ]
    }
}

// MARK: - Main Player View
struct VideoPlayerModal: View {
    let videoURL: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = VideoPlayerViewModel()
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    
    var body: some View {
        ZStack {
            Color.black
            
            VStack(spacing: 0) {
                // Video player area
                ZStack {
                    if let player = viewModel.player {
                        VideoPlayer(player: player)
                            .disabled(true) // Disable default controls
                            .onTapGesture {
                                viewModel.togglePlayPause()
                            }
                    } else {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    
                    // Close button overlay
                    VStack {
                        HStack {
                            Spacer()
                            Button(action: { dismiss() }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.white.opacity(0.8))
                                    .background(Circle().fill(Color.black.opacity(0.3)))
                            }
                            .buttonStyle(ScaleButtonStyle())
                            .padding()
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // Custom scrubber below the video
                VStack(spacing: 12) {
                    if let url = scrubberURL {
                        ScrubberView(
                            url: url,
                            duration: max(0.001, viewModel.duration),
                            currentTime: viewModel.currentTime,
                            onSeek: { t in viewModel.seek(to: t) },
                            onScrubStateChange: { dragging in viewModel.isDragging = dragging }
                        )
                        .padding(.horizontal)
                        .padding(.bottom, 12)
                    }
                }
            }
        }
        .frame(width: 800, height: 600)
        .onAppear {
            setupPlayer()
            startControlsTimer()
        }
        .onDisappear {
            viewModel.cleanup()
        }
        .onHover { isHovering in
            if isHovering {
                showControlsTemporarily()
            }
        }
    }
    
    private func setupPlayer() {
        let processedURL = videoURL.hasPrefix("file://") ? videoURL : "file://" + videoURL
        guard let url = URL(string: processedURL) else { return }
        if url.isFileURL {
            let path = url.path
            guard FileManager.default.fileExists(atPath: path) else { return }
        }
        viewModel.setupPlayer(url: url)
    }

    private var scrubberURL: URL? {
        let processedURL = videoURL.hasPrefix("file://") ? videoURL : "file://" + videoURL
        guard let url = URL(string: processedURL) else { return nil }
        return url
    }
    
    private func startControlsTimer() {
        controlsTimer?.invalidate()
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if viewModel.isPlaying && !viewModel.isDragging {
                showControls = false
            }
        }
    }
    
    private func showControlsTemporarily() {
        showControls = true
        startControlsTimer()
    }
}
