import SwiftUI
import Combine

enum CurrentView: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case debug = "Debug"
    var id: String { self.rawValue }
}

@MainActor // <--- Add this
protocol AppStateManaging: ObservableObject {
    // This requirement must now be fulfilled on the main actor
    var isRecording: Bool { get }
    var objectWillChange: ObservableObjectPublisher { get }
}

@MainActor
final class AppState: ObservableObject, AppStateManaging { // <-- Add AppStateManaging here
    static let shared = AppState()
    @Published var isRecording = true // This already satisfies the protocol requirement
    @Published var currentView: CurrentView = .timeline // New property for current view
    private init() {}
}
