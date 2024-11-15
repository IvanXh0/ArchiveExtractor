//
//  ContentView.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var archiveManager: ArchiveManager
    @StateObject private var viewModel = ContentViewModel()

    var body: some View {
        ZStack {
            DropZoneView(isDragActive: $viewModel.dragOver) {
                MainContent(
                    isExtracting: viewModel.isExtracting,
                    progress: archiveManager.progress
                )
            }
        }
        .frame(width: 400, height: 300)
        .padding()
        .onDrop(of: [.fileURL], isTargeted: $viewModel.dragOver) { providers in
            viewModel.handleDrop(providers, using: archiveManager)
        }
        .alert("Error", isPresented: $viewModel.showError, presenting: viewModel.lastError) { _ in
            Button("OK") {}
        } message: { error in
            Text(error)
        }
        .alert("Success", isPresented: $viewModel.showSuccess) {
            Button("OK") {}
        } message: {
            Text("Archive extracted successfully")
        }
    }
}
