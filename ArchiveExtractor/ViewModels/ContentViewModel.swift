//
//  ContentViewModel.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import SwiftUI
import UniformTypeIdentifiers

class ContentViewModel: ObservableObject {
    @Published var dragOver = false
    @Published var isExtracting = false
    @Published var showError = false
    @Published var showSuccess = false
    @Published var lastError: String?
    
    func handleDrop(_ providers: [NSItemProvider], using manager: ArchiveManager) -> Bool {
        guard let provider = providers.first else { return false }
        
        let _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
            guard let self = self, let url = url else {
                self?.handleError("Invalid file")
                return
            }
            
            Task { @MainActor in
                await self.handleDroppedFile(url, using: manager)
            }
        }
        return true
    }
    
    @MainActor
    private func handleDroppedFile(_ fileURL: URL, using manager: ArchiveManager) async {
        guard manager.isSupportedFile(fileURL) else {
            handleError("Unsupported file type")
            return
        }
        
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = "Choose extraction destination"
        
        let response = await Task {
            await panel.begin()
        }.value
        
        guard response == .OK,
              let destinationURL = panel.url else { return }
        
        isExtracting = true
        
        do {
            try await manager.extract(fileURL, to: destinationURL)
            isExtracting = false
            showSuccess = true
        } catch {
            isExtracting = false
            handleError(error.localizedDescription)
        }
    }

    private func handleError(_ message: String) {
        lastError = message
        showError = true
    }
}
