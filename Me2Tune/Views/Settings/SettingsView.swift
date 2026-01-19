//
//  SettingsView.swift
//  Me2Tune
//
//  设置界面 - 语言/主题/简洁模式/缓存设置
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var languageManager = LanguageManager.shared
    @ObservedObject private var cacheManager = CacheConfigManager.shared
    
    @State private var showLanguageChangeAlert = false
    @State private var showThemeChangeAlert = false
    @State private var pendingLanguage: LanguageManager.AppLanguage?
    @State private var pendingTheme: ThemeManager.ThemeMode?
    @State private var selectedTab = 0
    
    // 简洁模式
    @AppStorage("CleanMode") private var cleanMode = false
    
    var body: some View {
        VStack(spacing: 0) {
            customTabBar
            
            Divider()
            
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 360)
        .alert("language_change_title", isPresented: $showLanguageChangeAlert) {
            Button("restart_now") {
                if let language = pendingLanguage {
                    languageManager.setLanguage(language)
                    restartApp()
                }
                pendingLanguage = nil
            }
            Button("restart_later") {
                if let language = pendingLanguage {
                    languageManager.setLanguage(language)
                }
                pendingLanguage = nil
            }
            Button("cancel", role: .cancel) {
                pendingLanguage = nil
            }
        } message: {
            Text("language_change_message")
        }
        .alert("theme_change_title", isPresented: $showThemeChangeAlert) {
            Button("restart_now") {
                if let theme = pendingTheme {
                    themeManager.setThemeMode(theme)
                    restartApp()
                }
                pendingTheme = nil
            }
            Button("restart_later") {
                if let theme = pendingTheme {
                    themeManager.setThemeMode(theme)
                }
                pendingTheme = nil
            }
            Button("cancel", role: .cancel) {
                pendingTheme = nil
            }
        } message: {
            Text("theme_change_message")
        }
    }
    
    // MARK: - Custom Tab Bar
    
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(index: 0, title: String(localized: "settings_general"), icon: "gearshape")
            tabButton(index: 1, title: String(localized: "settings_advanced"), icon: "slider.horizontal.3")
            tabButton(index: 2, title: String(localized: "settings_about"), icon: "info.circle")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func tabButton(index: Int, title: String, icon: String) -> some View {
        Button(action: {
            selectedTab = index
        }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                Text(title)
                    .font(.system(size: 13))
            }
            .foregroundColor(selectedTab == index ? .accentColor : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case 0:
            generalSettings
        case 1:
            advancedSettings
        case 2:
            aboutSettings
        default:
            generalSettings
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("settings_language_label")
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { languageManager.currentLanguage },
                        set: { newLanguage in
                            guard newLanguage != languageManager.currentLanguage else { return }
                            pendingLanguage = newLanguage
                            showLanguageChangeAlert = true
                        }
                    )) {
                        ForEach(LanguageManager.AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            } header: {
                Text("settings_language_header")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .textCase(nil)
            }
            
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("settings_theme_label")
                        .font(.system(size: 13))
                    
                    Spacer()
                    
                    Picker("", selection: Binding(
                        get: { themeManager.themeMode },
                        set: { newMode in
                            guard newMode != themeManager.themeMode else { return }
                            pendingTheme = newMode
                            showThemeChangeAlert = true
                        }
                    )) {
                        ForEach(ThemeManager.ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
            } header: {
                Text("settings_appearance_header")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .textCase(nil)
            } footer: {
                Text("settings_theme_footer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
    
    // MARK: - Advanced Settings
    
    private var advancedSettings: some View {
        Form {
            // 缓存设置
            Section {
                // 第一行：标题
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("cache_location")
                        .font(.system(size: 13))
                }
                .padding(.bottom, 4)
                
                // 第二行：当前路径 + 状态 + Finder按钮
                HStack(spacing: 8) {
                    // 状态图标
                    Image(systemName: cacheManager.isCustomPathWritable ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(cacheManager.isCustomPathWritable ? .green : .red)
                    
                    // 路径文本
                    Text(displayCachePath)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    // Finder 按钮
                    Button(action: {
                        cacheManager.revealInFinder()
                    }) {
                        Image(systemName: "magnifyingglass.circle")
                            .font(.system(size: 14))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // 第三行：选择目录按钮
                HStack {
                    Spacer()
                    
                    Button(action: selectCacheDirectory) {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 12))
                            Text("select_directory")
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    
                    // 恢复默认按钮
                    if cacheManager.customCachePath != nil {
                        Button(action: {
                            cacheManager.setCustomCachePath(nil)
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 12))
                                Text("reset_default")
                                    .font(.system(size: 12))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color(NSColor.controlBackgroundColor))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Spacer()
                }
                .padding(.top, 4)
                
            } header: {
                Text("cache_settings_header")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .textCase(nil)
            } footer: {
                Text(
                    String(
                        format: String(localized: "cache_settings_footer"),
                        CacheConfigManager.maxCacheCount
                    )
                )

                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            // 视觉效果设置
            Section {
                Toggle("settings_clean_mode", isOn: $cleanMode)
            } header: {
                Text("settings_visual_header")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
                    .textCase(nil)
            } footer: {
                Text("settings_clean_mode_footer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
    }
    
    // MARK: - About Settings
    
    private var aboutSettings: some View {
        VStack(spacing: 20) {
            Spacer()
            
            // App Icon
            if let appIcon = NSImage(named: "AppIcon") {
                Image(nsImage: appIcon)
                    .resizable()
                    .frame(width: 80, height: 80)
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.2), radius: 4)
            } else {
                Image(systemName: "headphones")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .foregroundColor(.accentColor)
            }
            
            // App Name & Version
            VStack(spacing: 6) {
                Text("Me2Tune")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                   let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                {
                    Text("Version \(version) (\(build))")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }
            
            // Copyright
            Text("© 2025 Me2Tune")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }
    
    // MARK: - Helpers
    
    private var displayCachePath: String {
        if let customPath = cacheManager.customCachePath {
            return customPath.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return "~/Library/Caches/Me2Tune"
    }
    
    private func selectCacheDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "select_cache_directory_message")
        
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            
            Task { @MainActor in
                cacheManager.setCustomCachePath(url)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open '\(Bundle.main.bundlePath)'"]
        task.launch()
        
        NSApp.terminate(nil)
    }
}

#Preview {
    SettingsView()
}
