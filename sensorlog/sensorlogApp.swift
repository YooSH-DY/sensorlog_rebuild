//
//  sensorlogApp.swift
//  sensorlog
//
//  Created by Velab on 12/26/24.
//

import SwiftUI

@main
struct sensorlogApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}

