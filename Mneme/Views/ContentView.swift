//
//  ContentView.swift
//  Mneme
//
//  Created by Emre Tekneci on 3.11.2025.
//

import SwiftUI

private enum Tab: String, CaseIterable, Identifiable {
    case notepad, reminders, calendar, summary

    var id: Self { self }

    var title: String {
        switch self {
        case .notepad: return "Notepad"
        case .reminders: return "Reminders"
        case .calendar: return "Calendar"
        case .summary: return "Daily Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .notepad: return "note.text"
        case .reminders: return "checklist"
        case .calendar: return "calendar"
        case .summary: return "chart.bar"
        }
    }
}

struct ContentView: View {
    @State private var selection: Tab = .notepad
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var healthKitService = HealthKitService.shared
    @StateObject private var eventKitService = EventKitService.shared
    
    @State private var showPermissionsOnboarding = false
    @State private var showTutorial = false
    
    @AppStorage("hasShownPermissionsOnboarding") private var hasShownPermissionsOnboarding = false
    @AppStorage("hasShownTutorial") private var hasShownTutorial = false

    private var backgroundColor: Color {
        Color.appBackground(colorScheme: colorScheme)
    }
    
    private var selectedTabColor: Color {
        switch selection {
        case .notepad: return .orange
        case .reminders: return .green
        case .calendar: return .red
        case .summary: return .blue
        }
    }

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                NotepadView()
            }
            .tabItem { Label(Tab.notepad.title, systemImage: Tab.notepad.systemImage) }
            .tag(Tab.notepad)

            NavigationStack {
                RemindersView()
                    .navigationTitle(Tab.reminders.title)
            }
            .tabItem { Label(Tab.reminders.title, systemImage: Tab.reminders.systemImage) }
            .tag(Tab.reminders)

            NavigationStack {
                CalendarView()
            }
            .tabItem { Label(Tab.calendar.title, systemImage: Tab.calendar.systemImage) }
            .tag(Tab.calendar)

            NavigationStack {
                DailySummaryView()
                    .navigationTitle(Tab.summary.title)
            }
            .tabItem { Label("Summary", systemImage: Tab.summary.systemImage) }
            .tag(Tab.summary)
        }
        .tabViewStyle(.automatic)
        .tint(selectedTabColor)
        .background(backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $showPermissionsOnboarding) {
            PermissionsOnboardingView {
                hasShownPermissionsOnboarding = true
                showPermissionsOnboarding = false
            }
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showTutorial) {
            TutorialView {
                hasShownTutorial = true
                showTutorial = false
                // Trigger permissions after tutorial if not shown yet
                if !hasShownPermissionsOnboarding {
                    showPermissionsOnboarding = true
                }
            }
            .interactiveDismissDisabled()
        }
        .onAppear {
            if !hasShownTutorial {
                showTutorial = true
            } else if !hasShownPermissionsOnboarding {
                showPermissionsOnboarding = true
            }
        }
    }
}

#Preview {
    ContentView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ContentView()
        .preferredColorScheme(.dark)
}
