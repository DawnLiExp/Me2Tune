//
//  RotatingVinylLayer.swift
//  Me2Tune
//
//  GPU加速唱片旋转动画 - CABasicAnimation实现 + Coordinator状态管理
//

import AppKit
import OSLog
import SwiftUI

private let logger = Logger.vinyl

struct RotatingVinylLayer: NSViewRepresentable {
    let artwork: NSImage?
    let shouldRotate: Bool
    let vinylSize: CGFloat
    
    // MARK: - NSViewRepresentable
    
    func makeNSView(context: Context) -> VinylHostView {
        let view = VinylHostView()
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        
        setupVinylLayers(view: view)
        
        // ✅ 立即初始化封面状态（解决冷启动和无封面问题）
        context.coordinator.currentArtwork = artwork
        updateArtwork(layer: view.artworkLayer, artwork: artwork)

        return view
    }
    
    func updateNSView(_ nsView: VinylHostView, context: Context) {
        let coordinator = context.coordinator
        
        // ✅ 明确处理所有封面状态转换
        let needsUpdate: Bool = switch (coordinator.currentArtwork, artwork) {
        case (nil, nil):
            // 都是 nil，不需要更新
            false
        case (nil, .some):
            true
        case (.some, nil):
            // 有封面 -> nil（需要显示默认图标）
            true
        case (.some(let old), .some(let new)):
            // 都有封面，比较引用是否相同
            old !== new
        }
        
        if needsUpdate {
            coordinator.currentArtwork = artwork
            updateArtwork(layer: nsView.artworkLayer, artwork: artwork)
            logger.debug("🔄 Artwork updated: \(artwork != nil ? "image" : "default icon")")
        }
        
        if coordinator.isRotating != shouldRotate {
            let oldState = coordinator.isRotating
            coordinator.isRotating = shouldRotate
            
            if shouldRotate {
                nsView.startRotation()
            } else {
                nsView.pauseRotation()
            }
            
            logger.debug("🔄 Rotation state changed: \(oldState) → \(shouldRotate)")
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    // MARK: - Coordinator
    
    final class Coordinator {
        var currentArtwork: NSImage?
        var isRotating = false
    }
    
    // MARK: - Layer Setup
    
    private func setupVinylLayers(view: VinylHostView) {
        guard let hostLayer = view.layer else { return }
        
        let bounds = CGRect(x: 0, y: 0, width: vinylSize, height: vinylSize)
        
        let vinylBaseLayer = createVinylBaseLayer(bounds: bounds)
        let artworkLayer = createArtworkLayer(bounds: bounds)
        let centerHoleLayer = createCenterHoleLayer(bounds: bounds)
        
        view.artworkLayer = artworkLayer
        
        let containerLayer = CALayer()
        containerLayer.frame = bounds
        containerLayer.addSublayer(vinylBaseLayer)
        containerLayer.addSublayer(artworkLayer)
        containerLayer.addSublayer(centerHoleLayer)
        
        setupHalfCircleMask(on: hostLayer, bounds: bounds)
        setupHalfCircleShadow(on: containerLayer, bounds: bounds)
        
        hostLayer.addSublayer(containerLayer)
        view.containerLayer = containerLayer
    }
    
    private func setupHalfCircleMask(on layer: CALayer, bounds: CGRect) {
        let maskLayer = CAShapeLayer()
        let maskPath = CGMutablePath()
        let center = CGPoint(x: vinylSize / 2, y: vinylSize / 2)
        maskPath.addArc(
            center: center,
            radius: vinylSize / 2,
            startAngle: 0,
            endAngle: .pi,
            clockwise: false
        )
        maskPath.closeSubpath()
        maskLayer.path = maskPath
        layer.mask = maskLayer
    }
    
    private func setupHalfCircleShadow(on layer: CALayer, bounds: CGRect) {
        let shadowPath = CGMutablePath()
        let center = CGPoint(x: vinylSize / 2, y: vinylSize / 2)
        shadowPath.addArc(
            center: center,
            radius: vinylSize / 2,
            startAngle: 0,
            endAngle: .pi,
            clockwise: false
        )
        shadowPath.closeSubpath()
        
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.6
        layer.shadowOffset = CGSize(width: 0, height: 12)
        layer.shadowRadius = 20
        layer.shadowPath = shadowPath
    }
    
    // MARK: - Layer Creation
    
    private func createVinylBaseLayer(bounds: CGRect) -> CALayer {
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = bounds
        gradientLayer.type = .radial
        gradientLayer.colors = [
            NSColor(white: 0.20, alpha: 1).cgColor,
            NSColor(white: 0.10, alpha: 1).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        gradientLayer.configureCircularMask(bounds: bounds)
        
        return gradientLayer
    }
    
    private func createArtworkLayer(bounds: CGRect) -> CALayer {
        let layer = CALayer()
        let artworkSize: CGFloat = 255
        let offset = (vinylSize - artworkSize) / 2
        
        layer.frame = CGRect(
            x: offset,
            y: offset,
            width: artworkSize,
            height: artworkSize
        )
        layer.cornerRadius = artworkSize / 2
        layer.masksToBounds = true
        layer.borderWidth = 2.5
        layer.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        
        return layer
    }
    
    private func updateArtwork(layer: CALayer?, artwork: NSImage?) {
        guard let layer else { return }
        
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        layer.contents = nil
        
        if let artwork {
            layer.contents = artwork
            layer.contentsGravity = .resizeAspectFill
            layer.backgroundColor = nil
        } else {
            layer.backgroundColor = NSColor.clear.cgColor
            layer.contents = createDefaultMusicIcon()
            layer.contentsGravity = .center
        }
    }
    
    private func createDefaultMusicIcon() -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 70, weight: .regular)
        
        guard let baseImage = NSImage(systemSymbolName: "guitars.fill", accessibilityDescription: nil),
              let configuredImage = baseImage.withSymbolConfiguration(config)
        else {
            return nil
        }
        
        return configuredImage.tinted(with: .gray)
    }
    
    private func createCenterHoleLayer(bounds: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        
        let outerGradient = CAGradientLayer()
        outerGradient.frame = CGRect(
            x: (vinylSize - 100) / 2,
            y: (vinylSize - 100) / 2,
            width: 100,
            height: 100
        )
        outerGradient.type = .radial
        outerGradient.colors = [
            NSColor(white: 0.26, alpha: 1).cgColor,
            NSColor(white: 0.08, alpha: 1).cgColor
        ]
        outerGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        outerGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        outerGradient.configureCircularMask(bounds: CGRect(x: 0, y: 0, width: 100, height: 100))
        
        let innerHole = CAShapeLayer()
        innerHole.frame = CGRect(
            x: (vinylSize - 30) / 2,
            y: (vinylSize - 30) / 2,
            width: 30,
            height: 30
        )
        innerHole.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 30, height: 30), transform: nil)
        innerHole.fillColor = NSColor.black.withAlphaComponent(0.9).cgColor
        innerHole.applyDropShadow()
        
        let highlight = CAGradientLayer()
        highlight.frame = innerHole.frame
        highlight.type = .radial
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.25).cgColor,
            NSColor.clear.cgColor
        ]
        highlight.startPoint = CGPoint(x: 0.35, y: 0.35)
        highlight.endPoint = CGPoint(x: 1.0, y: 1.0)
        highlight.configureCircularMask(bounds: CGRect(x: 0, y: 0, width: 30, height: 30))
        
        container.addSublayer(outerGradient)
        container.addSublayer(innerHole)
        container.addSublayer(highlight)
        
        return container
    }
}

// MARK: - Host View

final class VinylHostView: NSView {
    weak var containerLayer: CALayer?
    weak var artworkLayer: CALayer?
    
    private let rotationKey = "infiniteRotation"
    
    // MARK: - Rotation Control
    
    func startRotation() {
        guard let containerLayer else { return }
        
        if containerLayer.animation(forKey: rotationKey) == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.fromValue = 0
            rotation.toValue = -Double.pi * 2
            rotation.duration = 39.0
            rotation.repeatCount = .infinity
            rotation.isRemovedOnCompletion = false
            
            containerLayer.add(rotation, forKey: rotationKey)
            logger.debug("▶️ Started vinyl rotation")
        } else {
            resumeLayer(containerLayer)
        }
    }
    
    func pauseRotation() {
        guard let containerLayer,
              containerLayer.animation(forKey: rotationKey) != nil else { return }
        pauseLayer(containerLayer)
    }
    
    // MARK: - CALayer Pause/Resume
    
    private func pauseLayer(_ layer: CALayer) {
        let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
        layer.speed = 0.0
        layer.timeOffset = pausedTime
        logger.debug("⏸ Paused vinyl rotation")
    }
    
    private func resumeLayer(_ layer: CALayer) {
        let pausedTime = layer.timeOffset
        layer.speed = 1.0
        layer.timeOffset = 0.0
        layer.beginTime = 0.0
        let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
        layer.beginTime = timeSincePause
        logger.debug("▶️ Resumed vinyl rotation")
    }
}

// MARK: - Helper Extensions

private extension CAGradientLayer {
    func configureCircularMask(bounds: CGRect) {
        let mask = CAShapeLayer()
        mask.path = CGPath(ellipseIn: bounds, transform: nil)
        self.mask = mask
    }
}

private extension CAShapeLayer {
    func applyDropShadow() {
        shadowColor = NSColor.black.cgColor
        shadowOpacity = 0.8
        shadowRadius = 8
        shadowOffset = CGSize(width: 0, height: 2)
    }
}

private extension NSImage {
    func tinted(with color: NSColor) -> NSImage {
        let image = self.copy() as! NSImage
        image.lockFocus()
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        return image
    }
}
