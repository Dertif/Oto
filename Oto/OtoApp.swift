import SwiftUI

@main
struct OtoApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(state: state)
                .onAppear {
                    state.refreshPermissionStatus()
                }
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        let activeName = "MenuBarIconActive"
        let idleName = "MenuBarIcon"
        let chosenName = state.isRecording ? activeName : idleName

        if NSImage(named: chosenName) != nil {
            Image(chosenName)
        } else if NSImage(named: idleName) != nil {
            Image(idleName)
        } else {
            Image(systemName: state.isRecording ? "mic.fill" : "mic")
        }
    }
}
