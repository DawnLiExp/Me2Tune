//
//  SettingsView.swift
//  Me2Tune
//
//  Settings interface - Features/Appearance/Statistics/About
//

import OSLog
import SwiftData
import SwiftUI

private let logger = Logger.persistence

struct SettingsView: View {
    private enum SettingsTab: CaseIterable, Identifiable {
        case features
        case appearance
        case statistics
        case about

        var id: Self { self }

        var titleKey: LocalizedStringKey {
            switch self {
            case .features:
                "settings_features"
            case .appearance:
                "settings_appearance"
            case .statistics:
                "settings_statistics"
            case .about:
                "settings_about"
            }
        }

        var iconName: String {
            switch self {
            case .features:
                "slider.horizontal.3"
            case .appearance:
                "paintpalette"
            case .statistics:
                "chart.bar"
            case .about:
                "info.circle"
            }
        }

        var windowHeight: CGFloat {
            switch self {
            case .features:
                480
            case .appearance:
                340
            case .statistics:
                530
            case .about:
                340
            }
        }
    }

    @State private var currentTheme = ThemeManager.shared.themeMode
    @State private var currentLanguage = LanguageManager.shared.currentLanguage
    
    // CacheConfigManager
    private let cacheManager = CacheConfigManager.shared
    
    @State private var showLanguageChangeAlert = false
    @State private var showThemeChangeAlert = false
    @State private var pendingLanguage: LanguageManager.AppLanguage?
    @State private var pendingTheme: ThemeManager.ThemeMode?
    @State private var selectedTab: SettingsTab = .features
    
    @State private var statisticsViewModel = StatisticsViewModel()
    @State private var showResetConfirmation = false

    @AppStorage("CleanMode") private var cleanMode = false
    @AppStorage("nowPlayingEnabled") private var nowPlayingEnabled = true
    @AppStorage("audioBufferingEnabled") private var audioBufferingEnabled = false
    @AppStorage("backgroundGlowMode") private var backgroundGlowMode = BackgroundGlowMode.legacy.rawValue
    @AppStorage("glowBreathingRate") private var glowBreathingRate = GlowBreathingRate.medium.rawValue
    @AppStorage("glowBreathingIntensity") private var glowBreathingIntensity = GlowBreathingIntensity.medium.rawValue
    
    var body: some View {
        VStack(spacing: 0) {
            customTabBar
            
            Divider()
            
            tabContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 500, height: selectedTab.windowHeight)
        .background(Color(NSColor.windowBackgroundColor))
        .background(
            SettingsWindowPresentationObserver(
                onPresented: {
                    statisticsViewModel.schedulePresentationRefresh(delay: .seconds(1))
                },
                onClosed: {
                    statisticsViewModel.cancelScheduledPresentationRefresh()
                }
            )
        )
        .onChange(of: selectedTab) { _, newTab in
            adjustWindowHeight(for: newTab)
        }
        .onAppear {
            adjustWindowHeight(for: selectedTab)
        }
        .onDisappear {
            statisticsViewModel.cancelScheduledPresentationRefresh()
        }
        .alert("language_change_title", isPresented: $showLanguageChangeAlert) {
            Button("restart_now") {
                if let language = pendingLanguage {
                    LanguageManager.shared.setLanguage(language)
                    restartApp()
                }
                pendingLanguage = nil
            }
            Button("restart_later") {
                if let language = pendingLanguage {
                    LanguageManager.shared.setLanguage(language)
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
                    ThemeManager.shared.setThemeMode(theme)
                    restartApp()
                }
                pendingTheme = nil
            }
            Button("restart_later") {
                if let theme = pendingTheme {
                    ThemeManager.shared.setThemeMode(theme)
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
            ForEach(SettingsTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    private func tabButton(_ tab: SettingsTab) -> some View {
        Button(action: {
            selectedTab = tab
        }) {
            HStack(spacing: 6) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 13))
                Text(tab.titleKey)
                    .font(.system(size: 13))
            }
            .foregroundColor(selectedTab == tab ? .accentColor : Color(NSColor.secondaryLabelColor))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selectedTab == tab ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Tab Content
    
    private var tabContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                switch selectedTab {
                case .features:
                    featuresSettings
                case .appearance:
                    appearanceSettings
                case .statistics:
                    StatisticsView(viewModel: statisticsViewModel)
                case .about:
                    aboutSettings
                }
            }
            .padding(24)
        }
    }
    
    // MARK: - Features Settings
    
    private var featuresSettings: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: "folder.badge.gearshape")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .frame(width: 20)
                    
                    Text("cache_location")
                        .font(.system(size: 12))
                    
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
                                        .font(.system(size: 11))
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
            
            VStack(spacing: 16) {
                settingRow(icon: "waveform.circle", label: "audio_buffering", helpText: "audio_buffering_footer") {
                    Toggle(isOn: $audioBufferingEnabled) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
                
                settingRow(icon: "music.note.list", label: "now_playing_sync", helpText: "now_playing_sync_footer") {
                    Toggle(isOn: $nowPlayingEnabled) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .onChange(of: nowPlayingEnabled) { _, newValue in
                        if !newValue {
                            NowPlayingService.shared.setPlaceholderInfo()
                        }
                    }
                }
            }

            Divider()

            // MARK: Danger Zone

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                    Text("settings_danger_zone")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.8))
                    Spacer()
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("settings_reset_db")
                            .font(.system(size: 13))
                        Text("settings_reset_db_description")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(role: .destructive) {
                        showResetConfirmation = true
                    } label: {
                        Label("settings_reset_db_button", systemImage: "trash")
                            .font(.system(size: 12))
                    }
                    .confirmationDialog(
                        "settings_reset_db",
                        isPresented: $showResetConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("settings_reset_db_confirm", role: .destructive) { resetDatabase() }
                        Button("cancel", role: .cancel) {}
                    } message: {
                        Text("settings_reset_db_message")
                    }
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.05))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.15), lineWidth: 1)
                        )
                )
            }
        }
    }
    
    // MARK: - Appearance Settings

    private var appearanceSettings: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                settingRow(icon: "globe", label: "settings_language_label") {
                    Picker(selection: $currentLanguage) {
                        ForEach(LanguageManager.AppLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: currentLanguage) { _, newLanguage in
                        if newLanguage != LanguageManager.shared.currentLanguage {
                            pendingLanguage = newLanguage
                            showLanguageChangeAlert = true
                        }
                    }
                }
                
                settingRow(icon: "paintpalette", label: "settings_theme_label", helpText: "settings_theme_footer") {
                    Picker(selection: $currentTheme) {
                        ForEach(ThemeManager.ThemeMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                    .onChange(of: currentTheme) { _, newMode in
                        if newMode != ThemeManager.shared.themeMode {
                            pendingTheme = newMode
                            showThemeChangeAlert = true
                        }
                    }
                }
            }
            
            Divider()
            
            VStack(spacing: 16) {
                settingRow(icon: "wand.and.stars", label: "settings_glow_mode", helpText: "settings_glow_mode_footer") {
                    Picker(selection: $backgroundGlowMode) {
                        ForEach(BackgroundGlowMode.allCases) { mode in
                            Text(mode.displayName).tag(mode.rawValue)
                        }
                    } label: {
                        EmptyView()
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 140)
                }
                
                Group {
                    settingRow(icon: "speedometer", label: "glow_breathing_rate") {
                        TickedSlider<GlowBreathingRate>(
                            selection: $glowBreathingRate,
                            leftLabel: "glow_rate_slow_short",
                            rightLabel: "glow_rate_fast_short"
                        )
                    }
                    
                    settingRow(icon: "waveform", label: "glow_breathing_intensity") {
                        TickedSlider<GlowBreathingIntensity>(
                            selection: $glowBreathingIntensity,
                            leftLabel: "glow_intensity_weak_short",
                            rightLabel: "glow_intensity_strong_short"
                        )
                    }
                }
                .disabled(backgroundGlowMode != BackgroundGlowMode.meshGradient.rawValue)
                .opacity(backgroundGlowMode == BackgroundGlowMode.meshGradient.rawValue ? 1 : 0.4)

                settingRow(icon: "sparkles", label: "settings_clean_mode", helpText: "settings_clean_mode_footer") {
                    Toggle(isOn: $cleanMode) {
                        EmptyView()
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                }
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
                        Text(versionText(version: version, build: build))
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
                        Text("settings_website")
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

    private func versionText(version: String, build: String) -> String {
        let format = String(localized: "settings_version_format")
        return String(format: format, locale: Locale.current, version, build)
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
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                
                if let helpText {
                    HelpPopoverButton(helpText: helpText)
                }
            }
            .layoutPriority(1)
            
            Spacer(minLength: 20)
            
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

    private func resetDatabase() {
        guard let storeURL = DataService.shared.modelContainer.configurations.first?.url else {
            logger.error("❌ resetDatabase: could not resolve store URL")
            return
        }

        let suffixes = ["", "-shm", "-wal"]
        for suffix in suffixes {
            let target = URL(fileURLWithPath: storeURL.path + suffix)
            try? FileManager.default.removeItem(at: target)
        }

        logger.info("🗑️ Database reset - restarting")
        restartApp()
    }
    
    private func restartApp() {
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", "sleep 0.5; open '\(Bundle.main.bundlePath)'"]
        task.launch()
        
        NSApp.terminate(nil)
    }
    
    private func adjustWindowHeight(for tab: SettingsTab) {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isKeyWindow }) else {
            return
        }
        
        let targetHeight = tab.windowHeight
        var frame = window.frame
        let heightDifference = targetHeight - frame.height
        
        frame.origin.y -= heightDifference
        frame.size.height = targetHeight
   
        window.setFrame(frame, display: true)
    }
}

// MARK: - HelpPopoverButton

private struct HelpPopoverButton: View {
    let helpText: LocalizedStringKey
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 11))
                .foregroundColor(isPresented ? .accentColor : .secondary.opacity(0.6))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            Text(helpText)
                .font(.system(size: 12))
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .fixedSize()
        }
    }
}

#Preview {
    SettingsView()
}
