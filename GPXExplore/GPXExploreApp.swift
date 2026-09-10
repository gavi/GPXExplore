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
                ZStack {
                    // Regular document content
                    ContentView(document: file.$document)
                        .onAppear {
                            setupNotificationObserver()
                        }
                        
                    // Overlay for direct-opened documents
                    if isSharedDocumentPresented, let document = sharedDocument {
                        Color.black.opacity(0.001)
                            .onAppear {
                                // Present the shared document in a full-screen cover
                                presentSharedDocument(document: document)
                            }
                    }
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
    private func presentSharedDocument(document: GPXExploreDocument) {
        // Present the document full screen
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("Could not find root view controller to present document")
            return
        }
        
        // Create a hosting controller with the content view
        let contentView = ContentView(document: .constant(document))
        let hostingController = UIHostingController(rootView: 
            NavigationStack {
                contentView
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Close") {
                                self.sharedDocument = nil
                                self.isSharedDocumentPresented = false
                                rootViewController.dismiss(animated: true)
                            }
                        }
                    }
            }
        )
        
        // Present full screen
        hostingController.modalPresentationStyle = .fullScreen
        rootViewController.present(hostingController, animated: true)
    }
    
    private func setupNotificationObserver() {
        // Listen for notifications about files being shared to our app
        NotificationCenter.default.addObserver(
            forName: Notification.Name("OpenGPXFile"),
            object: nil,
            queue: .main
        ) { notification in
            // Handle document directly if passed
            if let document = notification.object as? GPXExploreDocument {
                print("Received document directly: \(document.gpxFile?.filename ?? "unnamed")")
                self.sharedDocument = document
                self.isSharedDocumentPresented = true
            }
            // Otherwise handle URL
            else if let url = notification.object as? URL {
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
        print("AppDelegate: Received URL to open: \(url)")
        
        // Let SceneDelegate handle the URL
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let sceneDelegate = windowScene.delegate as? SceneDelegate {
            // Use the scene delegate's method to handle the URL
            sceneDelegate.handleURLDirectly(url, in: windowScene)
        }
        
        return true
    }
    
    // Supporting function for iOS 13+
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let sceneConfig = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        sceneConfig.delegateClass = SceneDelegate.self
        return sceneConfig
    }
    
    private func handleIncomingURL(_ url: URL) {
        print("Handling incoming URL: \(url)")
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
            
            // Notify the app to open this file using the shared notification center
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
            let url = urlContext.url
            
            // We need to delay this slightly at launch to ensure the window is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.handleURLDirectly(url, in: scene)
            }
        } else if let i = CommandLine.arguments.firstIndex(of: "-openFile"), i + 1 < CommandLine.arguments.count {
            // The screenshot script (AppStore/shots.sh) opens a sample straight from a host path
            let url = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.handleURLDirectly(url, in: scene)
            }
        }
    }
    
    func handleURLDirectly(_ url: URL, in scene: UIScene) {
        print("SceneDelegate: Handling URL directly: \(url)")
        
        // Create a temporary URL in the app's Documents directory to store the file
        let fileManager = FileManager.default
        let documentsDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destinationURL = documentsDirectory.appendingPathComponent(url.lastPathComponent)
        
        do {
            // Copy the file to our documents directory if it doesn't exist
            if !fileManager.fileExists(atPath: destinationURL.path) {
                let accessGranted = url.startAccessingSecurityScopedResource()
                
                defer {
                    if accessGranted {
                        url.stopAccessingSecurityScopedResource()
                    }
                }
                
                try fileManager.copyItem(at: url, to: destinationURL)
                print("File copied to app's documents: \(destinationURL)")
            }
            
            // Create a user activity to record this document in recents
            let activity = NSUserActivity(activityType: "com.objectgraph.GPXExplore.viewing")
            activity.title = url.lastPathComponent
            // Don't set webpageURL - file:// URLs aren't allowed
            activity.userInfo = ["url": destinationURL.path]
            activity.isEligibleForHandoff = true
            activity.isEligibleForSearch = true
            activity.isEligibleForPrediction = true
            activity.becomeCurrent()
            
            // Now open the file using UIKit
            if let windowScene = scene as? UIWindowScene {
                // Read the file data
                let data = try Data(contentsOf: destinationURL)
                if let content = String(data: data, encoding: .utf8) {
                    // Parse GPX data
                    var document = GPXExploreDocument(text: content)
                    document.gpxFile = GPXParser.parseGPXData(data, filename: destinationURL.lastPathComponent)
                    
                    // Create and present the view
                    if let rootViewController = windowScene.windows.first?.rootViewController {
                        let contentView = ContentView(document: .constant(document))
                        let hostingController = UIHostingController(rootView: 
                            NavigationStack {
                                contentView
                                    .toolbar {
                                        ToolbarItem(placement: .navigationBarLeading) {
                                            Button("Close") {
                                                rootViewController.dismiss(animated: true)
                                            }
                                        }
                                    }
                            }
                        )
                        
                        hostingController.modalPresentationStyle = .fullScreen
                        DispatchQueue.main.async {
                            rootViewController.present(hostingController, animated: true)
                        }
                    }
                }
            }
        } catch {
            print("Error processing URL: \(error)")
        }
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let urlContext = URLContexts.first else { return }
        
        let url = urlContext.url
        print("SceneDelegate: Received URL from openURLContexts: \(url)")
        
        // Use our direct handler
        handleURLDirectly(url, in: scene)
    }
    
    // We're not using a document controller anymore, 
    // going with direct ContentView presentation instead
    
    private func handleIncomingURL(_ url: URL) {
        print("Handling incoming URL: \(url)")
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
            
            // Notify the app to open this file using the shared notification center
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
