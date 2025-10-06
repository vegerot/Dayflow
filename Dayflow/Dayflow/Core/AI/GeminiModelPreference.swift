//
//  GeminiModelPreference.swift
//  Dayflow
//

import Foundation

enum GeminiModel: String, Codable, CaseIterable {
    case pro = "gemini-2.5-pro"
    case flash = "gemini-2.5-flash"
    case flashLite = "gemini-2.5-flash-lite"

    var displayName: String {
        switch self {
        case .pro: return "Gemini 2.5 Pro"
        case .flash: return "Gemini 2.5 Flash"
        case .flashLite: return "Gemini Flash Lite"
        }
    }

    var shortLabel: String {
        switch self {
        case .pro: return "2.5 Pro"
        case .flash: return "2.5 Flash"
        case .flashLite: return "Flash Lite"
        }
    }
}

struct GeminiModelPreference: Codable {
    private static let storageKey = "geminiSelectedModel"

    let primary: GeminiModel

    static let `default` = GeminiModelPreference(primary: .pro)

    var orderedModels: [GeminiModel] {
        switch primary {
        case .pro: return [.pro, .flash, .flashLite]
        case .flash: return [.flash, .flashLite]
        case .flashLite: return [.flashLite]
        }
    }

    var fallbackSummary: String {
        switch primary {
        case .pro:
            return "Falls back to 2.5 Flash, then Flash Lite if needed"
        case .flash:
            return "Falls back to Flash Lite if 2.5 Flash is unavailable"
        case .flashLite:
            return "Always uses Flash Lite"
        }
    }

    static func load(from defaults: UserDefaults = .standard) -> GeminiModelPreference {
        if let data = defaults.data(forKey: storageKey),
           let preference = try? JSONDecoder().decode(GeminiModelPreference.self, from: data) {
            return preference
        }

        let preference = GeminiModelPreference.default
        preference.save(to: defaults)
        return preference
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}

