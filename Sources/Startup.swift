import AppKit
import ServiceManagement
import Carbon

enum Startup {
    static var isLoginLaunchEvent: Bool {
        isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
    }

    static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event else { return false }
        let keyword = AEKeyword(keyAELaunchedAsLogInItem)
        return event.paramDescriptor(forKeyword: keyword)?.booleanValue == true
            || event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?
                .forKeyword(keyword)?.booleanValue == true
    }

    static var installed: Bool {
        let parent = Bundle.main.bundleURL.deletingLastPathComponent().standardizedFileURL.path
        return parent == "/Applications" || parent == FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
    }

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }
    static var errorMessage: String?

    static func enableOnce() {
        guard installed, !UserDefaults.standard.bool(forKey: "loginItemAttempted") else { return }
        UserDefaults.standard.set(true, forKey: "loginItemAttempted")
        setEnabled(true)
    }

    static func setEnabled(_ enabled: Bool) {
        guard installed else { return }
        do {
            if enabled {
                if needsApproval { SMAppService.openSystemSettingsLoginItems() }
                else if !isEnabled { try SMAppService.mainApp.register() }
            } else { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch { errorMessage = "Не удалось изменить автозапуск. Открой настройки входа и проверь «Точку»." }
    }
}
