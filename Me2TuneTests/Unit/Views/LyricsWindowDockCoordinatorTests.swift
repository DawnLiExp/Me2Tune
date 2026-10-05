//
//  LyricsWindowDockCoordinatorTests.swift
//  Me2TuneTests
//
//  歌词窗口吸附联动单元测试
//

import AppKit
import Foundation
import Testing
@testable import Me2Tune

@MainActor
@Suite("LyricsWindowDockCoordinator 单元测试")
struct LyricsWindowDockCoordinatorTests {
    @Test("右边缘磁吸：靠近主窗口右侧时自动吸附并对齐顶部")
    func testSnappingToRightEdge() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        #expect(!coordinator.isDocked)
        
        // 拖动歌词面板靠近主窗口右边缘 (main.maxX = 595)，距离 10 pt（< 22 pt 阈值）
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        
        #expect(coordinator.isDocked)
        #expect(coordinator.dockEdge == .right)
        #expect(lyrics.frame.origin.x == 595)
        #expect(lyrics.frame.origin.y == 100) // 自动吸附对齐顶部/底部
    }
    
    @Test("左边缘磁吸：靠近主窗口左侧时自动吸附并对齐顶部")
    func testSnappingToLeftEdge() {
        let main = NSWindow(contentRect: NSRect(x: 500, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 0, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        #expect(!coordinator.isDocked)
        
        // 拖动歌词面板靠近主窗口左边缘 (main.minX = 500)，期望 X 为 500 - 440 = 60
        // 距离 10 pt
        lyrics.setFrameOrigin(NSPoint(x: 50, y: 105))
        
        #expect(coordinator.isDocked)
        #expect(coordinator.dockEdge == .left)
        #expect(lyrics.frame.origin.x == 60)
        #expect(lyrics.frame.origin.y == 100)
    }
    
    @Test("联动整体移动：吸附后移动主面板，歌词面板同步跟随")
    func testMovingMainWindowMovesBothTogether() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        #expect(coordinator.isDocked)
        
        // 移动主窗口 (+50, +30)
        main.setFrameOrigin(NSPoint(x: 150, y: 130))
        
        // 歌词窗口在系统 WindowServer 底层同步跟随移动
        #expect(lyrics.frame.origin.x == 150 + 495)
        #expect(lyrics.frame.origin.y == 130)
    }
    
    @Test("微移防抖：吸附状态下小幅度拖拽保持磁吸锁定")
    func testSmallDragRetainsMagneticLatch() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        #expect(coordinator.isDocked)
        
        // 微移 10 pt（< 30 pt 脱离阈值）
        lyrics.setFrameOrigin(NSPoint(x: lyrics.frame.origin.x + 10, y: lyrics.frame.origin.y))
        
        #expect(coordinator.isDocked)
        #expect(lyrics.frame.origin.x == 595) // 保持锁定在 595
    }
    
    @Test("脱离吸附：大幅度拖拽歌词面板后解除吸附，主窗口不再带动歌词面板")
    func testPullingLyricsWindowAwayUndocks() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        #expect(coordinator.isDocked)
        
        // 大幅度拉开 50 pt（> 30 pt 脱离阈值）
        lyrics.setFrameOrigin(NSPoint(x: lyrics.frame.origin.x + 50, y: lyrics.frame.origin.y))
        
        #expect(!coordinator.isDocked)
        #expect(lyrics.frame.origin.x == 595 + 50)
        
        // 解绑后移动主面板，歌词面板不再移动
        let lyricsXBefore = lyrics.frame.origin.x
        main.setFrameOrigin(NSPoint(x: 300, y: 100))
        #expect(lyrics.frame.origin.x == lyricsXBefore)
    }
    
    @Test("主窗口尺寸变化自适应：吸附状态下主窗口调整大小时歌词面板自动保持贴边")
    func testMainWindowResizeKeepsDockedAlignment() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        #expect(coordinator.isDocked)
        
        // 主窗口宽度增加 50 pt
        main.setFrame(NSRect(x: 100, y: 100, width: 545, height: 750), display: true)
        
        #expect(lyrics.frame.origin.x == 100 + 545)
    }
    
    @Test("通知发送：磁吸触发时发送 lyricsWindowDidDock 通知且包含吸附边")
    func testDockNotificationPostedWithEdge() {
        let main = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 495, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 100, width: 440, height: 750), styleMask: [.titled], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        var receivedEdge: LyricsDockEdge?
        let observer = NotificationCenter.default.addObserver(
            forName: .lyricsWindowDidDock,
            object: coordinator,
            queue: .main
        ) { notification in
            receivedEdge = notification.userInfo?["edge"] as? LyricsDockEdge
        }
        
        lyrics.setFrameOrigin(NSPoint(x: 605, y: 105))
        #expect(coordinator.isDocked)
        #expect(receivedEdge == .right)
        
        NotificationCenter.default.removeObserver(observer)
    }
    
    @Test("顶部对齐：吸附时歌词面板顶部与主面板顶部严格对齐")
    func testTopAlignmentWhenDocked() {
        let main = NSWindow(contentRect: NSRect(x: 200, y: 150, width: 495, height: 750), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        let lyrics = LyricsWindow(contentRect: NSRect(x: 800, y: 150, width: 440, height: 750), styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        main.orderFront(nil)
        lyrics.orderFront(nil)
        
        let coordinator = LyricsWindowDockCoordinator(mainWindow: main, lyricsWindow: lyrics)
        lyrics.dockCoordinator = coordinator
        
        // 拖动靠近右侧（Y 坐标略有偏差 15 pt，在 28 pt 阈值内）
        lyrics.setFrameOrigin(NSPoint(x: main.frame.maxX + 10, y: 150 + 15))
        
        #expect(coordinator.isDocked)
        #expect(lyrics.frame.maxY == main.frame.maxY)
        #expect(lyrics.frame.origin.y == main.frame.origin.y)
    }
}
