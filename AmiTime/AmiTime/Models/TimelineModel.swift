// Models/TimelineModel.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import Foundation
import SwiftUI // For Color

// Represents a top-level subject category (e.g., "Computer Science")
struct Subject: Identifiable, Hashable {
    let id = UUID()
    var name: String
    var icon: String? // SF Symbol name or emoji
    var color: Color = .gray // Default color
    var children: [TimelineEvent] = []
}

// Represents a single event/task within a subject
struct TimelineEvent: Identifiable, Hashable {
    let id = UUID()
    var subjectID: Subject.ID // Link back to the parent Subject
    var title: String
    var startTime: Date
    var endTime: Date
    var icon: String? // Optional specific icon for the event
    var color: Color? // Optional override color
}

// Helper to get duration
extension TimelineEvent {
    var duration: TimeInterval {
        endTime.timeIntervalSince(startTime)
    }
} 