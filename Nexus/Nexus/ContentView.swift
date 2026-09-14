import Cocoa
import SwiftUI
import Foundation
import Combine

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
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: radius, y: radius)
        
        path.move(to: CGPoint(x: 0, y: rect.height))
        if rect.height > radius {
            path.addLine(to: CGPoint(x: 0, y: radius))
        }
        
        if radius > 0 {
            path.addArc(center: center,
                        radius: radius,
                        startAngle: .degrees(180),
                        endAngle: .degrees(270),
                        clockwise: false)
        } else {
            path.addLine(to: CGPoint(x: 0, y: 0))
        }
        
        if rect.width > radius {
            path.addLine(to: CGPoint(x: rect.width, y: 0))
        }
        
        return path
    }
}

class CaptureManager: ObservableObject {
    @Published var startLoc: CGPoint? = nil
    @Published var currentLoc: CGPoint = .zero
    @Published var isDragging = false
    @Published var isHoveringClose = false
    
    var isCursorHidden = false
    
    var isFinished = false
    
    func hideCursor() {
        if isFinished { return }
        if !isCursorHidden {
            NSCursor.hide()
            isCursorHidden = true
        }
    }
    
    func unhideCursor() {
        if isCursorHidden {
            NSCursor.unhide()
            isCursorHidden = false
        }
    }
    
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

struct GlassMenuButton: View {
    var icon: String
    var action: () -> Void
    var manager: CaptureManager
    var isCloseButton: Bool = false
    var isBlackDot: Bool = false
    
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if !isBlackDot {
                    Image(icon) // Uses custom Phosphor SVGs from Asset Catalog
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .foregroundColor(isCloseButton ? .white : .white)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .frame(width: 56, height: 56)
        }
        .buttonStyle(PlainButtonStyle())
        .glassEffect(
            .regular.tint(
                isBlackDot ? .black : (isCloseButton ? .red.opacity(0.8) : .white.opacity(isHovering ? 0.2 : 0.1))
            ),
            in: .circle
        )
        .overlay(Circle().stroke(isBlackDot ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
        .shadow(color: isBlackDot ? .clear : .black.opacity(0.2), radius: 5)
        .focusable(false)
        .onHover { hovering in
            isHovering = hovering
            manager.isHoveringClose = hovering
            if hovering {
                manager.unhideCursor()
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
                manager.hideCursor()
            }
        }
    }
}

struct CaptureOverlayView: View {
    @ObservedObject var manager: CaptureManager
    var onCapture: (CGRect) -> Void
    var onCancel: () -> Void
    @State private var eventMonitor: Any?
    @State private var isVisible = false
    @State private var buttonsExpanded = false
    @State private var dropYOffset: CGFloat = -20
    @Namespace private var glassSpace
    
    var body: some View {
        ZStack {
            Color.clear.ignoresSafeArea()
            
            // Navy Blue Gradient Overlay with Blur
            VStack(spacing: 0) {
                Color.clear
                    .glassEffect(.regular.tint(Color(red: 0.05, green: 0.1, blue: 0.3).opacity(0.6)), in: .rect)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [.black, .clear]), startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 200)
                    .offset(y: isVisible ? 0 : -200)
                Spacer()
                Color.clear
                    .glassEffect(.regular.tint(Color(red: 0.05, green: 0.1, blue: 0.3).opacity(0.6)), in: .rect)
                    .mask(
                        LinearGradient(gradient: Gradient(colors: [.clear, .black]), startPoint: .top, endPoint: .bottom)
                    )
                    .frame(height: 200)
                    .offset(y: isVisible ? 0 : 200)
            }
            .ignoresSafeArea(.all, edges: [.bottom, .leading, .trailing])
            .allowsHitTesting(false)
            
            let r = manager.rect
            
            // Liquid Glass & Corners
            ZStack {
                let dynamicRadius = min(16, min(r.width / 4, r.height / 4))
                let cSize = min(24, min(r.width / 3, r.height / 3))
                
                // Apple Liquid Glass
                Color.clear
                    .frame(width: r.width, height: r.height)
                    .glassEffect(.clear, in: .rect(cornerRadius: dynamicRadius))
                
                let thick: CGFloat = 4
                let col = Color.white.opacity(0.9)
                let sh = Color.black.opacity(0.3)
                
                CornerShape(radius: dynamicRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))
                    .frame(width: cSize, height: cSize).offset(x: -r.width/2 + cSize/2, y: -r.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: dynamicRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(90))
                    .frame(width: cSize, height: cSize).offset(x: r.width/2 - cSize/2, y: -r.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: dynamicRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(180))
                    .frame(width: cSize, height: cSize).offset(x: r.width/2 - cSize/2, y: r.height/2 - cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: dynamicRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(270))
                    .frame(width: cSize, height: cSize).offset(x: -r.width/2 + cSize/2, y: r.height/2 - cSize/2).shadow(color: sh, radius: 2)
            }
            .position(x: r.midX, y: r.midY)
            .opacity(manager.isHoveringClose ? 0 : 1)
            
            // Dynamic Glass Island Drop
            VStack {
                GlassEffectContainer(spacing: 12) { // 12pt threshold ensures they stay close but don't join
                    ZStack {
                        // The anchor dot inside the notch (ensures a gooey tear-off effect)
                        Color.clear
                            .frame(width: 80, height: 40)
                            .glassEffect(.regular.tint(.black), in: .rect(cornerRadius: 20))
                            .offset(y: -20)
                        
                        // The moving group that falls and expands
                        ZStack {
                            if buttonsExpanded {
                                GlassMenuButton(icon: "phosphor_search", action: {}, manager: manager)
                                    .offset(x: -148)
                                    .glassEffectID("search", in: glassSpace)
                                
                                GlassMenuButton(icon: "phosphor_music-notes", action: {}, manager: manager)
                                    .offset(x: -74)
                                    .glassEffectID("music", in: glassSpace)
                            }
                            
                            GlassMenuButton(
                                icon: "phosphor_translate",
                                action: {
                                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                        buttonsExpanded.toggle()
                                    }
                                },
                                manager: manager,
                                isBlackDot: !buttonsExpanded
                            )
                            .glassEffectID("center", in: glassSpace)
                            
                            if buttonsExpanded {
                                GlassMenuButton(icon: "phosphor_cursor-text", action: {}, manager: manager)
                                    .offset(x: 74)
                                    .glassEffectID("text", in: glassSpace)
                                
                                GlassMenuButton(icon: "phosphor_x", action: { onCancel() }, manager: manager, isCloseButton: true)
                                    .offset(x: 148)
                                    .glassEffectID("close", in: glassSpace)
                            }
                        }
                        .offset(y: dropYOffset)
                    }
                }
                .padding(.top, 0)
                Spacer()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                withAnimation(.easeOut(duration: 0.4)) {
                    isVisible = true
                }
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    dropYOffset = 60
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                    buttonsExpanded = true
                }
            }
            manager.currentLoc = NSEvent.mouseLocation
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .keyDown]) { event in
                if event.type == .keyDown && event.keyCode == 53 {
                    onCancel()
                    return nil
                }
                
                let global = NSEvent.mouseLocation
                manager.currentLoc = global
                
                // Fallback check if it's in the top right 100x100 area
                let isTopRight = global.x > manager.unionRect.maxX - 120 && global.y > manager.unionRect.maxY - 120
                let isOverClose = manager.isHoveringClose || isTopRight
                
                if event.type == .leftMouseDown {
                    if isOverClose { return event }
                    manager.startLoc = global
                    manager.isDragging = true
                } else if event.type == .leftMouseUp {
                    if isOverClose { return event }
                    if !manager.isDragging { return event }
                    
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
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
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
    let serpApiKey: String = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"] ?? ""
    let geminiApiKey: String = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    
    var captureWindow: NSWindow?
    var eventMonitor: Any?
    var mainWindow: NSWindow?
    
    func startCapture() {
        DispatchQueue.main.async {
            self.mainWindow?.orderOut(nil) // Hide main window while capturing
            self.isScraping = true
            self.statusText = self.useMockData ? "Capturing (Mock Mode)..." : "Capturing screen..."
            self.matches = []
            self.overview = ""
            self.showCaptureOverlay()
        }
    }
    
    private func showCaptureOverlay() {
        let manager = CaptureManager()
        manager.hideCursor()
        
        let overlayView = CaptureOverlayView(manager: manager, onCapture: { [weak self] rect in
            DispatchQueue.main.async {
                manager.isFinished = true
                self?.captureWindow?.orderOut(nil)
                self?.captureWindow = nil
                manager.unhideCursor()
                
                // Allow window to disappear before capturing
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self?.executeScreencapture(rect: rect)
                }
            }
        }, onCancel: { [weak self] in
            DispatchQueue.main.async {
                manager.isFinished = true
                self?.captureWindow?.orderOut(nil)
                self?.captureWindow = nil
                manager.unhideCursor()
                self?.isScraping = false
                self?.statusText = "Capture cancelled."
            }
        })
        
        captureWindow = CaptureWindow(contentRect: manager.unionRect, styleMask: [.borderless], backing: .buffered, defer: false)
        captureWindow?.level = .floating
        captureWindow?.backgroundColor = .clear
        captureWindow?.isOpaque = false
        captureWindow?.hasShadow = false
        captureWindow?.acceptsMouseMovedEvents = true
        captureWindow?.contentView = NSHostingView(rootView: overlayView)
        captureWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeScreencapture(rect: CGRect) {
        let tempFilePath = NSTemporaryDirectory().appending("nexus_temp.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-R", "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)", tempFilePath]
        
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    // Show the main window again once the capture is complete
                    self?.mainWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                    
                    if self?.useMockData == true {
                        try? FileManager.default.removeItem(atPath: tempFilePath)
                        self?.loadMockData()
                    } else {
                        self?.uploadToSerpApi(filePath: tempFilePath)
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.mainWindow?.makeKeyAndOrderFront(nil)
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
        let rawImageData = try? Data(contentsOf: fileUrl)
        try? fileManager.removeItem(atPath: filePath) // Immediately delete the temp file once read
        
        guard let imageData = rawImageData else {
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
                    let base64String = imageData.base64EncodedString()
                    self?.querySerpApi(imageId: imageId, imageBase64: base64String)
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
    
    private func querySerpApi(imageId: String, imageBase64: String) {
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
                    self?.generateGeminiOverview(imageBase64: imageBase64, matches: serpResponse.visual_matches ?? [])
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
    
    private func generateGeminiOverview(imageBase64: String, matches: [VisualMatch]) {
        DispatchQueue.main.async {
            self.statusText = "Generating AI Overview..."
        }
        
        guard !geminiApiKey.isEmpty else {
            DispatchQueue.main.async {
                self.overview = "Gemini API key is not set. Showing raw visual matches."
                self.isScraping = false
            }
            return
        }
        
        var matchesText = ""
        for (index, match) in matches.prefix(5).enumerated() {
            matchesText += "\(index + 1). \(match.title ?? "Unknown") - \(match.source ?? "Unknown Source")\n"
        }
        
        let prompt = "Analyze the provided image along with these visual match results from Google Lens:\n\n\(matchesText)\n\nProvide a concise, helpful overview of what this is."
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent?key=\(geminiApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        ["inlineData": [
                            "mimeType": "image/png",
                            "data": imageBase64
                        ]]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self?.overview = "Failed to reach Gemini API."
                    self?.isScraping = false
                }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let errorObj = json["error"] as? [String: Any], let msg = errorObj["message"] as? String {
                        DispatchQueue.main.async {
                            self?.overview = "Gemini API Error: \(msg)"
                            self?.isScraping = false
                        }
                    } else if let candidates = json["candidates"] as? [[String: Any]],
                       let firstCandidate = candidates.first,
                       let content = firstCandidate["content"] as? [String: Any],
                       let parts = content["parts"] as? [[String: Any]],
                       let firstPart = parts.first,
                       let text = firstPart["text"] as? String {
                        DispatchQueue.main.async {
                            self?.overview = text
                            self?.isScraping = false
                        }
                    } else {
                        DispatchQueue.main.async {
                            self?.overview = "Failed to parse Gemini response."
                            self?.isScraping = false
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.overview = "Error parsing Gemini response."
                    self?.isScraping = false
                }
            }
        }
        task.resume()
    }
    
    private func loadMockData() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.matches = [
                VisualMatch(title: "Apple MacBook Pro M3 Max - 16-inch", source: "Apple", link: "https://apple.com/macbook-pro", thumbnail: "https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp16-spaceblack-select-202310?wid=904&hei=840&fmt=jpeg&qlt=90&.v=1698169226604"),
                VisualMatch(title: "MacBook Pro 16\" Space Black Review", source: "The Verge", link: "https://theverge.com", thumbnail: "https://cdn.vox-cdn.com/thumbor/n4J1YF5C8a17kQG4R4630lW_2K4=/0x0:2040x1360/2000x1333/filters:focal(1020x680:1021x681)/cdn.vox-cdn.com/uploads/chorus_asset/file/25061698/236773_Apple_MacBook_Pro_16_inch_M3_Max_AKrales_0023.jpg"),
                VisualMatch(title: "M3 Max vs M2 Max: Which MacBook Pro is Right for You?", source: "MacRumors", link: "https://macrumors.com", thumbnail: "https://images.macrumors.com/t/2c89Fv2p0kHw-vO0l8U0L8X0Z0=/1600x/article-new/2023/10/MacBook-Pro-M3-Space-Black-Feature.jpg"),
                VisualMatch(title: "Space Black MacBook Pro: Fingerprint Resistant?", source: "9to5Mac", link: "https://9to5mac.com", thumbnail: "https://i0.wp.com/9to5mac.com/wp-content/uploads/sites/6/2023/11/space-black-macbook-pro-1.jpg?w=1500&quality=82&strip=all&ssl=1")
            ]
            self.overview = "Based on the visual matches, this appears to be the new Apple MacBook Pro featuring the M3 Max chip in the Space Black color finish. The visual results suggest an interest in reviews, comparisons, and purchasing options for this high-performance laptop."
            self.isScraping = false
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
                Text("Nexus (SerpApi)").font(.headline)
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
                .onHover { hovering in
                    if hovering { NSCursor.pointingHand.push() }
                    else { NSCursor.pop() }
                }
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
                                    if let urlString = match.thumbnail, let url = URL(string: urlString) {
                                        AsyncImage(url: url) { phase in
                                            if let image = phase.image {
                                                image
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(height: 140)
                                                    .clipped()
                                            } else if phase.error != nil {
                                                Rectangle()
                                                    .fill(Color(NSColor.windowBackgroundColor))
                                                    .frame(height: 140)
                                                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                            } else {
                                                Rectangle()
                                                    .fill(Color(NSColor.windowBackgroundColor))
                                                    .frame(height: 140)
                                                    .overlay(ProgressView())
                                            }
                                        }
                                        .cornerRadius(8)
                                    } else {
                                        Rectangle()
                                            .fill(Color(NSColor.windowBackgroundColor))
                                            .frame(height: 140)
                                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                            .cornerRadius(8)
                                    }
                                    
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
