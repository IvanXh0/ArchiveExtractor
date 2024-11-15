//
//  ArchiveExtractorApp.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import SwiftUI

@main
struct ArchiveExtractorApp: App {
    @StateObject private var archiveManager = ArchiveManager()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(archiveManager)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
