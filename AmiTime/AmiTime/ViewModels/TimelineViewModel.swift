// ViewModels/TimelineViewModel.swift
//  AmiTime
//
//  Created by [Your Name] on [Date].
//

import Foundation
import SwiftUI
import Combine

// Defines a visible row in the timeline (either a Subject header or a TimelineEvent)
enum TimelineRowItem: Identifiable, Hashable {
    case subject(Subject)
    case event(TimelineEvent)

    var id: AnyHashable {
        switch self {
        case .subject(let subject): return subject.id
        case .event(let event): return event.id
        }
    }
}

class TimelineViewModel: ObservableObject {
    // --- Core Data ---
    @Published var subjects: [Subject] = []
    @Published var events: [TimelineEvent] = [] // Flattened list for easier lookup

    // --- UI State ---
    @Published var expandedSubjectIDs: Set<Subject.ID> = Set()
    @Published var zoomScale: CGFloat = 1000.0 // Points per hour
    @Published var verticalScrollOffset: CGPoint = .zero // Use CGPoint for TrackableScrollView

    // --- Derived Data ---
    @Published var visibleRows: [TimelineRowItem] = []

    // --- Date Range (Placeholder - needs refinement) ---
    // Initialize with a default value, will be overwritten in init
    var totalTimeRangeStart: Date = Date()
    var totalTimeRangeEnd: Date = Date()

    private var cancellables = Set<AnyCancellable>()

    init(subjects: [Subject] = PreviewData.subjects) {
        // Initialize core data first
        self.subjects = subjects
        self.events = subjects.flatMap { $0.children }

        // Now calculate the actual date range and overwrite the defaults
        let allTimes = self.events.flatMap { [$0.startTime, $0.endTime] }
        if let minTime = allTimes.min(), let maxTime = allTimes.max() {
            self.totalTimeRangeStart = Calendar.current.date(byAdding: .hour, value: -1, to: minTime) ?? minTime
            self.totalTimeRangeEnd = Calendar.current.date(byAdding: .hour, value: 1, to: maxTime) ?? maxTime
        } else {
            // Default fallback range
            self.totalTimeRangeStart = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
            self.totalTimeRangeEnd = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date())!
        }

        // Initialize expanded set (e.g., expand first subject by default)
        if let firstSubjectID = subjects.first?.id {
            expandedSubjectIDs.insert(firstSubjectID)
        }

        // Recalculate visible rows whenever subjects or expansion state changes
        Publishers.CombineLatest($subjects, $expandedSubjectIDs)
            .map { subjects, expandedIDs in
                var rows: [TimelineRowItem] = []
                for subject in subjects {
                    rows.append(.subject(subject))
                    if expandedIDs.contains(subject.id) {
                        rows.append(contentsOf: subject.children.map { .event($0) })
                    }
                }
                return rows
            }
            .assign(to: \.visibleRows, on: self)
            .store(in: &cancellables)
    }

    // --- Actions ---
    func toggleSubjectExpansion(subjectID: Subject.ID) {
        if expandedSubjectIDs.contains(subjectID) {
            expandedSubjectIDs.remove(subjectID)
        } else {
            expandedSubjectIDs.insert(subjectID)
        }
    }

    // --- Helpers ---
    func getEvents(for subjectID: Subject.ID) -> [TimelineEvent] {
        return events.filter { $0.subjectID == subjectID }
    }

    func getSubject(for event: TimelineEvent) -> Subject? {
        return subjects.first { $0.id == event.subjectID }
    }
} 