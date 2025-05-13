//
//  BatchDebugView.swift
//  AmiTime
//
//  2025‑05‑08  – Adds “Download MP4” button next to “Process Batch”.
//                When clicked it stitches the selected batch into a single
//                MP4 and copies it to the user's Downloads folder as
//                Batch_<id>.mp4, then shows a confirmation alert.
//
import SwiftUI
import AVKit

struct BatchDebugView: View {
    // MARK: – State
    @State private var batches = StorageManager.shared.allBatches()
    @State private var selected: Int64?
    @State private var player: AVPlayer?

    @State private var isProcessing = false
    @State private var requestPrompt: String = ""
    @State private var responseJSON: String = ""
    @State private var errorMessage: String?

    @State private var showDownloadAlert = false
    @State private var downloadPath: String = ""

    var body: some View {
        HStack(spacing: 0) {
            // — left column —
            List(batches, id: \..id, selection: $selected) { b in
                VStack(alignment: .leading) {
                    Text("Batch \(b.id)").font(.headline)
                    Text("\(dateString(b.start)) – \(dateString(b.end))")
                        .font(.caption).foregroundColor(.secondary)
                    Text(b.status).font(.caption2)
                }
            }
            .frame(width: 210)
            .onChange(of: selected) { _, new in
                loadBatch(new)
                clearDebug()
            }

            Divider()

            // — right column —
            VStack(alignment: .leading, spacing: 12) {
                Group {
                    if let p = player {
                        VideoPlayer(player: p)
                            .frame(minHeight: 220)
                            .onAppear { p.play() }
                            .onDisappear { p.pause() }
                    } else {
                        VStack { Spacer(); Text("Select a batch").foregroundColor(.secondary); Spacer() }
                            .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .background(Color.black.opacity(0.7)).cornerRadius(8)

                HStack(spacing: 16) {
                    Button("Process Batch") { triggerAnalysis() }
                        .disabled(selected == nil || isProcessing)
                    Button("Download MP4") { downloadBatchVideo() }
                        .disabled(selected == nil)
                    if isProcessing { ProgressView() }
                    if let err = errorMessage { Text(err).foregroundColor(.red) }
                }

                if !requestPrompt.isEmpty || !responseJSON.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !requestPrompt.isEmpty {
                                Text("Prompt ✉️:").font(.headline)
                                Text(requestPrompt).font(.system(.body, design: .monospaced))
                            }
                            if !responseJSON.isEmpty {
                                Text("Gemini Response 📬:").font(.headline).padding(.top, 6)
                                Text(responseJSON).font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(4)
                    }
                    .background(Color(.white))
                    .cornerRadius(6)
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { refreshBatches() }
        .alert("Video saved to Downloads", isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(downloadPath)
        }
    }

    // MARK: – Helper methods

    private func refreshBatches() { batches = StorageManager.shared.allBatches() }

    private func loadBatch(_ id: Int64?) {
        guard let id else { player = nil; return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        guard !chunks.isEmpty else { player = nil; return }

        let comp = AVMutableComposition()
        for c in chunks {
            let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
            try? comp.insertTimeRange(.init(start: .zero, duration: asset.duration),
                                       of: asset, at: comp.duration)
        }
        player = AVPlayer(playerItem: AVPlayerItem(asset: comp))
    }

    private func triggerAnalysis() {
        guard let id = selected else { return }
        isProcessing = true; errorMessage = nil; requestPrompt = ""; responseJSON = ""
        requestPrompt = "Analyze this screen recording and return a JSON array of timeline cards with title, description, category, startTimestamp, endTimestamp."
        GeminiService.shared.processBatch(id) { result in
            isProcessing = false
            switch result {
            case .success(let resp): if let js = try? String(data: JSONEncoder().encode(resp), encoding: .utf8) { responseJSON = js }
            case .failure(let err): errorMessage = err.localizedDescription
            }
            refreshBatches()
        }
    }

    private func downloadBatchVideo() {
        guard let id = selected else { return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        guard !chunks.isEmpty else { return }

        // 1. Ask user where to save (sandbox‑safe)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Batch_\(id).mp4"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }

            // 2. Build composition on a background queue
            DispatchQueue.global(qos: .utility).async {
                let comp = AVMutableComposition()
                var cursor = CMTime.zero
                for c in chunks {
                    let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
                    try? comp.insertTimeRange(.init(start: .zero, duration: asset.duration), of: asset, at: cursor)
                    cursor = CMTimeAdd(cursor, asset.duration)
                }
                guard let exporter = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetHighestQuality) else { return }
                exporter.outputURL = destURL
                exporter.outputFileType = .mp4
                exporter.timeRange = .init(start: .zero, duration: cursor)
                exporter.exportAsynchronously {
                    DispatchQueue.main.async {
                        if exporter.status == .completed {
                            downloadPath = destURL.path
                            showDownloadAlert = true
                        } else if let err = exporter.error {
                            errorMessage = "Export failed: \(err.localizedDescription)"
                        }
                    }
                }
            }
        }
    }

    private func clearDebug() { requestPrompt = ""; responseJSON = ""; errorMessage = nil; isProcessing = false }

    private func dateString(_ ts: Int) -> String {
        let df = DateFormatter(); df.dateFormat = "HH:mm:ss"; return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
