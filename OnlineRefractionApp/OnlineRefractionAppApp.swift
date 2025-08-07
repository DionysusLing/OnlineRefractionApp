import SwiftUI

@main
struct OnlineRefractionAppApp: App {
    @StateObject private var services = AppServices()
    var body: some Scene {
        WindowGroup {
            AppRouter()
                .environmentObject(services)
        }
    }
}
