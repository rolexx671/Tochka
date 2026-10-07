/// First-run assistance is distinct from a normal background start.
enum LaunchBehavior {
    static func shouldShowSetup(hasPermission: Bool, setupCompleted: Bool, loginLaunch: Bool) -> Bool {
        !loginLaunch && !hasPermission && !setupCompleted
    }
}
