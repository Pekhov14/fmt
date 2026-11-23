import Foundation
import ServiceManagement

/// Запуск приложения при входе в macOS через официальный API SMAppService.
/// Отдельный helper-application не нужен, работаёт и в песочнице.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        if #available(macOS 14.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) async -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if SMAppService.mainApp.status == .enabled {
                try await SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("fmt: не удалось изменить запуск при входе: %@", String(describing: error))
            return false
        }
    }
}
