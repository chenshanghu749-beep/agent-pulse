import Foundation

enum RouteUpgradeCoordinator {
    @discardableResult
    static func reconcileIfNeeded<AuthSnapshot>(
        needsReconciliation: () -> Bool,
        currentRoute: () -> RouteChoice,
        snapshotAuth: () throws -> AuthSnapshot,
        prepareAuth: (RouteChoice) throws -> Void,
        restoreAuth: (AuthSnapshot) throws -> Void,
        applyConfig: (RouteChoice) throws -> Void
    ) throws -> Bool {
        guard needsReconciliation() else { return false }
        let route = currentRoute()
        let authSnapshot = try snapshotAuth()
        do {
            try prepareAuth(route)
            try applyConfig(route)
        } catch {
            try? restoreAuth(authSnapshot)
            throw error
        }
        return true
    }
}
