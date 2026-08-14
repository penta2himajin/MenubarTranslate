import AppKit
import SwiftUI
import MenubarTranslateCore

/// The menu-bar panel chrome. Output and error slots are always present so
/// MenuBarExtra does not clip results that appear after first layout.
public struct PanelChrome: View {
    @Bindable public var vm: AppViewModel
    @Binding public var draft: String
    public var onQuit: () -> Void

    @State private var historyOpen = false
    @State private var hoverButton = false
    @State private var hoverCard = false
    @State private var hoveredHistoryID: UUID?
    @State private var scrollSync = FieldScrollSync()

    public init(
        vm: AppViewModel,
        draft: Binding<String>,
        onQuit: @escaping () -> Void = {}
    ) {
        self.vm = vm
        self._draft = draft
        self.onQuit = onQuit
    }

    private var pickerLanguages: [AppLanguage] { AppLanguage.pickerLanguages() }
    private let fieldHeight: CGFloat = 120

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Translate to")
                    .font(.body)
                    .foregroundStyle(.secondary)
                TargetLanguageMenu(selection: $vm.targetLanguage, languages: pickerLanguages)
                Spacer()
                if let caption = vm.progressCaption {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            IMESourceEditor(
                text: $draft,
                onStableChange: { vm.scheduleLiveTranslate($0) },
                sync: scrollSync
            )
                .frame(minHeight: fieldHeight, maxHeight: fieldHeight)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.white, lineWidth: 1.5))
                .accessibilityIdentifier("source-input")

            ZStack(alignment: .bottomTrailing) {
                TranslationOutputEditor(text: vm.output, sync: scrollSync)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(vm.output, forType: .string)
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.primary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.6)))
                .disabled(vm.output.isEmpty)
                .padding(6)
                .accessibilityIdentifier("copy-output")
            }
            .overlay(alignment: .bottomLeading) {
                if let err = vm.errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(6)
                        .accessibilityIdentifier("translation-error")
                }
            }
            .frame(minHeight: fieldHeight, maxHeight: fieldHeight)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))

            HStack {
                Text(vm.statusLine)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .accessibilityIdentifier("status-line")
                Spacer()
                historyButton
                Button("Quit", action: onQuit)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottomTrailing) {
            if historyOpen {
                historyCard
                    .offset(x: -8, y: -36)
            }
        }
        .onChange(of: vm.targetLanguage) {
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                vm.scheduleLiveTranslate(draft)
            }
        }
    }

    private var historyButton: some View {
        Image(systemName: "clock.arrow.circlepath")
            .imageScale(.medium)
            .padding(4)
            .contentShape(Rectangle())
            .onHover { hovering in
                hoverButton = hovering
                refreshHistoryOpen()
            }
            .accessibilityIdentifier("history-button")
            .help("Recent translations")
    }

    private var historyCard: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if vm.history.isEmpty {
                    Text("No history yet").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(vm.history.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider() }
                    historyRow(item)
                }
            }
            .padding(10)
        }
        .frame(width: 280, height: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .shadow(radius: 8)
        .onHover { hovering in
            hoverCard = hovering
            if !hovering { hoveredHistoryID = nil }
            refreshHistoryOpen()
        }
        .accessibilityIdentifier("history-card")
    }

    private func historyRow(_ item: TranslationHistoryItem) -> some View {
        let focused = hoveredHistoryID == item.id
        return Button {
            vm.applyHistory(item)
            draft = item.source
            historyOpen = false
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.source)
                    .font(.caption)
                    .lineLimit(2)
                Text(item.output)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.primary.opacity(focused ? 0.35 : 0), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredHistoryID = hovering ? item.id : nil
            hoverCard = true
            refreshHistoryOpen()
        }
    }

    private func refreshHistoryOpen() {
        if hoverButton || hoverCard {
            historyOpen = true
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if !hoverButton && !hoverCard { historyOpen = false }
        }
    }

}
