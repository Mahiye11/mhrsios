import SwiftUI

@main
struct MHRSApp: App {
    // Core Data kullanmıyorsan bu satırları kaldır
    // let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
            // .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
