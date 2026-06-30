import SwiftUI

@main
struct LocalSTTApplication: App {
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup { ContentView().environmentObject(model).frame(minWidth: 900, minHeight: 620) }
        Settings { SettingsView().environmentObject(model).frame(width: 650, height: 480) }
    }
}
