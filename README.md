# Mneme

Privacy-first personal operating system for your day. Mneme turns free-form notes into reminders, calendar events, health logs, finances, meals, work sessions, and insights using on-device Apple Foundation Models. Built with SwiftUI for iOS.

## Highlights
- On-device understanding with Foundation Models + custom parsers; multilingual input (English, Turkish, French, Spanish, German, Italian, Portuguese, ...).
- One notepad for everything: reminders, events, expenses, income, meals, activities, work start/end, calorie adjustments, journals with mood emoji.
- Connected data: EventKit, HealthKit, Core Data mirrored to CloudKit with resilient local fallback.
- Rich visuals: calories, finance, and productivity charts plus AI-generated daily pattern insights.
- Privacy by default: no server dependency; optional iCloud sync and USDA calorie lookups only when needed.

## Tabs & Capabilities
- **Notepad**: Debounced parsing of free-text (~1s); intent detection, slot extraction, validation; variable arithmetic (e.g., `+salary-rent`, `+protein_shake`); tags with shared palette; location and URL detection; quick "Done" processing to create reminders/events or log entries; keyboard-friendly multi-line editing.
- **Reminders**: View/manage EventKit reminders created from parsed lines; keep tags and links attached.
- **Calendar**: Create and edit calendar events with normalized titles, day/time sanitization, and optional locations/URLs.
- **Daily Summary**: Calories consumed/burned/net, finances (income, expense, net), and productivity snapshots using the `Charts` module; shortcuts to settings.
- **Analysis**: `SummaryInsightsService` correlates mood, work minutes, calories, and balance for the last 30 days using `SystemLanguageModel`, with deterministic heuristics as fallback.
- **Settings**: Base currency, personal details, theme, and cloud sync status; currency conversion for mixed-currency entries.
- **Health**: HealthKit-backed steps/active energy/distance plus activity calorie estimates; meals get calorie lookup via Foundation Models and USDA when available.

## How Parsing Works
1. Each notepad line is stored in `LineStore` (dictionary keyed by UUID for safe concurrent updates).
2. `NotepadViewModel` debounces keystrokes, then calls `NLPService` which bridges `FoundationModelsNLP`, translation, and intent-specific parser services.
3. `HandlerFactory` routes results to handlers (reminder, event, expense, income, meal, activity, work session, calorie adjustment, journal) to validate fields and build `ParsingResultItem`s.
4. Successful lines create EventKit items, log work sessions, or write structured entries via `NotepadEntryStore`; tags, locations, and URLs are preserved.
5. `PersistenceController` uses Core Data with CloudKit mirroring, falling back to a local store automatically.
6. Charts and insights read from stores/HealthKit and render in SwiftUI with per-tab theming.

## Tech Stack
- Swift + SwiftUI + async/await
- Foundation Models (`SystemLanguageModel`, `Translation`) on-device
- EventKit, HealthKit
- Core Data + CloudKit mirroring (with local fallback)
- SwiftUI Charts + custom chart components
- Combine-powered stores and managers

## Requirements
- Xcode 16+ (Foundation Models require the 2025 toolchain)
- iOS 26.1 for on-device models and Translation
- iCloud account for CloudKit sync (optional; falls back to local persistence)
- Physical iOS device for HealthKit data

## Setup
1. Clone the repo: `git clone <repo-url>` and `cd Mneme`.
2. Open `Mneme.xcodeproj` in Xcode.
3. Set your Development Team and bundle identifier.
4. Configure an iCloud container ID in `Info.plist` and Signing & Capabilities if you want CloudKit sync; otherwise the app will run in local-only mode.
5. Build & run on device or simulator (HealthKit features need a device). During first launch, complete permissions for Reminders, Calendar, Health, Notifications, and Location as prompted.

## Usage
- Type free-form notes in Notepad; parsing runs automatically after a short pause.
- Review extracted fields (intent, subject, day/time, amount, currency, calories, distance, links).
- Press "Done" to create reminders/events or log journal/meals/expenses/income/activities/work sessions.
- View and edit items in Reminders/Calendar; explore charts and insights in Daily Summary and Analysis.

Example inputs:
```
remind me to call the dentist tomorrow at 2pm
meeting with team on monday 10:00 @HQ
bought coffee for 5 EUR
earned 1000 USD from freelance work
ate pizza 300g
🙂 felt great after morning run 5km 30min
work start project phoenix 09:00
work end 18:15
+salary-rent
+1000$
+100 kcal
-200 kcal etc.
```

## Data & Privacy
- All NLP happens on-device; no third-party servers.
- CloudKit sync is optional; if unavailable, data stays local.
- HealthKit and EventKit access is explicit and only used for the features you enable.
- Meal calorie lookup may contact USDA endpoints; everything else is offline.

## Project Structure
- `MnemeApp.swift`: app entry and shared environment objects.
- `Views/`: SwiftUI screens (Notepad, Reminders, Calendar, Daily Summary, Analysis, Settings, onboarding/tutorial).
- `ViewModels/`: UI coordinators (`NotepadViewModel`).
- `Managers/`: Line, Tag, EventKit, Location, WorkSession coordination.
- `Handlers/`: Intent-specific processors.
- `Stores/`: Observable stores (entries, tags, user settings, currency settings, work sessions, cloud sync status).
- `Services/`: NLP pipeline, parser services, EventKit/HealthKit/Currency/Translation, persistence, summaries.
- `Charts/`: Chart components, models, utilities, and tabs.
- `Models/`: Shared types and Core Data schema.
- `Resources/Theme.swift`, `Assets.xcassets`: styling and assets.
- `Mneme.xcodeproj/`: Xcode project configuration.

## Contributing
- Fork the repo, create a feature branch, and keep changes modular.
- Prefer small, focused PRs with clear descriptions and screenshots when UI changes.
- Follow Swift async/await patterns already in the codebase; avoid blocking the main thread.
- Add tests when possible (in-memory persistence is available for isolation).

## Roadmap (early open-source)
- Automated tests for parsing and handlers
- Recurring event/reminder support
- Export/backup options
- Additional widgets/shortcuts for quick capture
- More chart breakouts and filters

## License
Planned for open-source distribution; add a LICENSE file before public release.
