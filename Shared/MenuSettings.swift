import Foundation

/// Настройки, общие для приложения и Finder Sync extension.
///
/// App Group требует регистрации в аккаунте Apple, поэтому используется
/// обычный файл в /Users/Shared: у расширения уже есть доступ ко всей ФС,
/// а приложение получило доступ к этому пути в entitlements.
enum MenuSettings {
    static let settingsURL = URL(fileURLWithPath: "/Users/Shared/fmt/menu-settings.json")
    static let didChangeNotification = Notification.Name("fmt.menuSettingsDidChange")

    enum Key: String {
        // Ключ в JSON остаётся прежним, чтобы не сбрасывать настройки пользователя.
        case copy = "copyPath"
        case createFile
        case openInTerminal
    }

    enum AppLanguage: String, Codable, CaseIterable, Identifiable {
        case system
        case en
        case ru

        var id: String { rawValue }
    }

    struct Settings: Codable, Equatable {
        var copyPath = true
        var createFile = true
        var openInTerminal = true
        var language: AppLanguage = .system

        private enum CodingKeys: String, CodingKey {
            case copyPath, createFile, openInTerminal, language
        }

        init() {}

        /// Неизвестные или отсутствующие поля не должны сбрасывать остальные настройки.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            copyPath = try container.decodeIfPresent(Bool.self, forKey: .copyPath) ?? true
            createFile = try container.decodeIfPresent(Bool.self, forKey: .createFile) ?? true
            openInTerminal = try container.decodeIfPresent(Bool.self, forKey: .openInTerminal) ?? true
            language = try container.decodeIfPresent(AppLanguage.self, forKey: .language) ?? .system
        }
    }

    static func load() -> Settings {
        guard let data = try? Data(contentsOf: settingsURL),
              let decoded = try? JSONDecoder().decode(Settings.self, from: data) else {
            return Settings()
        }
        return decoded
    }

    @discardableResult
    static func save(_ settings: Settings) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            // Без .atomic: исключение в entitlements даёт доступ только к самому файлу.
            try encoder.encode(settings).write(to: settingsURL)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
            return true
        } catch {
            NSLog("fmt: не удалось сохранить настройки в %@: %@", settingsURL.path, String(describing: error))
            return false
        }
    }

    static func isEnabled(_ key: Key) -> Bool {
        let settings = load()
        switch key {
        case .copy: return settings.copyPath
        case .createFile: return settings.createFile
        case .openInTerminal: return settings.openInTerminal
        }
    }

    static func set(_ key: Key, enabled: Bool) {
        var settings = load()
        switch key {
        case .copy: settings.copyPath = enabled
        case .createFile: settings.createFile = enabled
        case .openInTerminal: settings.openInTerminal = enabled
        }
        save(settings)
    }
}
