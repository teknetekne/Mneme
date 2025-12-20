import Foundation

nonisolated struct MealWordCleaningHelper {
    // Word cleaning lists based on user's selected language
    nonisolated static func getMealVerbs(for locale: Locale = .current) -> [String] {
        let languageCode = locale.language.languageCode?.identifier ?? "en"
        
        switch languageCode {
        case "tr":  // Turkish
            return ["yedi", "yedim", "yiyorum", "yiyor", "yiyoruz", "yiyorlar", "yedik", "yediler", "yedin", "yiyeceğim", "yiyeceğiz"]
        case "en":  // English
            return ["had", "ate", "eating", "consumed", "finished", "having", "eat", "eaten", "consumed"]
        case "fr":  // French
            return ["mangé", "mange", "manger", "mangé", "mangeait", "mangé", "consommé"]
        case "es":  // Spanish
            return ["comí", "comido", "comer", "comiendo", "comiste", "comieron"]
        case "de":  // Almanca
            return ["gegessen", "essen", "aß", "gegessen", "isst"]
        case "it":  // Italian
            return ["mangiato", "mangiare", "mangia", "mangiato", "mangiava"]
        case "pt":  // Portekizce
            return ["comi", "comido", "comer", "comendo", "comeu"]
        default:  // Default: English + Turkish
            return ["had", "ate", "eating", "consumed", "finished", "having", "yedi", "yedim", "yiyorum", "yiyor", "yiyoruz", "yiyorlar", "yedik", "yediler"]
        }
    }
    
    // Comprehensive list supporting all languages (fallback)
    nonisolated static func getAllMealVerbs() -> [String] {
        return [
            // English
            "had", "ate", "eating", "consumed", "finished", "having", "eat", "eaten",
            // Turkish
            "yedi", "yedim", "yiyorum", "yiyor", "yiyoruz", "yiyorlar", "yedik", "yediler", "yedin", "yiyeceğim", "yiyeceğiz",
            // French
            "mangé", "mange", "manger", "mangeait", "consommé",
            // Spanish
            "comí", "comido", "comer", "comiendo", "comiste", "comieron",
            // Almanca
            "gegessen", "essen", "aß", "isst",
            // Italian
            "mangiato", "mangiare", "mangia", "mangiava",
            // Portekizce
            "comi", "comido", "comer", "comendo", "comeu"
        ]
    }
}
