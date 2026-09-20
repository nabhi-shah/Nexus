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
    @Published var isCapturing = false
    @Published var isProcessing = false
    @Published var capturedImage: NSImage? = nil
    @Published var imagePosition: CGPoint = .zero
    @Published var imageScale: CGFloat = 1.0
    @Published var isAnimatingToWindow = false
    
    var isCursorHidden = false
    
    var isFinished = false
    var hasAddedMonitor = false
    
    func hideCursor() {
        // Disabled to keep cursor visible
    }
    
    func unhideCursor() {
        // Disabled to keep cursor visible
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
        
        if (isDragging || isCapturing || isProcessing), let _ = startLoc {
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

struct GooeyBackground: View {
    var expanded: Bool
    var dropYOffset: CGFloat
    
    var body: some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 12))
            
            context.drawLayer { ctx in
                for i in 0..<6 {
                    if let resolved = context.resolveSymbol(id: i) {
                        ctx.draw(resolved, at: CGPoint(x: size.width / 2, y: 22)) // Center of 44pt height view in top-aligned ZStack
                    }
                }
            }
        } symbols: {
            // Anchor (fixed at the top notch)
            // Mimics the MacBook physical notch (approx 216x32 visible). 
            // Height 64 centered at 0 (via -22 offset) makes it extend exactly 32pt down.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .frame(width: 216, height: 64)
                .offset(y: -22) // Cancel out the y:22 draw position
                .tag(0)
            
            // Dots (move with dropYOffset)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? -116 : 0, y: dropYOffset).tag(1)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? -58 : 0, y: dropYOffset).tag(2)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(y: dropYOffset).tag(3)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 58 : 0, y: dropYOffset).tag(4)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 116 : 0, y: dropYOffset).tag(5)
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
                        .frame(width: 20, height: 20)
                        .foregroundColor(isCloseButton ? .white : .white)
                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isBlackDot ? Color.black : (isCloseButton ? Color.red.opacity(isHovering ? 0.7 : 0.2) : Color.white.opacity(isHovering ? 0.2 : 0.05)))
        )
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isBlackDot ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
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


struct RippleDistortionView: View {
    var rect: CGRect
    var cornerRadius: CGFloat
    @ObservedObject var manager: CaptureManager
    @State private var time: Float = 0.0
    
    var body: some View {
        ZStack {
            if let img = manager.capturedImage {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .layerEffect(
                        ShaderLibrary.chromaticRipple(
                            .float(time),
                            .float2(Float(rect.width / 2), Float(rect.height / 2)),
                            .float(50.0), // very strong amplitude
                            .float(25.0), // frequency
                            .float(0.01) // decay (slower decay so it reaches edges strongly)
                        ),
                        maxSampleOffset: CGSize(width: 150, height: 150) // Allow for large coordinate shifts
                    )
            } else {
                Color.clear
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2.0)) {
                time = 2.0
            }
        }
        .allowsHitTesting(false)
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
    @State private var isClosing = false
    
    private func closeWithAnimation() {
        guard !isClosing else { return }
        isClosing = true
        
        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
            buttonsExpanded = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                dropYOffset = -20
            }
            withAnimation(.easeOut(duration: 0.4)) {
                isVisible = false
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            onCancel()
        }
    }
    
    var body: some View {
        ZStack {
            // Removed Color.clear to allow clicks to pass through
            
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
                
                if manager.isProcessing {
                    RippleDistortionView(rect: r, cornerRadius: dynamicRadius, manager: manager)
                        .frame(width: r.width, height: r.height)
                        .transition(.opacity) // Prevent layout animation on insertion
                }
            }
            .position(manager.isAnimatingToWindow ? manager.imagePosition : CGPoint(x: r.midX, y: r.midY))
            .scaleEffect(manager.isAnimatingToWindow ? manager.imageScale : 1.0)
            .opacity(manager.isHoveringClose ? 0 : 1)
            
            // Dynamic Glass Island Drop
            VStack {
                ZStack(alignment: .top) {
                    GooeyBackground(expanded: buttonsExpanded, dropYOffset: dropYOffset)
                        .frame(width: 400, height: 200)
                        .opacity(buttonsExpanded ? 0 : 1)
                    
                    GlassEffectContainer(spacing: 12) {
                        ZStack {
                            GlassMenuButton(icon: "phosphor_search", action: {}, manager: manager, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? -116 : 0)
                                .glassEffectID("search", in: glassSpace)
                            
                            GlassMenuButton(icon: "phosphor_music-notes", action: {}, manager: manager, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? -58 : 0)
                                .glassEffectID("music", in: glassSpace)
                            
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
                            
                            GlassMenuButton(icon: "phosphor_cursor-text", action: {}, manager: manager, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 58 : 0)
                                .glassEffectID("text", in: glassSpace)
                            
                            GlassMenuButton(icon: "phosphor_x", action: { closeWithAnimation() }, manager: manager, isCloseButton: true, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 116 : 0)
                                .glassEffectID("close", in: glassSpace)
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
            
            if manager.hasAddedMonitor { return }
            manager.hasAddedMonitor = true
            
            eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp, .keyDown]) { event in
                if event.type == .keyDown && event.keyCode == 53 {
                    closeWithAnimation()
                    return nil
                }
                
                let global = NSEvent.mouseLocation
                if !manager.isCapturing && !manager.isProcessing {
                    manager.currentLoc = global
                }
                
                // Fallback check if it's in the top right 100x100 area
                let isTopRight = global.x > manager.unionRect.maxX - 120 && global.y > manager.unionRect.maxY - 120
                let isOverClose = manager.isHoveringClose || isTopRight
                
                if event.type == .leftMouseDown {
                    if isOverClose { return event }
                    manager.startLoc = global
                    manager.capturedImage = nil
                    manager.isDragging = true
                } else if event.type == .leftMouseUp {
                    if isOverClose { return event }
                    if !manager.isDragging { return event }
                    
                    manager.isDragging = false
                    manager.isCapturing = true
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
    @Published var isScraping: Bool = false {
        didSet {
            if !isScraping {
                DispatchQueue.main.async {
                    self.closeCaptureWindow()
                    self.mainWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
    }
    @Published var statusText: String = ""
    
    let useMockData: Bool = true
    let serpApiKey: String = ProcessInfo.processInfo.environment["SERPAPI_API_KEY"] ?? ""
    let geminiApiKey: String = ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
    
    var captureWindows: [NSWindow] = []
    var eventMonitor: Any?
    var mainWindow: NSWindow?
    
    private func closeCaptureWindow() {
        for window in captureWindows {
            window.orderOut(nil)
        }
        captureWindows.removeAll()
    }
    
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
        
        let overlayView = CaptureOverlayView(manager: manager, onCapture: { [weak self] rect in
            DispatchQueue.main.async {
                manager.isCapturing = true // State flag
                self?.executeScreencapture(rect: rect, manager: manager)
            }
        }, onCancel: { [weak self] in
            DispatchQueue.main.async {
                manager.isFinished = true
                self?.statusText = "Capture cancelled."
                self?.isScraping = false
            }
        })
        
        captureWindows.removeAll()
        for screen in NSScreen.screens {
            let window = CaptureWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .floating
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.sharingType = .none
            window.acceptsMouseMovedEvents = true
            
            let offsetX = manager.unionRect.minX - screen.frame.minX
            let offsetY = -(manager.unionRect.maxY - screen.frame.maxY)
            
            let shiftedView = overlayView
                .frame(width: manager.unionRect.width, height: manager.unionRect.height)
                .position(x: manager.unionRect.width / 2 + offsetX,
                          y: manager.unionRect.height / 2 + offsetY)
                .frame(width: screen.frame.width, height: screen.frame.height)
                .clipped()
            
            window.contentView = NSHostingView(rootView: shiftedView)
            window.makeKeyAndOrderFront(nil)
            captureWindows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func executeScreencapture(rect: CGRect, manager: CaptureManager) {
        let tempFilePath = NSTemporaryDirectory().appending("nexus_temp.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)", tempFilePath]
        
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    if FileManager.default.fileExists(atPath: tempFilePath), let img = NSImage(contentsOfFile: tempFilePath) {
                        manager.capturedImage = img
                    }
                    manager.imagePosition = CGPoint(x: rect.midX, y: rect.midY)
                    manager.imageScale = 1.0
                    
                    // Transition to loading UI (ripple starts)
                    withAnimation(.easeOut(duration: 0.3)) {
                        manager.isProcessing = true
                        manager.isCapturing = false
                    }
                    for window in self?.captureWindows ?? [] {
                        window.ignoresMouseEvents = true
                    }
                    
                    // Wait for the ripple to finish (approx 1.0s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        guard let self = self else { return }
                        
                        // 1. Calculate Target Window Frame (Opposite side of screen)
                        let screenRect = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
                        let fullScreenBounds = NSScreen.main?.frame ?? screenRect // For SwiftUI coords
                        
                        let windowWidth: CGFloat = 420
                        let windowHeight = screenRect.height
                        
                        let isLeft = rect.midX < fullScreenBounds.midX
                        let windowX = isLeft ? screenRect.maxX - windowWidth : screenRect.minX
                        let windowY = screenRect.minY
                        let targetWindowRect = NSRect(x: windowX, y: windowY, width: windowWidth, height: windowHeight)
                        
                        // 2. Open Main Window there immediately
                        self.mainWindow?.setFrame(targetWindowRect, display: true)
                        self.mainWindow?.makeKeyAndOrderFront(nil)
                        
                        // 3. Animate the image to the main window
                        manager.isAnimatingToWindow = true
                        
                        // Calculate target position in overlay window's coordinates (SwiftUI top-left)
                        let targetGlobalX = windowX + windowWidth / 2.0
                        let targetGlobalY = windowY + windowHeight / 2.0
                        let targetPos = manager.toLocal(CGPoint(x: targetGlobalX, y: targetGlobalY))
                        
                        // Scale down to fit inside the window width nicely
                        let targetScale = min(1.0, (windowWidth - 60) / rect.width)
                        
                        // Curved animation (X and Y with different easing)
                        withAnimation(.easeIn(duration: 0.6)) {
                            manager.imagePosition.x = targetPos.x
                        }
                        withAnimation(.easeOut(duration: 0.6)) {
                            manager.imagePosition.y = targetPos.y
                            manager.imageScale = targetScale
                        }
                        
                        // 4. Wait for curved animation to finish, then proceed with API call
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) {
                            if self.useMockData {
                                try? FileManager.default.removeItem(atPath: tempFilePath)
                                self.loadMockData()
                            } else {
                                self.uploadToSerpApi(filePath: tempFilePath)
                            }
                            
                            // Close capture window
                            self.closeCaptureWindow()
                        }
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
                Text("Nexus (SerpApi)").font(.custom("Geist", size: 16).weight(.semibold))
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
                        .font(.custom("Geist", size: 60))
                        .foregroundColor(.secondary)
                        .padding()
                    Text("Ready.")
                        .font(.custom("Geist", size: 16).weight(.semibold))
                    Text("Click 'Take Snapshot' to search using SerpApi.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Results UI
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Overview")
                        .font(.custom("Geist", size: 16).weight(.semibold))
                        .padding(.top)
                    
                    Text(scraper.overview)
                        .font(.custom("Geist", size: 14).weight(.regular))
                        .foregroundColor(.secondary)
                    
                    Text("Visual Matches")
                        .font(.custom("Geist", size: 16).weight(.semibold))
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
                                            .font(.custom("Geist", size: 12).weight(.regular))
                                            .fontWeight(.semibold)
                                            .foregroundColor(.secondary)
                                        
                                        Text(match.title ?? "No title")
                                            .font(.custom("Geist", size: 12).weight(.regular))
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
import Cocoa
import ApplicationServices
import Vision

class TextEditManager: ObservableObject {
    static let shared = TextEditManager()
    
    @Published var isProcessing = false
    @Published var overlayText = ""
    @Published var errorMessage = ""
    
    // Store the focused element
    var currentElement: AXUIElement?
    var originalText: String = ""
    var wasTextSelected: Bool = false
    
    func getFocusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)
        if err == .success, let focusedElement = focusedElement {
            return (focusedElement as! AXUIElement)
        }
        return nil
    }
    
    func isTextField(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        
        // 1. Check native settable fields
        var settable: DarwinBoolean = false
        if AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue {
            return true
        }
        
        // 2. Check selected text in Accessibility
        var selectedText: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
        if let sel = selectedText as? String, !sel.isEmpty {
            return true
        }
        
        if let roleStr = role as? String {
            if roleStr == kAXTextFieldRole || roleStr == kAXTextAreaRole || roleStr == "AXComboBox" || roleStr == "AXSearchField" {
                return true
            }
        }
        
        // 3. Robust Clipboard Fallback
        // Save full pasteboard
        let pasteboard = NSPasteboard.general
        let oldItems = pasteboard.pasteboardItems?.map { item -> NSPasteboardItem in
            let newItem = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    newItem.setData(data, forType: type)
                }
            }
            return newItem
        }
        
        pasteboard.clearContents()
        simulateKeystroke(keyCode: 8, flags: .maskCommand) // Cmd+C
        usleep(150_000)
        
        var foundText = false
        if let copied = pasteboard.string(forType: .string), !copied.isEmpty {
            foundText = true
        }
        
        // Restore full pasteboard
        if let items = oldItems {
            pasteboard.clearContents()
            pasteboard.writeObjects(items)
        }
        
        return foundText
    }
    
        func getCursorPosition(element: AXUIElement?) -> CGPoint? {
        func log(_ msg: String) {
            let path = "/tmp/nexus_debug.txt"
            if let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((msg + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (msg + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        
        guard let element = element else { 
            log("getCursorPosition: element is nil")
            return nil 
        }
        
        // 1. Try exact text cursor bounds
        var selectedRangeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRangeValue) == .success {
            var boundsValue: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString, selectedRangeValue!, &boundsValue) == .success {
                let axValue = boundsValue as! AXValue
                var rect = CGRect.zero
                if AXValueGetValue(axValue, .cgRect, &rect) {
                    log("getCursorPosition: found bounds \(rect)")
                    return CGPoint(x: rect.midX, y: rect.minY) // Top center of selection
                }
            }
        }
        
        log("getCursorPosition: failed to find exact cursor bounds")
        return nil
    }

    func extractText(from element: AXUIElement?) -> String? {
        if let element = element {
            var selectedText: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedText)
            if let selText = selectedText as? String, !selText.isEmpty {
                self.wasTextSelected = true
                return selText
            }
            
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
            if let text = value as? String, !text.isEmpty {
                self.wasTextSelected = false
                return text
            }
        }
        
        // Fallback to Clipboard (Cmd+C) if AXUI fails (e.g. in Electron apps)
        let pasteboard = NSPasteboard.general
        let oldString = pasteboard.string(forType: .string)
        pasteboard.clearContents()
        
        simulateKeystroke(keyCode: 8, flags: .maskCommand) // Cmd+C
        usleep(100_000) // 100ms
        
        if let copied = pasteboard.string(forType: .string), !copied.isEmpty {
            self.wasTextSelected = true
            if let old = oldString { pasteboard.setString(old, forType: .string) }
            return copied
        }
        
        // If nothing was selected, Select All then Copy
        simulateKeystroke(keyCode: 0, flags: .maskCommand) // Cmd+A
        usleep(150_000)
        simulateKeystroke(keyCode: 8, flags: .maskCommand) // Cmd+C
        usleep(100_000)
        
        if let copied = pasteboard.string(forType: .string), !copied.isEmpty {
            self.wasTextSelected = false
            if let old = oldString { pasteboard.setString(old, forType: .string) }
            return copied
        }
        
        if let old = oldString { pasteboard.setString(old, forType: .string) }
        return nil
    }
    
    func simulateKeystroke(keyCode: CGKeyCode, flags: CGEventFlags? = nil) {
        let src = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: src, virtualKey: keyCode, keyDown: false)
        if let flags = flags {
            keyDown?.flags = flags
            keyUp?.flags = flags
        }
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
    
    func replaceText(newText: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)
        
        // If text wasn't originally selected, we want to replace everything
        if !self.wasTextSelected {
            simulateKeystroke(keyCode: 0, flags: .maskCommand) // Cmd+A
            usleep(150_000) // 50ms wait
        }
        
        // Paste the text (this will overwrite the selection)
        simulateKeystroke(keyCode: 9, flags: .maskCommand) // Cmd+V
        usleep(100_000) // 100ms wait
    }
    
    var extractedText: String? = nil
    var menuPosition: CGPoint = .zero



    func findHighlightPosition(element: AXUIElement, screenHeight: CGFloat) -> CGPoint? {
        func log(_ msg: String) {
            let path = "/tmp/nexus_debug.txt"
            if let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((msg + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (msg + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        
        log("Finding highlight...")
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var elementPos = CGPoint.zero
        var elementSize = CGSize.zero
        var usingFallbackBounds = false
        
        // 1. Try to get exact input element bounds
        let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef)
        let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef)
        
        if posErr == .success && sizeErr == .success,
           let axPos = posRef as! AXValue?, let axSize = sizeRef as! AXValue? {
            AXValueGetValue(axPos, .cgPoint, &elementPos)
            AXValueGetValue(axSize, .cgSize, &elementSize)
        } 
        
        // 2. If it failed, or size is suspicious (e.g. 0x0), try to get the parent Window bounds!
        if elementSize.width <= 0 || elementSize.height <= 0 {
            log("Input box bounds unavailable. Falling back to Window bounds.")
            usingFallbackBounds = true
            
            var windowRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
               let windowElement = windowRef as! AXUIElement? {
                let wPosErr = AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef)
                let wSizeErr = AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef)
                
                if wPosErr == .success && wSizeErr == .success,
                   let axPos = posRef as! AXValue?, let axSize = sizeRef as! AXValue? {
                    AXValueGetValue(axPos, .cgPoint, &elementPos)
                    AXValueGetValue(axSize, .cgSize, &elementSize)
                }
            }
        }
        
        if elementSize.width <= 0 || elementSize.height <= 0 { 
            log("Window bounds also unavailable. Trying main screen bounds.")
            if let screen = NSScreen.main {
                // Note: screen.frame is bottom-left, we need top-left for our math.
                // But screencapture -R uses top-left coordinates! 
                // Let's just use the screen frame converted to top-left.
                let frame = screen.frame
                elementPos = CGPoint(x: frame.minX, y: 0) // rough approximation
                elementSize = frame.size
            } else {
                return nil
            }
        }
        
        log("Capture bounds: \(elementPos.x),\(elementPos.y) \(elementSize.width)x\(elementSize.height)")
        
        let rect = CGRect(origin: elementPos, size: elementSize)
        let tempFilePath = NSTemporaryDirectory().appending("nexus_temp_highlight.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)", tempFilePath]
        
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            log("Screencapture failed")
            return nil
        }
        
        guard let nsImage = NSImage(contentsOfFile: tempFilePath),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else { 
            log("Could not read image")
            return nil 
        }
        try? FileManager.default.removeItem(atPath: tempFilePath)
        
        let width = cgImage.width
        let height = cgImage.height
        log("Image size: \(width)x\(height)")
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        
        guard let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { 
            log("Context failed")
            return nil 
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0
        var foundCount = 0
        
        // For fallback we might find multiple blue things. Let's find the cluster of blue.
        // We'll track the bounding box of ALL blue pixels. If we scan the whole window, 
        // there might be a blue button. A blue button is usually small, a text highlight is usually wide.
        for y in 0..<height {
            for x in 0..<width {
                let byteIndex = (bytesPerRow * y) + x * bytesPerPixel
                let r = Int(rawData[byteIndex])
                let g = Int(rawData[byteIndex + 1])
                let b = Int(rawData[byteIndex + 2])
                
                // Blueish heuristic
                if b > r + 15 && b > g + 15 && b > 60 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    foundCount += 1
                }
            }
        }
        
        if foundCount > 10 { // Ensure it's not just a stray pixel
            log("Found blue bounding box: \(minX),\(minY) to \(maxX),\(maxY) with \(foundCount) pixels")
            let relativeMidX = CGFloat(minX + maxX) / 2.0 / CGFloat(width)
            let relativeMidY = CGFloat(minY + maxY) / 2.0 / CGFloat(height)
            
            let invertedRelativeMidY = 1.0 - relativeMidY
            
            let globalX = elementPos.x + relativeMidX * elementSize.width
            let globalY = screenHeight - (elementPos.y + invertedRelativeMidY * elementSize.height)
            log("Returning global pos: \(globalX), \(globalY)")
            return CGPoint(x: globalX, y: globalY)
        }
        log("No blue found")
        return nil
    }

    func identifyMenuPositionWithJev(apiKey: String, fullText: String, element: AXUIElement?, screenHeight: CGFloat) async -> CGPoint? {
        func log(_ msg: String) {
            let path = "/tmp/nexus_debug.txt"
            if let fileHandle = FileHandle(forWritingAtPath: path) {
                fileHandle.seekToEndOfFile()
                fileHandle.write((msg + "\n").data(using: .utf8)!)
                fileHandle.closeFile()
            } else {
                try? (msg + "\n").write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
        
        log("--- Starting OCR Menu Position ---")
        log("Target fullText: \(fullText)")
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        var elementPos = CGPoint.zero
        var elementSize = CGSize.zero
        
        if let element = element {
            if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posRef) == .success, let axPos = posRef as! AXValue? {
                AXValueGetValue(axPos, .cgPoint, &elementPos)
            }
            if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success, let axSize = sizeRef as! AXValue? {
                AXValueGetValue(axSize, .cgSize, &elementSize)
            }
            log("Initial element bounds: \(elementPos), \(elementSize)")
            
            if elementSize.width <= 0 || elementSize.height <= 0 {
                var windowRef: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowRef) == .success,
                   let windowElement = windowRef as! AXUIElement? {
                    if AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success, let axPos = posRef as! AXValue? {
                        AXValueGetValue(axPos, .cgPoint, &elementPos)
                    }
                    if AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success, let axSize = sizeRef as! AXValue? {
                        AXValueGetValue(axSize, .cgSize, &elementSize)
                    }
                    log("Fallback window bounds: \(elementPos), \(elementSize)")
                }
            }
        }
        
        if elementSize.width <= 0 || elementSize.height <= 0 {
            if let screen = NSScreen.main {
                let frame = screen.frame
                elementPos = CGPoint(x: frame.minX, y: 0)
                elementSize = frame.size
                log("Fallback screen bounds: \(elementPos), \(elementSize)")
            } else {
                log("Failed to get any bounds")
                return nil
            }
        }
        
        let rect = CGRect(origin: elementPos, size: elementSize)
        let tempFilePath = NSTemporaryDirectory().appending("nexus_ocr_vision.png")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", "\(rect.minX),\(rect.minY),\(rect.width),\(rect.height)", tempFilePath]
        try? process.run()
        process.waitUntilExit()
        
        var foundPos: CGPoint? = nil
        
        if let nsImage = NSImage(contentsOfFile: tempFilePath),
           let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            
            log("Captured image size: \(nsImage.size)")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let request = VNRecognizeTextRequest { req, err in
                    if let err = err {
                        log("VNRecognizeTextRequest error: \(err)")
                    }
                    if let results = req.results as? [VNRecognizedTextObservation] {
                        let targetText = fullText.lowercased()
                        let cleanTarget = targetText.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                        log("Clean target text: \(cleanTarget)")
                        
                        for obs in results {
                            if let topCandidate = obs.topCandidates(1).first {
                                let ocrText = topCandidate.string.lowercased()
                                let cleanOcr = ocrText.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                                
                                let isMatch = (!cleanOcr.isEmpty && !cleanTarget.isEmpty) && 
                                              ((cleanOcr.count >= 3 && cleanTarget.contains(cleanOcr)) || 
                                               (cleanTarget.count >= 3 && cleanOcr.contains(cleanTarget)) || 
                                               cleanOcr == cleanTarget)
                                
                                if isMatch {
                                    log("MATCH FOUND! OCR: \(ocrText)")
                                    let visionBBox = obs.boundingBox
                                    let pixelX = visionBBox.origin.x * elementSize.width
                                    let pixelY = (1.0 - visionBBox.origin.y - visionBBox.height) * elementSize.height
                                    let pixelWidth = visionBBox.width * elementSize.width
                                    
                                    let finalX = elementPos.x + pixelX + (pixelWidth / 2.0)
                                    let finalY = elementPos.y + pixelY // Top edge
                                    
                                    foundPos = CGPoint(x: finalX, y: finalY)
                                    log("Found position: \(foundPos!)")
                                    break
                                } else {
                                    // log("NO MATCH: \(cleanOcr)") // Too spammy, only uncomment if needed
                                }
                            }
                        }
                    }
                    continuation.resume()
                }
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                
                // FORCE CPU TO BYPASS NEURAL ENGINE E5 BUGS ON MACOS 14+
                request.usesCPUOnly = true
                
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                DispatchQueue.global(qos: .userInitiated).async {
                    try? handler.perform([request])
                }
            }
        } else {
            log("Failed to load image from \(tempFilePath)")
        }
        
        try? FileManager.default.removeItem(atPath: tempFilePath)
        log("Finished OCR. Returning: \(String(describing: foundPos))")
        return foundPos
    }

    func processText(action: String, customPrompt: String? = nil, completion: @escaping (Bool, String?) -> Void) {
        guard let text = extractedText else {
            self.errorMessage = "No text was selected or found."
            completion(false, nil)
            return
        }
        
        self.originalText = text
        self.isProcessing = true
        self.errorMessage = ""
        
        Task {
            do {
                let result = try await callGemini(text: text, action: action, customPrompt: customPrompt)
                
                DispatchQueue.main.async {
                    if result.hasPrefix("ERROR:") {
                        self.errorMessage = result.replacingOccurrences(of: "ERROR:", with: "").trimmingCharacters(in: .whitespaces)
                        self.isProcessing = false
                        completion(false, nil)
                    } else {
                        self.isProcessing = false
                        // Return the text so the UI can close FIRST, then paste it
                        completion(true, result.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Failed to reach Gemini: \(error.localizedDescription)"
                    self.isProcessing = false
                    completion(false, nil)
                }
            }
        }
    }
    
    func callGemini(text: String, action: String, customPrompt: String?) async throws -> String {
        let delegate = NSApplication.shared.delegate as? AppDelegate
        let geminiApiKey: String = delegate?.scraper.geminiApiKey ?? ProcessInfo.processInfo.environment["GEMINI_API_KEY"] ?? ""
        if geminiApiKey.isEmpty {
            return "ERROR: GEMINI_API_KEY environment variable is missing."
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=\(geminiApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var systemPrompt = ""
        if action == "rephrase" {
            systemPrompt = "You are a text editor. Rephrase the following text to make it clearer and more natural. Output ONLY the rephrased text, nothing else."
        } else if action == "formalize" {
            systemPrompt = "You are a text editor. Rewrite the following text to be more formal and professional. Output ONLY the rewritten text, nothing else."
        } else if action == "custom", let cp = customPrompt {
            systemPrompt = """
            You are a strict text editor. You are given a user text and an edit instruction.
            Instruction: "\(cp)"
            
            If the instruction is NOT a text edit operation (e.g., if it asks a general question like 'what is the capital of France' or 'write a poem'), you MUST output exactly: ERROR: The prompt must be a text edit operation.
            Otherwise, apply the instruction to the text and output ONLY the modified text, nothing else.
            """
        }
        
        let fullPrompt = "\(systemPrompt)\n\nText: \(text)"
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": fullPrompt]
                    ]
                ]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let candidates = json["candidates"] as? [[String: Any]],
           let firstCandidate = candidates.first,
           let content = firstCandidate["content"] as? [String: Any],
           let parts = content["parts"] as? [[String: Any]],
           let firstPart = parts.first,
           let responseText = firstPart["text"] as? String {
            return responseText
        }
        
        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
             return "ERROR: Gemini API Error: \(message)"
        }
        
        throw URLError(.badServerResponse)
    }
}

struct TextEditGlassButton: View {
    var systemIcon: String
    var title: String? = nil
    var action: () -> Void
    var isCloseButton: Bool = false
    
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if let t = title {
                    Text(t)
                        .font(.custom("Geist", size: 14).weight(.medium))
                        .foregroundColor(.white)
                } else {
                    if systemIcon.hasPrefix("phosphor_") {
                        Image(systemIcon)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 18, height: 18)
                            .foregroundColor(isCloseButton ? .red : .white)
                    } else {
                        Image(systemName: systemIcon)
                            .font(.custom("Geist", size: 16).weight(.semibold))
                            .foregroundColor(isCloseButton ? .red : .white)
                    }
                }
            }
            .frame(width: title != nil ? 90 : 44, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isCloseButton ? Color.red.opacity(isHovering ? 0.8 : 0.4) : Color.black.opacity(isHovering ? 0.6 : 0.4))
        )
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1))
        .shadow(color: .black.opacity(0.2), radius: 5)
        .focusable(false)
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}


struct TextEditOverlayView: View {
    var onCancel: () -> Void
    @State private var isVisible = false
    @State private var buttonsExpanded = false
    @State private var dropYOffset: CGFloat = -20
    @Namespace private var glassSpace
    
    @State private var isEditExpanded = false
    @State private var customPrompt = ""
    @ObservedObject var manager = TextEditManager.shared
    
    var body: some View {
        ZStack(alignment: .top) {
            
            // Removed Color.clear to allow clicks to pass through
            
            VStack {
                ZStack(alignment: .top) {
                    GlassEffectContainer(spacing: 12) {
                        HStack(spacing: 12) {
                            if !isEditExpanded {
                                TextEditGlassButton(systemIcon: "phosphor_translate", title: "Rephrase", action: {
                                    manager.processText(action: "rephrase") { success, newText in
                                        if success, let newText = newText { 
                                            onCancel()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                manager.replaceText(newText: newText)
                                            }
                                        }
                                    }
                                })
                                .glassEffectID("rephrase", in: glassSpace)
                                .transition(.scale.combined(with: .opacity))
                                
                                TextEditGlassButton(systemIcon: "briefcase", title: "Formalize", action: {
                                    manager.processText(action: "formalize") { success, newText in
                                        if success, let newText = newText { 
                                            onCancel()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                manager.replaceText(newText: newText)
                                            }
                                        }
                                    }
                                })
                                .glassEffectID("formalize", in: glassSpace)
                                .transition(.scale.combined(with: .opacity))
                            }
                            
                            if isEditExpanded {
                                // Custom Input
                                HStack {
                                    TextField("Edit instruction...", text: $customPrompt, axis: .vertical)
                                        .lineLimit(1...6)
                                        .textFieldStyle(PlainTextFieldStyle())
                                        .font(.custom("Geist", size: 14))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .mask(
                                            LinearGradient(
                                                gradient: Gradient(stops: [
                                                    .init(color: .clear, location: 0.0),
                                                    .init(color: .black, location: 0.15),
                                                    .init(color: .black, location: 0.85),
                                                    .init(color: .clear, location: 1.0)
                                                ]),
                                                startPoint: .top,
                                                endPoint: .bottom
                                            )
                                        )
                                        .onSubmit {
                                            manager.processText(action: "custom", customPrompt: customPrompt) { success, newText in
                                                if success, let newText = newText { 
                                                    onCancel()
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                        manager.replaceText(newText: newText)
                                                    }
                                                }
                                            }
                                        }
                                    
                                    Button(action: {
                                        manager.processText(action: "custom", customPrompt: customPrompt) { success, newText in
                                            if success, let newText = newText { 
                                                onCancel()
                                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                                    manager.replaceText(newText: newText)
                                                }
                                            }
                                        }
                                    }) {
                                        Image(systemName: "arrow.up.circle.fill")
                                            .foregroundColor(.white)
                                            .font(.custom("Geist", size: 20))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .padding(.trailing, 8)
                                }
                                .frame(width: 200).frame(minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black.opacity(0.4)))
                                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.3), lineWidth: 1))
                                .shadow(color: .black.opacity(0.2), radius: 5)
                                .matchedGeometryEffect(id: "edit_m", in: glassSpace)
                            } else {
                                TextEditGlassButton(systemIcon: "phosphor_cursor-text", action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isEditExpanded.toggle()
                                    }
                                })
                                .glassEffectID("edit", in: glassSpace)
                                .matchedGeometryEffect(id: "edit_m", in: glassSpace)
                            }
                            
                            if !isEditExpanded {
                                TextEditGlassButton(systemIcon: "phosphor_x", action: { onCancel() }, isCloseButton: true)
                                    .glassEffectID("close", in: glassSpace)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                TextEditGlassButton(systemIcon: "phosphor_x", action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isEditExpanded = false
                                        customPrompt = ""
                                    }
                                }, isCloseButton: true)
                                    .glassEffectID("close", in: glassSpace)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                    }
                    .scaleEffect(buttonsExpanded ? 1.0 : 0.01, anchor: .bottom)
                    .opacity(buttonsExpanded ? 1.0 : 0.0)
                    
                    if manager.isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.top, 20)
                    }
                    
                    if !manager.errorMessage.isEmpty {
                        Text(manager.errorMessage)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(.top, 20)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.65)) {
                dropYOffset = 20
                buttonsExpanded = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.isEqual(NSApplication.shared.keyWindow) == false {
                if window is CaptureWindow && window.frame.size.width == 400 {
                    onCancel()
                }
            }
        }
    }
}

