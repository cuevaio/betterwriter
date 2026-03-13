import SwiftUI
import SwiftData

@main
struct BetterWriterApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            DayEntry.self,
        ])

        // Ensure Application Support directory exists before SwiftData tries to
        // create its SQLite store file, avoiding verbose CoreData error logs on
        // first launch.
        let fm = FileManager.default
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        // Attempt normal persistent store first.
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false
        )
        if let container = try? ModelContainer(for: schema, configurations: [modelConfiguration]) {
            return container
        }

        // Store is incompatible (schema changed). Delete it and start fresh.
        // User data will be lost, but this only happens after a breaking model change.
        print("BetterWriterApp: SwiftData store incompatible, deleting and recreating.")
        if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let files = (try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "store"
                || file.lastPathComponent.hasSuffix(".store-shm")
                || file.lastPathComponent.hasSuffix(".store-wal") {
                try? fm.removeItem(at: file)
            }
        }

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(sharedModelContainer)
    }
}
