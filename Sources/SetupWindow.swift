import AppKit
import ServiceManagement

// A menu-bar utility must not compete with the frontmost application's activation.
// Keep keyboard input local to the panel instead of activating the accessory app.
final class UtilityPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(contentRect: NSRect, resizable: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .nonactivatingPanel]
        if resizable { style.insert(.resizable) }
        super.init(contentRect: contentRect, styleMask: style, backing: .buffered, defer: false)
        isFloatingPanel = false
        hidesOnDeactivate = false
        level = .normal
        isReleasedWhenClosed = false
        isRestorable = false
        animationBehavior = .none
    }
}

// Draw the keycaps natively so their edges and legends stay sharp on Retina displays.
private final class KeycapView: NSView {
    private let symbol: String

    init(symbol: String, frame: NSRect) {
        self.symbol = symbol
        super.init(frame: frame)
        // The physical black keycap uses the same white ink in either system appearance.
        appearance = NSAppearance(named: .aqua)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(symbol)
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }

    override func draw(_ dirtyRect: NSRect) {
        let face = NSBezierPath(roundedRect: bounds.insetBy(dx: 3, dy: 3), xRadius: 6, yRadius: 6)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowBlurRadius = 3
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.set()
        NSColor(calibratedWhite: 0.06, alpha: 1).setFill()
        face.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSGradient(starting: NSColor(calibratedWhite: 0.08, alpha: 1),
            ending: NSColor(calibratedWhite: 0.16, alpha: 1))?.draw(in: face, angle: 90)
        NSColor(calibratedWhite: 0.28, alpha: 1).setStroke()
        face.lineWidth = 0.7
        face.stroke()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 29, weight: .regular), .foregroundColor: NSColor.white]
        let text = symbol as NSString
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2 + 1), withAttributes: attributes)
    }
}

final class SetupWindow: NSWindowController {
    private static let initialContentSize = NSSize(width: 560, height: 640)
    private var layoutSize = SetupWindow.initialContentSize
    var permissionAction: (() -> Void)?
    var testAction: (() -> Void)?
    var finishAction: (() -> Void)?
    private let permissionStatus = NSTextField(labelWithString: "")
    private let sourceStatus = NSTextField(wrappingLabelWithString: "")
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let permissionButton = NSButton(title: "Открыть разрешение macOS", target: nil, action: nil)
    private let finishButton = NSButton(title: "Готово", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Запускать при входе в Mac", target: nil, action: nil)
    private var positioned = false
    private var lastState: ViewState?

    private struct ViewState: Equatable {
        let trusted: Bool
        let active: Bool
        let secure: Bool
        let enabled: Bool
        let russian: Bool
        let loginEnabled: Bool
        let loginApproval: Bool
        let error: String?
    }

    init() {
        let window = UtilityPanel(contentRect: NSRect(origin: .zero, size: Self.initialContentSize))
        window.title = "Точка"
        super.init(window: window)
        let content = NSView(frame: NSRect(origin: .zero, size: Self.initialContentSize))
        window.contentView = content

        func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular,
                   secondary: Bool = false, wrapping: Bool = true) -> NSTextField {
            let field = wrapping ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = secondary ? .secondaryLabelColor : .labelColor
            field.alignment = .center
            return field
        }
        func stack(_ views: [NSView], vertical: Bool, spacing: CGFloat) -> NSStackView {
            let result = NSStackView(views: views)
            result.orientation = vertical ? .vertical : .horizontal
            result.alignment = vertical ? .centerX : .centerY
            result.distribution = .fill
            result.spacing = spacing
            result.edgeInsets = NSEdgeInsetsZero
            result.translatesAutoresizingMaskIntoConstraints = false
            return result
        }
        func size(_ view: NSView, width: CGFloat? = nil, height: CGFloat? = nil) {
            view.translatesAutoresizingMaskIntoConstraints = false
            if let width { view.widthAnchor.constraint(equalToConstant: width).isActive = true }
            if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
        }
        func button(_ view: NSButton, inline: Bool = false) {
            view.bezelStyle = inline ? .inline : .rounded
            view.controlSize = inline ? .regular : .large
            view.font = .systemFont(ofSize: 13, weight: inline ? .regular : .medium)
            // Use native visible heights; no negative frame offsets or bezel compensation.
            size(view, height: inline ? 20 : 28)
        }

        let column = stack([], vertical: true, spacing: 0)
        content.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            column.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            column.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
        func add(_ view: NSView, height: CGFloat? = nil, fullWidth: Bool = true, after: CGFloat) {
            column.addArrangedSubview(view)
            size(view, height: height)
            if fullWidth { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
            column.setCustomSpacing(after, after: view)
        }

        let icon = NSImageView()
        icon.image = NSImage(named: "AppIcon")
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityLabel("Точка")
        size(icon, width: 64, height: 64)
        let title = label("Точка. На своём месте.", size: 27, weight: .bold, wrapping: false)
        let subtitle = label("Привычные знаки в русской раскладке Mac.", size: 15,
            secondary: true, wrapping: false)
        let heading = stack([title, subtitle], vertical: true, spacing: 4)
        let header = stack([icon, heading], vertical: false, spacing: 20)
        add(header, height: 64, fullWidth: false, after: 24)
        header.widthAnchor.constraint(lessThanOrEqualTo: column.widthAnchor).isActive = true

        let card = NSBox()
        card.boxType = .custom
        card.borderWidth = 0
        card.cornerRadius = 14
        card.contentViewMargins = .zero
        card.fillColor = .quaternaryLabelColor
        let keys = stack([], vertical: false, spacing: 0)
        keys.distribution = .fillEqually
        for (caption, symbol) in [("Справа от Ю", "."), ("Она же с Shift", ","),
                                  ("Shift + 7", "?"), ("Shift + 6", "/")] {
            let text = label(caption, size: 13, secondary: true, wrapping: false)
            size(text, height: 18)
            let key = KeycapView(symbol: symbol, frame: .zero)
            size(key, width: 58, height: 58)
            keys.addArrangedSubview(stack([text, key], vertical: true, spacing: 8))
        }
        let keyContent = card.contentView!
        keyContent.addSubview(keys)
        NSLayoutConstraint.activate([
            keys.leadingAnchor.constraint(equalTo: keyContent.leadingAnchor),
            keys.trailingAnchor.constraint(equalTo: keyContent.trailingAnchor),
            keys.centerYAnchor.constraint(equalTo: keyContent.centerYAnchor)
        ])
        add(card, height: 104, after: 8)
        add(label("Четыре сочетания в «Русской». Другие раскладки работают без изменений.",
            size: 12, secondary: true), height: 16, after: 24)

        add(label("Один раз разреши управление клавиатурой", size: 19, weight: .semibold),
            height: 24, after: 8)
        let permissionInstructions = label("Нажми кнопку ниже и включи переключатель рядом с «Точка».\nmacOS может попросить пароль или Touch ID. Затем вернись сюда.",
            size: 14, weight: .bold)
        permissionInstructions.textColor = NSColor(srgbRed: 1, green: 133.0 / 255, blue: 73.0 / 255, alpha: 1)
        add(permissionInstructions, height: 36, after: 16)
        button(permissionButton)
        size(permissionButton, width: 264)
        permissionButton.target = self
        permissionButton.action = #selector(permission)
        permissionStatus.font = .systemFont(ofSize: 13, weight: .medium)
        permissionStatus.alignment = .center
        size(permissionStatus, width: 180)
        let permissionRow = stack([permissionButton, permissionStatus], vertical: false, spacing: 16)
        add(permissionRow, height: 28, fullWidth: false, after: 8)
        let reveal = NSButton(title: "Нет в списке? Показать приложение", target: self, action: #selector(revealApp))
        button(reveal, inline: true)
        size(reveal, width: 304)
        add(reveal, fullWidth: false, after: 24)

        loginCheckbox.font = .systemFont(ofSize: 13)
        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin)
        let loginSettings = NSButton(title: "Настройки входа…", target: self, action: #selector(openLoginSettings))
        button(loginSettings, inline: true)
        size(loginSettings, width: 148)
        let loginRow = stack([loginCheckbox, NSView(), loginSettings], vertical: false, spacing: 16)
        loginCheckbox.setContentHuggingPriority(.required, for: .horizontal)
        add(loginRow, height: 28, after: 8)
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        loginStatus.alignment = .center
        add(loginStatus, height: 30, after: 16)
        sourceStatus.font = .systemFont(ofSize: 13)
        sourceStatus.textColor = .secondaryLabelColor
        sourceStatus.alignment = .center
        add(sourceStatus, height: 34, after: 8)
        add(label("Работает на твоём Mac. Не сохраняет набранный текст и не использует интернет.",
            size: 12, secondary: true), height: 16, after: 16)

        let test = NSButton(title: "Попробовать ввод", target: self, action: #selector(testInput))
        button(test)
        button(finishButton)
        finishButton.keyEquivalent = "\r"
        finishButton.target = self
        finishButton.action = #selector(finish)
        let footer = stack([test, finishButton], vertical: false, spacing: 16)
        footer.distribution = .fillEqually
        add(footer, height: 28, after: 0)

        content.layoutSubtreeIfNeeded()
        layoutSize = NSSize(width: Self.initialContentSize.width, height: ceil(column.fittingSize.height) + 48)
        window.setContentSize(layoutSize)
        content.layoutSubtreeIfNeeded()
    }

    required init?(coder: NSCoder) { fatalError("Not implemented") }
    @objc private func permission() { permissionAction?() }
    @objc private func testInput() { testAction?() }
    @objc private func revealApp() { NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL]) }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    @objc private func toggleLogin() {
        Startup.setEnabled(loginCheckbox.state == .on)
        lastState = nil
    }
    @objc private func finish() { finishAction?(); close() }

    func update(trusted: Bool, active: Bool, secure: Bool, enabled: Bool, sourceID: String) {
        let state = ViewState(trusted: trusted, active: active, secure: secure, enabled: enabled,
            russian: sourceID == Punctuation.russianID, loginEnabled: Startup.isEnabled,
            loginApproval: Startup.needsApproval, error: Startup.errorMessage)
        guard state != lastState else { return }
        lastState = state
        permissionStatus.stringValue = trusted && active ? "✓ Разрешение получено" : trusted ? "Подключаем клавиатуру…" : "Ожидаем разрешение"
        permissionStatus.textColor = trusted && active ? .systemGreen : .secondaryLabelColor
        permissionButton.title = trusted ? "Открыть настройки разрешения" : "Открыть разрешение macOS"
        finishButton.isEnabled = trusted && active
        loginCheckbox.state = state.loginEnabled ? .on : state.loginApproval ? .mixed : .off
        loginStatus.stringValue = state.error ?? (state.loginApproval ? "Подтверди автозапуск «Точки» в настройках входа."
            : state.loginEnabled ? "Будет готова к работе после перезагрузки и входа в учётную запись." : "Автозапуск выключен. «Точку» можно открывать из «Программ».")
        sourceStatus.stringValue = !enabled ? "Точка выключена. Нажми значок в строке меню, чтобы включить переназначения."
            : !trusted || !active ? "Точка включена. Для работы нужно разрешение и подключение клавиатуры."
            : secure ? "Сейчас включён защищённый ввод. Выйди из поля пароля, чтобы проверить знаки."
            : sourceID == Punctuation.russianID ? "Русская раскладка выбрана. Нажми «Попробовать ввод» для проверки."
            : "Для проверки выбери стандартную раскладку «Русская». Другие раскладки работают без изменений."
    }

    func present() {
        guard let window else { return }
        if !positioned {
            let restored = window.setFrameUsingName("TochkaSetupWindow")
            let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
            // Restore position, but never restore the obsolete wider content size.
            window.setContentSize(layoutSize)
            if restored { window.setFrameTopLeftPoint(topLeft) } else { window.center() }
            window.setFrameAutosaveName("TochkaSetupWindow")
            positioned = true
        }
        if window.isMiniaturized { window.deminiaturize(nil) }
        showWindow(nil)
    }
}
