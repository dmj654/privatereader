import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ReaderCore

/// 导入书源：粘贴 / 文件 / 剪贴板 / 链接。
///
/// 网友源动辄几千条、几 MB，直接粘进 TextEditor 会卡；
/// 所以默认推荐「从文件导入」，粘贴框只作为小批量补充。
struct SourceImportSheet: View {
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    var onImported: (SourceImportSummary) -> Void

    @State private var text = ""
    @State private var isImporting = false
    @State private var summary: SourceImportSummary?
    @State private var errorMessage: String?
    @State private var showingFilePicker = false
    @State private var forceEnable = true

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 14) {
                        fileCard
                        pasteCard
                        optionsCard

                        if let summary {
                            resultCard(summary)
                        }
                    }
                    .padding(.horizontal, Spacing.l)
                    .padding(.vertical, 14)
                }
            }
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        importText()
                    } label: {
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("导入").fontWeight(.semibold)
                        }
                    }
                    .disabled(isImporting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.json, .plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                handleFile(result)
            }
            .alert("导入失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("知道了", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    // MARK: 卡片

    private var fileCard: some View {
        Button {
            showingFilePicker = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "doc.badge.plus")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Palette.accent)
                    .frame(width: 42, height: 42)
                    .background(Palette.accentSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("从文件导入")
                        .font(Typo.headline)
                        .foregroundStyle(Palette.ink)
                    Text("支持 legado 导出的 .json / .txt，几千条也可以")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.ink3)
            }
            .padding(14)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var pasteCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("粘贴 JSON 或链接")
                    .font(Typo.headline)
                    .foregroundStyle(Palette.ink)
                Spacer()
                Button("从剪贴板") {
                    if let pasted = UIPasteboard.general.string {
                        text = pasted
                    }
                }
                .font(Typo.micro)
                .foregroundStyle(Palette.accent)
            }

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120)
                .padding(8)
                .background(Palette.surfaceAlt)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("[{\"bookSourceName\":\"…\",\"bookSourceUrl\":\"…\"}]")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Palette.ink3.opacity(0.7))
                            .padding(.horizontal, 13)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }

            if text.lowercased().hasPrefix("http") {
                Label("将从这个链接下载书源", systemImage: "link")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    private var optionsCard: some View {
        Toggle(isOn: $forceEnable) {
            VStack(alignment: .leading, spacing: 2) {
                Text("导入后全部启用")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.ink)
                Text("关掉则沿用书源自带的开关状态")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .tint(Palette.accent)
        .padding(14)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    private func resultCard(_ summary: SourceImportSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("导入完成", systemImage: "checkmark.circle.fill")
                .font(Typo.headline)
                .foregroundStyle(Color(hex: 0x4E8A5F))
            Text("新增 \(summary.added) 条，覆盖 \(summary.updated) 条，共 \(summary.total) 条。")
                .font(Typo.caption)
                .foregroundStyle(Palette.ink2)
            if summary.total > 0 {
                Text("回到列表可以「测一下全部」，把失效的源关掉。")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    // MARK: 动作

    private func handleFile(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try importData(data)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importText() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if trimmed.lowercased().hasPrefix("http"),
           let url = URL(string: trimmed) {
            download(url)
            return
        }
        guard let data = trimmed.data(using: .utf8) else {
            errorMessage = "文本编码不是 UTF-8"
            return
        }
        do {
            try importData(data)
        } catch {
            errorMessage = readable(error)
        }
    }

    private func download(_ url: URL) {
        isImporting = true
        Task {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                    throw URLError(.badServerResponse)
                }
                await MainActor.run {
                    do {
                        try importData(data)
                    } catch {
                        errorMessage = readable(error)
                    }
                    isImporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "下载失败：\(error.localizedDescription)"
                    isImporting = false
                }
            }
        }
    }

    private func importData(_ data: Data) throws {
        isImporting = true
        defer { isImporting = false }
        let service = SourceImportService(repo: env.sources)
        let result = try service.importJSON(data, forceEnabled: forceEnable)
        summary = result
        text = ""
        onImported(result)
    }

    private func readable(_ error: Error) -> String {
        if let error = error as? LegadoParserError {
            return error.errorDescription ?? "书源格式不正确"
        }
        return error.localizedDescription
    }
}
