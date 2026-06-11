# Mneme

<p align="center">
  <img src="https://www.mneme.website/assets/mneme-logo.png" width="120" alt="Mneme Logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL v3">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift: 6.0">
  <img src="https://img.shields.io/badge/Platform-iOS%2026.1-lightgrey.svg" alt="Platform: iOS 26.1">
</p>

Mneme (pronounced *nee-mee*, named after the Muse of memory) turns free-form text into structured actions. One text field replaces your calendar, health tracker, finance log, and diary.

Powered by Apple Foundation Models, everything runs on-device. Your data never touches a third-party server.

<p align="center">
  <a href="https://www.mneme.website">
    <img src="https://www.mneme.website/assets/notepad.png" width="250" alt="Mneme Notepad">
  </a>
</p>

[mneme.website](https://www.mneme.website)

## Usage

Type naturally. Mneme understands what you mean.

### Events & Reminders

```
Meeting with Sarah tomorrow at 3pm
Dentist appointment next friday 10:00
Call mom at 18:00
```

Add a location with `@`:

```
Dinner with Ashley @ Hard Rock Cafe
```

### Expenses & Income

```
Coffee 4.50 USD
Groceries 120 TRY
Freelance payment 500 EUR
```

### Meals & Calories

Mneme looks up calories via the USDA database automatically.

```
Ate 200g chicken breast
2 eggs and toast
Coffee with milk
```

### Work Sessions

```
Work started
Work ended
Work started on iOS project
```

### Activities

```
Ran 5km
30 min cycling
```

### Journal & Mood (`:`)

Type `:` to open the mood picker, then select an emoji to start a journal entry. Journal parsing uses the emoji-prefixed text.

```
: Productive day, finished the refactor
: Feeling tired after the long meeting
```

### Smart Variables

Define reusable shortcuts for recurring amounts. Combine them with `+` and `-`:

```
+salary
-rent
+salary-rent-bills
+breakfast (meal variable, logs calories)
```

### Calorie Adjustments

```
+200 kcal
-150 kcal
```

## Key Capabilities

- **One Input, Many Actions** — A single text field handles events, reminders, expenses, meals, work sessions, activities, and journal entries.
- **On-Device NLP** — Intent classification and entity extraction via `SystemLanguageModel`. Supports multilingual input, with event/reminder translation when needed. No cloud calls, no latency.
- **Privacy First** — All processing happens locally. iCloud sync mirrors data across your devices, but logic never leaves the phone.
- **Native Integrations** — Calendar and Reminders via EventKit. Steps, active energy, and distance via HealthKit (read-only).
- **Analytics Dashboard** — Six chart tabs: Overview, Productivity, Calories, Balance, Mood, and Analysis with AI-generated correlations.
- **Smart Variables** — Define named shortcuts for recurring expenses, income, or meals. Combine them in expressions (`+salary-rent`).
- **Multi-Currency** — Automatic currency conversion via FreeCurrencyAPI. Expenses in any currency are converted to your base currency.

## App Structure

The app has four main tabs:

| Tab | Purpose |
|---|---|
| **Notepad** | Primary input — type and Mneme parses |
| **Reminders** | View and manage reminders (EventKit) |
| **Calendar** | View calendar events (EventKit) |
| **Summary** | Analytics dashboard with 6 chart views |

## How Parsing Works

1. **Input** — User types in the Notepad. `NotepadViewModel` debounces with a 300ms throttle and 800ms parse delay.
2. **Variable Check** — `VariableHandler` checks for variable expressions (`+salary`, `-rent+bonus`) before NLP.
3. **Intent Classification** — `IntentClassificationService` classifies raw text into one of: `meal`, `expense`, `income`, `event`, `reminder`, `activity`, `work_start`, `work_end`, `journal`, `calorie_adjustment`.
4. **Translation** — Event and reminder extraction translate non-English text on-device when needed.
5. **Entity Extraction** — Specialized handlers (`MealHandler`, `ExpenseHandler`, `EventHandler`, `ActivityHandler`, `WorkSessionHandler`, `JournalHandler`, `CalorieAdjustmentHandler`) extract structured fields using a mix of LLM extraction and deterministic regex.
6. **Action** — Results are saved to Core Data. Events and reminders sync to EventKit. Calorie data is enriched via the USDA API.

## Tech Stack

- **Language**: Swift 6 with strict concurrency
- **UI**: SwiftUI + Swift Charts
- **AI/NLP**: Apple Foundation Models (`SystemLanguageModel`), on-device Translation, custom regex parsers
- **Persistence**: Core Data with `NSPersistentCloudKitContainer` (automatic iCloud sync, local fallback)
- **Integrations**: EventKit (Calendar + Reminders), HealthKit (read-only)
- **Data Sources**: USDA FoodData Central (calories), FreeCurrencyAPI (exchange rates)
- **Architecture**: MVVM with composition — `NotepadViewModel` coordinates `LineStore`, `LineManager`, `TagManager`, `EventKitManager`, `WorkSessionManager`, and `LocationManager`

## Requirements

- iOS 26.1+
- Xcode 26+
- No external dependencies (no CocoaPods, Carthage, or SPM)

## Building

```bash
xcodebuild build \
  -project Mneme.xcodeproj \
  -scheme Mneme \
  -destination 'platform=iOS Simulator,name=iPhone 16'
```

### API Keys (optional)

Set these in a local Xcode scheme or your local environment. Do not commit secrets to the shared scheme:

- `CURRENCY_API_KEY` — [FreeCurrencyAPI](https://freecurrencyapi.com) key for exchange rates
- `USDA_API_KEY` — [USDA FoodData Central](https://fdc.nal.usda.gov/api-guide) key (falls back to `DEMO_KEY`)

### LSP / Build Server

Generate `buildServer.json` locally when needed:

```bash
xcode-build-server config -project Mneme.xcodeproj -scheme Mneme
```

## Contributing

Contributions are welcome. Bug fixes, parser improvements for new languages, new chart types, or new intent handlers.

1. Fork the repo
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes
4. Push and open a Pull Request

## License

Source code is licensed under the **GNU General Public License v3.0 (GPLv3)**. See [LICENSE](LICENSE) for details.
