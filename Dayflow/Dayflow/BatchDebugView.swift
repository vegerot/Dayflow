//
//  BatchDebugView.swift
//  Dayflow
//
//  2025‑05‑08  – Adds “Download MP4” button next to “Process Batch”.
//  2025‑05‑13  – Fix crash on window close: never nil out AVPlayerItem.
//

import SwiftUI
import AVKit

struct BatchDebugView: View {
    // MARK: ‑ State -----------------------------------------------------------

    @State private var batches  = StorageManager.shared.allBatches()
    @State private var selected : Int64?
    @State private var player   = AVPlayer()          // single long‑lived player

    @State private var isProcessing   = false
    @State private var requestPrompt  = ""
    @State private var responseJSON   = ""
    @State private var errorMessage   : String?

    @State private var showDownloadAlert = false
    @State private var downloadPath      = ""

    // MARK: ‑ View ------------------------------------------------------------

    var body: some View {
        HStack(spacing: 0) {

            // ── Batch list ──────────────────────────────────────────────────
            List(batches, id: \.id, selection: $selected) { b in
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

            // ── Right side – preview & controls ───────────────────────────
            VStack(alignment: .leading, spacing: 12) {

                Group {
                    if player.currentItem != nil {
                        VideoPlayer(player: player)
                            .frame(minHeight: 220)
                            .onAppear { player.play() }
                    } else {
                        VStack {
                            Spacer()
                            Text("Select a batch").foregroundColor(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity, minHeight: 220)
                    }
                }
                .background(Color.black.opacity(0.7))
                .cornerRadius(8)

                HStack(spacing: 16) {
                    Button("Process Batch") { triggerAnalysis() }
                        .disabled(selected == nil || isProcessing)

                    Button("Download MP4") { downloadBatchVideo() }
                        .disabled(selected == nil)

                    if isProcessing { ProgressView() }
                    if let err = errorMessage {
                        Text(err).foregroundColor(.red)
                    }
                }

                if !requestPrompt.isEmpty || !responseJSON.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            if !requestPrompt.isEmpty {
                                Text("Prompt ✉️:").font(.headline)
                                Text(requestPrompt)
                                    .font(.system(.body, design: .monospaced))
                            }
                            if !responseJSON.isEmpty {
                                Text("Gemini Response 📬:")
                                    .font(.headline)
                                    .padding(.top, 6)
                                Text(responseJSON)
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                        .padding(4)
                    }
                    .background(Color.white)
                    .cornerRadius(6)
                }
                Spacer()
            }
            .padding(12)
        }
        .frame(minWidth: 760, minHeight: 480)
        .onAppear { refreshBatches() }
        .onDisappear {
            player.pause()                     // just pause, don’t clear item
            print("BatchDebugView disappeared, player paused.")
        }
        .alert("Video saved to Downloads",
               isPresented: $showDownloadAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(downloadPath)
        }
    }

    // MARK: ‑ Helper methods --------------------------------------------------

    private func refreshBatches() {
        batches = StorageManager.shared.allBatches()
    }

    private func loadBatch(_ id: Int64?) {
        player.pause()                         // stop any previous playback

        guard let id else { return }

        let chunks = StorageManager.shared.chunksForBatch(id)
        guard !chunks.isEmpty else { return }

        let comp = AVMutableComposition()
        for c in chunks {
            let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
            guard
                asset.isPlayable,
                let track = asset.tracks(withMediaType: .video).first
                          ?? asset.tracks(withMediaType: .audio).first
            else { continue }

            try? comp.insertTimeRange(
                .init(start: .zero, duration: asset.duration),
                of: track.asset!,
                at: comp.duration
            )
        }

        guard comp.tracks.first != nil else { return }

        player.replaceCurrentItem(with: AVPlayerItem(asset: comp))
    }

    private func triggerAnalysis() {
        guard let id = selected else { return }
        isProcessing = true
        errorMessage = nil
        requestPrompt = ""
        responseJSON  = ""

        requestPrompt =
            "Analyze this screen recording and return a JSON array of " +
            "timeline cards with title, description, category, " +
            "startTimestamp, endTimestamp."

        GeminiService.shared.processBatch(id) { result in
            isProcessing = false
            switch result {
            case .success(let resp):
                if let js = try? String(data: JSONEncoder().encode(resp),
                                        encoding: .utf8) {
                    responseJSON = js
                }
            case .failure(let err):
                errorMessage = err.localizedDescription
            }
            refreshBatches()
        }
    }

    private func downloadBatchVideo() {
        guard let id = selected else { return }
        let chunks = StorageManager.shared.chunksForBatch(id)
        guard !chunks.isEmpty else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Batch_\(id).mp4"
        panel.canCreateDirectories = true

        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }

            DispatchQueue.global(qos: .utility).async {
                let comp   = AVMutableComposition()
                var cursor = CMTime.zero

                for c in chunks {
                    let asset = AVURLAsset(url: URL(fileURLWithPath: c.fileUrl))
                    guard
                        asset.isPlayable,
                        let track = asset.tracks(withMediaType: .video).first
                                  ?? asset.tracks(withMediaType: .audio).first
                    else { continue }

                    try? comp.insertTimeRange(
                        .init(start: .zero, duration: asset.duration),
                        of: track.asset!,
                        at: cursor
                    )
                    cursor = CMTimeAdd(cursor, asset.duration)
                }

                guard
                    comp.tracks.first != nil,
                    let exporter = AVAssetExportSession(
                        asset: comp,
                        presetName: AVAssetExportPresetHighestQuality
                    )
                else { return }

                exporter.outputURL      = destURL
                exporter.outputFileType = .mp4
                exporter.timeRange      = .init(start: .zero, duration: cursor)

                exporter.exportAsynchronously {
                    DispatchQueue.main.async {
                        if exporter.status == .completed {
                            downloadPath      = destURL.path
                            showDownloadAlert = true
                        } else {
                            errorMessage =
                                exporter.error?.localizedDescription
                                ?? "Export failed."
                        }
                    }
                }
            }
        }
    }

    private func clearDebug() {
        requestPrompt = ""
        responseJSON  = ""
        errorMessage  = nil
        isProcessing  = false
    }

    private func dateString(_ ts: Int) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }
}
