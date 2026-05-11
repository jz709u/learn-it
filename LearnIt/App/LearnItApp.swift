import SwiftUI
import UIKit

@main
struct LearnItApp: App {
    @StateObject private var deckStore = FlashcardDeckStore()
    @StateObject private var creditStore = ImportCreditStore()

    init() {
        configureNavigationBarAppearance()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView(deckStore: deckStore)
                .environmentObject(creditStore)
                .preferredColorScheme(.light)
        }
    }

    private func configureNavigationBarAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .orange
        appearance.titleTextAttributes = [.foregroundColor: UIColor.black]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.black]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = .black
    }
}
