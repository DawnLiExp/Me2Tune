//
//  RotatingVinylLayer.swift
//  Me2Tune
//
//  GPU加速唱片旋转动画 - CABasicAnimation实现
//

import AppKit
import SwiftUI

struct RotatingVinylLayer: NSViewRepresentable {
    let artwork: NSImage?
    let isRotating: Bool
    let isRotationEnabled: Bool
    let vinylSize: CGFloat
    
    func makeNSView(context: Context) -> VinylHostView {
        let view = VinylHostView()
        view.wantsLayer = true
        view.layer?.masksToBounds = false
        
        setupVinylLayers(view: view)
        
        return view
    }
    
    func updateNSView(_ nsView: VinylHostView, context: Context) {
        // 更新封面
        if let artworkLayer = nsView.artworkLayer {
            updateArtwork(layer: artworkLayer, artwork: artwork)
        }
        
        // 控制动画状态
        let shouldRotate = isRotating && isRotationEnabled
        
        if shouldRotate {
            nsView.startRotation()
        } else {
            nsView.stopRotation()
        }
    }
    
    // MARK: - Setup Layers
    
    private func setupVinylLayers(view: VinylHostView) {
        guard let hostLayer = view.layer else { return }
        
        let bounds = CGRect(x: 0, y: 0, width: vinylSize, height: vinylSize)
        
        // 1. 唱片底盘
        let vinylBaseLayer = createVinylBaseLayer(bounds: bounds)
        
        // 2. 封面层
        let artworkLayer = createArtworkLayer(bounds: bounds)
        view.artworkLayer = artworkLayer
        
        // 3. 中心孔
        let centerHoleLayer = createCenterHoleLayer(bounds: bounds)
        
        // 添加到容器
        let containerLayer = CALayer()
        containerLayer.frame = bounds
        containerLayer.addSublayer(vinylBaseLayer)
        containerLayer.addSublayer(artworkLayer)
        containerLayer.addSublayer(centerHoleLayer)
        
        // 半圆遮罩（上半圆）
        let maskLayer = CAShapeLayer()
        let maskPath = CGMutablePath()
        let center = CGPoint(x: vinylSize / 2, y: vinylSize / 2)
        maskPath.addArc(
            center: center,
            radius: vinylSize / 2,
            startAngle: 0,        // 从右边开始
            endAngle: .pi,        // 到左边
            clockwise: false      // 逆时针 = 上半圆
        )
        maskPath.closeSubpath()
        maskLayer.path = maskPath
        hostLayer.mask = maskLayer
        
        // 阴影（使用shadowPath确保半圆阴影正确）
        let shadowPath = CGMutablePath()
        shadowPath.addArc(
            center: center,
            radius: vinylSize / 2,
            startAngle: 0,
            endAngle: .pi,
            clockwise: false
        )
        shadowPath.closeSubpath()
        
        containerLayer.shadowColor = NSColor.black.cgColor
        containerLayer.shadowOpacity = 0.6
        containerLayer.shadowOffset = CGSize(width: 0, height: 12)
        containerLayer.shadowRadius = 80
        containerLayer.shadowPath = shadowPath
        
        hostLayer.addSublayer(containerLayer)
        view.containerLayer = containerLayer
        
        // 初始化时更新封面
        updateArtwork(layer: artworkLayer, artwork: artwork)
    }
    
    // MARK: - Vinyl Base Layer
    
    private func createVinylBaseLayer(bounds: CGRect) -> CALayer {
        let layer = CAGradientLayer()
        layer.frame = bounds
        layer.type = .radial
        layer.colors = [
            NSColor(white: 0.16, alpha: 1).cgColor,
            NSColor(white: 0.08, alpha: 1).cgColor
        ]
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint = CGPoint(x: 1.0, y: 1.0)
        
        let circlePath = CGMutablePath()
        circlePath.addEllipse(in: bounds)
        
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = circlePath
        layer.mask = shapeLayer
        
        return layer
    }
    
    // MARK: - Artwork Layer
    
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
    
    private func updateArtwork(layer: CALayer, artwork: NSImage?) {
        // 移除旧的子层
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        
        if let artwork = artwork {
            layer.contents = artwork
            layer.contentsGravity = .resizeAspectFill
            layer.backgroundColor = nil
        } else {
            // 默认图标
            layer.contents = nil
            layer.backgroundColor = NSColor.clear.cgColor
            
            // 创建 SF Symbol 渲染图像
            let iconSize = CGSize(width: 100, height: 100)
            let config = NSImage.SymbolConfiguration(pointSize: 50, weight: .regular)
            
            if let icon = NSImage(systemSymbolName: "guitars.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                // 渲染成带颜色的图像
                let renderedImage = NSImage(size: iconSize)
                renderedImage.lockFocus()
                
                NSColor.gray.set()
                let iconRect = NSRect(
                    x: (iconSize.width - icon.size.width) / 2,
                    y: (iconSize.height - icon.size.height) / 2,
                    width: icon.size.width,
                    height: icon.size.height
                )
                icon.draw(in: iconRect)
                
                renderedImage.unlockFocus()
                
                layer.contents = renderedImage
                layer.contentsGravity = .center
            }
        }
    }
    
    // MARK: - Center Hole Layer
    
    private func createCenterHoleLayer(bounds: CGRect) -> CALayer {
        let container = CALayer()
        container.frame = bounds
        
        // 外圈渐变
        let outerGradient = CAGradientLayer()
        outerGradient.frame = CGRect(x: (vinylSize - 100) / 2, y: (vinylSize - 100) / 2, width: 100, height: 100)
        outerGradient.type = .radial
        outerGradient.colors = [
            NSColor(white: 0.18, alpha: 1).cgColor,
            NSColor(white: 0.12, alpha: 1).cgColor
        ]
        outerGradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        outerGradient.endPoint = CGPoint(x: 1.0, y: 1.0)
        
        let outerMask = CAShapeLayer()
        outerMask.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 100, height: 100), transform: nil)
        outerGradient.mask = outerMask
        
        // 中心黑孔
        let innerHole = CAShapeLayer()
        innerHole.frame = CGRect(x: (vinylSize - 30) / 2, y: (vinylSize - 30) / 2, width: 30, height: 30)
        innerHole.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 30, height: 30), transform: nil)
        innerHole.fillColor = NSColor.black.withAlphaComponent(0.9).cgColor
        innerHole.shadowColor = NSColor.black.cgColor
        innerHole.shadowOpacity = 0.8
        innerHole.shadowRadius = 8
        innerHole.shadowOffset = CGSize(width: 0, height: 2)
        
        // 高光
        let highlight = CAGradientLayer()
        highlight.frame = CGRect(x: (vinylSize - 30) / 2, y: (vinylSize - 30) / 2, width: 30, height: 30)
        highlight.type = .radial
        highlight.colors = [
            NSColor.white.withAlphaComponent(0.15).cgColor,
            NSColor.clear.cgColor
        ]
        highlight.startPoint = CGPoint(x: 0.35, y: 0.35)
        highlight.endPoint = CGPoint(x: 1.0, y: 1.0)
        
        let highlightMask = CAShapeLayer()
        highlightMask.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: 30, height: 30), transform: nil)
        highlight.mask = highlightMask
        
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
    
    private var isAnimationAdded = false
    private let rotationKey = "infiniteRotation"
    
    func startRotation() {
        guard let containerLayer = containerLayer else { return }
        
        if isAnimationAdded {
            // 已有动画，恢复播放
            let pausedTime = containerLayer.timeOffset
            containerLayer.speed = 1.0
            containerLayer.timeOffset = 0.0
            containerLayer.beginTime = 0.0
            let timeSincePause = containerLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            containerLayer.beginTime = timeSincePause
            return
        }
        
        // 首次创建无限旋转动画（顺时针）
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        rotation.fromValue = 0
        rotation.toValue = -Double.pi * 2  // 负值 = 顺时针
        rotation.duration = 36.0
        rotation.repeatCount = .infinity
        rotation.isRemovedOnCompletion = false
        
        containerLayer.add(rotation, forKey: rotationKey)
        isAnimationAdded = true
    }
    
    func stopRotation() {
        guard let containerLayer = containerLayer else { return }
        guard isAnimationAdded else { return }
        
        // 暂停动画但保持当前角度
        let pausedTime = containerLayer.convertTime(CACurrentMediaTime(), from: nil)
        containerLayer.speed = 0.0
        containerLayer.timeOffset = pausedTime
    }
}
