import Cocoa
import SwiftUI
import Foundation
import Combine
import QuartzCore
import CoreImage
import CoreImage.CIFilterBuiltins

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
                for i in 0..<7 {
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
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? -145 : 0, y: dropYOffset).tag(1)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? -87 : 0, y: dropYOffset).tag(2)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? -29 : 0, y: dropYOffset).tag(3)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 29 : 0, y: dropYOffset).tag(4)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 87 : 0, y: dropYOffset).tag(5)
            RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 145 : 0, y: dropYOffset).tag(6)
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
    @State private var handlesOpacity: Double = 1.0
    @State private var contentOpacity: Double = 1.0
    
    var body: some View {
        let cSize = min(24, min(rect.width / 3, rect.height / 3))
        let thick: CGFloat = 4
        let col = Color.white.opacity(0.9)
        let sh = Color.black.opacity(0.3)
        
        ZStack {
            if let img = manager.capturedImage {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            } else {
                Color.clear
            }
            
            // Screen grab handles and liquid glass borders that distort and dissolve with the ripple
            ZStack {
                Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
                
                CornerShape(radius: cornerRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round))
                    .frame(width: cSize, height: cSize).offset(x: -rect.width/2 + cSize/2, y: -rect.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: cornerRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(90))
                    .frame(width: cSize, height: cSize).offset(x: rect.width/2 - cSize/2, y: -rect.height/2 + cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: cornerRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(180))
                    .frame(width: cSize, height: cSize).offset(x: rect.width/2 - cSize/2, y: rect.height/2 - cSize/2).shadow(color: sh, radius: 2)
                CornerShape(radius: cornerRadius).stroke(col, style: StrokeStyle(lineWidth: thick, lineCap: .round, lineJoin: .round)).rotationEffect(.degrees(270))
                    .frame(width: cSize, height: cSize).offset(x: -rect.width/2 + cSize/2, y: rect.height/2 - cSize/2).shadow(color: sh, radius: 2)
            }
            .opacity(handlesOpacity)
        }
        .opacity(contentOpacity)
        .frame(width: rect.width, height: rect.height)
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
        .onAppear {
            withAnimation(.linear(duration: 1.5)) {
                time = 1.5
            }
            withAnimation(.easeOut(duration: 0.35)) {
                handlesOpacity = 0.0
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                contentOpacity = 0.0
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
                
                if !manager.isProcessing {
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
                
                if manager.isProcessing {
                    RippleDistortionView(rect: r, cornerRadius: dynamicRadius, manager: manager)
                        .frame(width: r.width, height: r.height)
                        .transition(.identity) // Clean seamless swap
                }
            }
            .position(CGPoint(x: r.midX, y: r.midY))
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
                                .offset(x: buttonsExpanded ? -145 : 0)
                                .glassEffectID("search", in: glassSpace)
                            
                            GlassMenuButton(
                                icon: "phosphor_clock-counter-clockwise",
                                action: {
                                    closeWithAnimation()
                                    if let delegate = NSApplication.shared.delegate as? AppDelegate {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                            delegate.scraper.mainWindow?.makeKeyAndOrderFront(nil)
                                            NSApp.activate(ignoringOtherApps: true)
                                        }
                                    }
                                },
                                manager: manager,
                                isBlackDot: !buttonsExpanded
                            )
                            .offset(x: buttonsExpanded ? -87 : 0)
                            .glassEffectID("history", in: glassSpace)
                            
                            GlassMenuButton(icon: "phosphor_music-notes", action: {}, manager: manager, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? -29 : 0)
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
                            .offset(x: buttonsExpanded ? 29 : 0)
                            .glassEffectID("center", in: glassSpace)
                            
                            GlassMenuButton(icon: "phosphor_cursor-text", action: {}, manager: manager, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 87 : 0)
                                .glassEffectID("text", in: glassSpace)
                            
                            GlassMenuButton(icon: "phosphor_x", action: { closeWithAnimation() }, manager: manager, isCloseButton: true, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 145 : 0)
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
    @Published var isOverviewLoading: Bool = false
    private var overviewTask: Task<Void, Never>? = nil
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
    @Published var capturedImage: NSImage? = nil
    
    var useMockData: Bool = false
    var serpApiKey: String {
        AppSecrets.serpApiKey
    }
    var geminiApiKey: String {
        AppSecrets.geminiApiKey
    }
    
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
            self.overviewTask?.cancel()
            self.mainWindow?.orderOut(nil) // Hide main window while capturing
            self.isScraping = true
            self.statusText = self.useMockData ? "Capturing (Mock Mode)..." : "Capturing screen..."
            self.matches = []
            self.overview = ""
            self.isOverviewLoading = false
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
        process.arguments = ["-x", "-R", "\(Int(rect.minX)),\(Int(rect.minY)),\(Int(rect.width)),\(Int(rect.height))", tempFilePath]
        
        do {
            try process.run()
            process.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    if FileManager.default.fileExists(atPath: tempFilePath), let img = NSImage(contentsOfFile: tempFilePath) {
                        manager.capturedImage = img
                        self?.capturedImage = img
                        
                        // Kick off Gemini streaming overview immediately in parallel!
                        if self?.useMockData == false {
                            self?.generateGeminiOverviewStream(image: img)
                        }
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
                    
                    // Allow the ripple distortion & dissolve to play out (0.75s)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
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
                        
                        // 3. Close capture overlay immediately (no flying screenshot movement)
                        self.closeCaptureWindow()
                        
                        // 4. Start search immediately
                        if self.useMockData {
                            try? FileManager.default.removeItem(atPath: tempFilePath)
                            self.loadMockData()
                        } else {
                            self.uploadToSerpApi(filePath: tempFilePath)
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
    
    private func compressImageUnder500KB(data: Data) -> (data: Data, mimeType: String, filename: String) {
        guard let image = NSImage(data: data) else {
            return (data, "image/png", "image.png")
        }
        
        var targetSize = image.size
        let maxDim: CGFloat = 1600
        if max(targetSize.width, targetSize.height) > maxDim {
            let ratio = maxDim / max(targetSize.width, targetSize.height)
            targetSize = NSSize(width: targetSize.width * ratio, height: targetSize.height * ratio)
        }
        
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else {
            return (data, "image/png", "image.png")
        }
        
        for factor in [0.8, 0.65, 0.5, 0.35, 0.2] {
            if let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: factor]), jpeg.count < 450_000 {
                return (jpeg, "image/jpeg", "image.jpg")
            }
        }
        
        let smallSize = NSSize(width: min(targetSize.width, 900), height: min(targetSize.height, 900))
        let smallResized = NSImage(size: smallSize)
        smallResized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: smallSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        smallResized.unlockFocus()
        if let smallTiff = smallResized.tiffRepresentation,
           let smallBitmap = NSBitmapImageRep(data: smallTiff),
           let smallJpeg = smallBitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.5]) {
            return (smallJpeg, "image/jpeg", "image.jpg")
        }
        
        return (data, "image/png", "image.png")
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
        
        let payload = compressImageUnder500KB(data: imageData)
        
        var request = URLRequest(url: URL(string: "https://serpapi.com/image")!)
        request.httpMethod = "POST"
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"api_key\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(serpApiKey)\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(payload.filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(payload.mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(payload.data)
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
                    withAnimation(.easeOut(duration: 0.35)) {
                        self?.matches = serpResponse.visual_matches ?? []
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
    
    private func prepareImageForGemini(image: NSImage) -> (base64: String, mimeType: String)? {
        var targetSize = image.size
        let maxDim: CGFloat = 800
        if max(targetSize.width, targetSize.height) > maxDim {
            let ratio = maxDim / max(targetSize.width, targetSize.height)
            targetSize = NSSize(width: max(1, targetSize.width * ratio), height: max(1, targetSize.height * ratio))
        }
        
        let resized = NSImage(size: targetSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: targetSize), from: NSRect(origin: .zero, size: image.size), operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        
        guard let tiff = resized.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return (jpeg.base64EncodedString(), "image/jpeg")
    }
    
    func generateGeminiOverviewStream(image: NSImage) {
        overviewTask?.cancel()
        
        guard !geminiApiKey.isEmpty else {
            DispatchQueue.main.async {
                self.isOverviewLoading = false
            }
            return
        }
        
        guard let payload = prepareImageForGemini(image: image) else {
            DispatchQueue.main.async {
                self.isOverviewLoading = false
            }
            return
        }
        
        DispatchQueue.main.async {
            self.overview = ""
            self.isOverviewLoading = true
        }
        
        let prompt = "Analyze this image and identify what is shown. Provide a concise, clear, and helpful overview (1-2 sentences) of what it is, its key features, and context."
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:streamGenerateContent?alt=sse&key=\(geminiApiKey)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": prompt],
                        ["inlineData": [
                            "mimeType": payload.mimeType,
                            "data": payload.base64
                        ]]
                    ]
                ]
            ],
            "generationConfig": [
                "thinkingConfig": [
                    "thinkingBudget": 0
                ]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: requestBody)
        
        overviewTask = Task { [weak self] in
            do {
                let (bytes, response) = try await URLSession.shared.bytes(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                    print("⚠️ Gemini Overview HTTP Error: \(http.statusCode)")
                    await MainActor.run {
                        self?.isOverviewLoading = false
                    }
                    return
                }
                
                for try await line in bytes.lines {
                    guard !Task.isCancelled else { return }
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed.hasPrefix("data:") else { continue }
                    let jsonStr = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
                    if jsonStr.isEmpty || jsonStr == "[DONE]" { continue }
                    
                    guard let data = jsonStr.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let candidates = json["candidates"] as? [[String: Any]],
                          let first = candidates.first,
                          let content = first["content"] as? [String: Any],
                          let parts = content["parts"] as? [[String: Any]] else {
                        continue
                    }
                    
                    for part in parts {
                        if let text = part["text"] as? String, !text.isEmpty {
                            await MainActor.run {
                                self?.overview.append(text)
                            }
                        }
                    }
                }
                
                await MainActor.run {
                    self?.isOverviewLoading = false
                }
            } catch {
                print("⚠️ Gemini Overview Stream Error: \(error.localizedDescription)")
                await MainActor.run {
                    self?.isOverviewLoading = false
                }
            }
        }
    }
    
    private func loadMockData() {
        self.overview = ""
        self.isOverviewLoading = true
        
        let fullMock = "Based on the visual matches, this appears to be the new **Apple MacBook Pro** featuring the **M3 Max** chip in the Space Black color finish."
        let words = fullMock.split(separator: " ").map(String.init)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            var idx = 0
            Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] t in
                guard let self = self else { t.invalidate(); return }
                if idx < words.count {
                    let chunk = words[idx..<min(idx + 2, words.count)].joined(separator: " ")
                    self.overview += (self.overview.isEmpty ? "" : " ") + chunk
                    idx += 2
                } else {
                    t.invalidate()
                    self.isOverviewLoading = false
                }
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.35)) {
                self.matches = [
                    VisualMatch(title: "Apple MacBook Pro M3 Max - 16-inch", source: "Apple", link: "https://apple.com/macbook-pro", thumbnail: "https://store.storeimages.cdn-apple.com/4982/as-images.apple.com/is/mbp16-spaceblack-select-202310?wid=904&hei=840&fmt=jpeg&qlt=90&.v=1698169226604"),
                    VisualMatch(title: "MacBook Pro 16\" Space Black Review", source: "The Verge", link: "https://theverge.com", thumbnail: "https://cdn.vox-cdn.com/thumbor/n4J1YF5C8a17kQG4R4630lW_2K4=/0x0:2040x1360/2000x1333/filters:focal(1020x680:1021x681)/cdn.vox-cdn.com/uploads/chorus_asset/file/25061698/236773_Apple_MacBook_Pro_16_inch_M3_Max_AKrales_0023.jpg"),
                    VisualMatch(title: "M3 Max vs M2 Max: Which MacBook Pro is Right for You?", source: "MacRumors", link: "https://macrumors.com", thumbnail: "https://images.macrumors.com/t/2c89Fv2p0kHw-vO0l8U0L8X0Z0=/1600x/article-new/2023/10/MacBook-Pro-M3-Space-Black-Feature.jpg"),
                    VisualMatch(title: "Space Black MacBook Pro: Fingerprint Resistant?", source: "9to5Mac", link: "https://9to5mac.com", thumbnail: "https://i0.wp.com/9to5mac.com/wp-content/uploads/sites/6/2023/11/space-black-macbook-pro-1.jpg?w=1500&quality=82&strip=all&ssl=1")
                ]
                self.isScraping = false
            }
        }
    }
}

// MARK: - Variable Blur (CAFilter implementation adapted from nikstar/VariableBlur)

public enum VariableBlurDirection {
    case blurredTopClearBottom
    case blurredBottomClearTop
}

public struct VariableBlurView: NSViewRepresentable {
    public var maxBlurRadius: CGFloat = 20
    public var direction: VariableBlurDirection = .blurredTopClearBottom
    public var startOffset: CGFloat = 0
    
    public init(maxBlurRadius: CGFloat = 20, direction: VariableBlurDirection = .blurredTopClearBottom, startOffset: CGFloat = 0) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
    }
    
    public func makeNSView(context: Context) -> VariableBlurNSView {
        VariableBlurNSView(maxBlurRadius: maxBlurRadius, direction: direction, startOffset: startOffset)
    }
    
    public func updateNSView(_ nsView: VariableBlurNSView, context: Context) {
        nsView.update(maxBlurRadius: maxBlurRadius, direction: direction, startOffset: startOffset)
    }
}

open class VariableBlurNSView: NSView {
    private var maxBlurRadius: CGFloat
    private var direction: VariableBlurDirection
    private var startOffset: CGFloat
    
    public init(maxBlurRadius: CGFloat = 20, direction: VariableBlurDirection = .blurredTopClearBottom, startOffset: CGFloat = 0) {
        self.maxBlurRadius = maxBlurRadius
        self.direction = direction
        self.startOffset = startOffset
        super.init(frame: .zero)
        
        self.wantsLayer = true
        applyVariableBlur()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func makeBackingLayer() -> CALayer {
        if let LayerCls = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            return LayerCls.init()
        }
        return super.makeBackingLayer()
    }
    
    public func update(maxBlurRadius: CGFloat, direction: VariableBlurDirection, startOffset: CGFloat) {
        if self.maxBlurRadius != maxBlurRadius || self.direction != direction || self.startOffset != startOffset {
            self.maxBlurRadius = maxBlurRadius
            self.direction = direction
            self.startOffset = startOffset
            applyVariableBlur()
        }
    }
    
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window = window, let layer = self.layer {
            layer.setValue(window.backingScaleFactor, forKey: "scale")
            layer.contentsScale = window.backingScaleFactor
        }
    }
    
    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window = window, let layer = self.layer {
            layer.setValue(window.backingScaleFactor, forKey: "scale")
            layer.contentsScale = window.backingScaleFactor
        }
    }
    
    private func applyVariableBlur() {
        guard let layer = self.layer else { return }
        
        let clsName = String("retliFAC".reversed())
        guard let Cls = NSClassFromString(clsName) as? NSObject.Type else {
            return
        }
        let selName = String(":epyThtiWretlif".reversed())
        guard let variableBlur = Cls.self.perform(NSSelectorFromString(selName), with: "variableBlur")?.takeUnretainedValue() as? NSObject else {
            return
        }
        
        let gradientImage = makeGradientImage(startOffset: startOffset, direction: direction)
        
        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(gradientImage, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")
        
        layer.filters = [variableBlur]
    }
    
    private func makeGradientImage(width: CGFloat = 100, height: CGFloat = 100, startOffset: CGFloat, direction: VariableBlurDirection) -> CGImage? {
        let ciGradientFilter = CIFilter.smoothLinearGradient()
        ciGradientFilter.color0 = CIColor.black
        ciGradientFilter.color1 = CIColor.clear
        ciGradientFilter.point0 = CGPoint(x: 0, y: height)
        ciGradientFilter.point1 = CGPoint(x: 0, y: startOffset * height)
        if case .blurredBottomClearTop = direction {
            ciGradientFilter.point0.y = 0
            ciGradientFilter.point1.y = height - ciGradientFilter.point1.y
        }
        guard let output = ciGradientFilter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: CGRect(x: 0, y: 0, width: width, height: height))
    }
    
    open override func hitTest(_ point: NSPoint) -> NSView? {
        return nil // Non-blocking: let mouse interactions pass smoothly to underlying views
    }
}

// MARK: - Border Glow Wave Animation
struct BorderBeamView: View {
    var beamColor: Color = Color(red: 0.35, green: 0.65, blue: 1.0)
    var duration: Double = 2.8
    var lineWidth: CGFloat = 2.5
    var cornerRadius: CGFloat = 20.0

    var body: some View {
        TimelineView(.animation) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let angle = (time / duration).truncatingRemainder(dividingBy: 1.0) * 360.0
            let breath = 0.88 + 0.12 * sin(time * 2.2)

            // Spectrum colors representing continuous shifts in wavelength:
            let cViolet = Color(red: 0.52, green: 0.42, blue: 1.00) // Shorter wavelength (~430nm, indigo/violet)
            let cRoyal  = Color(red: 0.28, green: 0.50, blue: 1.00) // Mid-short wavelength (~460nm, royal blue)
            let cSky    = Color(red: 0.24, green: 0.68, blue: 1.00) // Mid wavelength (~475nm, cerulean/sky)
            let cCyan   = Color(red: 0.12, green: 0.86, blue: 0.96) // Longer wavelength (~500nm, electric aqua)
            let cPeak   = Color(red: 0.92, green: 0.98, blue: 1.00) // Peak luminescence (pure energy highlight)

            // 2-wave harmonic cycle across 360 degrees:
            // The entire perimeter remains actively glowing at all times (min opacity >= 0.40),
            // while waves of varying wavelength (color spectrum) and intensity rotate smoothly around the edge.
            let waveGradient = AngularGradient(
                gradient: Gradient(stops: [
                    // Wave 1 Trough: Short wavelength (violet-blue), baseline ambient intensity
                    .init(color: cViolet.opacity(0.42), location: 0.00),
                    // Ascending: Shifting toward sky blue, rising intensity
                    .init(color: cRoyal.opacity(0.60),  location: 0.10),
                    .init(color: cSky.opacity(0.78),    location: 0.18),
                    // Wave 1 Crest: Long wavelength (cyan) + intense luminous core
                    .init(color: cCyan.opacity(0.95),   location: 0.25),
                    .init(color: cPeak.opacity(1.00),   location: 0.28),
                    .init(color: cCyan.opacity(0.95),   location: 0.31),
                    // Descending: Softening back toward royal blue
                    .init(color: cSky.opacity(0.72),    location: 0.38),
                    .init(color: cRoyal.opacity(0.55),  location: 0.44),
                    
                    // Wave 2 Trough: Short wavelength (violet-blue), baseline ambient intensity
                    .init(color: cViolet.opacity(0.40), location: 0.50),
                    // Ascending: Shifting toward sky blue, rising intensity
                    .init(color: cRoyal.opacity(0.60),  location: 0.60),
                    .init(color: cSky.opacity(0.78),    location: 0.68),
                    // Wave 2 Crest: Long wavelength (cyan) + intense luminous core
                    .init(color: cCyan.opacity(0.95),   location: 0.75),
                    .init(color: cPeak.opacity(1.00),   location: 0.78),
                    .init(color: cCyan.opacity(0.95),   location: 0.81),
                    // Descending: Softening back toward royal blue
                    .init(color: cSky.opacity(0.72),    location: 0.88),
                    .init(color: cRoyal.opacity(0.55),  location: 0.94),
                    
                    // Seamless loop matching 0.00 exactly
                    .init(color: cViolet.opacity(0.42), location: 1.00)
                ]),
                center: .center,
                startAngle: .degrees(angle),
                endAngle: .degrees(angle + 360)
            )

            ZStack {
                // 1. Full perimeter ambient glow (ensures complete edge is actively glowing at all times)
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(beamColor.opacity(0.28 * breath), lineWidth: lineWidth + 4)
                    .blur(radius: 7)

                // 2. Wide rotating wavelength & intensity diffuse halo
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(waveGradient, lineWidth: lineWidth + 6)
                    .blur(radius: 8)
                    .opacity(0.85 * breath)

                // 3. Focused rotating wavelength & intensity mid-glow
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(waveGradient, lineWidth: lineWidth + 2)
                    .blur(radius: 3)
                    .opacity(0.90 * breath)

                // 4. Sharp crisp luminous electric core
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(waveGradient, lineWidth: lineWidth)
                    .shadow(color: beamColor.opacity(0.7 * breath), radius: 5)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

// MARK: - Streaming Blur Text Renderer
@available(macOS 14.0, *)
struct StreamingBlurTextRenderer: TextRenderer {
    var revealedCount: Int
    var totalChars: Int
    var blurWindow: Int = 6
    
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        if revealedCount >= totalChars + blurWindow {
            for line in layout {
                context.draw(line)
            }
            return
        }
        
        var glyphIndex = 0
        for line in layout {
            for run in line {
                for glyph in run {
                    if glyphIndex < revealedCount {
                        let distanceToLeading = (revealedCount - 1) - glyphIndex
                        if distanceToLeading < blurWindow {
                            let progress = Double(distanceToLeading) / Double(blurWindow)
                            let blurRadius = (1.0 - progress) * 4.0
                            let opacity = 0.35 + progress * 0.65
                            
                            var subContext = context
                            subContext.opacity = opacity
                            if blurRadius > 0.4 {
                                subContext.addFilter(.blur(radius: blurRadius))
                            }
                            subContext.draw(glyph)
                        } else {
                            context.draw(glyph)
                        }
                    }
                    glyphIndex += 1
                }
            }
        }
    }
}

// MARK: - Shimmering Skeleton Loader
struct SummarySkeletonLoaderView: View {
    @State private var phase: CGFloat = -0.8
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(maxWidth: .infinity)
                .frame(height: 16)
                .padding(.trailing, 24)
            
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .frame(width: 250, height: 16)
        }
        .padding(.vertical, 6)
        .overlay(
            GeometryReader { geo in
                let shimmerWidth = max(240, geo.size.width * 0.75)
                LinearGradient(
                    gradient: Gradient(stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color.white.opacity(0.02), location: 0.15),
                        .init(color: Color.white.opacity(0.06), location: 0.32),
                        .init(color: Color.white.opacity(0.12), location: 0.50),
                        .init(color: Color.white.opacity(0.06), location: 0.68),
                        .init(color: Color.white.opacity(0.02), location: 0.85),
                        .init(color: .clear, location: 1.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: shimmerWidth)
                .blur(radius: 6)
                .offset(x: phase * (geo.size.width + shimmerWidth * 0.5))
                .blendMode(.plusLighter)
            }
            .mask(
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(maxWidth: .infinity)
                        .frame(height: 16)
                        .padding(.trailing, 24)
                    
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .frame(width: 250, height: 16)
                }
                .padding(.vertical, 6)
            )
        )
        .onAppear {
            withAnimation(.linear(duration: 2.0).repeatForever(autoreverses: false)) {
                phase = 1.2
            }
        }
    }
}

// MARK: - Markdown Bold Parser
func parseBoldMarkdown(_ input: String, fontSize: CGFloat = 20, fontName: String = "Averia Serif Libre") -> AttributedString {
    var text = input
    
    // Hide a solitary trailing "*" if it looks like the start of an incoming "**" delimiter during streaming
    if text.hasSuffix("*") && !text.hasSuffix("**") {
        let starCount = text.reduce(0) { $1 == "*" ? $0 + 1 : $0 }
        if starCount % 2 != 0 {
            text.removeLast()
        }
    }
    
    var result = AttributedString()
    let parts = text.components(separatedBy: "**")
    
    for (index, part) in parts.enumerated() {
        guard !part.isEmpty else { continue }
        var attrPart = AttributedString(part)
        if index % 2 == 1 {
            // Text between ** and ** -> Bold
            attrPart.font = .custom(fontName, size: fontSize).weight(.bold)
            attrPart.inlinePresentationIntent = .stronglyEmphasized
        } else {
            // Regular text
            attrPart.font = .custom(fontName, size: fontSize).weight(.regular)
        }
        result.append(attrPart)
    }
    return result
}

// MARK: - Streaming Ticker Manager
@MainActor
final class StreamingTicker: ObservableObject {
    @Published var revealedCount: Int = 0
    private var targetCount: Int = 0
    private var isFinished: Bool = false
    private var runningTask: Task<Void, Never>? = nil
    private let blurWindow: Int = 6
    
    func update(renderedCount: Int, isLoading: Bool) {
        self.targetCount = renderedCount
        self.isFinished = !isLoading && renderedCount > 0
        
        if renderedCount == 0 {
            runningTask?.cancel()
            runningTask = nil
            revealedCount = 0
            return
        }
        
        // If results were already complete before view mounted, reveal immediately
        if !isLoading && runningTask == nil && revealedCount == 0 {
            revealedCount = renderedCount + blurWindow
            return
        }
        
        if !isLoading && revealedCount >= targetCount + blurWindow {
            return
        }
        
        if runningTask == nil || runningTask?.isCancelled == true {
            startLoop()
        }
    }
    
    func cancel() {
        runningTask?.cancel()
        runningTask = nil
    }
    
    private func startLoop() {
        runningTask?.cancel()
        runningTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }
                
                let maxTarget = self.isFinished ? (self.targetCount + self.blurWindow) : self.targetCount
                
                if self.revealedCount < maxTarget {
                    let remaining = self.targetCount - self.revealedCount
                    let step: Int
                    if remaining > 30 {
                        step = 4
                    } else if remaining > 15 {
                        step = 2
                    } else {
                        step = 1
                    }
                    self.revealedCount = min(self.revealedCount + step, maxTarget)
                    try? await Task.sleep(nanoseconds: 12_000_000)
                } else if self.isFinished {
                    self.revealedCount = max(self.revealedCount, self.targetCount + self.blurWindow)
                    break
                } else {
                    try? await Task.sleep(nanoseconds: 16_000_000)
                }
            }
        }
    }
}

// MARK: - Streaming AI Overview View
struct StreamingOverviewView: View {
    var fullText: String
    var isLoading: Bool
    
    @StateObject private var ticker = StreamingTicker()
    private let blurWindow: Int = 6
    
    private var formattedText: AttributedString {
        parseBoldMarkdown(fullText, fontSize: 20, fontName: "Averia Serif Libre")
    }
    
    private var renderedCount: Int {
        formattedText.characters.count
    }
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            if fullText.isEmpty && isLoading {
                SummarySkeletonLoaderView()
                    .transition(.opacity.animation(.easeInOut(duration: 0.25)))
            } else if !fullText.isEmpty {
                Text(formattedText)
                    .font(.custom("Averia Serif Libre", size: 20))
                    .foregroundColor(.primary)
                    .textRenderer(StreamingBlurTextRenderer(revealedCount: ticker.revealedCount, totalChars: renderedCount, blurWindow: blurWindow))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 2)
        .onChange(of: fullText) { _ in
            ticker.update(renderedCount: renderedCount, isLoading: isLoading)
        }
        .onChange(of: isLoading) { newLoading in
            ticker.update(renderedCount: renderedCount, isLoading: newLoading)
        }
        .onAppear {
            ticker.update(renderedCount: renderedCount, isLoading: isLoading)
        }
        .onDisappear {
            ticker.cancel()
        }
    }
}

// MARK: - UI
struct ContentView: View {
    @StateObject var scraper: LensScraper
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var animatedCardIds: Set<UUID> = []
    @State private var clickMonitor: Any? = nil
    
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var isImageEnlarged = false
    @Namespace private var imageAnimation

    var body: some View {
        ZStack(alignment: .top) {
            // Full background glass effect with brand blue gradient
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.05, green: 0.1, blue: 0.3).opacity(0.65),
                        Color(red: 0.02, green: 0.06, blue: 0.18).opacity(0.5)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1.0)
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                isSearchFocused = false
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            
            // Results Scroll Area
            GeometryReader { geo in
                ScrollView(showsIndicators: false) {
                    Group {
                        if scraper.matches.isEmpty && scraper.overview.isEmpty && !scraper.isOverviewLoading {
                            if scraper.isScraping {
                                // Clean canvas under sticky search bar while the whole-window beam glow is active
                                VStack {
                                    Color.clear.frame(height: scraper.capturedImage != nil ? 116 : 0)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, minHeight: 400)
                            } else {
                                VStack(spacing: 16) {
                                    if scraper.statusText.contains("Error") || scraper.statusText.contains("Failed") {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .font(.custom("Geist", size: 50))
                                            .foregroundColor(.red)
                                            .padding(.top, 40)
                                        Text("Search Failed")
                                            .font(.custom("Geist", size: 18).weight(.semibold))
                                            .foregroundColor(.red)
                                        Text(scraper.statusText)
                                            .font(.custom("Geist", size: 13))
                                            .foregroundColor(.secondary)
                                            .multilineTextAlignment(.center)
                                            .padding(.horizontal, 20)
                                    } else {
                                        Image(systemName: "photo.on.rectangle.angled")
                                            .font(.custom("Geist", size: 60))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 40)
                                        Text("Ready.")
                                            .font(.custom("Geist", size: 16).weight(.semibold))
                                        Text("Click 'Take Snapshot' to search using SerpApi.")
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 400, alignment: .center)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 14) {
                                // Balanced spacer below sticky search bar (reduced spacing)
                                Color.clear.frame(height: scraper.capturedImage != nil ? 116 : 0)
                                
                                if !scraper.overview.isEmpty || scraper.isOverviewLoading {
                                    StreamingOverviewView(fullText: scraper.overview, isLoading: scraper.isOverviewLoading)
                                }
                            
                                // Masonry Grid with Fixed Column Widths
                                if !scraper.matches.isEmpty {
                                    let availableWidth = max(280, min(geo.size.width - 48, 750))
                                    let numCols = availableWidth > 580 ? 3 : 2
                                    let spacing: CGFloat = 16
                                    let colWidth = floor((availableWidth - spacing * CGFloat(numCols - 1)) / CGFloat(numCols))
                                    
                                    HStack(alignment: .top, spacing: spacing) {
                                        ForEach(0..<numCols, id: \.self) { colIndex in
                                            VStack(spacing: spacing) {
                                                ForEach(Array(scraper.matches.enumerated()).filter { $0.offset % numCols == colIndex }, id: \.element.id) { pair in
                                                    VisualMatchCard(match: pair.element, index: pair.offset, cardWidth: colWidth, animatedCardIds: $animatedCardIds)
                                                }
                                            }
                                            .frame(width: colWidth)
                                        }
                                    }
                                    .frame(width: availableWidth)
                                    .padding(.vertical, 4)
                                    .padding(.bottom, 60)
                                    .transition(.opacity.animation(.easeOut(duration: 0.35)))
                                }
                            }
                            .frame(width: max(280, min(geo.size.width - 48, 750)), alignment: .leading)
                            .opacity(scraper.isScraping && !scraper.matches.isEmpty ? 0.65 : 1.0)
                            .animation(.easeInOut(duration: 0.25), value: scraper.isScraping)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, 24)
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        isSearchFocused = false
                        NSApp.keyWindow?.makeFirstResponder(nil)
                    }
                )
            }
            
            // Bottom Progressive Blur (VariableBlur CAFilter + subtle liquid gradient)
            VStack {
                Spacer()
                VariableBlurView(maxBlurRadius: 20, direction: .blurredBottomClearTop, startOffset: 0)
                    .frame(height: 38)
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(red: 0.02, green: 0.05, blue: 0.16).opacity(0.85), location: 0.0),
                                .init(color: Color(red: 0.02, green: 0.05, blue: 0.16).opacity(0.35), location: 0.6),
                                .init(color: Color(red: 0.02, green: 0.05, blue: 0.16).opacity(0.0), location: 1.0)
                            ]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .zIndex(8)
            
            // Top Progressive Blur behind Sticky Search Bar (VariableBlur CAFilter + subtle liquid gradient)
            if scraper.capturedImage != nil {
                VariableBlurView(maxBlurRadius: 28, direction: .blurredTopClearBottom, startOffset: 0)
                    .frame(height: 145)
                    .overlay(
                        LinearGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(red: 0.03, green: 0.07, blue: 0.22).opacity(0.85), location: 0.0),
                                .init(color: Color(red: 0.03, green: 0.07, blue: 0.22).opacity(0.45), location: 0.55),
                                .init(color: Color(red: 0.03, green: 0.07, blue: 0.22).opacity(0.0), location: 1.0)
                            ]),
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .ignoresSafeArea(edges: .top)
                    .allowsHitTesting(false)
                    .zIndex(9)
            }
            
            // Sticky Search Bar Overlay with Liquid Glass Capsule & Brand Blue Active Highlight
            if let img = scraper.capturedImage {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        SearchCapturedImage(img: img, onEnlarge: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { isImageEnlarged = true }
                        })
                        
                        TextField("add to search", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .font(.system(size: 15))
                            .focused($isSearchFocused)
                            .onChange(of: searchText) { newValue in
                                searchTask?.cancel()
                                searchTask = Task {
                                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                                    guard !Task.isCancelled else { return }
                                    
                                    if searchText == newValue && !newValue.isEmpty {
                                        DispatchQueue.main.async {
                                            scraper.isScraping = true
                                            scraper.statusText = "Searching Google Lens with text..."
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            scraper.isScraping = false
                                        }
                                    }
                                }
                            }
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(
                                isSearchFocused ? Color(red: 0.25, green: 0.55, blue: 1.0) : Color.white.opacity(0.22),
                                lineWidth: isSearchFocused ? 2.0 : 1.0
                            )
                            .shadow(color: isSearchFocused ? Color(red: 0.25, green: 0.55, blue: 1.0).opacity(0.45) : Color.clear, radius: 6)
                    )
                    .frame(maxWidth: 750)
                    .padding(.horizontal, 24)
                    .padding(.top, 48)
                    .padding(.bottom, 16)
                }
                .frame(maxWidth: .infinity)
                .zIndex(10)
            }
            
            // Enlarged Image Modal
            if isImageEnlarged, let img = scraper.capturedImage {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .overlay(Color.black.opacity(0.8))
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation { isImageEnlarged = false } }
                    
                    Image(nsImage: img)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(1.04)
                        .clipped()
                        .padding(40)
                    
                    VStack {
                        HStack {
                            Spacer()
                            EnlargedImageCloseButton {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    isImageEnlarged = false
                                }
                            }
                            .padding(20)
                        }
                        Spacer()
                    }
                }
                .transition(.opacity.animation(.easeInOut(duration: 0.2)))
                .zIndex(100)
            }
            
            // Whole Window Border Beam Glow during image search
            if scraper.isScraping {
                BorderBeamView(
                    beamColor: Color(red: 0.35, green: 0.65, blue: 1.0),
                    duration: 2.8,
                    lineWidth: 2.5,
                    cornerRadius: 20
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.animation(.easeInOut(duration: 0.35)))
                .zIndex(50)
            }
        }
        .onAppear {
            isSearchFocused = false
            if clickMonitor == nil {
                clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { event in
                    if isSearchFocused, let win = event.window {
                        let hitView = win.contentView?.hitTest(event.locationInWindow)
                        let isInsideTextField = (hitView is NSTextField) || (hitView is NSTextView)
                        if !isInsideTextField {
                            DispatchQueue.main.async {
                                isSearchFocused = false
                                win.makeFirstResponder(nil)
                            }
                        }
                    }
                    return event
                }
            }
        }
        .onDisappear {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
                clickMonitor = nil
            }
        }
        .onChange(of: scraper.matches.count) {
            if scraper.matches.isEmpty {
                animatedCardIds.removeAll()
            }
        }
        .ignoresSafeArea(.all, edges: .top)
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 500, maxHeight: .infinity)
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
                    // If they didn't select text, and the bounding box is huge, it's a browser bug!
                    if !TextEditManager.shared.wasTextSelected && rect.height > 60 {
                        log("getCursorPosition: bounding box too tall (\(rect.height)) for typing, falling back")
                        return nil 
                    }
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
        usleep(300_000) // 300ms (Electron apps are slow to write to clipboard)
        
        if let copied = pasteboard.string(forType: .string), !copied.isEmpty {
            self.wasTextSelected = true
            if let old = oldString { pasteboard.setString(old, forType: .string) }
            return copied
        }
        
        // If nothing was selected, Select All then Copy
        simulateKeystroke(keyCode: 0, flags: .maskCommand) // Cmd+A
        usleep(150_000)
        simulateKeystroke(keyCode: 8, flags: .maskCommand) // Cmd+C
        usleep(300_000) // 300ms
        
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



    func findHighlightPosition(element: AXUIElement?, screenHeight: CGFloat) -> CGPoint? {
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
        if let element = element {
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
                
                // Stricter Blueish heuristic to avoid false-positives on dark-mode grey/blue backgrounds
                if b > r + 30 && b > g + 30 && b > 80 {
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                    foundCount += 1
                }
            }
        }
        
        if foundCount > 10 { // Ensure it's not just a stray pixel
            let boxHeight = maxY - minY
            // If the "highlight" spans more than 80% of the capture area, it's almost certainly a false positive (like a desktop wallpaper or app background)
            if CGFloat(boxHeight) > CGFloat(height) * 0.8 {
                log("Rejected blue bounding box because it is too large (height \(boxHeight) vs \(height)). Probably a background false-positive.")
                return nil
            }
            log("Found blue bounding box: \(minX),\(minY) to \(maxX),\(maxY) with \(foundCount) pixels")
            let relativeMidX = CGFloat(minX + maxX) / 2.0 / CGFloat(width)
            let relativeTopY = CGFloat(minY) / CGFloat(height) // Use top edge instead of middle
            
            let globalX = elementPos.x + relativeMidX * elementSize.width
            let globalY = screenHeight - (elementPos.y + relativeTopY * elementSize.height)
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
                        
                        var minX: CGFloat = 99999
                        var maxX: CGFloat = 0
                        var minY: CGFloat = 99999
                        var maxY: CGFloat = 0
                        var foundAny = false
                        
                        for obs in results {
                            if let topCandidate = obs.topCandidates(1).first {
                                let ocrText = topCandidate.string.lowercased()
                                let cleanOcr = ocrText.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
                                
                                var isMatch = false
                                if !cleanOcr.isEmpty && !cleanTarget.isEmpty {
                                    let isShortTarget = cleanTarget.count < 15
                                    if isShortTarget {
                                        // For short selections (1-2 words), accept substring matches
                                        if cleanOcr == cleanTarget || cleanTarget.contains(cleanOcr) || cleanOcr.contains(cleanTarget) {
                                            isMatch = true
                                        }
                                    } else {
                                        // For long selections, require a substantial substring match OR fuzzy word match
                                        let ocrWords = ocrText.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { $0.count >= 4 }
                                        var matchCount = 0
                                        for word in ocrWords {
                                            if cleanTarget.contains(word) {
                                                matchCount += 1
                                            }
                                        }
                                        
                                        if (cleanOcr.count >= 15 && cleanTarget.contains(cleanOcr)) || matchCount >= 3 {
                                            isMatch = true
                                        }
                                    }
                                }
                                
                                if isMatch {
                                    log("MATCH FOUND! OCR: \(ocrText)")
                                    let visionBBox = obs.boundingBox
                                    let pixelX = visionBBox.origin.x * elementSize.width
                                    let pixelY = (1.0 - visionBBox.origin.y - visionBBox.height) * elementSize.height
                                    let pixelWidth = visionBBox.width * elementSize.width
                                    let pixelHeight = visionBBox.height * elementSize.height
                                    
                                    let tMinX = elementPos.x + pixelX
                                    let tMaxX = tMinX + pixelWidth
                                    let tMinY = elementPos.y + pixelY
                                    let tMaxY = tMinY + pixelHeight
                                    
                                    if tMinX < minX { minX = tMinX }
                                    if tMaxX > maxX { maxX = tMaxX }
                                    if tMinY < minY { minY = tMinY }
                                    if tMaxY > maxY { maxY = tMaxY }
                                    foundAny = true
                                }
                            }
                        }
                        
                        if foundAny {
                            let finalX = (minX + maxX) / 2.0
                            let finalY = minY // Top edge of the entire matched text block
                            foundPos = CGPoint(x: finalX, y: finalY)
                            log("Found combined position: \(foundPos!)")
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
        let geminiApiKey: String = delegate?.scraper.geminiApiKey ?? AppSecrets.geminiApiKey
        if geminiApiKey.isEmpty {
            return "ERROR: GEMINI_API_KEY is missing."
        }
        
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.8-flash:generateContent?key=\(geminiApiKey)")!
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
    var isBlackDot: Bool = false
    
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                if !isBlackDot {
                    if let t = title {
                        Text(t)
                            .font(.custom("Geist", size: 14).weight(.medium))
                            .foregroundColor(.white)
                            .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                    } else {
                        if systemIcon.hasPrefix("phosphor_") {
                            Image(systemIcon)
                                .renderingMode(.template)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18)
                                .foregroundColor(isCloseButton ? .red : .white)
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        } else {
                            Image(systemName: systemIcon)
                                .font(.custom("Geist", size: 16).weight(.semibold))
                                .foregroundColor(isCloseButton ? .red : .white)
                                .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                        }
                    }
                }
            }
            .frame(width: (title != nil && !isBlackDot) ? 90 : 44, height: 44)
        }
        .buttonStyle(PlainButtonStyle())
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isBlackDot ? Color.black : (isCloseButton ? Color.red.opacity(isHovering ? 0.8 : 0.4) : Color.black.opacity(isHovering ? 0.6 : 0.4)))
        )
        .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(isBlackDot ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
        .shadow(color: isBlackDot ? .clear : .black.opacity(0.2), radius: 5)
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


struct TextEditGooeyBackground: View {
    var expanded: Bool
    var isEditExpanded: Bool
    
    var body: some View {
        Canvas { context, size in
            context.addFilter(.alphaThreshold(min: 0.5, color: .black))
            context.addFilter(.blur(radius: 12))
            
            context.drawLayer { ctx in
                for i in 0..<5 {
                    if let resolved = context.resolveSymbol(id: i) {
                        ctx.draw(resolved, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    }
                }
            }
        } symbols: {
            // Anchor
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .frame(width: 44, height: 44)
                .tag(0)
            
            if isEditExpanded {
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 248, height: 44).offset(x: expanded ? -22 : 0).tag(1)
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 136 : 0).tag(4)
            } else {
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 90, height: 44).offset(x: expanded ? -101 : 0).tag(1)
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 90, height: 44).offset(x: expanded ? 1 : 0).tag(2)
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 80 : 0).tag(3)
                RoundedRectangle(cornerRadius: 14, style: .continuous).frame(width: 44, height: 44).offset(x: expanded ? 136 : 0).tag(4)
            }
        }
    }
}


class EventMonitorHolder {
    var globalMonitor: Any?
    var localMonitor: Any?
}

struct TextEditOverlayView: View {
    var onCancel: () -> Void
    @State private var isVisible = false
    @State private var buttonsExpanded = false
    @Namespace private var glassSpace
    
    @State private var isEditExpanded = false
    @State private var customPrompt = ""
    @ObservedObject var manager = TextEditManager.shared
    
    @State private var monitorHolder = EventMonitorHolder()
    
    private func closeWithAnimation() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            buttonsExpanded = false
            isEditExpanded = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeIn(duration: 0.15)) {
                isVisible = false
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onCancel()
        }
    }
    
    var body: some View {
        ZStack(alignment: .center) {
            Color.white.opacity(0.001) // Transparent background to catch clicks inside our large 500x200 window
                .onTapGesture { closeWithAnimation() }
                
            VStack {
                ZStack(alignment: .center) {
                    TextEditGooeyBackground(expanded: buttonsExpanded, isEditExpanded: isEditExpanded)
                        .frame(width: 500, height: 200)
                        .opacity(buttonsExpanded ? 0 : 1)
                    
                    GlassEffectContainer(spacing: 12) {
                        ZStack(alignment: .center) {
                            if !isEditExpanded {
                                TextEditGlassButton(systemIcon: "phosphor_translate", title: "Rephrase", action: {
                                    manager.processText(action: "rephrase") { success, newText in
                                        if success, let newText = newText { 
                                            closeWithAnimation()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { manager.replaceText(newText: newText) }
                                        }
                                    }
                                }, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? -101 : 0)
                                .glassEffectID("rephrase", in: glassSpace)
                                
                                TextEditGlassButton(systemIcon: "briefcase", title: "Formalize", action: {
                                    manager.processText(action: "formalize") { success, newText in
                                        if success, let newText = newText { 
                                            closeWithAnimation()
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { manager.replaceText(newText: newText) }
                                        }
                                    }
                                }, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 1 : 0)
                                .glassEffectID("formalize", in: glassSpace)
                            }
                            
                            if isEditExpanded {
                                ZStack {
                                    if !buttonsExpanded {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black).frame(width: 44, height: 44)
                                    } else {
                                        HStack {
                                            TextField("Edit instruction...", text: $customPrompt, axis: .vertical)
                                                .lineLimit(1...6)
                                                .textFieldStyle(PlainTextFieldStyle())
                                                .font(.custom("Geist", size: 14))
                                                .foregroundColor(.white)
                                                .padding(.horizontal, 12)
                                                .padding(.vertical, 8)
                                                .mask(LinearGradient(gradient: Gradient(stops: [.init(color: .clear, location: 0.0), .init(color: .black, location: 0.15), .init(color: .black, location: 0.85), .init(color: .clear, location: 1.0)]), startPoint: .top, endPoint: .bottom))
                                                .onSubmit {
                                                    manager.processText(action: "custom", customPrompt: customPrompt) { success, newText in
                                                        if success, let newText = newText { 
                                                            closeWithAnimation()
                                                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { manager.replaceText(newText: newText) }
                                                        }
                                                    }
                                                }
                                            
                                            Button(action: {
                                                manager.processText(action: "custom", customPrompt: customPrompt) { success, newText in
                                                    if success, let newText = newText { 
                                                            closeWithAnimation()
                                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { manager.replaceText(newText: newText) }
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
                                        .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                                    }
                                }
                                .frame(width: !buttonsExpanded ? 44 : 248).frame(minHeight: 44)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(!buttonsExpanded ? Color.black : Color.black.opacity(0.4)))
                                .glassEffect(.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(!buttonsExpanded ? Color.clear : Color.white.opacity(0.3), lineWidth: 1))
                                .shadow(color: !buttonsExpanded ? .clear : .black.opacity(0.2), radius: 5)
                                .matchedGeometryEffect(id: "edit_m", in: glassSpace)
                                .offset(x: buttonsExpanded ? -22 : 0)
                            } else {
                                TextEditGlassButton(systemIcon: "phosphor_chat", action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isEditExpanded.toggle()
                                    }
                                }, isBlackDot: !buttonsExpanded)
                                .offset(x: buttonsExpanded ? 80 : 0)
                                .glassEffectID("edit", in: glassSpace)
                                .matchedGeometryEffect(id: "edit_m", in: glassSpace)
                            }
                            
                            if !isEditExpanded {
                                TextEditGlassButton(systemIcon: "phosphor_x", action: { closeWithAnimation() }, isCloseButton: true, isBlackDot: !buttonsExpanded)
                                    .offset(x: buttonsExpanded ? 136 : 0)
                                    .glassEffectID("close", in: glassSpace)
                            } else {
                                TextEditGlassButton(systemIcon: "phosphor_x", action: {
                                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                                        isEditExpanded = false
                                        customPrompt = ""
                                    }
                                }, isCloseButton: true, isBlackDot: !buttonsExpanded)
                                    .offset(x: buttonsExpanded ? 136 : 0)
                                    .glassEffectID("close", in: glassSpace)
                            }
                        }
                    }
                    
                    if manager.isProcessing {
                        BorderBeamView(
                            beamColor: Color(red: 0.35, green: 0.65, blue: 1.0),
                            duration: 2.2,
                            lineWidth: 2.0,
                            cornerRadius: 14
                        )
                        .frame(width: isEditExpanded ? 248 : 320, height: 44)
                        .offset(x: isEditExpanded ? (buttonsExpanded ? -22 : 0) : 0)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.top, 80)
                    }
                    
                    if !manager.errorMessage.isEmpty {
                        Text(manager.errorMessage)
                            .foregroundColor(.red)
                            .padding(8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                            .padding(.top, 80)
                    }
                }
                .scaleEffect(isVisible ? 1.0 : 0.01, anchor: .center)
                .opacity(isVisible ? 1.0 : 0.0)
            }
        }
        .onAppear {
            monitorHolder.globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { event in
                if event.type == .keyDown && event.keyCode == 53 {
                    closeWithAnimation()
                } else if event.type == .leftMouseDown || event.type == .rightMouseDown {
                    let mouseLoc = NSEvent.mouseLocation
                    let winWidth: CGFloat = 500
                    let winHeight: CGFloat = 200
                    let originX = manager.menuPosition.x - (winWidth / 2)
                    let originY = manager.menuPosition.y - (winHeight / 2)
                    let windowFrame = CGRect(x: originX, y: originY, width: winWidth, height: winHeight)
                    
                    if !windowFrame.contains(mouseLoc) {
                        closeWithAnimation()
                    }
                }
            }
            monitorHolder.localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                if event.keyCode == 53 {
                    closeWithAnimation()
                    return nil
                }
                return event
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                withAnimation(.easeOut(duration: 0.12)) {
                    isVisible = true
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    buttonsExpanded = true
                }
            }
        }
        .onDisappear {
            if let monitor = monitorHolder.globalMonitor { NSEvent.removeMonitor(monitor) }
            if let monitor = monitorHolder.localMonitor { NSEvent.removeMonitor(monitor) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if let window = notification.object as? NSWindow, window.isEqual(NSApplication.shared.keyWindow) == false {
                if window is CaptureWindow && window.frame.size.width == 500 {
                    closeWithAnimation()
                }
            }
        }
    }
}




struct VisualMatchCard: View {
    var match: VisualMatch
    var index: Int
    var cardWidth: CGFloat
    @Binding var animatedCardIds: Set<UUID>
    @State private var appearBlur: Bool
    
    init(match: VisualMatch, index: Int, cardWidth: CGFloat, animatedCardIds: Binding<Set<UUID>>) {
        self.match = match
        self.index = index
        self.cardWidth = cardWidth
        self._animatedCardIds = animatedCardIds
        let alreadyAnimated = animatedCardIds.wrappedValue.contains(match.id)
        self._appearBlur = State(initialValue: !alreadyAnimated)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail with fixed width & natural aspect ratio height
            if let urlString = match.thumbnail, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: cardWidth)
                            .cornerRadius(14)
                    } else if phase.error != nil {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.06))
                            .frame(width: cardWidth, height: cardWidth * 0.75)
                            .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                    } else {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white.opacity(0.04))
                            .frame(width: cardWidth, height: cardWidth * 0.75)
                            .overlay(ProgressView().scaleEffect(0.8))
                    }
                }
                .frame(width: cardWidth)
            } else {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white.opacity(0.06))
                    .frame(width: cardWidth, height: cardWidth * 0.75)
                    .overlay(Image(systemName: "photo").foregroundColor(.secondary))
            }
            
            // Text
            VStack(alignment: .leading, spacing: 4) {
                Text(match.source ?? "Unknown Source")
                    .font(.custom("Geist", size: 11).weight(.regular))
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Text(match.title ?? "No title")
                    .font(.custom("Geist", size: 12).weight(.regular))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
            }
            .frame(width: cardWidth, alignment: .leading)
        }
        .frame(width: cardWidth, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture {
            if let link = match.link, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        }
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
        }
        .blur(radius: appearBlur ? 8 : 0)
        .opacity(appearBlur ? 0 : 1)
        .onAppear {
            if !animatedCardIds.contains(match.id) {
                animatedCardIds.insert(match.id)
                withAnimation(.easeOut(duration: 0.35).delay(Double(min(index, 12)) * 0.04)) {
                    appearBlur = false
                }
            }
        }
    }
}

struct SearchCapturedImage: View {
    var img: NSImage
    var onEnlarge: () -> Void
    @State private var isHovering = false
    @State private var appearBlur = true
    
    var body: some View {
        Image(nsImage: img)
            .resizable()
            .scaledToFit()
            .scaleEffect(1.04) // Pushes the 1px black screencapture artifact out of bounds
            .frame(height: 48)
            .clipped()
            .cornerRadius(16)
            .overlay(
                ZStack {
                    if isHovering {
                        Color.black.opacity(0.4)
                        Image("phosphor_corners_out")
                            .renderingMode(.template)
                            .resizable()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                    }
                }
            )
            .cornerRadius(16)
            .onHover { h in isHovering = h }
            .onTapGesture { onEnlarge() }
            .blur(radius: appearBlur ? 10 : 0)
            .opacity(appearBlur ? 0 : 1)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { appearBlur = false }
            }
    }
}

struct IconPressButtonStyle: ButtonStyle {
    var isHovering: Bool
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : (isHovering ? 1.08 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.65), value: configuration.isPressed)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovering)
    }
}

struct EnlargedImageCloseButton: View {
    var action: () -> Void
    @State private var isHovering = false
    
    var body: some View {
        Button(action: action) {
            Image("phosphor_x")
                .renderingMode(.template)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 22, height: 22)
                .foregroundColor(isHovering ? Color.red : Color.white)
                .shadow(color: isHovering ? Color.red.opacity(0.8) : Color.black.opacity(0.4), radius: isHovering ? 8 : 3)
                .padding(10)
                .background(
                    Circle()
                        .fill(isHovering ? Color.red.opacity(0.18) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(IconPressButtonStyle(isHovering: isHovering))
        .glassEffect(isHovering ? .regular.tint(Color.red.opacity(0.55)) : .clear, in: Circle())
        .onHover { hovering in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                isHovering = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if isHovering {
                NSCursor.pop()
                isHovering = false
            }
        }
    }
}


