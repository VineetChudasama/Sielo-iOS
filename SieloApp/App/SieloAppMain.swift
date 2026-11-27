import SwiftUI
import FirebaseCore

@main
struct SieloAppMain: App {
    @StateObject private var container = SieloContainer()

    init() {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
        }

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 13/255, green: 27/255, blue: 42/255, alpha: 1)
        appearance.titleTextAttributes = [.foregroundColor: UIColor(red: 244/255, green: 241/255, blue: 222/255, alpha: 1)]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = UIColor(red: 212/255, green: 196/255, blue: 168/255, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            SieloRootView()
                .environmentObject(container)
                .preferredColorScheme(.dark)
        }
    }
}
