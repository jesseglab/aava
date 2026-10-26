import SwiftUI

@main struct AavaApp: App {
    @StateObject private var store = BrowserStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            BrowserView().environmentObject(store)
                .onOpenURL { store.openExternal($0) }
                .onChange(of: phase) { _, next in if next != .active { store.saveNow() } }
        }
    }
}
