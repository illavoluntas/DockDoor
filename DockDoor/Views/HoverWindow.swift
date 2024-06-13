//
//  HoverWindow.swift
//  DockDoor
//
//  Created by Ethan Bills on 6/5/24.
//

import Cocoa
import SwiftUI									
import KeyboardShortcuts

@Observable class CurrentWindow {
    static let shared = CurrentWindow()
    
    var currIndex: Int = 0
    var showingTabMenu: Bool = false
    
    func setShowing(toState: Bool) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut) {
                self.showingTabMenu = toState
            }
        }
    }
    
    func setIndex(to: Int) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut) {
                self.currIndex = to
            }
        }
    }
}

class HoverWindow: NSWindow {
    static let shared = HoverWindow()
    
    private var appName: String = ""
    private var windows: [WindowInfo] = []
    private var onWindowTap: (() -> Void)?
    private var hostingView: NSHostingView<HoverView>?
    
    var bestGuessMonitor: NSScreen? = NSScreen.main
    
    private init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        level = .floating
        isMovableByWindowBackground = true // Allow dragging from anywhere
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // Show in all spaces and on top of fullscreen apps
        backgroundColor = .clear // Make window background transparent
        hasShadow = false // Remove shadow
        
        // Set up tracking area for mouse exit detection
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways]
        let trackingArea = NSTrackingArea(rect: self.frame, options: options, owner: self, userInfo: nil)
        contentView?.addTrackingArea(trackingArea)
    }
    
    // Method to hide the window
    func hideWindow() {
        DispatchQueue.main.async { [weak self] in
            self?.orderOut(nil)
            self?.windows.removeAll()
            CurrentWindow.shared.setIndex(to: 0)
        }
    }
    
    // Mouse exited tracking area - hide the window
    override func mouseExited(with event: NSEvent) {
        if !CurrentWindow.shared.showingTabMenu { hideWindow() }
    }
    
    // Calculate hover window's size and position based on content and mouse location
    private func updateContentViewSizeAndPosition(mouseLocation: CGPoint? = nil, animated: Bool, centerOnScreen: Bool = false) {
        guard let hostingView = hostingView else { return }
        guard !self.windows.isEmpty else {
            hideWindow()
            return
        }
        
        CurrentWindow.shared.setShowing(toState: centerOnScreen)

        // Update content view based on new data
        hostingView.rootView = HoverView(appName: self.appName, windows: self.windows, onWindowTap: self.onWindowTap)
        
        let hoverWindowSize = hostingView.fittingSize
        var hoverWindowOrigin: CGPoint
        
        if centerOnScreen {
            // Center the window on the screen
            guard let screen = self.bestGuessMonitor else { return }
            let screenFrame = screen.frame
            hoverWindowOrigin = CGPoint(
                x: screenFrame.midX - (hoverWindowSize.width / 2),
                y: screenFrame.midY - (hoverWindowSize.height / 2)
            )
        } else if let mouseLocation = mouseLocation, let screen = screenContainingPoint(mouseLocation) {
            // Use mouse location for initial placement
            hoverWindowOrigin = mouseLocation
            
            let screenFrame = screen.frame
            let dockPosition = DockUtils.shared.getDockPosition()
            let dockHeight = DockUtils.shared.calculateDockHeight(screen)
            
            // Position window above/below dock depending on position
            switch dockPosition {
            case .bottom:
                hoverWindowOrigin.y = dockHeight
            case .left, .right:
                hoverWindowOrigin.y -= hoverWindowSize.height / 2
                if dockPosition == .left {
                    hoverWindowOrigin.x = screenFrame.minX + dockHeight
                } else { // dockPosition == .right
                    hoverWindowOrigin.x = screenFrame.maxX - hoverWindowSize.width - dockHeight
                }
            case .unknown:
                break
            }
            
            // Adjust horizontal position if the window is wider than the screen and the dock is on the side
            if dockPosition == .left || dockPosition == .right, hoverWindowSize.width > screenFrame.width - dockHeight {
                hoverWindowOrigin.x = dockPosition == .left ? screenFrame.minX : screenFrame.maxX - hoverWindowSize.width
            }
            
            // Center the window horizontally if the dock is at the bottom
            if dockPosition == .bottom {
                hoverWindowOrigin.x -= hoverWindowSize.width / 2
            }

            // Ensure the window stays within screen bounds
            hoverWindowOrigin.x = max(screenFrame.minX, min(hoverWindowOrigin.x, screenFrame.maxX - hoverWindowSize.width))
            hoverWindowOrigin.y = max(screenFrame.minY, min(hoverWindowOrigin.y, screenFrame.maxY - hoverWindowSize.height))
        } else {
            return
        }

        let finalFrame = NSRect(origin: hoverWindowOrigin, size: hoverWindowSize)
        
        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.animator().setFrame(finalFrame, display: true)
            }, completionHandler: nil)
        } else {
            setFrame(finalFrame, display: true)
        }
    }
    
    // Helper method to find the screen containing a given point
    private func screenContainingPoint(_ point: CGPoint) -> NSScreen? {
        self.bestGuessMonitor = NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
        return self.bestGuessMonitor
    }
    
    func showWindow(appName: String, windows: [WindowInfo], mouseLocation: CGPoint, onWindowTap: (() -> Void)? = nil) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.appName = appName
            self.windows = windows
            self.onWindowTap = onWindowTap

            if self.hostingView == nil {
                // Create a new hosting view if we don't have one
                let hoverView = HoverView(appName: appName, windows: windows, onWindowTap: onWindowTap)
                let hostingView = NSHostingView(rootView: hoverView)
                self.contentView = hostingView
                self.hostingView = hostingView
            } else {
                // Update the existing hostingView's rootView
                self.hostingView?.rootView = HoverView(appName: appName, windows: windows, onWindowTap: onWindowTap)
            }

            let isMouseEvent = mouseLocation != .zero
            
            CurrentWindow.shared.setShowing(toState: !isMouseEvent)
            
            self.updateContentViewSizeAndPosition(mouseLocation: mouseLocation, animated: true, centerOnScreen: !isMouseEvent)
            self.makeKeyAndOrderFront(nil)
        }
    }

    func cycleWindows() {
        guard !windows.isEmpty else { return }

        let newIndex = CurrentWindow.shared.currIndex + 1
        CurrentWindow.shared.setIndex(to: newIndex >= windows.count ? 0 : newIndex)
        print(CurrentWindow.shared.currIndex)
    }

    private func updateWindowDisplay() {
        guard !windows.isEmpty else { return }

        // Update the rootView of the existing hostingView
        hostingView?.rootView = HoverView(appName: self.appName, windows: self.windows, onWindowTap: self.onWindowTap)

        // Do not use mouse location, center on screen only for cycling
        updateContentViewSizeAndPosition(animated: false, centerOnScreen: true)
        makeKeyAndOrderFront(nil)
    }
    
    // Method to select and bring the current window to the front
    func selectAndBringToFrontCurrentWindow() {
        guard !windows.isEmpty else { return }

        let selectedWindow = windows[CurrentWindow.shared.currIndex]
        WindowUtil.bringWindowToFront(windowInfo: selectedWindow)
        hideWindow()
    }
}

struct HoverView: View {
    let appName: String
    let windows: [WindowInfo]
    let onWindowTap: (() -> Void)?

    @State private var showWindows: Bool = false

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    ForEach(windows.indices, id: \.self) { index in
                        WindowPreview(windowInfo: windows[index], onTap: onWindowTap, index: index)
                            .id(index)
                    }
                }
                .onAppear {
                    self.runAnimation()
                }
                .onChange(of: CurrentWindow.shared.currIndex) { _, newIndex in
                    // Smoothly scroll to the new index
                    withAnimation {
                        scrollProxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onChange(of: self.windows) { _, _ in
                    self.runAnimation()
                }
            }
            .frame(
                maxWidth: HoverWindow.shared.bestGuessMonitor?.visibleFrame.width ?? 800
            )
            .scaledToFit()
            .padding()
            .scaleEffect(showWindows ? 1 : 0.90)
            .opacity(showWindows ? 1 : 0.8)
        }
    }
    
    private func runAnimation() {
        self.showWindows = false
        
        withAnimation(.spring(response: 0.3, dampingFraction: 0.3)) {
            showWindows = true
        }
    }
}

struct WindowPreview: View {
    let windowInfo: WindowInfo
    let onTap: (() -> Void)?
    let index: Int									
    
    @State private var isHovering = false
    
    var body: some View {
        let isHighlighted = (index == CurrentWindow.shared.currIndex && CurrentWindow.shared.showingTabMenu)
        VStack {
            if let cgImage = windowInfo.image {
                let image = Image(decorative: cgImage, scale: 1.0)
                
                ZStack {
                    image
                        .resizable()
                        .scaledToFit()
                        .padding()
                        .frame(width: roughWidthCap)
                        .frame(maxHeight: roughHeightCap)
                        .overlay(
                            VStack {
                                if let name = windowInfo.windowName, !name.isEmpty {
                                    Text(name)
                                        .padding(4)
                                        .background(.thickMaterial)
                                        .foregroundColor(.white)
                                        .cornerRadius(8)
                                        .padding(8)
                                        .lineLimit(1)
                                }
                            },
                            alignment: .topTrailing
                        )
                    
                    AnimatedGradientOverlay(shouldDisplay: isHovering || isHighlighted)
                }
                .background(.ultraThinMaterial)
                .shadow(radius: 4.0)
                .cornerRadius(16)
                .scaleEffect(isHovering || isHighlighted ? 0.95 : 1.0)
            } else {
                ProgressView()
            }
        }
        .onHover { over in
            print("hovering")
            if !CurrentWindow.shared.showingTabMenu { withAnimation(.easeInOut) { isHovering = over }}
        }
        .onTapGesture {
            WindowUtil.bringWindowToFront(windowInfo: windowInfo)
            onTap?()
        }
    }
}
