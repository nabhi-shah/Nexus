import Cocoa
import SwiftUI
import Foundation

struct SerpApiResponse: Codable {
    let visual_matches: [VisualMatch]?
    let knowledge_graph: [KnowledgeGraphEntity]?
}

struct SerpApiImageResponse: Codable {
    let message: String?
    let image_id: String?
    let error: String?
}

struct VisualMatch: Identifiable, Codable {
    let id = UUID()
    let title: String?
    let source: String?
    let link: String?
    let thumbnail: String?
    
    enum CodingKeys: String, CodingKey {
        case title, source, link, thumbnail
    }
}

struct KnowledgeGraphEntity: Codable {
    let title: String?
    let subtitle: String?
}

class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return true }
}

struct CornerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height * 0.35))
        path.addQuadCurve(to: CGPoint(x: rect.width * 0.35, y: 0),
                          control: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        return path
    }
}

class CaptureManager: ObservableObject {
    @Published var startLoc: CGPoint? = nil
    @Published var currentLoc: CGPoint = .zero
    @Published var isDragging = false
    
    let unionRect: NSRect
    
    init() {
        var r: NSRect = .zero
        for s in NSScreen.screens { r = r.union(s.frame) }
        self.unionRect = r
    }
    
    func toLocal(_ global: CGPoint) -> CGPoint {
        let sx = global.x - unionRect.minX
        let sy = unionRect.height - (global.y - unionRect.minY)
        return CGPoint(x: sx, y: sy)
    }
    
    var rect: CGRect {
        let start = toLocal(startLoc ?? currentLoc)
        let curr = toLocal(currentLoc)
        let size: CGFloat = 30
        
        if isDragging, let _ = startLoc {
            var rectX = min(start.x, curr.x)
            var rectY = min(start.y, curr.y)
            var rectW = abs(start.x - curr.x)
            var rectH = abs(start.y - curr.y)
            
            if rectW < size {
                rectW = size
                if curr.x < start.x { rectX = start.x - size }
            }
            if rectH < size {
                rectH = size
                if curr.y < start.y { rectY = start.y - size }
            }
            return CGRect(x: rectX, y: rectY, width: rectW, height: rectH)
        } else {
            return CGRect(x: curr.x - size/2, y: curr.y - size/2, width: size, height: size)
        }
    }
}

struct CaptureOverlayView: View {
    @ObservedObject var manager: CaptureManager
    var onCapture: (CGRect) -> Void
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            let r = manager.rect
            
            // Liquid Glass & Corners
            ZStack {
                // Apple Liquid Glass
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .glassEffect(.clear, in: .rect(cornerRadius: 8))
                
                let cSize: CGFloat = 12
                let thick: CGFloat = 4
                let col = Color.white.opacity(0.9)
                let sh = Color.black.opacity(0.3)
                
                CornerShape().stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))
                    .frame(width: cSize, height: cSize).offset(x: -r.width/2 + cSize/2, y: -r.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape().stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(90))
                    .frame(width: cSize, height: cSize).offset(x: r.width/2 - cSize/2, y: -r.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape().stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(180))
                    .frame(width: cSize, height: cSize).offset(x: r.width/2 - cSize/2, y: r.height/2 - cSize/2).shadow(color: sh, radius: 2)
                CornerShape().stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(270))
                    .frame(width: cSize, height: cSize).offset(x: -r.width/2 + cSize/2, y: r.height/2 - cSize/2).shadow(color: sh, radius: 2)
            }
            .position(x: r.midX, y: r.midY)
        }
        .onAppear {
            manager.currentLoc = NSEvent.mouseLocation
            NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]) { event in
                let global = NSEvent.mouseLocation
                manager.currentLoc = global
                if event.type == .leftMouseDown {
                    manager.startLoc = global
                    manager.isDragging = true
                } else if event.type == .leftMouseUp {
                    manager.isDragging = false
                    if let start = manager.startLoc {
                        let minX = min(start.x, global.x)
                        let maxX = max(start.x, global.x)
                        let minY = min(start.y, global.y)
                        let maxY = max(start.y, global.y)
                        let w = max(maxX - minX, 10)
                        let h = max(maxY - minY, 10)
                        
                        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                        let quartzY = primaryHeight - maxY
                        
                        onCapture(CGRect(x: minX, y: quartzY, width: w, height: h))
                    }
                }
                return event
            }
        }
    }
}

// MARK: - View Model
class LensScraper: ObservableObject {
    @Published var matches: [VisualMatch] = []
    @Published var overview: String = ""
    @Published var isScraping: Bool = false
    @Published var statusText: String = ""
    
    let useMockData: Bool = true
    let serpApiKey: String = "033ad9db7b3b5cad579bca498474ea0e596e288545fd878a8c61cbfac04eb9f8"
    
    var captureWindow: NSWindow?
    var eventMonitor: Any?
    
    func startCapture() {
        DispatchQueue.main.async {
            self.isScraping = true
            self.statusText = self.useMockData ? "Capturing (Mock Mode)..." : "Capturing screen..."
            self.matches = []
            self.overview = ""
            self.showCaptureOverlay()
        }
    }
    
    private func showCaptureOverlay() {
        NSCursor.hide()
        let manager = CaptureManager()
        
        let overlayView = CaptureOverlayView(manager: manager) { [weak self] rect in
            DispatchQueue.main.async {
                self?.captureWindow?.orderOut(nil)
                self?.captureWindow = nil
                NSCursor.unhide()
                
                // Allow window to disappear before capturing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.executeScreencapture(rect: rect)
                }
            }
        }
        
        captureWindow = CaptureWindow(contentRect: manager.unionRect, styleMask: [.borderless], backing: .buffered, defer: false)
        captureWindow?.level = .screenSaver
        captureWindow?.backgroundColor = .clear
        captureWindow?.isOpaque = false
        captureWindow?.hasShadow = false
        captureWindow?.acceptsMouseMovedEvents = true
        captureWindow?.contentView = NSHostingView(rootView: overlayView)
        captureWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeScreencapture(rect: CGRect) {
        let tempFilePath = NSTemporaryDirectory().appending("lensgrab_temp.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-R", "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)", tempFilePath]
        
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    if self?.useMockData == true {
                        self?.loadMockData()
                    } else {
                        self?.uploadToSerpApi(filePath: tempFilePath)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.statusText = "Capture failed: \(error.localizedDescription)"
                self.isScraping = false
            }
        }
    }
    
    private func uploadToSerpApi(filePath: String) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: filePath) else {
            DispatchQueue.main.async {
                self.isScraping = false
                self.statusText = "Capture cancelled."
            }
            return
        }
        
        DispatchQueue.main.async {
            self.statusText = "Uploading securely to SerpApi Image API..."
        }
        
        let fileUrl = URL(fileURLWithPath: filePath)
        guard let imageData = try? Data(contentsOf: fileUrl) else {
            DispatchQueue.main.async { self.isScraping = false }
            return
        }
        
        var request = URLRequest(url: URL(string: "https://serpapi.com/image")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(serpApiKey)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            try? fileManager.removeItem(atPath: filePath)
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.statusText = "Failed to reach SerpApi."
                    self?.isScraping = false
                }
                return
            }
            
            do {
                let imgResponse = try JSONDecoder().decode(SerpApiImageResponse.self, from: data)
                if let err = imgResponse.error {
                    DispatchQueue.main.async {
                        self?.statusText = "SerpApi Error: \(err)"
                        self?.isScraping = false
                    }
                    return
                }
                
                if let imageId = imgResponse.image_id {
                    self?.querySerpApi(imageId: imageId)
                } else {
                    DispatchQueue.main.async {
                        self?.statusText = "No image_id returned."
                        self?.isScraping = false
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusText = "Failed to parse image response."
                    self?.isScraping = false
                }
            }
        }
        task.resume()
    }
    
    private func querySerpApi(imageId: String) {
        DispatchQueue.main.async {
            self.statusText = "Searching Google Lens..."
        }
        
        var components = URLComponents(string: "https://serpapi.com/search.json")!
        components.queryItems = [
            URLQueryItem(name: "engine", value: "google_lens"),
            URLQueryItem(name: "image_id", value: imageId),
            URLQueryItem(name: "no_cache", value: "true"),
            URLQueryItem(name: "api_key", value: serpApiKey)
        ]
        
        let request = URLRequest(url: components.url!)
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.statusText = "API request failed."
                    self?.isScraping = false
                }
                return
            }
            
            do {
                let serpResponse = try JSONDecoder().decode(SerpApiResponse.self, from: data)
                DispatchQueue.main.async {
                    self?.matches = serpResponse.visual_matches ?? []
                    
                    if let kg = serpResponse.knowledge_graph?.first, let title = kg.title {
                        let subtitle = kg.subtitle ?? ""
                        self?.overview = "\(title)\n\(subtitle)"
                    } else {
                        self?.overview = "Here are the visual matches for your image."
                    }
                    
                    self?.isScraping = false
                }
            } catch {
                DispatchQueue.main.async {
                    self?.statusText = "Failed to parse API response."
                    self?.isScraping = false
                    print(error)
                }
            }
        }
        task.resume()
    }
    
    private func loadMockData() {
        guard let url = Bundle.main.url(forResource: "mock_response", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            DispatchQueue.main.async {
                self.statusText = "Failed to load mock data."
                self.isScraping = false
            }
            return
        }
        
        do {
            let serpResponse = try JSONDecoder().decode(SerpApiResponse.self, from: data)
            DispatchQueue.main.async {
                self.matches = serpResponse.visual_matches ?? []
                if let kg = serpResponse.knowledge_graph?.first, let title = kg.title {
                    let subtitle = kg.subtitle ?? ""
                    self.overview = "\(title)\n\(subtitle)"
                } else {
                    self.overview = "Here are the visual matches for your image."
                }
                self.isScraping = false
            }
        } catch {
            DispatchQueue.main.async {
                self.statusText = "Failed to parse mock data."
                self.isScraping = false
            }
        }
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject var scraper: LensScraper
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("LensGrabber (SerpApi)").font(.headline)
                Spacer()
                Button(action: {
                    scraper.startCapture()
                }) {
                    Image(systemName: "camera.viewfinder")
                    Text("Take Snapshot")
                }
                .disabled(scraper.isScraping)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(8)
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            if scraper.isScraping {
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text(scraper.statusText)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scraper.matches.isEmpty {
                VStack {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                        .padding()
                    Text("Ready.")
                        .font(.headline)
                    Text("Click 'Take Snapshot' to search using SerpApi.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Results UI
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Overview")
                        .font(.headline)
                        .padding(.top)
                    
                    Text(scraper.overview)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Visual Matches")
                        .font(.headline)
                        .padding(.top)
                    
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180, maximum: 220), spacing: 16)], spacing: 16) {
                            ForEach(scraper.matches) { match in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Thumbnail
                                    AsyncImage(url: URL(string: match.thumbnail ?? "")) { phase in
                                        if let image = phase.image {
                                            image
                                                .resizable()
                                                .scaledToFill()
                                                .frame(height: 140)
                                                .clipped()
                                        } else {
                                            Rectangle()
                                                .fill(Color(NSColor.windowBackgroundColor))
                                                .frame(height: 140)
                                                .overlay(ProgressView())
                                        }
                                    }
                                    .cornerRadius(8)
                                    
                                    // Text
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(match.source ?? "Unknown Source")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        
                                        Text(match.title ?? "No title")
                                            .font(.caption)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                    }
                                    .padding(.horizontal, 4)
                                    .padding(.bottom, 8)
                                }
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                                .onTapGesture {
                                    if let link = match.link, let url = URL(string: link) {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .onHover { hovering in
                                    if hovering { NSCursor.pointingHand.push() }
                                    else { NSCursor.pop() }
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding(.horizontal)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var scraper: LensScraper!
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        scraper = LensScraper()
        let contentView = ContentView(scraper: self.scraper)
        
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.center()
        window.title = "LensGrabber (SerpApi)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        scraper.startCapture()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            window.makeKeyAndOrderFront(nil)
        }
        scraper.startCapture()
        return true
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
