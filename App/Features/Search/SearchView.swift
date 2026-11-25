import SwiftUI
import ReaderCore

struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: TabRouter
    @StateObject private var model = SearchViewModel()
    @FocusState private var keyboardFocus: Bool
    @State private var choosing: SearchViewModel.MergedBook?

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                kindPicker
                content
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: router.selection) { tab in
            keyboardFocus = (tab == .search && model.query.isEmpty && model.books.isEmpty)
        }
        .sheet(item: $choosing) { book in
            SourceChooserSheet(book: book)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: 搜索框

    private var searchBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Palette.ink3)

                TextField("书名或作者", text: $model.query)
                    .font(.system(size: 15))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($keyboardFocus)
                    .onSubmit {
                        keyboardFocus = false
                        model.search(env: env)
                    }

                if !model.query.isEmpty {
                    Button {
                        model.query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(Palette.ink3.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }

            Button("搜索") {
                keyboardFocus = false
                model.search(env: env)
            }
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(model.query.trimmingCharacters(in: .whitespaces).isEmpty
                             ? Palette.ink3 : Palette.accent)
            .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(SearchViewModel.Kind.allCases) { kind in
                Button {
                    keyboardFocus = false
                    model.setKind(kind, env: env)
                } label: {
                    Text(kind.title)
                        .font(.system(size: 13, weight: model.kind == kind ? .semibold : .regular))
                        .foregroundStyle(model.kind == kind ? Color.white : Palette.ink2)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(model.kind == kind ? Palette.accent : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.bottom, 8)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage, model.books.isEmpty {
            ScrollView {
                EmptyStateView(symbol: "antenna.radiowaves.left.and.right.slash",
                               title: "暂时搜不了",
                               message: message)
                if !model.history.isEmpty {
                    historySection.padding(.horizontal, Spacing.l)
                }
            }
        } else if model.books.isEmpty && !model.isSearching {
            ScrollView {
                historySection
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, 4)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(model.books) { book in
                        Button {
                            choosing = book
                        } label: {
                            bookRow(book)
                        }
                        .buttonStyle(.plain)
                    }
                    footer
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
        }
    }

    private func bookRow(_ book: SearchViewModel.MergedBook) -> some View {
        HStack(alignment: .top, spacing: 11) {
            OnlineCoverView(url: book.coverUrl, title: book.name)
                .frame(width: 46, height: 63)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)

                Text([book.author, book.kindText]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · "))
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .lineLimit(1)

                if !book.lastChapter.isEmpty {
                    Text(book.lastChapter)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.ink3.opacity(0.85))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Image(systemName: "square.stack.3d.up")
                        .font(.system(size: 9))
                    Text("\(book.entries.count) 个源")
                        .font(.system(size: 10))
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.accentSoft)
                .clipShape(Capsule())
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink3.opacity(0.6))
                .padding(.top, 24)
        }
        .padding(10)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    private var footer: some View {
        Group {
            if model.isSearching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("已搜 \(model.finishedSources)/\(model.totalSources) 个源")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
                .padding(.top, 6)
            } else if model.failedCount > 0 {
                Button {
                    model.retryFailed(env: env)
                } label: {
                    Text("\(model.failedCount) 个源失败 · 点这里重试")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.accent)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            } else if model.books.isEmpty {
                Text("没有搜到「\(model.query)」。换个关键词，或去发现页换个源。")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 20)
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("搜索历史")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                Spacer()
                if !model.history.isEmpty {
                    Button("清空") { model.clearHistory() }
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
            }

            if model.history.isEmpty {
                Text("搜过的书名会留在这里。结果会按书合并，点进去可以换源。")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 2)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(model.history, id: \.self) { keyword in
                        Button {
                            model.selectHistory(keyword, env: env)
                        } label: {
                            Chip(title: keyword)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.top, 8)
    }
}

// MARK: - 选源（换源）

struct SourceChooserSheet: View {
    let book: SearchViewModel.MergedBook

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(book.entries.enumerated()), id: \.offset) { index, entry in
                        NavigationLink {
                            OnlineDetailView(online: entry)
                        } label: {
                            HStack(spacing: 11) {
                                OnlineCoverView(url: entry.coverUrl, title: entry.name)
                                    .frame(width: 38, height: 52)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sourceName(index))
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    if !entry.lastChapter.isEmpty {
                                        Text(entry.lastChapter)
                                            .font(Typo.micro)
                                            .foregroundStyle(Palette.ink3)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("选择书源")
                } footer: {
                    Text("同一个源点进去看详情，换源就是换一个站点的同一本书。")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(book.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func sourceName(_ index: Int) -> String {
        guard book.sourceNames.indices.contains(index) else { return "书源 \(index + 1)" }
        return book.sourceNames[index]
    }
}

/// 简易流式布局，给历史 chips 用。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth.isFinite ? maxWidth : rowWidth,
                      height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 在线封面：先显示占位书名，图到了再换。
struct OnlineCoverView: View {
    let url: String
    let title: String

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0xD9E3EC), Color(hex: 0xC3D2E0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(title)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(4)

            if let url = URL(string: url), !url.absoluteString.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Color.clear
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}
