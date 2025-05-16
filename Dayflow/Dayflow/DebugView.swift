import SwiftUI
import AVKit

struct DebugView: View {
    @State private var batches = StorageManager.shared.allBatches()
    @State private var selected: Int64?
    @State private var player = AVPlayer()
    @State private var timelineCards: [TimelineCard] = []
    @State private var llmCalls: [LLMCall] = []

    var body: some View {
        HStack(spacing: 0) {
            List(batches, id: \.id, selection: $selected) { b in
                VStack(alignment: .leading) {
                    Text("Batch \(b.id)").font(.headline)
                    Text("\(tsString(b.start)) – \(tsString(b.end))")
                        .font(.caption)
                    Text(b.status).font(.caption2)
                }
            }
            .frame(width: 220)
            .onChange(of: selected) { _, new in loadBatch(new) }

            Divider()

            if let _ = selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        VideoPlayer(player: player)
                            .frame(height: 200)
                            .cornerRadius(8)

                        if !timelineCards.isEmpty {
                            Text("Timeline Cards").font(.headline)
                            ForEach(timelineCards) { card in
                                VStack(alignment: .leading) {
                                    Text(card.title).bold()
                                    Text("\(card.startTimestamp) – \(card.endTimestamp)")
                                        .font(.caption)
                                    Text(card.category + " / " + card.subcategory)
                                        .font(.caption2)
                                    Text(card.summary).font(.caption)
                                }
                                .padding(.bottom, 4)
                            }
                        }

                        if !llmCalls.isEmpty {
                            Text("LLM Calls").font(.headline)
                            ForEach(Array(llmCalls.enumerated()), id: \.offset) { index, call in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Call \(index + 1) – " + dateFormatter.string(from: call.timestamp))
                                        .font(.subheadline)
                                    Text(String(format: "Latency %.2fs", call.latency))
                                        .font(.caption2)
                                    Text("Input: \(call.input)")
                                        .font(.caption2)
                                        .lineLimit(2)
                                    Text("Output: \(call.output)")
                                        .font(.caption2)
                                        .lineLimit(2)
                                }
                                .padding(.bottom, 4)
                            }
                        }
                    }
                    .padding()
                }
            } else {
                VStack { Spacer(); Text("Select a batch").foregroundColor(.secondary); Spacer() }
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { refresh() }
        .onDisappear { player.pause() }
    }

    private func refresh() { batches = StorageManager.shared.allBatches() }

    private func loadBatch(_ id: Int64?) {
        player.pause()
        timelineCards = []
        llmCalls = []

        guard let id else { return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        if !chunks.isEmpty {
            let comp = AVMutableComposition()
            for c in chunks {
                let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
                guard
                    asset.isPlayable,
                    let track = asset.tracks(withMediaType: .video).first ?? asset.tracks(withMediaType: .audio).first
                else { continue }
                try? comp.insertTimeRange(.init(start: .zero, duration: asset.duration), of: track.asset!, at: comp.duration)
            }
            if comp.tracks.first != nil {
                player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
            }
        }
        timelineCards = StorageManager.shared.fetchTimelineCards(forBatch: id)
        llmCalls = StorageManager.shared.fetchBatchLLMMetadata(batchId: id)
    }

    private func tsString(_ ts: Int) -> String {
        dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .short
        return df
    }
}
