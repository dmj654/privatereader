import SwiftUI
import ReaderCore

struct ShelfView: View {
    @EnvironmentObject private var env: AppEnvironment

    @State private var books: [Book] = []
    @State private var progressByBook: [String: Double] = [:]
    @State private var filter: ShelfFilter = .all
    @State private var sort: ShelfSort = .lastRead
    @State private var groups: [BookGroup] = []
    @State private var showingGroupManager = false
    @State private var activeBook: Book?
    @State private var showingDeleteConfirm = false
    @State private var showingImporter = false
    @State private var isImporting = false
    @State private var report: ImportReport?
    @State private var importError: String?

    private let columns = [
        GridItem(.flexible(), spacing: 13),
        GridItem(.flexible(), spacing: 13),
        GridItem(.flexible(), spacing: 13)
    ]

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                chips
                content
            }
        }
        .navigationBarHidden(true)
        .task { reload() }
        .onAppear { reload() }
        .confirmationDialog("删除这本书？", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("只删记录，保留文件") { deleteActive(removeFiles: false) }
            Button("删除记录和文件", role: .destructive) { deleteActive(removeFiles: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删记录时，原文件仍留在 App 内。")
        }
        .sheet(isPresented: $showingGroupManager) {
            GroupManagerSheet(groups: groups, onChanged: reload)
                .environmentObject(env)
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: ImportTypes.all,
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(item: $report) { report in
            ImportResultSheet(report: report)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .overlay {
            if isImporting {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView().tint(Palette.accent)
                        Text("正在解析并导入…")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(24)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Shadow.card, radius: 12, y: 4)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text("书架").font(Typo.display).foregroundStyle(Palette.ink)
                Text("\(books.count) 本 · \(books.filter { $0.status == .reading }.count) 本在读")
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink3)
            }
            Spacer()
            HStack(spacing: 9) {
                iconButton("plus") { showingImporter = true }
                iconButton("arrow.up.arrow.down") {
                    sort = sort == .lastRead ? .title : .lastRead
                    reload()
                }
                Button { showingGroupManager = true } label: {
                    Image(systemName: "ellipsis").font(.system(size: 17))
                        .foregroundStyle(Palette.ink2)
                        .frame(width: 36, height: 36)
                        .background(Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(Palette.line, lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.l)
        .padding(.bottom, Spacing.m)
        .glassTopBar()
    }

    private func iconButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Palette.ink2)
                .frame(width: 36, height: 36)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("全部", active: filter == .all) { filter = .all }
                chip("小说", active: filter == .novel) { filter = .novel }
                chip("漫画", active: filter == .comic) { filter = .comic }
                ForEach(groups) { group in
                    chip(group.name, active: filter == .group(group.id)) { filter = .group(group.id) }
                }
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, Spacing.l)
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Chip(title: title, isOn: active)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if books.isEmpty {
            EmptyStateView(
                symbol: "books.vertical",
                title: "书架还是空的",
                message: "从本地导入文件，或者去发现页找书"
            )
            Spacer()
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(displayBooks) { book in
                        NavigationLink {
                            DetailView(book: book)
                                .environmentObject(env)
                        } label: {
                            BookCell(
                                book: book,
                                coverURL: env.library.absoluteCoverURL(for: book),
                                progress: progressByBook[book.id] ?? 0
                            )
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("标记已读完") { markFinished(book) }
                            Button(book.groupId == BookGroup.builtinDroppedID ? "移回在追" : "标记弃读") { toggleDropped(book) }
                            Divider()
                            Button("删除", role: .destructive) {
                                activeBook = book
                                showingDeleteConfirm = true
                            }
                        }
                    }
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.bottom, 110)
            }
        }
    }

    private var displayBooks: [Book] {
        sort.apply(to: filter.apply(to: books))
    }

    private func reload() {
        do {
            groups = try env.groups.all()
            books = try env.books.all()
            var map: [String: Double] = [:]
            for book in books {
                map[book.id] = (try? env.progress.fetch(bookId: book.id))?.percent ?? 0
            }
            progressByBook = map
        } catch {
            books = []
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard !urls.isEmpty else { return }
            isImporting = true
            let library = env.library
            ImportRunner.run(urls: urls, library: library) { outcome in
                isImporting = false
                reload()
                if outcome.outcomes.isEmpty {
                    return
                }
                report = outcome
            }
        }
    }

    private func deleteActive(removeFiles: Bool) {
        guard let book = activeBook else { return }
        try? env.library.delete(book, removeFiles: removeFiles)
        activeBook = nil
        reload()
    }

    private func markFinished(_ book: Book) {
        try? env.books.updateStatus(bookId: book.id, status: .finished)
        reload()
    }

    private func toggleDropped(_ book: Book) {
        let target = book.groupId == BookGroup.builtinDroppedID
            ? BookGroup.builtinReadingID
            : BookGroup.builtinDroppedID
        try? env.books.updateGroup(bookId: book.id, groupId: target)
        reload()
    }
}
