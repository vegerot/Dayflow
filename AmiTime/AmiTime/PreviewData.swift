//
//  PreviewData.swift
//  AmiTime
//
//  Created by Jerry Liu on 4/20/25.
//

import Foundation
import SwiftUI

/// Handy fixtures for previews / prototyping.
struct PreviewData {

    /// Same anchor day reused so times are stable each hot‑reload.
    private static let anchorDay: Date = {
        let cal = Calendar.current
        let now = Date()
        // start at today's 5 PM local
        return cal.date(bySettingHour: 17, minute: 0, second: 0, of: now)!
    }()

    /// Convenience to build times offset by minutes from anchor.
    private static func time(_ minutes: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minutes, to: anchorDay)!
    }

    static var subjects: [Subject] {
        let cs = Subject(name: "Computer Science", icon: "💻", color: .blue)
        let geo = Subject(name: "Geography", icon: "🗺️", color: .green)
        let math = Subject(name: "Mathematics", icon: "➕", color: .orange)
        let bio = Subject(name: "Biology", icon: "🧬", color: .purple)

        var csSub = cs
        var geoSub = geo
        var mathSub = math
        var bioSub = bio

        let now = Date()
        let calendar = Calendar.current

        // --- Computer Science Events ---
        let event1 = TimelineEvent(
            subjectID: cs.id,
            title: "Research & Brainstorming",
            startTime: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 17, minute: 35, second: 0, of: now)!
        )
        let event2 = TimelineEvent(
            subjectID: cs.id,
            title: "First Draft",
            startTime: calendar.date(bySettingHour: 17, minute: 55, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 18, minute: 15, second: 0, of: now)!,
            icon: "📄"
        )
        let event3 = TimelineEvent(
            subjectID: cs.id,
            title: "Presentation Creation",
            startTime: calendar.date(bySettingHour: 18, minute: 30, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 19, minute: 0, second: 0, of: now)!,
            icon: "📊"
        )
        csSub.children = [event1, event2, event3]

        // --- Geography Events ---
        let event4 = TimelineEvent(
            subjectID: geo.id,
            title: "Map Analysis",
            startTime: calendar.date(bySettingHour: 17, minute: 40, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 18, minute: 20, second: 0, of: now)!
        )
         geoSub.children = [event4]

        // --- Mathematics Events ---
        let event5 = TimelineEvent(
            subjectID: math.id,
            title: "Research & Brainstorming", // Same name, different subject
            startTime: calendar.date(bySettingHour: 17, minute: 35, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 18, minute: 5, second: 0, of: now)!
        )
        let event6 = TimelineEvent(
            subjectID: math.id,
            title: "Problem Set 1",
            startTime: calendar.date(bySettingHour: 18, minute: 10, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 18, minute: 40, second: 0, of: now)!)
        let event7 = TimelineEvent(
            subjectID: math.id,
            title: "Proof Reading",
            startTime: calendar.date(bySettingHour: 18, minute: 45, second: 0, of: now)!,
            endTime: calendar.date(bySettingHour: 19, minute: 5, second: 0, of: now)!)

        mathSub.children = [event5, event6, event7]

        // --- Biology Events (No Events) ---
        // bioSub has no children

        return [csSub, geoSub, mathSub, bioSub]
    }

    // Example usage in Previews:
    // static var sampleViewModel = TimelineViewModel(subjects: PreviewData.subjects)
}
