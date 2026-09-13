import Cocoa
import SwiftUI
import Carbon.HIToolbox

@main
struct AppRunner {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // Runs in background without dock icon initially
        app.run()
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scraper: LensScraper!
    var statusItem: NSStatusItem!
    
    // Carbon HotKey reference
    var hotKeyRef: EventHotKeyRef?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        requestPermissions()
        
        scraper = LensScraper()
        let contentView = ContentView(scraper: self.scraper)
        
        // Setup menu bar icon
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nexus Capture")
            button.action = #selector(menuBarClicked)
            button.target = self
        }
        
        let menu = NSMenu()
        let captureItem = NSMenuItem(title: "Capture Screen", action: #selector(menuBarClicked), keyEquivalent: "n")
        captureItem.keyEquivalentModifierMask = [.control, .option] // ⌃⌥N
        menu.addItem(captureItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit Nexus", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem.menu = menu
        
        // Setup main window but do NOT show it immediately
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "Nexus"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        
        scraper.mainWindow = window
        
        setupCarbonHotkeys()
        
        // Start capture on launch
        scraper.startCapture()
    }
    
    private func requestPermissions() {
        // Request Accessibility Permission (Always On access)
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String : true]
        _ = AXIsProcessTrustedWithOptions(options)
        
        // Request Screen Recording Permission
        if #available(macOS 11.0, *) {
            if CGPreflightScreenCaptureAccess() == false {
                CGRequestScreenCaptureAccess()
            }
        } else {
            // Fallback for older macOS
            let displayCount = UnsafeMutablePointer<UInt32>.allocate(capacity: 1)
            CGGetActiveDisplayList(0, nil, displayCount)
            displayCount.deallocate()
        }
    }
    
    @objc func menuBarClicked() {
        scraper.startCapture()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(self)
    }
    
    private func setupCarbonHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            // When hotkey is pressed, start capture
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                DispatchQueue.main.async {
                    delegate.scraper.startCapture()
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        
        // Register Control + Option + N (⌃⌥N)
        var hotKeyID = EventHotKeyID(signature: OSType(fourCharCode: "NEXU"), id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            scraper.startCapture()
        }
        return true
    }
}

// Helper to create OSType from 4-character string
extension OSType {
    init(fourCharCode: String) {
        var result: OSType = 0
        if let data = fourCharCode.data(using: .macOSRoman) {
            data.withUnsafeBytes { ptr in
                if let baseAddress = ptr.baseAddress {
                    result = baseAddress.load(as: OSType.self).bigEndian
                }
            }
        }
        self = result
    }
}
