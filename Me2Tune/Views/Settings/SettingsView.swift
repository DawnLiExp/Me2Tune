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
    
    @AppStorage("CleanMode") private var cleanMode = false
    @AppStorage("nowPlayingEnabled") private var nowPlayingEnabled = true
    @AppStorage("audioBufferingEnabled") private var audioBufferingEnabled = false
    
    var body: some View {
        VStack(spacing: 0) {
            customTabBar
            
            Divider()
            
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: 350)
        .background(Color(NSColor.windowBackgroundColor))
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
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = index
            }
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
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == index ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Content
    
    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 24) {
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
            .padding(24)
        }
    }
    
    // MARK: - General Settings
    
    private var generalSettings: some View {
        VStack(spacing: 16) {
            // 语言设置
            settingRow(icon: "globe", label: "settings_language_label") {
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
            
            Divider()
                .padding(.leading, 32)
            
            // 主题设置
            settingRow(icon: "paintpalette", label: "settings_theme_label", helpText: "settings_theme_footer") {
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
        }
    }
    
    // MARK: - Advanced Settings
    
    private var advancedSettings: some View {
        VStack(spacing: 20) {
            // 缓存设置
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("cache_location")
                        .font(.system(size: 13))
                    
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: cacheManager.isCustomPathWritable ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(cacheManager.isCustomPathWritable ? .green : .red)
                        
                        Text(displayCachePath)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        Spacer()
                        
                        Button(action: {
                            cacheManager.revealInFinder()
                        }) {
                            Image(systemName: "magnifyingglass.circle")
                                .font(.system(size: 14))
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                        .help(Text("reveal_in_finder"))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(NSColor.controlBackgroundColor))
                    )
                    
                    HStack(spacing: 12) {
                        Button(action: selectCacheDirectory) {
                            HStack(spacing: 6) {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 11))
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
                                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        
                        if cacheManager.customCachePath != nil {
                            Button(action: {
                                cacheManager.setCustomCachePath(nil)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 11))
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
                    }
                }
                
                Text(String(format: String(localized: "cache_settings_footer"), CacheConfigManager.maxCacheCount))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 32)
            }
            
            Divider()
            
            // 音频缓冲
            settingRow(icon: "waveform.circle", label: "audio_buffering", helpText: "audio_buffering_footer") {
                Toggle("", isOn: $audioBufferingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            
            Divider()

            // Now Playing 同步
            settingRow(icon: "music.note.list", label: "now_playing_sync", helpText: "now_playing_sync_footer") {
                Toggle("", isOn: $nowPlayingEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
            
            Divider()
            
            // 视觉效果
            settingRow(icon: "sparkles", label: "settings_clean_mode", helpText: "settings_clean_mode_footer") {
                Toggle("", isOn: $cleanMode)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
    }
    
    // MARK: - About Settings
    
    private var aboutSettings: some View {
        VStack(spacing: 24) {
            // App Info
            VStack(spacing: 16) {
                if let appIcon = NSImage(named: "AppIcon") {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 72, height: 72)
                        .cornerRadius(14)
                        .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                } else {
                    Image(systemName: "headphones")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 64, height: 64)
                        .foregroundColor(.accentColor)
                }
                
                VStack(spacing: 4) {
                    Text("Me2Tune")
                        .font(.system(size: 20, weight: .bold))
                    
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                       let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
                    {
                        Text("Version \(version) (\(build))")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            VStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/DawnLiExp/Me2Tune")!) {
                    HStack(spacing: 6) {
                        Image(systemName: "link")
                            .font(.system(size: 12))
                        Text("Website")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                
                Text("© 2025 Me2Tune")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.tertiaryLabelColor))
            }
        }
        .padding(.top, 10)
    }
    
    // MARK: - Components
    
    private func settingRow(
        icon: String,
        label: LocalizedStringKey,
        helpText: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 13))
                
                if let helpText {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.6))
                        .help(Text(helpText))
                }
            }
            
            Spacer()
            
            content()
        }
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
