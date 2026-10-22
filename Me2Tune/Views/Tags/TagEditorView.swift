import SwiftUI
import AppKit

struct TagEditorView: View {
    @Bindable var model: TagEditorModel
    @State private var selection = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("tag_editor_title").font(.title2.bold())
            Text(model.receipt?.url.deletingPathExtension().lastPathComponent ?? model.track.title).font(.subheadline).lineLimit(2).foregroundStyle(.secondary)
            if model.isReading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.receipt != nil {
                recovery
            } else if let snapshot = model.snapshot {
                if !snapshot.writableFormat { Text("tag_read_only_format").foregroundStyle(.secondary) }
                TabView(selection: $selection) {
                    information.tabItem { Text("tag_information") }.tag(0)
                    cover.tabItem { Text("tag_cover") }.tag(1)
                    lyrics.tabItem { Text("tag_lyrics") }.tag(2)
                }
                .disabled(model.isSaving)
            } else {
                ContentUnavailableView("tag_read_failed", systemImage: "exclamationmark.triangle")
                Button("tag_reload") { Task { await model.load() } }
            }
            if let message = model.message {
                if model.receipt == nil, model.snapshot != nil {
                    Button("tag_reload_discard") { Task { await model.load() } }.disabled(model.isBusy)
                }
                ScrollView { Text(message).foregroundStyle(.red).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 85)
            }
            Divider()
            Text((model.receipt?.url ?? model.snapshot?.url ?? model.track.url).path)
                .font(.caption).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            HStack {
                Button("show_in_finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([model.receipt?.url ?? model.snapshot?.url ?? model.track.url])
                }
                Spacer()
                if model.isSaving { ProgressView().controlSize(.small) }
                Button("cancel") { model.requestClose() }.keyboardShortcut(.cancelAction).disabled(model.isSaving)
                Button(model.player.hasPlaybackSession ? "tag_stop_save" : "tag_save") { model.save() }
                    .keyboardShortcut("s", modifiers: .command)
                    .disabled(!model.canSave)
                    .buttonStyle(.borderedProminent)
            }
            if model.player.hasPlaybackSession, model.receipt == nil {
                Text("tag_stop_hint").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(width: 470, height: 620)
        .interactiveDismissDisabled(true)
        .onExitCommand { model.requestClose() }
        .task { if model.snapshot == nil { await model.load() } }
        .alert("tag_unsaved_title", isPresented: $model.showUnsavedPrompt) {
            Button("tag_save") { model.saveAndClose() }.disabled(!model.canSave)
            Button("tag_discard", role: .destructive) { model.discardAndClose() }
            Button("cancel", role: .cancel) { model.cancelClose() }
        } message: { Text("tag_unsaved_message") }
    }

    private var information: some View {
        ScrollView {
            Form {
                ForEach(TagField.allCases.filter { $0 != .lyrics }, id: \.self) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        if model.snapshot?.values(field).count ?? 0 > 1 {
                            LabeledContent(field.label) {
                                Text(model.snapshot?.text(field) ?? "").textSelection(.enabled)
                            }
                            Text("tag_multivalue_readonly").font(.caption).foregroundStyle(.secondary)
                        } else {
                            TextField(field.label, text: binding(field), axis: field == .comment ? .vertical : .horizontal)
                                .textFieldStyle(.roundedBorder)
                                .accessibilityLabel(field.label)
                                .disabled(model.snapshot?.writableFormat != true)
                            if let error = model.validationErrors[field] {
                                Text(error).font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                }
            }.padding(12)
        }
    }

    private var cover: some View {
        VStack(spacing: 16) {
            if let data = model.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: 260, maxHeight: 270)
                    .accessibilityLabel(Text("tag_main_cover"))
            } else {
                Image(systemName: "photo").font(.system(size: 80)).foregroundStyle(.secondary)
                    .frame(height: 230).accessibilityLabel(Text("tag_no_cover"))
            }
            HStack {
                Button("tag_choose_cover") { model.chooseArtwork() }
                Button("tag_remove_cover", role: .destructive) { model.artwork = nil }.disabled(model.artwork == nil)
            }
            .disabled(model.snapshot?.writableFormat != true)
            Text("tag_cover_hint").font(.caption).foregroundStyle(.secondary)
            Spacer()
        }.padding(16).frame(maxWidth: .infinity)
    }

    private var lyrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let local = model.localLyricsURL {
                Text("tag_local_lrc_priority").font(.caption).foregroundStyle(.secondary)
                Button("tag_show_lrc") { NSWorkspace.shared.activateFileViewerSelecting([local]) }
            } else {
                Text("tag_embedded_hint").font(.caption).foregroundStyle(.secondary)
            }
            if model.snapshot?.isReadOnly(.lyrics) == true {
                if model.snapshot?.values(.lyrics).count ?? 0 > 1 {
                    Text("tag_multiple_lyrics_readonly").font(.caption).foregroundStyle(.secondary)
                } else if model.snapshot?.readOnlyFields.contains("LYRICS") == true {
                    Text("tag_structured_lyrics_readonly").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView { Text(model.snapshot?.text(.lyrics) ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                TextEditor(text: binding(.lyrics)).font(.body).accessibilityLabel(Text("tag_lyrics"))
                    .border(.separator)
                HStack {
                    Button("tag_import_lyrics") { model.importLyrics() }
                    Button("tag_clear_lyrics", role: .destructive) { model.draft[.lyrics] = "" }
                }
            }
        }.padding(12)
    }

    private var recovery: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.fileWasSaved ? "tag_saved_sync_failed" : "tag_recovery_needed")
            Text("tag_recovery_hint").font(.callout).foregroundStyle(.secondary)
            Button(model.fileWasSaved ? "tag_retry_sync" : "tag_read_current") { model.retrySynchronization() }
                .disabled(model.isBusy || model.player.isRestoring)
            if let receipt = model.receipt {
                Button("tag_show_backup") { NSWorkspace.shared.activateFileViewerSelecting([receipt.backupURL]) }
                    .disabled(!FileManager.default.fileExists(atPath: receipt.backupURL.path))
            }
            Spacer()
        }.frame(maxHeight: .infinity).padding(.top, 12)
    }

    private func binding(_ field: TagField) -> Binding<String> {
        Binding(get: { model.draft[field] ?? "" }, set: { model.draft[field] = $0 })
    }
}
