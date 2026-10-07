import AppKit
import ApplicationServices
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let statusMenu = NSMenu()
    private var colorIcon: NSImage?
    private var disabledIcon: NSImage?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private let transformer = KeyTransformer()
    private var testWindow: NSWindow?
    private var setupWindow: SetupWindow?
    private var enabled = !UserDefaults.standard.bool(forKey: "paused")

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if PREVIEW
        // Screenshot mode for development builds only (scripts/build.sh with TOCHKA_PREVIEW=1).
        // Release builds do not contain this code.
        if CommandLine.arguments.contains("--preview-setup") {
            let preview = SetupWindow()
            let dark = CommandLine.arguments.contains("--dark")
            let ready = CommandLine.arguments.contains("--preview-ready")
            preview.window?.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            preview.update(trusted: ready, active: ready, secure: false,
                enabled: !CommandLine.arguments.contains("--disabled"), sourceID: Punctuation.russianID)
            let holdPreview = CommandLine.arguments.contains("--preview-hold")
            if holdPreview {
                setupWindow = preview
                preview.window?.center()
                preview.window?.makeKeyAndOrderFront(nil)
            } else {
                preview.window?.orderBack(nil)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let view = preview.window?.contentView {
                    view.layoutSubtreeIfNeeded()
                    view.displayIfNeeded()
                    let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    if let captured = bitmap.cgImage,
                       let context = CGContext(data: nil, width: captured.width, height: captured.height, bitsPerComponent: 8,
                           bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                        context.setFillColor(CGColor(gray: dark ? 0.12 : 0.97, alpha: 1))
                        context.fill(CGRect(x: 0, y: 0, width: captured.width, height: captured.height))
                        context.draw(captured, in: CGRect(x: 0, y: 0, width: captured.width, height: captured.height))
                        if let image = context.makeImage(),
                           let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
                           let path = CommandLine.arguments.last {
                            try? png.write(to: URL(fileURLWithPath: path))
                        }
                    }
                }
                if !holdPreview { NSApp.terminate(nil) }
            }
            return
        }
        #endif
        guard Startup.installed else {
            NSApp.setActivationPolicy(.accessory); NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Сначала перенеси «Точку» в «Программы»"
            alert.informativeText = "Закрой это окно. В образе диска перетащи «Точку» на папку «Программы», затем открой приложение из этой папки. Это нужно, чтобы разрешение и автозапуск сохранились."
            alert.addButton(withTitle: "Открыть «Программы»"); alert.addButton(withTitle: "Понятно")
            if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications")) }
            NSApp.terminate(nil); return
        }
        if let id = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: id).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [])
            NSApp.terminate(nil); return
        }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.autosaveName = "TochkaStatusItem"
        if let button = statusItem.button {
            let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            let icon = iconURL.flatMap { NSImage(contentsOf: $0) }
                ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Точка")
            icon?.size = NSSize(width: 20, height: 20)
            colorIcon = icon
            disabledIcon = icon.flatMap { StatusBarAppearance.grayscale($0) }
                ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Точка выключена")
            button.image = enabled ? colorIcon : disabledIcon
            button.title = ""
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityHelp("Нажатие включает и выключает Точку. Правый клик или Ctrl+клик открывает настройки.")
        }
        statusMenu.delegate = self
        rebuildMenu()
        statusItem.isVisible = true
        Startup.enableOnce()
        refresh()
        if LaunchBehavior.shouldShowSetup(hasPermission: AXIsProcessTrusted(),
            setupCompleted: UserDefaults.standard.bool(forKey: "setupCompleted"),
            loginLaunch: Startup.isLoginLaunchEvent) { showSetup() }
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refresh() }
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(woke),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if StatusBarInteraction.opensMenu(type: event?.type, modifiers: event?.modifierFlags ?? []) {
            // Attach only while tracking the menu, so ordinary clicks remain a toggle.
            statusItem.menu = statusMenu
            defer { statusItem.menu = nil }
            statusItem.button?.performClick(nil)
        } else {
            toggle()
        }
    }

    @objc private func woke() { transformer.reset(); refresh() }

    private func installTap() {
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let created = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let app = Unmanaged<AppDelegate>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    app.transformer.reset()
                    if let tap = app.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                } else {
                    app.transformer.transform(type: type, event: event, enabled: app.enabled,
                        sourceID: Punctuation.currentSourceID)
                }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return }
        tap = created
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)
    }

    private func refresh() {
        let trusted = AXIsProcessTrusted()
        if !trusted, let current = tap {
            CFMachPortInvalidate(current)
            if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
            tap = nil; runLoopSource = nil; transformer.reset()
        }
        if trusted && tap == nil { installTap() }
        let active = tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false
        if trusted && active && !UserDefaults.standard.bool(forKey: "setupCompleted") {
            // Granting permission completes onboarding even if the user closes the window
            // without clicking Done. A later login must not open it again.
            UserDefaults.standard.set(true, forKey: "setupCompleted")
        }
        let secure = IsSecureEventInputEnabled()
        setupWindow?.update(trusted: trusted, active: active, secure: secure, enabled: enabled,
            sourceID: Punctuation.currentSourceID())
        let icon = enabled ? colorIcon : disabledIcon
        if statusItem.button?.image !== icon { statusItem.button?.image = icon }
        let title = enabled ? "Точка включена" : "Точка выключена"
        statusItem.button?.setAccessibilityLabel(title)
        let warning = !trusted ? "Нужно разрешение macOS." : !active ? "Не удалось подключить ввод."
            : secure ? "Защищённый ввод — переназначение недоступно." : ""
        let tooltip = "\(title). Нажми для переключения.\nПравый клик или Ctrl+клик — настройки."
            + (warning.isEmpty ? "" : "\n" + warning)
        if statusItem.button?.toolTip != tooltip { statusItem.button?.toolTip = tooltip }
    }

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = statusMenu
        menu.removeAllItems()
        let toggleItem = menu.addItem(withTitle: enabled ? "Точка включена" : "Точка выключена",
            action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = enabled ? .on : .off
        let warning: String? = !AXIsProcessTrusted() ? "Нужно разрешение macOS"
            : !(tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false) ? "Не удалось подключить ввод"
            : IsSecureEventInputEnabled() ? "Защищённый ввод: временно недоступно" : nil
        if let warning { menu.addItem(withTitle: warning, action: nil, keyEquivalent: "") }
        menu.addItem(.separator())
        for title in ["Справа от Ю → .", "Shift + справа от Ю → ,", "Shift + 7 → ?", "Shift + 6 → /",
                      "Только стандартная «Русская»", "Другие раскладки работают без изменений"] {
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        }
        menu.addItem(.separator())
        add(menu, "Настройка и автозапуск…", #selector(showSetup))
        add(menu, "Проверить ввод…", #selector(showTest))
        add(menu, "Разрешение macOS…", #selector(requestPermission))
        menu.addItem(.separator())
        add(menu, "Исходный код и конфиденциальность…", #selector(openProjectPage))
        add(menu, "Завершить «Точку»", #selector(quit))
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: ""); item.target = self
    }
    @objc private func openProjectPage() { NSWorkspace.shared.open(Project.url) }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func toggle() { enabled.toggle(); UserDefaults.standard.set(!enabled, forKey: "paused"); refresh() }
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A running app may receive repeated reopen events from Finder or accessibility tools.
        // Do not recenter, unhide, or refocus an already visible window.
        if !flag && !Startup.isLoginLaunchEvent { showSetup() }
        return false
    }
    @objc private func showSetup() {
        if setupWindow == nil {
            let setup = SetupWindow()
            setup.permissionAction = { [weak self] in self?.requestPermission() }
            setup.testAction = { [weak self] in self?.showTest() }
            setup.finishAction = { UserDefaults.standard.set(true, forKey: "setupCompleted") }
            setupWindow = setup
        }
        refresh(); setupWindow?.present()
    }
    @objc private func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc private func showTest() {
        if testWindow == nil {
            let window = UtilityPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 290), resizable: true)
            window.title = "Точка — проверка ввода"; window.isReleasedWhenClosed = false
            let label = NSTextField(wrappingLabelWithString:
                "Включи «Точку», выбери стандартную «Русскую» и нажми: клавишу справа от Ю, затем её с Shift, Shift+7 и Shift+6. Должно получиться: .,?/\n\nДругие раскладки работают без изменений, независимо от их языка и количества.")
            label.frame = NSRect(x: 22, y: 166, width: 576, height: 100)
            label.autoresizingMask = [.width, .minYMargin]
            window.contentView?.addSubview(label)
            let scroll = NSScrollView(frame: NSRect(x: 22, y: 22, width: 576, height: 130))
            scroll.borderType = .bezelBorder; scroll.hasVerticalScroller = true
            scroll.autoresizingMask = [.width, .height]
            let text = NSTextView(frame: scroll.bounds)
            text.font = .monospacedSystemFont(ofSize: 25, weight: .regular)
            text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false
            text.isAutomaticDashSubstitutionEnabled = false; text.isAutomaticTextReplacementEnabled = false
            scroll.documentView = text; window.contentView?.addSubview(scroll)
            window.initialFirstResponder = text
            window.center()
            testWindow = window
        }
        testWindow?.makeKeyAndOrderFront(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
