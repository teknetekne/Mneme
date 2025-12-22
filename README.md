# Mneme

<p align="center">
  <img src="https://www.mneme.website/assets/mneme-logo.png" width="120" alt="Mneme Logo">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/License-GPLv3-blue.svg" alt="License: GPL v3">
  <img src="https://img.shields.io/badge/Swift-6.0-orange.svg" alt="Swift: 6.0">
  <img src="https://img.shields.io/badge/Platform-iOS%2026.1-lightgrey.svg" alt="Platform: iOS 26.1">
</p>

## 💡 **What is Mneme?**

Visit our website: [mneme.website](https://www.mneme.website)

Mneme (pronounced *nee-mee*, named after the Muse of memory) turns your free-form thoughts into structured actions. Instead of juggling 5 different apps for your calendar, health, finance, and diary, you just type naturally. **Profoundly Intuitive. The intelligent workspace that understands you.**

<p align="center">
  <a href="https://www.mneme.website">
    <img src="https://www.mneme.website/assets/notepad.png" width="250" alt="Mneme UI">
  </a>
</p>

Powered by Apple Foundation Models, everything happens on-device. Your data never touches a third-party server.

## ⚡️ Usage

Start typing naturally. Mneme uses simple formatting to understand your intent.

### 📍 Locations (`@`)
Use the `@` symbol to specify a location for your events or reminders.
- `Dinner with Ashley @ Hard Rock Cafe`
- `Meeting at 10am @ Office`

### 📔 Journal & Mood (`:`)
Start a line with `:` to create a journal entry by choosing your mood.
- `: I feel great today!`
- `: Had a productive meeting with the team.`

### 💰 Smart Variables
Define custom variables for recurring values like your salary or rent.
- `+salary` → Adds your defined salary amount.
- `-rent` → Deducts your rent amount.

### 🍎 Health & Food
Log your meals naturally. Mneme calculates calories automatically.
- `Ate 200g pizza`
- `Drank 1 cup of coffee`


## Key Capabilities

- ⚡️ **Frictionless Input**: One text field for everything. Debounced parsing understands intent, time, money, and calories instantly.
- 🧠 **On-Device Intelligence**: Uses `SystemLanguageModel` and custom parsers to understand English, Turkish, French, German, and more. No cloud latency, no privacy risks.
- 🔒 **Privacy First**: Your life stays on your phone. iCloud sync mirrors data across your devices, but logic runs locally.
- 🔗 **Deep Integration**: Native support for EventKit (Calendar/Reminders) and HealthKit. It feels like part of iOS.
- 📊 **Insightful**: Beautiful charts for finances and calories, plus AI-generated correlations (e.g., "You spend more money on days you don't sleep well").

## 🛠 Tech Stack

Designed for the modern Apple ecosystem, pushing the limits of what SwiftUI and on-device AI can do.

- **Language**: Swift 6
- **UI**: SwiftUI + Charts
- **AI/NLP**: FoundationModels (`SystemLanguageModel`), Translation framework, Custom Regex Parsers.
- **Persistence**: Core Data mirrored to CloudKit (with local fallback).
- **Integrations**: EventKit, HealthKit (Read-Only).
- **Data Sources**: USDA API (Calorie Data), FreeCurrencyAPI (Exchange Rates).
- **Architecture**: MVVM with centralized `ParsingService` and `LineStore`.

## 🏗 How Parsing Works (The Engine)

1. **Input**: User types in the Notepad. `NotepadViewModel` debounces the input.
2. **NLP Pipeline**: The text is passed to `NLPService`, which utilizes on-device Foundation Models to classify intent (Event vs. Expense vs. Journal).
3. **Extraction**: Specialized handlers (`MealHandler`, `FinanceHandler`, etc.) extract entities like Amount, Date, Calories using a mix of LLM extraction and deterministic regex for 100% accuracy on critical numbers.
4. **Action**:
    - **Health**: Reads activity data (Steps, Active Energy) from HealthKit. Consumed calories are enriched via **USDA API**.
    - **Calendar**: Syncs with EventKit.
    - **Storage**: Saves structured data to Core Data for charts/history.

## 🤝 Contributing

Contributions are welcome! Whether it's fixing a bug, improving the parser for a new language, or adding a new chart type.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## ⚖️ License & Copyright

Source Code: The source code of Mneme is licensed under the **GNU General Public License v3.0 (GPLv3)**. You are free to use, modify, and distribute the code, provided that any derivative works are also open-source under the same license. See [LICENSE](LICENSE) for details.