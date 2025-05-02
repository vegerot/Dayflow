//
//  BatchDebugView.swift
//  AmiTime
//
//  Created by Jerry Liu on 5/1/25.
//

import SwiftUI
import AVKit

struct BatchDebugView: View {
    @State private var batches = StorageManager.shared.allBatches()
    @State private var selected: Int64?
    @State private var player: AVPlayer?

    var body: some View {
        HStack {
            // –– left: batch list ––
            List(batches, id: \.id, selection: $selected) { b in
                VStack(alignment: .leading) {
                    Text("Batch \(b.id)")
                        .font(.headline)
                    Text("\(dateString(b.start)) – \(dateString(b.end))")
                        .font(.caption).foregroundColor(.secondary)
                    Text(b.status).font(.caption2)
                }
            }
            .frame(width: 200)
            .onChange(of: selected) { _, new in loadBatch(new) }

            Divider()

            // –– right: stitched playback ––
            Group {
                if let p = player {
                    VideoPlayer(player: p)
                        .onAppear { p.play() }
                        .onDisappear { p.pause() }
                } else {
                    Text("Select a batch").foregroundColor(.secondary)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }

    private func loadBatch(_ id: Int64?) {
        guard let id else { player = nil; return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        guard !chunks.isEmpty else { player = nil; return }

        // Seamless timeline
        let comp = AVMutableComposition()
        for c in chunks {
            let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
            try? comp.insertTimeRange(.init(start: .zero, duration: asset.duration),
                                      of: asset,
                                      at: comp.duration)
        }
        player = AVPlayer(playerItem: AVPlayerItem(asset: comp))
    }

    private func dateString(_ ts: Int) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
