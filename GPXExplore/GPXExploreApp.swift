//
//  GPXExploreApp.swift
//  GPXExplore
//
//  Created by Gavi Narra on 4/29/25.
//

import SwiftUI
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

@main
struct GPXExploreApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var sharedDocument: GPXExploreDocument?
    @State private var isSharedDocumentPresented = false
    #endif
    
    var body: some Scene {
        #if os(iOS)
        DocumentGroup(viewing: GPXExploreDocument.self) { file in
            NavigationStack {
                
                ContentView(document: file.$document)
                    .onAppear {
                        setupNotificationObserver()
                    }
            }
        }
        if #available(iOS 18, *) {
            DocumentGroupLaunchScene {
                
            }
            background: {
                Image(.gmBg)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
            }overlayAccessoryView: { _ in
                AccessoryView()
            }
        }
        
        #else
        DocumentGroup(viewing: GPXExploreDocument.self) { file in
            ContentView(document: file.$document)
        }
        .commands {
            CommandGroup(after: .importExport) {
                Button("Open from Files App") {
                    openDocument()
                }
                .keyboardShortcut("O", modifiers: [.command, .shift])
            }
        }
        #endif
    }
    
    #if os(iOS)
    private func setupNotificationObserver() {
        // Listen for notifications about files being shared to our app
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenGPXFile"),
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                // Try to load the document
                do {
                    // Try to access the security-scoped resource
                    var accessGranted = false
                    
                    // Check if this is a security-scoped URL
                    if url.startAccessingSecurityScopedResource() {
                        accessGranted = true
                        print("Successfully accessed security-scoped resource")
                    }
                    
                    // Ensure we release access when done
                    defer {
                        if accessGranted {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    // Try to read the data, with proper error handling
                    let data: Data
                    
                    do {
                        data = try Data(contentsOf: url)
                    } catch {
                        print("Error reading file data: \(error)")
                        
                        // Try with file coordination as a fallback
                        let coordinator = NSFileCoordinator()
                        var coordError: NSError?
                        var fileData: Data?
                        
                        coordinator.coordinate(readingItemAt: url, options: [], error: &coordError) { coordURL in
                            do {
                                fileData = try Data(contentsOf: coordURL)
                            } catch let coordReadError {
                                print("Coordinated read also failed: \(coordReadError)")
                            }
                        }
                        
                        if let coordError = coordError {
                            print("Coordination error: \(coordError)")
                        }
                        
                        guard let validData = fileData else {
                            throw NSError(domain: "GPXExplore", code: 2, userInfo: [
                                NSLocalizedDescriptionKey: "Failed to read file data even with coordination"
                            ])
                        }
                        
                        data = validData
                    }
                    
                    // Try to parse the data
                    if let content = String(data: data, encoding: .utf8) {
                        var document = GPXExploreDocument(text: content)
                        document.gpxFile = GPXParser.parseGPXData(data, filename: url.lastPathComponent)
                        
                        // Check if we actually have track data
                        if document.trackSegments.isEmpty {
                            print("Warning: No track segments found in GPX data")
                        }
                        
                        // Update our document and present it
                        self.sharedDocument = document
                        self.isSharedDocumentPresented = true
                        
                        // Create a new document window to display this file
                        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let rootViewController = windowScene.windows.first?.rootViewController {
                            // Create a SwiftUI view with our document
                            let contentView = ContentView(document: .constant(document))
                            let hostingController = UIHostingController(rootView: contentView)
                            
                            // Present it modally
                            rootViewController.present(hostingController, animated: true)
                        }
                    } else {
                        throw NSError(domain: "GPXExplore", code: 3, userInfo: [
                            NSLocalizedDescriptionKey: "Could not convert file data to text"
                        ])
                    }
                } catch {
                    print("Error loading shared document: \(error)")
                    
                    // You could show an error alert to the user here
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let rootViewController = windowScene.windows.first?.rootViewController {
                        
                        let alert = UIAlertController(
                            title: "Error Opening File",
                            message: "Could not open the GPX file. \(error.localizedDescription)",
                            preferredStyle: .alert
                        )
                        
                        alert.addAction(UIAlertAction(title: "OK", style: .default))
                        rootViewController.present(alert, animated: true)
                    }
                }
            }
        }
    }
    #endif
    
    #if os(macOS)
    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType.gpx, UTType.xml]
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                NSWorkspace.shared.open(url)
            }
        }
    }
    #endif
}

#if os(iOS)
// Add a UIApplicationDelegate to handle file opening from other apps
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Clean up any stale bookmarks
        cleanupStaleBookmarks()
        return true
    }
    
    private func cleanupStaleBookmarks() {
        let userDefaults = UserDefaults.standard
        let bookmarkKeys = userDefaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("LastGPXBookmark_") }
        
        for key in bookmarkKeys {
            if let bookmarkData = userDefaults.data(forKey: key) {
                do {
                    var isStale = false
                    // On iOS, just use empty options array - security scope is implicit
                    let url = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                    
                    if isStale {
                        print("Removing stale bookmark for \(key)")
                        userDefaults.removeObject(forKey: key)
                    } else {
                        // Validate that we can still access this file
                        if url.startAccessingSecurityScopedResource() {
                            url.stopAccessingSecurityScopedResource()
                        } else {
                            print("Can no longer access file at \(url), removing bookmark")
                            userDefaults.removeObject(forKey: key)
                        }
                    }
                } catch {
                    print("Failed to resolve bookmark for \(key): \(error)")
                    userDefaults.removeObject(forKey: key)
                }
            }
        }
    }
    
    // Supporting function for all iOS versions
    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        handleIncomingURL(url)
        return true
    }
    
    // Supporting function for iOS 13+
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Track access success for better error diagnostics
        var accessSuccess = false
        var resolvedURL = url
        
        // First, check if we have a bookmark for this file already
        if let bookmarkData = UserDefaults.standard.data(forKey: "LastGPXBookmark_\(url.lastPathComponent)") {
            do {
                var isStale = false
                let storedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && storedURL.startAccessingSecurityScopedResource() {
                    print("Successfully accessed file via existing bookmark: \(storedURL)")
                    resolvedURL = storedURL
                    accessSuccess = true
                } else if isStale {
                    print("Bookmark for \(url.lastPathComponent) is stale, will create a new one")
                    UserDefaults.standard.removeObject(forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                }
            } catch {
                print("Error resolving bookmark: \(error)")
            }
        }
        
        // If we don't have a bookmark or it failed, try direct access
        if !accessSuccess {
            accessSuccess = url.startAccessingSecurityScopedResource()
            if !accessSuccess {
                print("Failed to access security scoped resource: \(url)")
                
                // Try to proceed anyway as some files might not require security-scoped access
                // but log the issue for debugging
            } else {
                resolvedURL = url
            }
        }
        
        defer {
            // Only stop accessing if we successfully started
            if accessSuccess {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Create a bookmark for persistent access if needed
            if accessSuccess {
                let bookmarkData = try resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                
                // Store this bookmark data for future use
                UserDefaults.standard.set(bookmarkData, forKey: "LastGPXBookmark_\(resolvedURL.lastPathComponent)")
                print("Successfully created security-scoped bookmark for GPX file: \(resolvedURL.lastPathComponent)")
            }
            
            // Read the file data - this can sometimes work even if security-scoped access failed
            let data: Data
            do {
                data = try Data(contentsOf: resolvedURL)
            } catch {
                print("Failed to read data from URL: \(error)")
                // Try a different approach - ask for file coordination
                let coordinator = NSFileCoordinator()
                var readError: NSError?
                var fileData: Data?
                
                coordinator.coordinate(readingItemAt: resolvedURL, options: [], error: &readError) { coordinatedURL in
                    do {
                        fileData = try Data(contentsOf: coordinatedURL)
                    } catch {
                        print("Coordinated read also failed: \(error)")
                    }
                }
                
                if let readData = fileData {
                    data = readData
                } else {
                    throw NSError(domain: "GPXExplore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read file data even with coordination"])
                }
            }
            
            // Create a temporary file in the app's sandbox
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(resolvedURL.lastPathComponent)
            
            // Write the data to the temporary file
            try data.write(to: tempFileURL)
            
            // Notify the app to open this file
            NotificationCenter.default.post(
                name: Notification.Name("OpenGPXFile"),
                object: tempFileURL
            )
        } catch {
            print("Error processing URL: \(error)")
        }
    }
}

// Add a Scene Delegate to handle file opening at the scene level
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        // Handle any URLs that were passed when the app was launched
        if let urlContext = connectionOptions.urlContexts.first {
            handleIncomingURL(urlContext.url)
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        handleIncomingURL(urlContext.url)
    }
    
    private func handleIncomingURL(_ url: URL) {
        // Track access success for better error diagnostics
        var accessSuccess = false
        var resolvedURL = url
        
        // First, check if we have a bookmark for this file already
        if let bookmarkData = UserDefaults.standard.data(forKey: "LastGPXBookmark_\(url.lastPathComponent)") {
            do {
                var isStale = false
                let storedURL = try URL(resolvingBookmarkData: bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale)
                
                if !isStale && storedURL.startAccessingSecurityScopedResource() {
                    print("Successfully accessed file via existing bookmark: \(storedURL)")
                    resolvedURL = storedURL
                    accessSuccess = true
                } else if isStale {
                    print("Bookmark for \(url.lastPathComponent) is stale, will create a new one")
                    UserDefaults.standard.removeObject(forKey: "LastGPXBookmark_\(url.lastPathComponent)")
                }
            } catch {
                print("Error resolving bookmark: \(error)")
            }
        }
        
        // If we don't have a bookmark or it failed, try direct access
        if !accessSuccess {
            accessSuccess = url.startAccessingSecurityScopedResource()
            if !accessSuccess {
                print("Failed to access security scoped resource: \(url)")
                
                // Try to proceed anyway as some files might not require security-scoped access
                // but log the issue for debugging
            } else {
                resolvedURL = url
            }
        }
        
        defer {
            // Only stop accessing if we successfully started
            if accessSuccess {
                resolvedURL.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            // Create a bookmark for persistent access if needed
            if accessSuccess {
                let bookmarkData = try resolvedURL.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                
                // Store this bookmark data for future use
                UserDefaults.standard.set(bookmarkData, forKey: "LastGPXBookmark_\(resolvedURL.lastPathComponent)")
                print("Successfully created security-scoped bookmark for GPX file: \(resolvedURL.lastPathComponent)")
            }
            
            // Read the file data - this can sometimes work even if security-scoped access failed
            let data: Data
            do {
                data = try Data(contentsOf: resolvedURL)
            } catch {
                print("Failed to read data from URL: \(error)")
                // Try a different approach - ask for file coordination
                let coordinator = NSFileCoordinator()
                var readError: NSError?
                var fileData: Data?
                
                coordinator.coordinate(readingItemAt: resolvedURL, options: [], error: &readError) { coordinatedURL in
                    do {
                        fileData = try Data(contentsOf: coordinatedURL)
                    } catch {
                        print("Coordinated read also failed: \(error)")
                    }
                }
                
                if let readData = fileData {
                    data = readData
                } else {
                    throw NSError(domain: "GPXExplore", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to read file data even with coordination"])
                }
            }
            
            // Create a temporary file in the app's sandbox
            let fileManager = FileManager.default
            let tempDir = fileManager.temporaryDirectory
            let tempFileURL = tempDir.appendingPathComponent(resolvedURL.lastPathComponent)
            
            // Write the data to the temporary file
            try data.write(to: tempFileURL)
            
            // Notify the app to open this file
            NotificationCenter.default.post(
                name: Notification.Name("OpenGPXFile"),
                object: tempFileURL
            )
        } catch {
            print("Error processing URL: \(error)")
        }
    }
}
#endif
