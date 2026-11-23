import AppKit
import SwiftUI

@main
struct MyApp: App {
    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .resizable()
                .frame(width: 22, height: 22)
        }

        WindowGroup(id: "settings") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @State private var language = MenuSettings.load().language

    var body: some View {
        Group {
            Button(L10n.string("menubar.settings", language: language)) {
                openSettings()
            }
            Divider()
            Button(L10n.string("menubar.quit", language: language)) {
                NSApp.terminate(nil)
            }
        }
        // Меню может быть уже построено в момент смены языка в настройках.
        .onReceive(NotificationCenter.default.publisher(for: MenuSettings.didChangeNotification)) { _ in
            language = MenuSettings.load().language
        }
    }

    /// Приложение — агент без Dock-иконки, поэтому его нужно явно активировать.
    /// Если окно уже открыто, поднимаем его, а не создаём второе.
    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = SettingsWindow.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            SettingsWindow.configure(window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        openWindow(id: "settings")
        DispatchQueue.main.async {
            if let window = SettingsWindow.window {
                SettingsWindow.configure(window)
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
