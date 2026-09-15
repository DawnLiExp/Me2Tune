//
//  AlbumCardView.swift
//  Me2Tune
//
//  专辑卡片组件
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AlbumCardView: View, Equatable {
    nonisolated static func == (lhs: AlbumCardView, rhs: AlbumCardView) -> Bool {
        lhs.album.id == rhs.album.id
            && lhs.album.name == rhs.album.name
            && lhs.album.tracks.count == rhs.album.tracks.count
            && lhs.isDragging == rhs.isDragging
    }
    
    let album: Album
    let isDragging: Bool
    let onTap: (NSImage?) -> Void
    let onRename: () -> Void
    let onRemove: () -> Void
    
    @State private var artwork: NSImage?
    @AppStorage("CleanMode") private var cleanMode = false
    
    // MARK: - Body
    
    var body: some View {
        AlbumCardContent(
            artwork: artwork,
            title: album.name,
            count: trackCountText,
            isDragging: isDragging,
            cleanMode: cleanMode,
            accent: NSColor(Color.accent),
            primary: NSColor(Color.primaryText),
            secondary: NSColor(Color.secondaryText),
            placeholder: NSColor(Color.emptyStateIcon)
        )
        .frame(width: 135, height: 175)
        .contentShape(.interaction, Rectangle())
        .onTapGesture {
            onTap(artwork)
        }
        .contextMenu {
            Button("rename") {
                onRename()
            }
            
            Divider()
            
            Button("remove", role: .destructive) {
                onRemove()
            }
        }
        .task(id: album.id) {
            await loadArtwork()
        }
    }
    
    private var trackCountText: String {
        let format = String(localized: "track_count_format")
        return String(format: format, locale: Locale.current, Int64(album.tracks.count))
    }
    
    // MARK: - Artwork Loading
    
    private func loadArtwork() async {
        guard artwork == nil, let firstTrack = album.tracks.first else { return }
        artwork = await ArtworkCacheService.shared.artwork(for: firstTrack.url)
    }
}

// Keep hover changes out of SwiftUI state: profiling on macOS 15 showed repeated
// grid layout and hit testing while these animations were running.
private struct AlbumCardContent: NSViewRepresentable {
    let artwork: NSImage?
    let title: String
    let count: String
    let isDragging: Bool
    let cleanMode: Bool
    let accent: NSColor
    let primary: NSColor
    let secondary: NSColor
    let placeholder: NSColor

    func makeNSView(context: Context) -> AlbumCardContentView {
        AlbumCardContentView()
    }

    func updateNSView(_ view: AlbumCardContentView, context: Context) {
        view.configure(self, isEnabled: context.environment.isEnabled)
    }
}

private final class AlbumCardContentView: NSView {
    private let picture = CALayer()
    private let border = CAShapeLayer()
    private let placeholderView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private var artwork: NSImage?
    private var hoverArea: NSTrackingArea?
    private var hovered = false
    private var hoverEnabled = false
    private var highlighted = false
    private var dragging = false

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        picture.frame = CGRect(x: 0, y: 0, width: 135, height: 135)
        picture.cornerRadius = 12
        picture.masksToBounds = true
        picture.contentsGravity = .resizeAspectFill
        picture.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor
        layer?.addSublayer(picture)

        border.frame = picture.frame
        border.path = CGPath(
            roundedRect: CGRect(x: 1, y: 1, width: 133, height: 133),
            cornerWidth: 11, cornerHeight: 11, transform: nil
        )
        border.fillColor = nil
        border.lineWidth = 2
        border.opacity = 0
        layer?.addSublayer(border)
        layer?.shadowPath = CGPath(
            roundedRect: picture.frame, cornerWidth: 12, cornerHeight: 12, transform: nil
        )
        layer?.shadowRadius = 8
        layer?.shadowOffset = .zero
        layer?.shadowOpacity = 0

        placeholderView.image = NSImage(systemSymbolName: "opticaldisc", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 40, weight: .regular))
        placeholderView.imageScaling = .scaleProportionallyUpOrDown
        placeholderView.frame = NSRect(x: 47.5, y: 47.5, width: 40, height: 40)
        addSubview(placeholderView)

        titleLabel.font = .systemFont(ofSize: 13, weight: .medium)
        countLabel.font = .systemFont(ofSize: 11)
        for label in [titleLabel, countLabel] {
            label.alignment = .center
            label.lineBreakMode = .byTruncatingTail
            label.maximumNumberOfLines = 1
            addSubview(label)
        }
        // Compensate for NSTextField's horizontal text inset to retain 135pt of text.
        titleLabel.frame = NSRect(x: -2, y: 143, width: 139, height: 16)
        countLabel.frame = NSRect(x: -2, y: 161, width: 139, height: 14)
    }

    required init?(coder: NSCoder) { return nil }

    func configure(_ content: AlbumCardContent, isEnabled: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if artwork !== content.artwork {
            artwork = content.artwork
            picture.contents = artwork?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        placeholderView.isHidden = artwork != nil
        placeholderView.contentTintColor = content.placeholder
        if titleLabel.stringValue != content.title { titleLabel.stringValue = content.title }
        if countLabel.stringValue != content.count { countLabel.stringValue = content.count }
        if titleLabel.textColor != content.primary { titleLabel.textColor = content.primary }
        if countLabel.textColor != content.secondary { countLabel.textColor = content.secondary }
        border.strokeColor = content.accent.withAlphaComponent(0.4).cgColor
        layer?.shadowColor = content.accent.cgColor
        CATransaction.commit()

        if dragging != content.isDragging, let layer {
            dragging = content.isDragging
            animate(layer, keyPath: "opacity", to: dragging ? Float(0.4) : Float(1))
        }
        hoverEnabled = isEnabled && !content.cleanMode && !content.isDragging
        updateHighlight()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
        refreshHover()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 1
        picture.contentsScale = scale
        border.contentsScale = scale
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // inVisibleRect follows scrolling and resizing without re-registering the area.
        if hoverArea == nil {
            let area = NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                owner: self, userInfo: nil
            )
            addTrackingArea(area)
            hoverArea = area
        }
        refreshHover()
    }

    private func refreshHover() {
        if let window, window.isKeyWindow, !isHiddenOrHasHiddenAncestor {
            // Non-clipping views can report a visibleRect larger than their own bounds.
            let hoverRect = bounds.intersection(visibleRect)
            hovered = hoverRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        } else {
            hovered = false
        }
        updateHighlight()
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        updateHighlight()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        updateHighlight()
    }

    private func updateHighlight() {
        let active = hovered && hoverEnabled
        guard highlighted != active, let layer else { return }
        highlighted = active
        let scale: CGFloat = active ? 1.02 : 1
        // Match SwiftUI's center-based scale without changing the view layer's anchor.
        var transform = CATransform3DMakeScale(scale, scale, 1)
        transform.m41 = (1 - scale) * layer.bounds.width * (0.5 - layer.anchorPoint.x)
        transform.m42 = (1 - scale) * layer.bounds.height * (0.5 - layer.anchorPoint.y)
        animate(layer, keyPath: "transform", to: NSValue(caTransform3D: transform))
        animate(layer, keyPath: "shadowOpacity", to: active ? Float(0.2) : Float(0))
        animate(border, keyPath: "opacity", to: active ? Float(1) : Float(0))
    }

    private func animate(_ target: CALayer, keyPath: String, to value: Any) {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = target.presentation()?.value(forKeyPath: keyPath) ?? target.value(forKeyPath: keyPath)
        animation.toValue = value
        animation.duration = 0.15
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        target.setValue(value, forKeyPath: keyPath)
        CATransaction.commit()
        target.add(animation, forKey: keyPath)
    }
}
