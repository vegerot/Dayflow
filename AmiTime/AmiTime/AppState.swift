//
//  AppState.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/26/25.
//

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
    @Published var isRecording = true                         // menu-bar toggle
    private init() {}
}
