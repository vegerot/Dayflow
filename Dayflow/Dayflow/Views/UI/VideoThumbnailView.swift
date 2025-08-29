//
//  VideoThumbnailView.swift
//  Dayflow
//
//  Video thumbnail component for the new UI
//

import SwiftUI
import AVKit
import AVFoundation

struct VideoThumbnailView: View {
    let videoURL: String
    @State private var thumbnail: NSImage?
    @State private var showVideoPlayer = false
    @State private var requestId: Int = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let thumbnail = thumbnail {
                    // Display thumbnail with 30% zoom
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.3) // 30% zoom
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    // Loading state
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.5)
                        )
                }
                
                // Play button overlay (custom asset)
                Button(action: {
                    showVideoPlayer = true
                }) {
                    Image("VideoPlayButton")
                        .resizable()
                        .renderingMode(.original)
                        .interpolation(.high)
                        .frame(width: 64, height: 64)
                        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 2)
                        .accessibilityLabel("Play video summary")
                }
                .buttonStyle(PlainButtonStyle())
            }
            .id(videoURL)
            .onAppear { fetchViaCache(size: geometry.size) }
            // Ensure thumbnail updates when a new video URL is provided
            .onChange(of: videoURL) { _ in
                thumbnail = nil
                fetchViaCache(size: geometry.size)
            }
            // If our layout width meaningfully changes, refresh to better size
            .onChange(of: geometry.size.width) { _ in
                fetchViaCache(size: geometry.size)
            }
            .sheet(isPresented: $showVideoPlayer) {
                VideoPlayerModal(videoURL: videoURL)
            }
        }
    }
    
    private func fetchViaCache(size: CGSize) {
        // Create a unique request token to guard against race conditions
        requestId &+= 1
        let currentId = requestId
        // Use the actual geometry size; avoid zero sizes
        let w = max(1, size.width)
        let h = max(1, size.height)
        let target = CGSize(width: w, height: h)
        ThumbnailCache.shared.fetchThumbnail(videoURL: videoURL, targetSize: target) { image in
            // Guard against late completions from older URLs
            if currentId == requestId {
                self.thumbnail = image
            }
        }
    }
}
