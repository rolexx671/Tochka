import AppKit
import Carbon

@main
struct LaunchBehaviorTests {
    static func main() {
        // Brand-new install: guide the user to the permission exactly when needed.
        precondition(LaunchBehavior.shouldShowSetup(hasPermission: false, setupCompleted: false, loginLaunch: false))
        // A granted permission is sufficient; clicking Done must not be required.
        precondition(!LaunchBehavior.shouldShowSetup(hasPermission: true, setupCompleted: false, loginLaunch: false))
        // Login can precede TCC readiness. Neither state may pop a window at login.
        for permission in [false, true] {
            for completed in [false, true] {
                precondition(!LaunchBehavior.shouldShowSetup(hasPermission: permission, setupCompleted: completed, loginLaunch: true))
            }
        }
        // A configured app remains quiet when permission is temporarily unavailable/revoked;
        // its menu supplies the repair flow instead of taking focus on every restart.
        precondition(!LaunchBehavior.shouldShowSetup(hasPermission: false, setupCompleted: true, loginLaunch: false))
        precondition(!LaunchBehavior.shouldShowSetup(hasPermission: true, setupCompleted: true, loginLaunch: false))
        precondition(!Startup.isLoginLaunch(nil))
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        precondition(!Startup.isLoginLaunch(event))
        event.setParam(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(keyAELaunchedAsLogInItem))
        precondition(Startup.isLoginLaunch(event))
        event.removeParamDescriptor(withKeyword: AEKeyword(keyAELaunchedAsLogInItem))
        let properties = NSAppleEventDescriptor.record()
        properties.setDescriptor(NSAppleEventDescriptor(boolean: true), forKeyword: AEKeyword(keyAELaunchedAsLogInItem))
        event.setParam(properties, forKeyword: AEKeyword(keyAEPropData))
        precondition(Startup.isLoginLaunch(event))
        print("PASS: first-run, already-granted permission, all login states, permission unavailable after setup")
    }
}
