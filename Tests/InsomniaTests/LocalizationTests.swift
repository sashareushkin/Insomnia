import XCTest
@testable import Insomnia

@MainActor
final class LocalizationTests: XCTestCase {
    func testSupportedLanguageResolutionHandlesRegionalAndOrderedPreferences() {
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["ru"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["ru-RU"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["en"]), .english)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["en-US"]), .english)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["fr-FR", "ru-RU", "en-US"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["de-DE", "en-GB"]), .english)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: ["fr-CA"], system: ["de-DE", "ru-RU"]), .russian)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: ["en-US"], system: ["ru-RU"]), .english)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: ["fr-FR", "de-DE"]), .english)
        XCTAssertEqual(AppLanguage.resolve(appSpecific: [], system: []), .english)
    }

    func testManualChoiceIsTransientAndNextLaunchResolvesMacOSPreferencesAgain() {
        let manager = LocalizationManager()
        defer { LocalizationManager.shared.language = .english }

        manager.resolveAtLaunch(appSpecific: ["ru-RU"], system: ["en-US"])
        XCTAssertEqual(manager.language, .russian)

        manager.language = .english
        XCTAssertEqual(manager.language, .english)

        manager.resolveAtLaunch(appSpecific: ["ru-RU"], system: ["en-US"])
        XCTAssertEqual(manager.language, .russian)
    }

    func testOnlyRussianAndEnglishAreOfferedAndBothBundlesAreAvailable() {
        XCTAssertEqual(AppLanguage.allCases, [.russian, .english])
        XCTAssertEqual(L10n.availableLocalizations(), ["ru", "en"])
        XCTAssertEqual(L10n.string("Session", language: .english), "Session")
        XCTAssertEqual(L10n.string("Session", language: .russian), "Сессия")
    }

    func testManualLanguageFormattingUsesLocalizedCatalog() {
        XCTAssertEqual(L10n.format("Location: %@", language: .russian, "Allowed"), "Геопозиция: Allowed")
        XCTAssertEqual(L10n.presentation("could not write session: disk full", language: .russian), "Не удалось записать сессию: disk full")
        XCTAssertEqual(L10n.presentation("GitHub answered HTTP 429", language: .russian), "GitHub ответил кодом HTTP 429")
        XCTAssertEqual(L10n.presentation("could not write session: disk full", language: .english), "could not write session: disk full")
    }

    func testRussianPluralFormsForMinutesHoursDaysAndApplications() {
        XCTAssertEqual(L10n.plural("minutes", count: 1, language: .russian), "1 минута")
        XCTAssertEqual(L10n.plural("minutes", count: 2, language: .russian), "2 минуты")
        XCTAssertEqual(L10n.plural("minutes", count: 5, language: .russian), "5 минут")
        XCTAssertEqual(L10n.plural("minutes", count: 21, language: .russian), "21 минута")
        XCTAssertEqual(L10n.plural("minutes", count: 12, language: .russian), "12 минут")
        XCTAssertEqual(L10n.plural("hours", count: 3, language: .russian), "3 часа")
        XCTAssertEqual(L10n.plural("days", count: 5, language: .russian), "5 дней")
        XCTAssertEqual(L10n.plural("appsFrozen", count: 1, language: .russian), "1 приложение остановлено")
        XCTAssertEqual(L10n.plural("appsFrozen", count: 2, language: .russian), "2 приложения остановлены")
        XCTAssertEqual(L10n.plural("appsFrozen", count: 5, language: .russian), "5 приложений остановлено")
    }
}
