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
            if let image = NSImage(named: "MenuBarIcon") {
                image.isTemplate = true
                // Keep aspect ratio 84:81 roughly
                image.size = NSSize(width: 16, height: 16)
                button.image = image
            } else {
                button.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Nexus Capture")
            }
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
    
    var textHotKeyRef: EventHotKeyRef?
    
    private func setupCarbonHotkeys() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(GetApplicationEventTarget(), { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(theEvent, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            
            if let delegate = NSApplication.shared.delegate as? AppDelegate {
                DispatchQueue.main.async {
                    if hotKeyID.id == 1 {
                        delegate.scraper.startCapture()
                    } else if hotKeyID.id == 2 {
                        let manager = TextEditManager.shared
                        manager.currentElement = manager.getFocusedElement()
                        // Extract text BEFORE opening our window
                        manager.extractedText = manager.extractText(from: manager.currentElement)
                        let screenHeight = NSScreen.main?.frame.height ?? 800
                        let mousePos = NSEvent.mouseLocation
                        
                        if let text = manager.extractedText, !text.isEmpty {
                            Task {
                                let apiKey = "apikey_22513b59699a87844a2f96237441919e2e32_14fcdb742ae45567eef64cd0248e8c2e59a2a53537709c5099a04e3012ab5981"
                                if let newPos = await manager.identifyMenuPositionWithJev(apiKey: apiKey, fullText: text, element: manager.currentElement, screenHeight: screenHeight) {
                                    DispatchQueue.main.async {
                                        manager.menuPosition = CGPoint(x: newPos.x, y: screenHeight - newPos.y)
                                        delegate.showTextEditOverlay()
                                    }
                                } else {
                                    DispatchQueue.main.async {
                                        if let element = manager.currentElement, let highlightPos = manager.findHighlightPosition(element: element, screenHeight: screenHeight) {
                                            manager.menuPosition = highlightPos
                                        } else if let element = manager.currentElement, let cursorPos = manager.getCursorPosition(element: element) {
                                            manager.menuPosition = CGPoint(x: cursorPos.x, y: screenHeight - cursorPos.y)
                                        } else {
                                            manager.menuPosition = CGPoint(x: mousePos.x, y: mousePos.y)
                                        }
                                        delegate.showTextEditOverlay()
                                    }
                                }
                            }
                        } else {
                            if let element = manager.currentElement {
                                if let highlightPos = manager.findHighlightPosition(element: element, screenHeight: screenHeight) {
                                    manager.menuPosition = highlightPos
                                } else if let cursorPos = manager.getCursorPosition(element: element) {
                                    manager.menuPosition = CGPoint(x: cursorPos.x, y: screenHeight - cursorPos.y)
                                } else {
                                    manager.menuPosition = CGPoint(x: mousePos.x, y: mousePos.y)
                                }
                            } else {
                                manager.menuPosition = CGPoint(x: mousePos.x, y: mousePos.y)
                            }
                            delegate.showTextEditOverlay()
                        }
                    }
                }
            }
            return noErr
        }, 1, &eventType, nil, nil)
        
        // Register Control + Option + N (⌃⌥N) for Capture
        var captureHotKeyID = EventHotKeyID(signature: OSType(fourCharCode: "NEXU"), id: 1)
        let captureModifiers = UInt32(controlKey | optionKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), captureModifiers, captureHotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        
        // Register Control + Command + N (⌃⌘N) for Text Edit
        var textHotKeyID = EventHotKeyID(signature: OSType(fourCharCode: "NEXT"), id: 2)
        let textModifiers = UInt32(controlKey | cmdKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), textModifiers, textHotKeyID, GetApplicationEventTarget(), 0, &textHotKeyRef)
    }
    

    var textEditWindow: NSWindow?
    
    func handleHotkey() {
        let manager = TextEditManager.shared
        if let element = manager.getFocusedElement(), manager.isTextField(element) {
            manager.currentElement = element
            showTextEditOverlay()
        } else {
            scraper.startCapture()
        }
    }
    
        func showTextEditOverlay() {
        if textEditWindow == nil {
            // Make a window large enough to accommodate vertical expansion
            let window = CaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.acceptsMouseMovedEvents = true
            self.textEditWindow = window
        }
        
        let view = TextEditOverlayView { [weak self] in
            self?.textEditWindow?.orderOut(nil)
        }
        textEditWindow?.contentView = NSHostingView(rootView: view)
        
        // Position window globally!
        let manager = TextEditManager.shared
        let winWidth: CGFloat = 400
        let winHeight: CGFloat = 300
        
        // Target coordinates
        var originX = manager.menuPosition.x - (winWidth / 2)
        var originY = manager.menuPosition.y - 226
        
        // Clamp to screen bounds
        let screens = NSScreen.screens
        let screen = screens.first { $0.frame.contains(manager.menuPosition) } ?? NSScreen.main ?? screens.first
        
        if let screenFrame = screen?.visibleFrame {
            // Clamp X
            if originX < screenFrame.minX {
                originX = screenFrame.minX + 10
            } else if originX + winWidth > screenFrame.maxX {
                originX = screenFrame.maxX - winWidth - 10
            }
            
            // Clamp Y
            if originY < screenFrame.minY {
                originY = screenFrame.minY + 10
            } else if originY + winHeight > screenFrame.maxY {
                originY = screenFrame.maxY - winHeight - 10
            }
        }
        
        textEditWindow?.setFrameOrigin(NSPoint(x: originX, y: originY))
        NSApp.activate(ignoringOtherApps: true)
        textEditWindow?.makeKeyAndOrderFront(nil)
        textEditWindow?.orderFrontRegardless()
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
