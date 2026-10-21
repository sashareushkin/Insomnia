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

    func testSettingsNavigationUsesSevenStableDestinationsInTheAgreedOrder() {
        let sections = SettingsSection.allCases
        XCTAssertEqual(sections, [.general, .timer, .lidClose, .applications, .power, .network, .tmux])
        XCTAssertEqual(
            sections.map(\.destination),
            [.general, .timer, .lidClose, .applications, .power, .network, .tmux]
        )
        XCTAssertEqual(
            sections.map(\.symbol),
            ["gearshape", "timer", "laptopcomputer", "square.stack.3d.up", "battery.100percent", "wifi", "terminal"]
        )
        XCTAssertEqual(
            sections.map { L10n.string($0.titleKey, language: .english) },
            ["General", "Timer", "Lid Close", "Applications", "Power", "Network", "tmux"]
        )
        XCTAssertEqual(
            sections.map { L10n.string($0.titleKey, language: .russian) },
            ["Основные", "Таймер", "Закрытие крышки", "Приложения", "Питание", "Сеть", "tmux"]
        )
    }

    func testSettingsSectionCopyIsPresentInBothCatalogs() {
        let keys = [
            "Agent applications",
            "Applications",
            "Audio",
            "Display and keyboard",
            "Duration presets",
            "Explicit freeze list",
            "General",
            "Hotspot",
            "Lid Close",
            "Lid-close power",
            "Location Services",
            "Location permission lets macOS reveal Wi-Fi network names so Insomnia can find the configured hotspot.",
            "Network",
            "Power",
            "Protected/agent applications",
            "Reconnect nudges",
            "Session defaults",
            "Suspend on lid close",
            "The display brightness and keyboard backlight are saved, set to zero and restored when the lid opens. If Insomnia is not running when you open the lid, press the brightness-up key.",
            "Explicit freeze-list entries are stopped with SIGSTOP while the lid is closed and resumed when it opens, unless the hard denylist excludes them. With Freeze every other app on (off by default), every other Dock app is automatically stopped too, except agent apps, Apple apps, Docker Desktop, and built-in protected apps (editors, terminals, browsers, AI apps, password managers, local databases, Tailscale, local model servers, and meeting, recording, and dictation apps such as Zoom, Teams, Webex, Wispr Flow, Granola, Otter, OBS, and Loom). Agent apps, Apple apps, Insomnia, and Docker Desktop remain excluded even when listed explicitly. Built-in protected apps are excluded from automatic freeze-all; explicitly adding one to the freeze list overrides only that automatic exclusion.",
            "Agent apps are never frozen or throttled. Editors, AI apps, terminals, browsers, password managers, local databases, Tailscale, local model servers, and meeting, recording and dictation apps are also protected from the automatic lid-close scope even when they are not listed here; adding one to the freeze list above overrides that built-in automatic protection. The hard denylist still prevents explicit freezing of agent apps, Apple apps, Insomnia and Docker Desktop.",
            "The password is kept in the login keychain, readable without a prompt only by the build of Insomnia that saved it; after a reinstall, enter it again.",
            "This action only targets panes marked with the command above. With Enter enabled, it can submit unfinished input in a marked pane."
        ]

        for key in keys {
            XCTAssertEqual(L10n.string(key, language: .english), key, "English catalog: \(key)")
            XCTAssertNotEqual(L10n.string(key, language: .russian), key, "Russian catalog: \(key)")
        }
        XCTAssertEqual(L10n.format("Remove %@", language: .russian, "Safari"), "Удалить Safari")
        XCTAssertEqual(L10n.format("Remove preset %@", language: .russian, "30 мин"), "Удалить вариант длительности 30 мин")
        XCTAssertEqual(L10n.format("Remove tmux target %@", language: .russian, "main:1.2"), "Удалить цель tmux main:1.2")
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
