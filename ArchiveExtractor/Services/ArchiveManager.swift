//
//  ArchiveManager.swift
//  ArchiveExtractor
//
//  Created by Ivan Apostolovski on 14.11.24.
//

import Combine
import Foundation
import System
import UniformTypeIdentifiers
import ZIPFoundation

// MARK: - Error Types

enum ArchiveError: LocalizedError {
    case toolNotFound(String)
    case extractionFailed(String)
    case unsupportedFormat(String)
    case invalidDestination(String)
    case accessDenied(String)
    case insufficientSpace(String)
    case fileNotFound(String)
    case archiveCorrupted(String)
    
    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "Required extraction tool not found: \(tool)"
        case .extractionFailed(let message):
            return "Archive extraction failed: \(message)"
        case .unsupportedFormat(let format):
            return "Unsupported archive format: \(format)"
        case .invalidDestination(let path):
            return "Invalid destination path: \(path)"
        case .accessDenied(let path):
            return "Access denied to path: \(path)"
        case .insufficientSpace(let path):
            return "Insufficient disk space at: \(path)"
        case .fileNotFound(let path):
            return "Archive file not found at: \(path)"
        case .archiveCorrupted(let message):
            return "Archive appears to be corrupted: \(message)"
        }
    }
}

// MARK: - Archive Entry Model

struct ArchiveEntry: Identifiable, Hashable {
    let id = UUID()
    let path: String
    let size: UInt64
    let isDirectory: Bool
    let modificationDate: Date?
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Tool Bookmark Manager

class ToolBookmarkManager {
    static let shared = ToolBookmarkManager()
    private let defaults = UserDefaults.standard
    
    func saveToolBookmark(url: URL, for tool: String) throws {
        let bookmarkData = try url.bookmarkData(
            options: .minimalBookmark,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: "tool.bookmark.\(tool)")
    }
    
    func getToolURL(for tool: String) throws -> URL? {
        guard let bookmarkData = defaults.data(forKey: "tool.bookmark.\(tool)") else {
            return nil
        }
        
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        
        if isStale {
            try saveToolBookmark(url: url, for: tool)
        }
        
        return url
    }
}

// MARK: - Archive Manager

@available(macOS 11.0, *)
class ArchiveManager: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isExtracting = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentOperation: String = ""
    @Published private(set) var entries: [ArchiveEntry] = []
    
    // MARK: - Private Properties

    private let fileManager = FileManager.default
    private var cancellables = Set<AnyCancellable>()
    private let bookmarkManager = ToolBookmarkManager.shared
    
    private let supportedTypes: [UTType] = [
        .zip,
        .gzip,
        .bz2,
        .archive,
        .sevenZip,
        .rar
    ]
    
    private var toolPaths: [String: URL] = [:]
    
    // MARK: - Initialization

    init() {
        setupTools()
        fixToolPermissions()
    }
    
    private func setupTools() {
        let tools = [
            "7z": "/opt/homebrew/bin/7z",
            "unar": "/opt/homebrew/bin/unar",
            "unrar": "/opt/homebrew/bin/unrar"
        ]
           
        #if DEBUG
        print("\nSetting up tools...")
        #endif
           
        for (tool, path) in tools {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    toolPaths[tool] = url
                    #if DEBUG
                    print("\(tool) found and executable at: \(url.path)")
                    #endif
                } else {
                    #if DEBUG
                    print("\(tool) found but not executable at: \(url.path)")
                    #endif
                }
            } else {
                #if DEBUG
                print("\(tool) not found at: \(url.path)")
                #endif
            }
        }
           
        if toolPaths.isEmpty {
            #if DEBUG
            print("\nNo tools found. Please install required tools:")
            print("brew install p7zip")
            print("brew install unar")
            print("brew install unrar")
            #endif
        } else {
            #if DEBUG
            print("\nFound tools: \(toolPaths.keys.joined(separator: ", "))")
            #endif
        }
    }

    // MARK: - Public Methods

    func isSupportedFile(_ url: URL) -> Bool {
        guard let type = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
            return false
        }
        return supportedTypes.contains { type.conforms(to: $0) }
    }
    
    func listContents(of fileURL: URL) async throws -> [ArchiveEntry] {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ArchiveError.fileNotFound(fileURL.path)
        }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        
        if fileExtension == "zip" {
            return try listZipContents(fileURL)
        } else {
            return try await list7zContents(fileURL)
        }
    }
    
    func extract(_ fileURL: URL, to destinationURL: URL, password: String? = nil) async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ArchiveError.fileNotFound(fileURL.path)
        }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        
        #if DEBUG
        print("Extracting file: \(fileURL.path)")
        print("File extension: \(fileExtension)")
        print("Available tools: \(toolPaths)")
        #endif
        
        // Verify destination permissions
        guard canWriteToDestination(destinationURL) else {
            throw ArchiveError.accessDenied(destinationURL.path)
        }
        
        // Check available space
        guard try hassufficientSpace(for: fileURL, at: destinationURL) else {
            throw ArchiveError.insufficientSpace(destinationURL.path)
        }
        
        await MainActor.run {
            isExtracting = true
            progress = 0
            currentOperation = "Preparing to extract..."
        }
        
        defer {
            Task { @MainActor in
                isExtracting = false
                progress = 1.0
                currentOperation = ""
            }
        }
        
        // Create destination directory
        try fileManager.createDirectory(
            at: destinationURL,
            withIntermediateDirectories: true
        )
        
        do {
            switch fileExtension {
            case "zip":
                try await extractZip(fileURL: fileURL, to: destinationURL, password: password)
            case "rar":
                try await extract7z(fileURL: fileURL, to: destinationURL, password: password)
            case "7z":
                try await extract7z(fileURL: fileURL, to: destinationURL, password: password)
            default:
                try await extractWithUnar(fileURL: fileURL, to: destinationURL, password: password)
            }
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }
    
    // MARK: - Private Methods

    private func verifyTools() {
        for (tool, path) in toolPaths {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: path.path, isDirectory: &isDirectory)
            
            #if DEBUG
            print("\nVerifying \(tool):")
            print("Path: \(path.path)")
            print("Exists: \(exists)")
            #endif
        }
    }
    
    private func canWriteToDestination(_ url: URL) -> Bool {
        fileManager.isWritableFile(atPath: url.path)
    }
    
    private func hassufficientSpace(for archiveURL: URL, at destinationURL: URL) throws -> Bool {
        let archiveSize = try archiveURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let freespace = try destinationURL.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity ?? 0
        return Int64(archiveSize) * 3 < freespace
    }
    
    private func listZipContents(_ url: URL) throws -> [ArchiveEntry] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw ArchiveError.archiveCorrupted("Unable to read ZIP archive")
        }
        
        return archive.map { entry in
            ArchiveEntry(
                path: entry.path,
                size: UInt64(entry.uncompressedSize),
                isDirectory: entry.type == .directory,
                modificationDate: Date()
            )
        }
    }
    
    private func list7zContents(_ url: URL) async throws -> [ArchiveEntry] {
        guard let sevenZip = toolPaths["7z"] else {
            throw ArchiveError.toolNotFound("7z")
        }
        
        let output = try await runExternalTool(
            sevenZip,
            arguments: ["l", url.path],
            captureOutput: true
        )
        
        return parse7zOutput(output)
    }
    
    private func extractZip(fileURL: URL, to destinationURL: URL, password: String? = nil) async throws {
        await MainActor.run { currentOperation = "Extracting ZIP archive..." }
        
        let progress = Progress(totalUnitCount: 1)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        
        let observation = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Task { @MainActor in
                self?.progress = progress.fractionCompleted
            }
        }
        
        defer { observation.invalidate() }
        
        do {
            try fileManager.unzipItem(at: fileURL, to: destinationURL)
        } catch {
            try await extract7z(fileURL: fileURL, to: destinationURL, password: password)
        }
    }
    
    private func extract7z(fileURL: URL, to destinationURL: URL, password: String? = nil) async throws {
        let fileExtension = fileURL.pathExtension.lowercased()
        let isRAR = fileExtension == "rar"
        
        if isRAR {
            // For RAR files, try unar first
            if let unar = toolPaths["unar"] {
                await MainActor.run { currentOperation = "Extracting RAR with unar..." }
                
                #if DEBUG
                print("\nAttempting RAR extraction with unar")
                #endif
                
                var arguments = [
                    "-force-overwrite",
                    "-no-directory",
                    "-o",
                    destinationURL.path,
                    fileURL.path
                ]
                
                if let password = password {
                    arguments.insert(password, at: 0)
                    arguments.insert("-password", at: 0)
                }
                
                #if DEBUG
                print("Unar command:")
                print("Path: \(unar.path)")
                print("Arguments: \(arguments)")
                #endif
                
                do {
                    let _ = try await runExternalTool(unar, arguments: arguments)
                    
                    if let contents = try? FileManager.default.contentsOfDirectory(atPath: destinationURL.path) {
                        #if DEBUG
                        print("\nExtracted contents:")
                        contents.forEach { print(" - \($0)") }
                        #endif
                        return
                    }
                } catch {
                    #if DEBUG
                    print("Unar failed: \(error)")
                    #endif
                }
            }
            
            guard let sevenZip = toolPaths["7z"] else {
                throw ArchiveError.toolNotFound("No tools available for RAR extraction")
            }
            
            await MainActor.run { currentOperation = "Extracting RAR with 7-Zip..." }
            
            var arguments = [
                "e",
                fileURL.path,
                "-o" + destinationURL.path,
                "-y",
                "-aoa"
            ]
            
            if let password = password {
                arguments.append("-p" + password)
            }
            
            let _ = try await runExternalTool(sevenZip, arguments: arguments)
        } else {
            guard let sevenZip = toolPaths["7z"] else {
                throw ArchiveError.toolNotFound("7z not found")
            }
            
            await MainActor.run { currentOperation = "Extracting archive..." }
            
            var arguments = [
                "x",
                fileURL.path,
                "-o" + destinationURL.path,
                "-y"
            ]
            
            if let password = password {
                arguments.append("-p" + password)
            }
            
            let _ = try await runExternalTool(sevenZip, arguments: arguments)
        }
    }

    private func extractWithUnrar(unrarPath: URL, fileURL: URL, to destinationURL: URL, password: String? = nil) async throws {
        await MainActor.run { currentOperation = "Extracting with unrar..." }
        
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        
        var arguments = [
            "x",
            fileURL.path,
            destinationURL.path + "/",
            "-o+",
            "-y"
        ]
        
        if let password = password {
            arguments.insert("-p" + password, at: 1)
        }
        
        #if DEBUG
        print("Unrar arguments: \(arguments)")
        #endif
        
        let _ = try await runExternalTool(unrarPath, arguments: arguments)
    }

    func fixToolPermissions() {
        let tools = [
            "7z": "/opt/homebrew/bin/7z",
            "unar": "/opt/homebrew/bin/unar",
            "unrar": "/opt/homebrew/bin/unrar"
        ]
        
        for (tool, path) in tools {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/chmod")
            process.arguments = ["+x", path]
            
            do {
                try process.run()
                process.waitUntilExit()
                #if DEBUG
                print("Fixed permissions for \(tool)")
                #endif
            } catch {
                #if DEBUG
                print("Failed to fix permissions for \(tool): \(error)")
                #endif
            }
        }
    }

    private func findUnrar() throws -> URL? {
        let searchPaths = [
            "/opt/homebrew/bin/unrar",
            "/usr/local/bin/unrar",
            "/usr/bin/unrar"
        ]
        
        for path in searchPaths {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        
        return nil
    }

    private func extractWithUnar(fileURL: URL, to destinationURL: URL, password: String? = nil) async throws {
        guard let unar = toolPaths["unar"] else {
            throw ArchiveError.toolNotFound("unar")
        }
        
        await MainActor.run { currentOperation = "Extracting with unar..." }
        
        var arguments = ["-o", destinationURL.path, fileURL.path]
        if let password = password {
            arguments.insert("-password", at: 0)
            arguments.insert(password, at: 1)
        }
        
        let _ = try await runExternalTool(unar, arguments: arguments)
    }
    
    private func runExternalTool(_ toolURL: URL, arguments: [String], captureOutput: Bool = false) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = toolURL
            process.arguments = arguments
               
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe
               
            do {
                #if DEBUG
                print("\nRunning tool:")
                print("Path: \(toolURL.path)")
                print("Arguments: \(arguments)")
                #endif
                   
                try process.run()
                process.waitUntilExit()
                   
                if process.terminationStatus == 0 {
                    if captureOutput {
                        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(returning: nil)
                    }
                } else {
                    let error = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Unknown error"
                    #if DEBUG
                    print("Tool execution failed with error: \(error)")
                    #endif
                    continuation.resume(throwing: ArchiveError.extractionFailed(error))
                }
            } catch {
                #if DEBUG
                print("Failed to run process: \(error)")
                #endif
                continuation.resume(throwing: error)
            }
        }
    }

    private func parse7zOutput(_ output: String?) -> [ArchiveEntry] {
        guard let output = output else { return [] }
        
        var entries: [ArchiveEntry] = []
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.contains("|") {
                let components = line.components(separatedBy: "|")
                if components.count >= 3 {
                    entries.append(ArchiveEntry(
                        path: components[0].trimmingCharacters(in: .whitespaces),
                        size: UInt64(components[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                        isDirectory: components[0].hasSuffix("/"),
                        modificationDate: nil
                    ))
                }
            }
        }
        
        return entries
    }
}

// MARK: - UTType Extensions

@available(macOS 11.0, *)
extension UTType {
    static let sevenZip = UTType("org.7-zip.7-zip-archive")!
    static let rar = UTType("com.rarlab.rar-archive")!
}
