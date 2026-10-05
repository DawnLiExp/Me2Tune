//
//  AudioTagEditorView.swift
//  Me2Tune
//
//  音频文件详细 Tag 元数据读取与编辑面板 - macOS 原生多标签页风格
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

public struct AudioTagEditorView: View {
    let trackURL: URL
    let onDismiss: () -> Void
    var onSaved: ((DetailedAudioMetadata) -> Void)? = nil

    @State private var metadata: DetailedAudioMetadata?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var selectedTab: Tab = .details
    @State private var isDropTargeted = false

    private var theme: ThemeColors {
        ThemeManager.shared.currentTheme.colors
    }

    public enum Tab: String, CaseIterable, Identifiable {
        case details = "details"
        case artwork = "artwork"
        case lyrics = "lyrics"
        case file = "file"

        public var id: String { rawValue }

        var title: String {
            switch self {
            case .details: return String(localized: "tag_tab_details", defaultValue: "详细信息")
            case .artwork: return String(localized: "tag_tab_artwork", defaultValue: "封面插图")
            case .lyrics: return String(localized: "tag_tab_lyrics", defaultValue: "内嵌歌词")
            case .file: return String(localized: "tag_tab_file", defaultValue: "文件属性")
            }
        }

        var icon: String {
            switch self {
            case .details: return "info.circle"
            case .artwork: return "photo"
            case .lyrics: return "quote.bubble"
            case .file: return "doc.text"
            }
        }
    }

    public init(
        trackURL: URL,
        onDismiss: @escaping () -> Void,
        onSaved: ((DetailedAudioMetadata) -> Void)? = nil
    ) {
        self.trackURL = trackURL
        self.onDismiss = onDismiss
        self.onSaved = onSaved
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()

            if isLoading {
                loadingView
            } else if let errorMessage, metadata == nil {
                errorView(errorMessage)
            } else if metadata != nil {
                tabPickerBar
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                Divider()

                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                bottomBar
            }
        }
        .frame(width: 580, height: 600)
        .background(theme.mainBackground)
        .task {
            await loadMetadata()
        }
        .alert(
            String(localized: "tag_save_error_title", defaultValue: "保存失败"),
            isPresented: Binding(
                get: { errorMessage != nil && metadata != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button(String(localized: "ok", defaultValue: "好")) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Image(systemName: "music.note.list")
                .foregroundColor(theme.accent)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(metadata?.title.isEmpty == false ? metadata!.title : trackURL.lastPathComponent)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(theme.primaryText)
                    .lineLimit(1)

                Text(metadata?.artist.isEmpty == false ? metadata!.artist : String(localized: "unknown_artist", defaultValue: "未知艺术家"))
                    .font(.system(size: 12))
                    .foregroundColor(theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(theme.secondaryText.opacity(0.8))
                    .font(.system(size: 18))
            }
            .buttonStyle(.plain)
            .help(String(localized: "close", defaultValue: "关闭"))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Picker Bar

    private var tabPickerBar: some View {
        HStack(spacing: 8) {
            ForEach(Tab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12))
                        Text(tab.title)
                            .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                    }
                    .foregroundColor(selectedTab == tab ? theme.accent : theme.secondaryText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(selectedTab == tab ? theme.accent.opacity(0.15) : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        ScrollView {
            Group {
                switch selectedTab {
                case .details:
                    detailsTab
                case .artwork:
                    artworkTab
                case .lyrics:
                    lyricsTab
                case .file:
                    filePropertiesTab
                }
            }
            .padding(20)
        }
    }

    // MARK: - Tab 1: Details

    @ViewBuilder
    private var detailsTab: some View {
        if let binding = Binding($metadata) {
            VStack(spacing: 14) {
                editorRow(label: String(localized: "tag_title", defaultValue: "标题")) {
                    TextField("", text: binding.title)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_artist", defaultValue: "艺术家")) {
                    TextField("", text: binding.artist)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_album", defaultValue: "唱片集")) {
                    TextField("", text: binding.album)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_album_artist", defaultValue: "唱片集艺术家")) {
                    TextField("", text: binding.albumArtist)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_composer", defaultValue: "作曲者")) {
                    TextField("", text: binding.composer)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_genre", defaultValue: "流派")) {
                    TextField("", text: binding.genre)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_year", defaultValue: "年份 / 日期")) {
                    TextField("", text: binding.year)
                        .textFieldStyle(.roundedBorder)
                }

                editorRow(label: String(localized: "tag_track_number", defaultValue: "音轨编号")) {
                    HStack(spacing: 8) {
                        numericTextField(value: binding.trackNumber, placeholder: String(localized: "track_no", defaultValue: "编号"))
                        Text("/")
                            .foregroundColor(theme.secondaryText)
                        numericTextField(value: binding.trackTotal, placeholder: String(localized: "total", defaultValue: "总数"))
                        Spacer()
                    }
                }

                editorRow(label: String(localized: "tag_disc_number", defaultValue: "光盘编号")) {
                    HStack(spacing: 8) {
                        numericTextField(value: binding.discNumber, placeholder: String(localized: "disc_no", defaultValue: "编号"))
                        Text("/")
                            .foregroundColor(theme.secondaryText)
                        numericTextField(value: binding.discTotal, placeholder: String(localized: "total", defaultValue: "总数"))
                        Spacer()
                    }
                }

                editorRow(label: String(localized: "tag_bpm", defaultValue: "BPM (节拍)")) {
                    HStack {
                        numericTextField(value: binding.bpm, placeholder: "BPM")
                        Spacer()
                    }
                }

                editorRow(label: String(localized: "tag_compilation", defaultValue: "合辑")) {
                    Toggle(String(localized: "tag_compilation_hint", defaultValue: "属于不同艺人作品合辑"), isOn: binding.compilation)
                        .toggleStyle(.checkbox)
                }

                editorRow(label: String(localized: "tag_comment", defaultValue: "注释备注")) {
                    TextField("", text: binding.comment)
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
    }

    // MARK: - Tab 2: Artwork

    @ViewBuilder
    private var artworkTab: some View {
        if let binding = Binding($metadata) {
            VStack(spacing: 20) {
                // 封面预览与拖拽区
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(theme.controlBackground.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(isDropTargeted ? theme.accent : theme.borderGradientStart.opacity(0.4), lineWidth: isDropTargeted ? 2 : 1)
                        )
                        .frame(width: 260, height: 260)

                    if let data = binding.artworkData.wrappedValue, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 240, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(theme.secondaryText.opacity(0.6))

                            Text(String(localized: "drop_image_here", defaultValue: "拖入图片或点击下方按钮添加封面"))
                                .font(.system(size: 12))
                                .foregroundColor(theme.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }
                    }
                }
                .onDrop(of: [.image, .fileURL], isTargeted: $isDropTargeted) { providers in
                    handleArtworkDrop(providers: providers)
                }

                // 封面元信息
                if let data = binding.artworkData.wrappedValue {
                    HStack(spacing: 16) {
                        if let dimensions = binding.artworkDimensions.wrappedValue {
                            Label("\(Int(dimensions.width)) × \(Int(dimensions.height))", systemImage: "aspectratio")
                                .font(.system(size: 12))
                                .foregroundColor(theme.secondaryText)
                        }

                        Label(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file), systemImage: "scalemass")
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)

                        if let mime = binding.artworkMIMEType.wrappedValue {
                            Text(mime.uppercased().replacingOccurrences(of: "IMAGE/", with: ""))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(theme.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(theme.accent.opacity(0.15))
                                .cornerRadius(4)
                        }
                    }
                }

                // 操作按钮
                HStack(spacing: 12) {
                    Button(action: selectNewArtwork) {
                        Label(String(localized: "choose_artwork", defaultValue: "选取新封面..."), systemImage: "photo.on.rectangle")
                    }

                    if binding.artworkData.wrappedValue != nil {
                        Button(action: exportCurrentArtwork) {
                            Label(String(localized: "export_artwork", defaultValue: "导出封面..."), systemImage: "square.and.arrow.up")
                        }

                        Button(role: .destructive, action: removeArtwork) {
                            Label(String(localized: "delete_artwork", defaultValue: "删除封面"), systemImage: "trash")
                        }
                    }
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Tab 3: Lyrics

    @ViewBuilder
    private var lyricsTab: some View {
        if let binding = Binding($metadata) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(String(localized: "tag_lyrics_instruction", defaultValue: "编辑内嵌歌词（支持 LRC 时间戳或纯文本）:"))
                        .font(.system(size: 12))
                        .foregroundColor(theme.secondaryText)

                    Spacer()

                    if !binding.lyrics.wrappedValue.isEmpty {
                        Button(String(localized: "clear", defaultValue: "清空")) {
                            binding.lyrics.wrappedValue = ""
                        }
                        .font(.system(size: 12))
                        .buttonStyle(.plain)
                        .foregroundColor(.red)
                    }
                }

                TextEditor(text: binding.lyrics)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(8)
                    .background(theme.controlBackground.opacity(0.5))
                    .cornerRadius(8)
                    .frame(minHeight: 340)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(theme.borderGradientStart.opacity(0.3), lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Tab 4: File Properties

    @ViewBuilder
    private var filePropertiesTab: some View {
        if let meta = metadata {
            VStack(spacing: 14) {
                propertyRow(label: String(localized: "file_format", defaultValue: "编码格式"), value: meta.fileFormatName)
                propertyRow(label: String(localized: "file_size", defaultValue: "文件大小"), value: ByteCountFormatter.string(fromByteCount: meta.fileSize, countStyle: .file))
                propertyRow(label: String(localized: "duration", defaultValue: "音频时长"), value: formatTime(meta.duration))

                if let sampleRate = meta.sampleRate {
                    propertyRow(label: String(localized: "sample_rate", defaultValue: "采样率"), value: String(format: "%.1f kHz", sampleRate / 1000.0))
                }

                if let bitDepth = meta.bitDepth, bitDepth > 0 {
                    propertyRow(label: String(localized: "bit_depth", defaultValue: "采样位深"), value: "\(bitDepth) bit")
                }

                if let channels = meta.channels {
                    let channelText = channels == 1 ? String(localized: "mono", defaultValue: "单声道") : (channels == 2 ? String(localized: "stereo", defaultValue: "立体声") : "\(channels) 声道")
                    propertyRow(label: String(localized: "channels", defaultValue: "声道模式"), value: channelText)
                }

                if let bitrate = meta.bitrate, bitrate > 0 {
                    propertyRow(label: String(localized: "bitrate", defaultValue: "平均码率"), value: "\(bitrate) kbps")
                }

                Divider()
                    .padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "file_path", defaultValue: "存储位置:"))
                            .font(.system(size: 12))
                            .foregroundColor(theme.secondaryText)
                        Spacer()
                        Button(action: showInFinder) {
                            Label(String(localized: "show_in_finder", defaultValue: "在访达中显示"), systemImage: "folder")
                                .font(.system(size: 12))
                        }
                    }

                    Text(meta.fileURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(theme.primaryText.opacity(0.8))
                        .lineLimit(3)
                        .textSelection(.enabled)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.controlBackground.opacity(0.5))
                        .cornerRadius(6)
                }
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            Spacer()

            Button(String(localized: "cancel", defaultValue: "取消")) {
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)

            Button {
                Task {
                    await saveChanges()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 48)
                } else {
                    Text(String(localized: "save", defaultValue: "存储"))
                        .font(.system(size: 13, weight: .semibold))
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers & Actions

    private func editorRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.secondaryText)
                .frame(width: 95, alignment: .trailing)

            content()
        }
    }

    private func propertyRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(theme.secondaryText)
                .frame(width: 95, alignment: .trailing)

            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(theme.primaryText)

            Spacer()
        }
    }

    private func numericTextField(value: Binding<Int?>, placeholder: String) -> some View {
        TextField(
            placeholder,
            text: Binding(
                get: { value.wrappedValue.map(String.init) ?? "" },
                set: {
                    let cleaned = $0.filter { $0.isNumber }
                    value.wrappedValue = Int(cleaned)
                }
            )
        )
        .textFieldStyle(.roundedBorder)
        .frame(width: 60)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(theme.accent)
            Text(String(localized: "loading_metadata", defaultValue: "正在读取音频标签..."))
                .font(.system(size: 13))
                .foregroundColor(theme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ msg: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundColor(.yellow)
            Text(msg)
                .font(.system(size: 13))
                .foregroundColor(theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
            Button(String(localized: "retry", defaultValue: "重试")) {
                Task { await loadMetadata() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func loadMetadata() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await AudioTagService.shared.readDetailedMetadata(from: trackURL)
            await MainActor.run {
                self.metadata = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func saveChanges() async {
        guard let metadata else { return }
        isSaving = true
        do {
            try await AudioTagService.shared.writeMetadata(metadata, to: trackURL)
            await MainActor.run {
                self.isSaving = false
                self.onSaved?(metadata)
                self.onDismiss()
            }
        } catch {
            await MainActor.run {
                self.isSaving = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func selectNewArtwork() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .jpeg, .png]
        panel.prompt = String(localized: "choose", defaultValue: "选取")

        if panel.runModal() == .OK, let selectedURL = panel.url, let data = try? Data(contentsOf: selectedURL) {
            updateArtworkWithData(data)
        }
    }

    private func handleArtworkDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data {
                    DispatchQueue.main.async {
                        updateArtworkWithData(data)
                    }
                }
            }
            return true
        } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                if let data = item as? Data, let fileURL = URL(dataRepresentation: data, relativeTo: nil),
                   let imgData = try? Data(contentsOf: fileURL) {
                    DispatchQueue.main.async {
                        updateArtworkWithData(imgData)
                    }
                }
            }
            return true
        }
        return false
    }

    private func updateArtworkWithData(_ data: Data) {
        guard var meta = metadata, let image = NSImage(data: data) else { return }
        meta.artworkData = data
        meta.artworkDimensions = image.size
        meta.isArtworkModified = true

        if data.prefix(3) == Data([0xFF, 0xD8, 0xFF]) {
            meta.artworkMIMEType = "image/jpeg"
        } else if data.prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            meta.artworkMIMEType = "image/png"
        }
        self.metadata = meta
    }

    private func removeArtwork() {
        guard var meta = metadata else { return }
        meta.artworkData = nil
        meta.artworkDimensions = nil
        meta.artworkMIMEType = nil
        meta.isArtworkModified = true
        self.metadata = meta
    }

    private func exportCurrentArtwork() {
        guard let data = metadata?.artworkData else { return }
        let panel = NSSavePanel()
        let ext = (metadata?.artworkMIMEType == "image/png") ? "png" : "jpg"
        panel.nameFieldStringValue = "cover.\(ext)"
        panel.allowedContentTypes = (ext == "png") ? [.png] : [.jpeg]

        if panel.runModal() == .OK, let destinationURL = panel.url {
            try? data.write(to: destinationURL, options: .atomic)
        }
    }

    private func showInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([trackURL])
    }
}
