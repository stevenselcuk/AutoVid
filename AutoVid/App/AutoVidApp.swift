//
//  AutoVidApp.swift
//  AutoVid
//
//  Created by Steven J. Selcuk on 25.01.2026.
//
//

import SwiftUI

@main
struct AutoVidApp: App {
    @StateObject private var coordinator = AppCoordinator()
    
    var body: some Scene {
        WindowGroup {
            coordinator.start()
                .onOpenURL { url in
                    coordinator.handle(url: url)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultSize(width: AppConfig.UI.Dimensions.defaultWindowWidth, height: AppConfig.UI.Dimensions.defaultWindowHeight)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
