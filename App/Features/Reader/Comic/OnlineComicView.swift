import SwiftUI
import UIKit
import ReaderCore

/// 在线漫画：按话取图片地址，纵向连续阅读。
///
/// 和本地 CBZ 分开，是因为取图链路完全不同：这里每张图都要带源站 header
/// （防盗链），并且需要落盘缓存，否则每次翻回去都要重新下载。
struct OnlineComicView: View {
    let book: Book
    var initialChapter: Int? = nil

    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var manifest: OnlineManifest?
    @State private var source: LegadoSource?
    @State private var chapterIndex = 0
    @State private var pages: [String] = []
    @State private var headers: [String: String] = [:]
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showBars = true
    @State private var showCatalog = false

    private var chapters: [OnlineChapter] { manifest?.chapters ?? [] }

    var body: some View {
        ZStack {
            Palette.comicCanvas.ignoresSafeArea()

            if isLoading {
                ProgressView().tint(Palette.accent)
            } else if let errorMessage {
                VStack(spacing: 10) {
                    EmptyStateView(symbol: "exclamationmark.triangle", title: "这一话打不开", message: errorMessage)
                    Button("重试") { loadChapter() }
                        .buttonStyle(SecondaryButtonStyle(height: 40))
                        .frame(width: 140)
                }
            } else {
                pageList
            }

            if showBars {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .navigationBarHidden(true)
        .task { loadInitial() }
        .sheet(isPresented: $showCatalog) {
            catalogSheet
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: 页面

    private var pageList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, url in
                    OnlineComicPage(urlString: url,
                                    headers: headers,
                                    cacheURL: cacheURL(index: index),
                                    placeholderHeight: index == 0 ? 600 : 480)
                }

                if !pages.isEmpty {
                    Text("— 本话完 —")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 26)
                }
            }
        }
        .scrollIndicators(.hidden)
        .simultaneousGesture(
            TapGesture().onEnded {
                withAnimation(.easeInOut(duration: 0.16)) { showBars.toggle() }
            }
        )
    }

    // MARK: 顶栏 / 底栏

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 38, height: 38)
                    .background(Palette.surface.opacity(0.94))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(book.title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(chapters.indices.contains(chapterIndex) ? chapters[chapterIndex].name : "")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 11)
            .frame(height: 36)
            .background(Palette.surface.opacity(0.94))
            .clipShape(Capsule())

            Spacer(minLength: 0)

            Button {
                showCatalog = true
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 38, height: 38)
                    .background(Palette.surface.opacity(0.94))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button("上一话") { moveChapter(-1) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(chapterIndex > 0 ? Palette.ink : Palette.ink3.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Palette.surface.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(chapterIndex <= 0)

            Text("\(chapterIndex + 1) / \(max(chapters.count, 1))")
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Palette.surface.opacity(0.94))
                .clipShape(Capsule())

            Button("下一话") { moveChapter(1) }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(chapterIndex + 1 < chapters.count ? Palette.ink : Palette.ink3.opacity(0.5))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Palette.surface.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .disabled(chapterIndex + 1 >= chapters.count)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 24)
    }

    // MARK: 目录

    private var catalogSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(chapters.enumerated()), id: \.offset) { index, chapter in
                    Button {
                        showCatalog = false
                        chapterIndex = index
                        loadChapter()
                    } label: {
                        HStack {
                            Text(chapter.name)
                                .font(.system(size: 14))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Spacer()
                            if index == chapterIndex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("目录 · \(chapters.count) 话")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { showCatalog = false }
                }
            }
        }
    }

    // MARK: 数据

    private func loadInitial() {
        guard manifest == nil else { return }
        do {
            let manifest = try env.onlineReading.manifest(for: book)
            self.manifest = manifest

            let record = try env.sources.fetch(id: manifest.sourceId)
            let executable = record.flatMap {
                SourceImportService(repo: env.sources).executable(from: $0)
            }
            source = executable
            if let executable {
                headers = env.sourceClient.imageHeaders(source: executable)
            } else {
                errorMessage = "这本书所属的书源已被删除。"
            }

            let saved = initialChapter ?? UserDefaults.standard.integer(forKey: chapterKey)
            chapterIndex = min(max(saved, 0), max(manifest.chapters.count - 1, 0))
            loadChapter()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    private func moveChapter(_ delta: Int) {
        let target = chapterIndex + delta
        guard chapters.indices.contains(target) else { return }
        chapterIndex = target
        loadChapter()
    }

    private func loadChapter() {
        guard chapters.indices.contains(chapterIndex) else {
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil
        pages = []
        UserDefaults.standard.set(chapterIndex, forKey: chapterKey)

        let chapter = chapters[chapterIndex]
        let source = self.source
        Task {
            guard let source else {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "书源不可用，无法取图。"
                }
                return
            }
            do {
                let urls = try await env.sourceClient.comicPages(source: source, chapter: chapter)
                await MainActor.run {
                    pages = urls
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    pages = []
                    isLoading = false
                    errorMessage = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private var chapterKey: String { "comic.chapter.\(book.id)" }

    private func cacheURL(index: Int) -> URL {
        env.paths.cache
            .appendingPathComponent(book.id, isDirectory: true)
            .appendingPathComponent("online", isDirectory: true)
            .appendingPathComponent("\(chapterIndex)", isDirectory: true)
            .appendingPathComponent("\(index).img", isDirectory: false)
    }
}

// MARK: - 单张远程图

private struct OnlineComicPage: View {
    let urlString: String
    let headers: [String: String]
    let cacheURL: URL
    let placeholderHeight: CGFloat

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            } else {
                Rectangle()
                    .fill(Palette.surface.opacity(0.6))
                    .frame(height: placeholderHeight)
                    .overlay {
                        if failed {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.exclamationmark")
                                    .font(.system(size: 20, weight: .light))
                                Text("这张图没加载出来")
                                    .font(Typo.micro)
                            }
                            .foregroundStyle(Palette.ink3)
                        } else {
                            ProgressView().tint(Palette.accent.opacity(0.7))
                        }
                    }
            }
        }
        .task(id: urlString) { await load() }
    }

    private func load() async {
        guard let url = URL(string: urlString) else {
            failed = true
            return
        }
        if let cached = OnlineComicImageCache.shared.image(for: cacheURL) {
            image = cached
            return
        }
        if let downloaded = await OnlineComicImageCache.shared.download(
            url: url, headers: headers, to: cacheURL
        ) {
            image = downloaded
        } else {
            failed = true
        }
    }
}

/// 远程漫画页的内存 + 磁盘缓存。同样的图翻回来不再走网络。
final class OnlineComicImageCache {
    static let shared = OnlineComicImageCache()

    private let memory = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default

    private init() {
        memory.countLimit = 10
    }

    func image(for url: URL) -> UIImage? {
        let key = url.path as NSString
        if let cached = memory.object(forKey: key) { return cached }
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        memory.setObject(image, forKey: key)
        return image
    }

    func download(url: URL, headers: [String: String], to cacheURL: URL) async -> UIImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else {
            return nil
        }

        try? fileManager.createDirectory(at: cacheURL.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
        try? data.write(to: cacheURL, options: .atomic)

        let key = cacheURL.path as NSString
        memory.setObject(image, forKey: key)
        return image
    }
}
