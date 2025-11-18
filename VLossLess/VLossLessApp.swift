//
//  VLossLessApp.swift
//  VLossLess
//
//  Created by IT SF GOC HYD on 18/11/25.
//

import SwiftUI

@main
struct VLossLessApp: App {
    var body: some Scene {
        WindowGroup {
            MainVideoView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            // Remove unused menu items for cleaner interface
            CommandGroup(replacing: .newItem) {}
        }
    }
}
