//
//  GeminiService.swift
//  AmiTime
//
//  2025‑05‑08  —  Switch from **inline video** to the **Files API** so we can
//  send >20 MB batches without hitting the inline limit.  Flow:
//    1. Stitch chunk files → single .mp4.
//    2. Resumable upload via `upload/v1beta/files` (two‑step start + upload).
//    3. Call `generateContent` referencing the returned `file_uri`.
//    4. Still dumps shell‑ready curl scripts in /tmp for debugging.
//
import Foundation
import AVFoundation
import UniformTypeIdentifiers

// MARK: – Protocol -----------------------------------------------------------

protocol GeminiServicing {
    func processBatch(_ batchId: Int64,
                      completion: @escaping (Result<GeminiAnalysisResponse, Error>) -> Void)
    func apiKey() -> String?
    func setApiKey(_ key: String)
}

// MARK: – DTOs & Errors ------------------------------------------------------

struct GeminiAnalysisResponse: Codable {
    struct Card: Codable {
        let title: String
        let description: String?
        let category: String
        let startTimestamp: Int
        let endTimestamp: Int
        let metadata: String?
    }
    let cards: [Card]

    func toTimelineCards() -> [TimelineCard] {
        cards.map { c in
            TimelineCard(title: c.title,
                         description: c.description,
                         category: c.category,
                         startTimestamp: c.startTimestamp,
                         endTimestamp: c.endTimestamp,
                         metadata: c.metadata)
        }
    }
}

enum GeminiServiceError: Error, LocalizedError {
    case missingApiKey, noChunks, stitchingFailed
    case uploadStartFailed(String), uploadFailed(String)
    case processingTimeout, processingFailed(String)
    case requestFailed(String), invalidResponse
    var errorDescription: String? {
        switch self {
        case .missingApiKey: return "Missing Gemini API key. Set it in Settings."
        case .noChunks: return "Batch contains no video chunks."
        case .stitchingFailed: return "Failed to stitch video chunks."
        case .uploadStartFailed(let m): return "File‑API start failed – \(m)"
        case .uploadFailed(let m): return "File‑API upload failed – \(m)"
        case .processingTimeout: return "File processing exceeded 5 minutes."
        case .processingFailed(let s): return "File processing failed – \(s)"
        case .requestFailed(let m): return "Gemini request failed – \(m)"
        case .invalidResponse: return "Gemini returned an unexpected payload."
        }
    }
}

// MARK: – Service ------------------------------------------------------------

final class GeminiService: GeminiServicing {
    static let shared: GeminiServicing = GeminiService()
    private init() {}

    private let genEndpoint  = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-pro-exp-03-25:generateContent"
    private let fileEndpoint = "https://generativelanguage.googleapis.com/upload/v1beta/files"

    private let apiKeyKey = "AIzaSyBdPY2tes0GSNlOj5ks49T2SMwXbs9BpsI"
    private let userDefaults = UserDefaults.standard
    private let queue = DispatchQueue(label: "com.amitime.gemini", qos: .utility)

    func apiKey() -> String? { apiKeyKey }
    func setApiKey(_ key: String) { userDefaults.set(key, forKey: apiKeyKey) }

    // MARK: – Public ---------------------------------------------------------

    func processBatch(_ batchId: Int64,
                      completion: @escaping (Result<GeminiAnalysisResponse, Error>) -> Void) {
        guard let key = apiKey(), !key.isEmpty else {
            completion(.failure(GeminiServiceError.missingApiKey)); return
        }

        queue.async {
            do {
                // 1. gather & stitch -------------------------------------------------
                let chunks = StorageManager.shared.chunksForBatch(batchId)
                guard !chunks.isEmpty else { throw GeminiServiceError.noChunks }
                let urls = chunks.map { URL(fileURLWithPath: $0.fileUrl) }
                let stitched = try self.stitch(urls: urls)
                defer { try? FileManager.default.removeItem(at: stitched) }

                // 2. upload via Files API -------------------------------------------
                let mime = self.mimeType(for: stitched) ?? "video/mp4"
                let (fileName, fileURI) = try self.uploadAndAwait(stitched, mimeType: mime, key: key)


                // 3. generateContent -------------------------------------------------
                let prompt = "Analyze this screen recording and return a JSON array of timeline cards with title, description, category, startTimestamp, endTimestamp."
                let body: [String: Any] = [
                    "contents": [[
                        "parts": [
                            ["file_data": [
                                "mime_type": mime,
                                "file_uri": fileURI
                            ]],
                            ["text": prompt]
                        ]
                    ]],
                    "generationConfig": [
                        "temperature": 0.2,
                        "topK": 32,
                        "topP": 0.95,
                        "maxOutputTokens": 4096,
                        "responseMimeType": "application/json"
                    ]
                ]
                let jsonData = try JSONSerialization.data(withJSONObject: body)

                // curl dump -------------------------------------------------------
                self.dumpCurl(batchId: batchId, json: jsonData, key: key)

                // request --------------------------------------------------------
                var comps = URLComponents(string: self.genEndpoint)!; comps.queryItems = [URLQueryItem(name: "key", value: key)]
                var req = URLRequest(url: comps.url!);
                req.httpMethod = "POST"; req.setValue("application/json", forHTTPHeaderField: "Content-Type"); req.httpBody = jsonData; req.timeoutInterval = 300

                let (d, r) = try URLSession.shared.syncDataTask(with: req)
                guard let http = r as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    let msg = String(data: d ?? Data(), encoding: .utf8) ?? "<no body>"
                    throw GeminiServiceError.requestFailed(msg)
                }
                guard let data = d else { throw GeminiServiceError.invalidResponse }
                let decoded = try JSONDecoder().decode(GeminiAnalysisResponse.self, from: data)
                DispatchQueue.main.async { completion(.success(decoded)) }

            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    // MARK: – Upload helper ---------------------------------------------------

    private func uploadAndAwait(_ file: URL, mimeType: String, key: String) throws -> (String,String) {
            let size = (try FileManager.default.attributesOfItem(atPath:file.path)[.size] as! NSNumber).stringValue
            // start
            var startURL=URLComponents(string:fileEndpoint)!; startURL.queryItems=[URLQueryItem(name:"key",value:key)]
            var sReq=URLRequest(url:startURL.url!); sReq.httpMethod="POST"; sReq.setValue("resumable",forHTTPHeaderField:"X-Goog-Upload-Protocol"); sReq.setValue("start",forHTTPHeaderField:"X-Goog-Upload-Command"); sReq.setValue(size,forHTTPHeaderField:"X-Goog-Upload-Header-Content-Length"); sReq.setValue(mimeType,forHTTPHeaderField:"X-Goog-Upload-Header-Content-Type"); sReq.setValue("application/json",forHTTPHeaderField:"Content-Type"); sReq.httpBody=try JSONSerialization.data(withJSONObject:["file":["display_name":"VIDEO"]])
            let (_,sResp)=try URLSession.shared.syncDataTask(with:sReq); guard let http1=sResp as? HTTPURLResponse, let upURLString=http1.value(forHTTPHeaderField:"X-Goog-Upload-URL"), let upURL=URL(string:upURLString) else { throw GeminiServiceError.uploadStartFailed("missing upload URL") }
            // upload
            var uReq=URLRequest(url:upURL); uReq.httpMethod="PUT"; uReq.setValue(size,forHTTPHeaderField:"Content-Length"); uReq.setValue("0",forHTTPHeaderField:"X-Goog-Upload-Offset"); uReq.setValue("upload, finalize",forHTTPHeaderField:"X-Goog-Upload-Command"); uReq.httpBody=try Data(contentsOf:file); let (uData,_)=try URLSession.shared.syncDataTask(with:uReq)
            guard let uData=uData, let json=try? JSONSerialization.jsonObject(with:uData) as? [String:Any], let fileDict=json["file"] as? [String:Any], let fileName=fileDict["name"] as? String else { throw GeminiServiceError.uploadFailed("bad response") }
            // poll
            let pollURL = "https://generativelanguage.googleapis.com/v1beta/\(fileName)?key=\(key)"
            print(pollURL)
            var state="PROCESSING";
            var fileURI:String?;
            let deadline=Date().addingTimeInterval(300)
            
        while Date() < deadline {
            // 1. GET the file object
            var req = URLRequest(url: URL(string: pollURL)!)
            req.httpMethod = "GET"
            
            // synchronous helper; you can wrap this in async/await if preferred
            let (data, _) = try URLSession.shared.syncDataTask(with: req)
            
            // 2. Parse the top‑level JSON keys
            guard
                let bytes = data,
                let root  = try JSONSerialization.jsonObject(with: bytes) as? [String:Any],
                let newState = root["state"] as? String
            else {
                throw GeminiServiceError.invalidResponse          // malformed JSON
            }
            
            print("📡 poll JSON →", String(data: bytes, encoding: .utf8) ?? "<non‑utf8>")
            print("🛰️ state =", newState)
            state = newState          // update loop variable
            
            if state == "ACTIVE" {
                fileURI = root["uri"] as? String
                break                                   // ✅ ready to use
            }
            if state == "FAILED" {
                throw GeminiServiceError.processingFailed("File‑processing returned FAILED")
            }
            // else still PROCESSING
            Thread.sleep(forTimeInterval: 1)            // wait 1 s before next poll
        }
            if state=="PROCESSING" { throw GeminiServiceError.processingTimeout }
            if state=="FAILED" { throw GeminiServiceError.processingFailed(state) }
            guard let uri=fileURI else { throw GeminiServiceError.invalidResponse }
            return (fileName,uri)
        }

    // MARK: – Stitch helper ---------------------------------------------------

    private func stitch(urls: [URL]) throws -> URL {
        let comp = AVMutableComposition()
        guard let trak = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw GeminiServiceError.stitchingFailed
        }
        var cursor = CMTime.zero
        for u in urls {
            let asset = AVURLAsset(url: u)
            guard let src = asset.tracks(withMediaType: .video).first else { continue }
            try trak.insertTimeRange(CMTimeRange(start: .zero, duration: asset.duration), of: src, at: cursor)
            cursor = CMTimeAdd(cursor, asset.duration)
        }
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let exp = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough) else { throw GeminiServiceError.stitchingFailed }
        exp.outputURL = out; exp.outputFileType = .mp4
        let sema = DispatchSemaphore(value: 0); exp.exportAsynchronously { sema.signal() }; sema.wait()
        guard exp.status == .completed else { throw GeminiServiceError.stitchingFailed }
        return out
    }

    // MARK: – Misc -----------------------------------------------------------

    private func mimeType(for url: URL) -> String? {
        UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
    }

    private func dumpCurl(batchId: Int64, json: Data, key: String) {
        guard let js = String(data: json, encoding: .utf8) else { return }
        var comps = URLComponents(string: genEndpoint)!; comps.queryItems = [URLQueryItem(name: "key", value: key)]
        let script = """
#!/usr/bin/env bash
curl \"\(comps.url!.absoluteString)\" \
  -H 'Content-Type: application/json' \
  -X POST \
  -d '\(js)'
"""
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("gemini_batch_\(batchId).sh")
        try? script.write(to: path, atomically: true, encoding: .utf8)
        print("📝 curl 👉 \(path.path)")
    }
}

// MARK: – URLSession sync helper -------------------------------------------

private extension URLSession {
    func syncDataTask(with req: URLRequest) throws -> (Data?, URLResponse?) {
        let sema = DispatchSemaphore(value: 0)
        var d: Data?; var r: URLResponse?; var e: Error?
        dataTask(with: req) { d = $0; r = $1; e = $2; sema.signal() }.resume(); sema.wait()
        if let err = e { throw err }; return (d, r)
    }
}
