import AppKit
import SwiftUI

struct ContentView: View {
    @State private var settings = MenuSettings.load()
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginNeedsApproval = LaunchAtLogin.needsApproval

    private var language: MenuSettings.AppLanguage { settings.language }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Дата сборки берётся из mtime исполняемого файла — install.sh копирует
    /// приложение с сохранением времени (`cp -Rp`), поэтому оно не сбрасывается.
    private var buildDate: String {
        guard let executablePath = Bundle.main.executablePath,
              let attributes = try? FileManager.default.attributesOfItem(atPath: executablePath),
              let date = attributes[.modificationDate] as? Date else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L10n.string("settings.description", language: language))

            VStack(alignment: .leading, spacing: 6) {
                Toggle(L10n.string("menu.copy", language: language), isOn: $settings.copyPath)
                Toggle(L10n.string("menu.createFile", language: language), isOn: $settings.createFile)
                Toggle(L10n.string("menu.openInTerminal", language: language), isOn: $settings.openInTerminal)
            }
            .padding(.top, 4)

            Toggle(L10n.string("settings.launchAtLogin", language: language), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    Task {
                        await LaunchAtLogin.setEnabled(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                        loginNeedsApproval = LaunchAtLogin.needsApproval
                    }
                }

            if loginNeedsApproval {
                Text(L10n.string("settings.loginApproval", language: language))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Picker(L10n.string("settings.language", language: language), selection: $settings.language) {
                Text(L10n.string("settings.language.system", language: language))
                    .tag(MenuSettings.AppLanguage.system)
                Text("English").tag(MenuSettings.AppLanguage.en)
                Text("Русский").tag(MenuSettings.AppLanguage.ru)
            }
            .pickerStyle(.menu)

            Text(L10n.string("settings.firstLaunch", language: language))
                .font(.footnote)
                .foregroundStyle(.secondary)

            Button(L10n.string("settings.openExtensions", language: language)) {
                openFinderExtensionsSettings()
            }

            HStack {
                Text("\(L10n.string("settings.version", language: language)) \(appVersion) · \(L10n.string("settings.build", language: language)) \(buildDate)")
                Spacer()
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding()
        .frame(width: 420, alignment: .leading)
        .background(SettingsWindowAccessor())
        .onChange(of: settings) { _, newSettings in
            MenuSettings.save(newSettings)
        }
    }

    private func openFinderExtensionsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") else { return }
        NSWorkspace.shared.open(url)
    }
}

#Preview {
    ContentView()
}
