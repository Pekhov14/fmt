import Foundation

/// Локализация с возможностью переопределить язык в настройках приложения.
///
/// `NSLocalizedString` опирается на `CFBundleLocalizations`, а в этом проекте
/// Info.plist генерируется Xcode и списка языков не содержит. Поэтому системный
/// язык определяем сами и читаем нужный `.lproj` вручную. Один и тот же файл
/// используется и приложением, и Finder Sync extension.
enum L10n {
    static func string(
        _ key: String,
        language: MenuSettings.AppLanguage = .system,
        bundle: Bundle = .main
    ) -> String {
        let resolved: MenuSettings.AppLanguage
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            resolved = preferred.hasPrefix("ru") ? .ru : .en
        case .en, .ru:
            resolved = language
        }

        guard let path = bundle.path(forResource: resolved.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path) else {
            return NSLocalizedString(key, bundle: bundle, comment: "")
        }
        return NSLocalizedString(key, bundle: localizedBundle, comment: "")
    }
}
