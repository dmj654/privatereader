import SwiftUI
import UniformTypeIdentifiers
import ReaderCore

/// 一次导入的结果，用来在完成后给一张清单。
struct ImportReport: Identifiable {
    let id = UUID()
    let outcomes: [ImportOutcome]

    var successCount: Int { outcomes.filter { $0.isSuccess }.count }
    var failureCount: Int { outcomes.count - successCount }
}

/// 支持导入的扩展名 → UTType。epub / cbz 没有系统内置类型，只能按后缀造。
enum ImportTypes {
    static var all: [UTType] {
        var types: [UTType] = [.plainText, .pdf]
        for ext in ["epub", "cbz", "zip"] {
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }
}

/// 导入执行器：把「用户选中的 URL」变成「书架里的书」。
/// 在后台串行跑，任何一个文件失败都不影响其余，最后统一回主线程汇报。
enum ImportRunner {
    static func run(urls: [URL],
                    library: LibraryService,
                    completion: @escaping (ImportReport) -> Void) {
        let service = ImportService()

        DispatchQueue.global(qos: .userInitiated).async {
            var outcomes: [ImportOutcome] = []

            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                // 文件选择器给的是外部 URL，先拷到临时目录再解析，
                // 避免权限在异步过程中失效，也避免 LibraryService 拷到一半访问被收回。
                let tempDirectory = FileManager.default.temporaryDirectory
                    .appendingPathComponent("import-\(UUID().uuidString)", isDirectory: true)
                try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDirectory) }

                let localURL = tempDirectory.appendingPathComponent(url.lastPathComponent)
                do {
                    try FileManager.default.copyItem(at: url, to: localURL)
                } catch {
                    outcomes.append(ImportOutcome(
                        fileName: url.lastPathComponent,
                        content: nil,
                        errorMessage: "无法读取文件：\(error.localizedDescription)"
                    ))
                    continue
                }

                do {
                    let content = try service.parse(url: localURL)
                    _ = try library.save(content: content, originalURL: localURL)
                    outcomes.append(ImportOutcome(fileName: url.lastPathComponent, content: content, errorMessage: nil))
                } catch {
                    let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    outcomes.append(ImportOutcome(fileName: url.lastPathComponent, content: nil, errorMessage: message))
                }
            }

            let report = ImportReport(outcomes: outcomes)
            DispatchQueue.main.async { completion(report) }
        }
    }
}

/// 导入结果清单。
struct ImportResultSheet: View {
    let report: ImportReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 8) {
                            summaryPill("成功 \(report.successCount)", color: Palette.accent)
                            if report.failureCount > 0 {
                                summaryPill("失败 \(report.failureCount)", color: Palette.danger)
                            }
                            Spacer()
                        }
                        .padding(.bottom, 4)

                        ForEach(Array(report.outcomes.enumerated()), id: \.offset) { _, outcome in
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: outcome.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(outcome.isSuccess ? Palette.accent : Palette.danger)
                                    .padding(.top, 1)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(outcome.fileName)
                                        .font(.system(size: 14))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(2)
                                    if let message = outcome.errorMessage {
                                        Text(message)
                                            .font(.system(size: 12))
                                            .foregroundStyle(Palette.ink3)
                                    } else if let content = outcome.content {
                                        Text(describe(content))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Palette.ink3)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(12)
                            .background(Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Palette.line, lineWidth: 1)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.xl)
                    .padding(.vertical, Spacing.l)
                }
            }
            .navigationTitle("导入结果")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func summaryPill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color.opacity(0.1))
            .clipShape(Capsule())
    }

    private func describe(_ content: ImportedContent) -> String {
        switch content {
        case .novel(let novel):
            return "小说 · \(novel.chapters.count) 章"
        case .comic(let comic):
            return "漫画 · \(comic.pages.count) 页"
        }
    }
}
