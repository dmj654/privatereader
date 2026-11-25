import SwiftUI
import ReaderCore

struct SearchView: View {
    @EnvironmentObject private var env: AppEnvironment
    @StateObject private var model = SearchViewModel()
    @FocusState private var keyboardFocus: Bool

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                searchBar
                content
            }
        }
        .navigationTitle("搜索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { keyboardFocus = model.query.isEmpty }
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
        .padding(.vertical, 10)
    }

    // MARK: 内容

    @ViewBuilder
    private var content: some View {
        if let message = model.errorMessage {
            ScrollView {
                EmptyStateView(symbol: "antenna.radiowaves.left.and.right.slash",
                               title: "暂时搜不了",
                               message: message)
                if !model.history.isEmpty {
                    historySection
                        .padding(.horizontal, Spacing.l)
                }
            }
        } else if model.groups.isEmpty && model.localMatches.isEmpty {
            ScrollView {
                historySection
                    .padding(.horizontal, Spacing.l)
                    .padding(.top, 4)
            }
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    if !model.localMatches.isEmpty {
                        localSection
                    }
                    ForEach(model.groups) { group in
                        groupSection(group)
                    }
                    footer
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, 4)
                .padding(.bottom, 24)
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
                Text("搜过的书名会留在这里。书架里的书永远排在最前面。")
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

    private var localSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(title: "书架", detail: "\(model.localMatches.count) 本", failed: false)

            ForEach(model.localMatches) { book in
                NavigationLink {
                    DetailView(book: book)
                } label: {
                    HStack(spacing: 11) {
                        BookCoverView(book: book, coverURL: env.library.absoluteCoverURL(for: book))
                            .frame(width: 42, height: 58)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(book.title)
                                .font(.system(size: 14.5, weight: .medium))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text([book.author, book.type == .novel ? "小说" : "漫画"]
                                .compactMap { $0 }
                                .filter { !$0.isEmpty }
                                .joined(separator: " · "))
                                .font(Typo.micro)
                                .foregroundStyle(Palette.ink3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Text("已在书架")
                            .font(.system(size: 10.5))
                            .foregroundStyle(Palette.accent)
                    }
                    .padding(10)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.line, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func groupSection(_ group: SearchViewModel.Group) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: group.source.name,
                detail: group.isLoading
                    ? "搜索中…"
                    : (group.error == nil ? "\(group.books.count) 本 · \(Int(group.elapsed * 1000))ms" : "失败"),
                failed: group.error != nil
            )

            if group.isLoading {
                ForEach(0..<2, id: \.self) { _ in
                    skeletonRow
                }
            } else if let error = group.error {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.ink3)
                    Text(error)
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                        .lineLimit(2)
                    Spacer(minLength: 6)
                    Button("重试") { model.retry(group, env: env) }
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }
                .padding(11)
                .background(Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Palette.line, lineWidth: 1)
                }
            } else if group.books.isEmpty {
                Text("这个源没有结果")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .padding(.vertical, 4)
            } else {
                ForEach(group.books) { book in
                    NavigationLink {
                        OnlineDetailView(online: book)
                    } label: {
                        resultRow(book)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func resultRow(_ book: OnlineBook) -> some View {
        HStack(alignment: .top, spacing: 11) {
            OnlineCoverView(url: book.coverUrl, title: book.name)
                .frame(width: 42, height: 58)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.name)
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text([book.author, book.kind]
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
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.ink3.opacity(0.6))
                .padding(.top, 18)
        }
        .padding(10)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
    }

    private var skeletonRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Palette.line.opacity(0.7))
                .frame(width: 42, height: 58)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.line.opacity(0.7))
                    .frame(height: 12)
                    .frame(maxWidth: 150)
                RoundedRectangle(cornerRadius: 4)
                    .fill(Palette.line.opacity(0.5))
                    .frame(height: 10)
                    .frame(maxWidth: 90)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .redacted(reason: .placeholder)
    }

    private var footer: some View {
        Group {
            if model.isSearching {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("已回 \(model.finishedCount)/\(model.groups.count) 个源，剩下的还在路上")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.ink3)
                }
                .padding(.top, 6)
            } else if !model.hasResults {
                Text("所有源都没有搜到「\(model.query)」。换个关键词，或者去发现页换个源。")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .multilineTextAlignment(.center)
                    .padding(.top, 16)
            }
        }
    }

    private func sectionHeader(title: String, detail: String, failed: Bool) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(failed ? Palette.danger.opacity(0.8) : Palette.ink2)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(Palette.ink3)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
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
