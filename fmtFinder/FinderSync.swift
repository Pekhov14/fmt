import Cocoa
import FinderSync

/// Добавляет пункты меню в контекстное меню Finder.
///
/// Finder Sync extension — единственный официальный способ добавить пункты
/// при нажатии правой кнопкой на пустом месте папки (и на Рабочем столе).
final class FinderSync: FIFinderSync {

    private var lastObservedDirectory: URL?

    override init() {
        super.init()

        // "/" покрывает и Рабочий стол, и любые папки, включая смонтированные диски.
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func beginObservingDirectory(at url: URL) {
        lastObservedDirectory = url
    }

    override func endObservingDirectory(at url: URL) {
        if lastObservedDirectory == url {
            lastObservedDirectory = nil
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind == .contextualMenuForContainer ||
                menuKind == .contextualMenuForItems else {
            return nil
        }

        let menu = NSMenu(title: "")
        // Запоминаем объект, по которому кликнули, пока контекст меню ещё актуален.
        // Для меню по элементу сначала берём выделенный элемент: targetedURL()
        // у некоторых версий Finder возвращает папку вместо файла.
        let controller = FIFinderSyncController.default()
        let targetURL: URL?
        if menuKind == .contextualMenuForContainer {
            targetURL = controller.targetedURL() ?? lastObservedDirectory
        } else {
            targetURL = controller.selectedItemURLs()?.first
                ?? controller.targetedURL()
                ?? lastObservedDirectory
        }

        rememberClickedURL(targetURL)

        if MenuSettings.isEnabled(.createFile) {
            menu.addItem(makeItem(
                title: localized("menu.createFile"),
                action: #selector(createFile(_:)),
                symbol: "doc.text"
            ))
        }
        if MenuSettings.isEnabled(.copy) {
            let copyItem = makeItem(
                title: localized("menu.copy"),
                action: nil,
                symbol: "doc.on.doc"
            )
            let copyMenu = NSMenu(title: "")
            var copyActions: [(title: String, action: Selector)] = [
                (localized("menu.copy.path"), #selector(copyPath(_:))),
                (localized("menu.copy.name"), #selector(copyName(_:))),
            ]
            // У папки нет ни расширения, ни имени без расширения.
            if !isDirectoryURL(targetURL) {
                copyActions.append((localized("menu.copy.stem"), #selector(copyStem(_:))))
                copyActions.append((localized("menu.copy.extension"), #selector(copyExtension(_:))))
            }
            for entry in copyActions {
                let item = makeItem(title: entry.title, action: entry.action)
                item.representedObject = targetURL
                copyMenu.addItem(item)
            }
            copyItem.submenu = copyMenu
            menu.addItem(copyItem)
        }
        if MenuSettings.isEnabled(.openInTerminal) {
            menu.addItem(makeItem(
                title: localized("menu.openInTerminal"),
                action: #selector(openInTerminal(_:)),
                symbol: "terminal"
            ))
        }

        return menu.items.isEmpty ? nil : menu
    }

    private func makeItem(title: String, action: Selector?, symbol: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        if let symbol {
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        }
        return item
    }

    /// Bundle.main для extension — это Finder, поэтому берём бандл самого расширения.
    /// Язык берём из общих настроек, чтобы переключатель в приложении влиял и на меню.
    private func localized(_ key: String) -> String {
        L10n.string(
            key,
            language: MenuSettings.load().language,
            bundle: Bundle(for: FinderSync.self)
        )
    }

    /// URL, по которому кликнули. Для пустого места — сама папка.
    private func clickedURL() -> URL? {
        let controller = FIFinderSyncController.default()
        if let targeted = controller.targetedURL() { return targeted }
        if let selected = controller.selectedItemURLs(), selected.count == 1 { return selected[0] }
        return lastObservedDirectory
    }

    /// В actions меню полагаться на targetedURL() нельзя — используем сохранённый URL.
    private func actionURL(from sender: AnyObject?) -> URL? {
        let represented = (sender as? NSMenuItem)?.representedObject as? URL
        return represented ?? rememberedClickedURL() ?? clickedURL()
    }

    private static let clickedURLFile = URL(fileURLWithPath: "/Users/Shared/fmt/last-clicked-url")

    private func rememberClickedURL(_ url: URL?) {
        try? (url?.path ?? "").write(to: Self.clickedURLFile, atomically: true, encoding: .utf8)
    }

    private func rememberedClickedURL() -> URL? {
        guard let path = try? String(contentsOf: Self.clickedURLFile, encoding: .utf8),
              !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func isDirectoryURL(_ url: URL?) -> Bool {
        guard let url else { return false }
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    /// Папка, в которой нужно работать: при клике по папке — она сама,
    /// при клике по файлу — папка, где он лежит.
    private func directoryForAction() -> URL? {
        let controller = FIFinderSyncController.default()
        var directory = clickedURL()

        if let selected = controller.selectedItemURLs(), selected.count == 1 {
            let values = try? selected[0].resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            if values?.isDirectory == true && values?.isPackage != true {
                directory = selected[0]
            }
        }

        guard var directory else { return nil }

        let values = try? directory.resourceValues(forKeys: [.isDirectoryKey])
        if values?.isDirectory != true {
            directory = directory.deletingLastPathComponent()
        }

        return directory
    }

    @objc private func createFile(_ sender: AnyObject?) {
        guard let directory = directoryForAction() else {
            NSLog("fmtFinder: не удалось определить папку для создания файла")
            NSSound.beep()
            return
        }

        let didStartAccess = directory.startAccessingSecurityScopedResource()
        defer {
            if didStartAccess {
                directory.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let created = try FileFactory.createFile(in: directory)
            NSLog("fmtFinder: создан файл %@", created.path)
        } catch {
            NSLog("fmtFinder: ошибка создания файла в %@: %@", directory.path, String(describing: error))
            NSSound.beep()
        }
    }

    @objc private func copyPath(_ sender: AnyObject?) {
        guard let url = actionURL(from: sender) else {
            NSLog("fmtFinder: не удалось определить путь для копирования")
            NSSound.beep()
            return
        }
        copyToPasteboard(url.path, description: "путь")
    }

    @objc private func copyName(_ sender: AnyObject?) {
        guard let url = actionURL(from: sender) else {
            NSLog("fmtFinder: не удалось определить имя для копирования")
            NSSound.beep()
            return
        }
        copyToPasteboard(url.lastPathComponent, description: "имя")
    }

    @objc private func copyStem(_ sender: AnyObject?) {
        guard let url = actionURL(from: sender) else {
            NSLog("fmtFinder: не удалось определить имя для копирования")
            NSSound.beep()
            return
        }
        copyToPasteboard(url.deletingPathExtension().lastPathComponent, description: "имя без расширения")
    }

    @objc private func copyExtension(_ sender: AnyObject?) {
        guard let url = actionURL(from: sender) else {
            NSLog("fmtFinder: не удалось определить расширение для копирования")
            NSSound.beep()
            return
        }
        // Папка с точкой в имени (например, "my.folder") не имеет расширения.
        // Пакеты (.app и т. п.) — это файлы для Finder, их расширение копируем.
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values?.isDirectory == true && values?.isPackage != true {
            NSLog("fmtFinder: «%@» — папка, расширения нет", url.lastPathComponent)
            NSSound.beep()
            return
        }

        let extensionName = url.pathExtension
        guard !extensionName.isEmpty else {
            NSLog("fmtFinder: у «%@» нет расширения", url.lastPathComponent)
            NSSound.beep()
            return
        }
        copyToPasteboard(extensionName, description: "расширение")
    }

    private func copyToPasteboard(_ value: String, description: String) {
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(value, forType: .string) else {
            NSLog("fmtFinder: не удалось скопировать %@ %@", description, value)
            NSSound.beep()
            return
        }
        NSLog("fmtFinder: скопирован %@ %@", description, value)
    }

    @objc private func openInTerminal(_ sender: AnyObject?) {
        guard let directory = directoryForAction() else {
            NSLog("fmtFinder: не удалось определить папку для Terminal")
            NSSound.beep()
            return
        }

        guard let terminalURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: "com.apple.Terminal"
        ) else {
            NSLog("fmtFinder: Terminal.app не найден")
            NSSound.beep()
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: terminalURL,
            configuration: configuration
        ) { _, error in
            if let error {
                NSLog("fmtFinder: ошибка открытия Terminal в %@: %@", directory.path, String(describing: error))
                NSSound.beep()
            }
        }
    }
}

private enum FileFactory {
    /// Создаёт file.txt. Если имя занято — file 2.txt, file 3.txt и т.д.
    static func createFile(in directory: URL) throws -> URL {
        let manager = FileManager.default
        var candidate = directory.appendingPathComponent("file.txt")
        var index = 2

        while manager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("file \(index).txt")
            index += 1
        }

        try Data().write(to: candidate, options: .withoutOverwriting)
        return candidate
    }
}
