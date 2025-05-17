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
                                DisclosureGroup {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("\(card.startTimestamp) – \(card.endTimestamp)")
                                            .font(.caption)
                                        Text(card.category + " / " + card.subcategory)
                                            .font(.caption2)
                                        Text(card.summary).font(.caption)

                                        if let path = card.videoSummaryURL,
                                           !path.isEmpty,
                                           let url = videoURL(from: path) {
                                            InlineVideoPlayer(url: url)
                                                .frame(height: 120)
                                                .cornerRadius(6)
                                        }

                                        if let distractions = card.distractions,
                                           !distractions.isEmpty {
                                            Text("Distractions").font(.subheadline)
                                            ForEach(distractions) { d in
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(d.title).bold().font(.caption)
                                                    Text("\(d.startTime) – \(d.endTime)")
                                                        .font(.caption2)
                                                    Text(d.summary).font(.caption2)
                                                    if let dPath = d.videoSummaryURL,
                                                       !dPath.isEmpty,
                                                       let dUrl = videoURL(from: dPath) {
                                                        InlineVideoPlayer(url: dUrl)
                                                            .frame(height: 80)
                                                            .cornerRadius(4)
                                                    }
                                                }
                                                .padding(.leading, 8)
                                            }
                                        }
                                    }
                                    .padding(.vertical, 4)
                                } label: {
                                    Text(card.title).bold()
                                }
                                .padding(.bottom, 4)
                            }
                        }

                        if !llmCalls.isEmpty {
                            Text("LLM Calls").font(.headline)
                            ForEach(Array(llmCalls.enumerated()), id: \.offset) { index, call in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Call \(index + 1) – " + dateFormatter.string(from: call.timestamp))
                                        .font(.subheadline)
                                    Text(String(format: "Latency %.2fs", call.latency))
                                        .font(.caption2)
                                    Text("Input:")
                                        .font(.caption2)
                                    Text(prettyJSON(call.input))
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text("Output:")
                                        .font(.caption2)
                                    Text(prettyJSON(call.output))
                                        .font(.system(size: 12, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                                .padding(.bottom, 6)
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

    private func videoURL(from path: String) -> URL? {
        if path.hasPrefix("file://") {
            return URL(string: path)
        }
        return URL(string: "file://" + path)
    }

    private func prettyJSON(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return text
        }
        return prettyString
    }
}

private struct InlineVideoPlayer: View {
    let url: URL
    @State private var player = AVPlayer()

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: url)) }
            .onDisappear { player.pause() }
    }
}
