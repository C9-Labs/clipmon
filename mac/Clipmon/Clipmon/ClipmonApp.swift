//
//  ClipmonApp.swift
//  Clipmon
//
//  Created by Ved on 02/05/26.
//

import SwiftUI
import SwiftData

@main
struct ClipmonApp: App {
    @StateObject private var controller = ClipboardHistoryController()

    private var sharedModelContainer: ModelContainer = {
        let fileManager = FileManager.default
        let schema = Schema([ClipboardEntry.self])
        let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Clipmon", isDirectory: true)
        let modelConfiguration = ModelConfiguration(
            "Clipmon",
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .automatic,
            cloudKitDatabase: .automatic
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            try? fileManager.removeItem(at: supportDirectory)
            try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true, attributes: nil)

            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer: \(error)")
            }
        }
    }()

    var body: some Scene {
        Window("Clipmon", id: "main") {
            ContentView()
                .environmentObject(controller)
        }
        .windowResizability(.contentMinSize)
        .modelContainer(sharedModelContainer)

        MenuBarExtra("Clipmon", systemImage: "doc.on.clipboard") {
            MenuBarView()
                .environmentObject(controller)
        }
        .menuBarExtraStyle(.window)
        .modelContainer(sharedModelContainer)
    }
}
