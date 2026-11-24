import SwiftUI
import ReaderCore

struct CatalogDrawer: View {
    let chapters: [NovelChapter]
    let currentIndex: Int
    let bookmarks: [Bookmark]
    let onSelect: (Int) -> Void
    let onClose: () -> Void

    @State private var keyword = ""
    @State private var tab = 0

    private var filtered: [(index: Int, title: String)] {
        let all = chapters.enumerated().map { (index: $0.offset, title: $0.element.title) }
        guard !keyword.isEmpty else { return all }
        return all.filter { $0.title.contains(keyword) }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.24)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 22) {
                    tabButton("目录", index: 0)
                    tabButton("书签", index: 1)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 54)
                .padding(.bottom, 2)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Palette.line).frame(height: 1)
                }

                searchField
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                if tab == 0 {
                    chapterList
                } else {
                    bookmarkList
                }
            }
            .frame(width: 322)
            .frame(maxHeight: .infinity)
            .background(Palette.surface)
            .ignoresSafeArea(edges: .bottom)
        }
    }

    private func tabButton(_ title: String, index: Int) -> some View {
        Button { tab = index } label: {
            VStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: tab == index ? .semibold : .regular))
                    .foregroundStyle(tab == index ? Palette.ink : Palette.ink3)
                Rectangle()
                    .fill(tab == index ? Palette.accent : Color.clear)
                    .frame(height: 2)
            }
        }
        .buttonStyle(.plain)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Palette.ink3)
            TextField("输入关键字搜索目录", text: $keyword)
                .font(.system(size: 13))
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color(hex: 0xEBEFF3))
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var chapterList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered, id: \.index) { item in
                        Button { onSelect(item.index) } label: {
                            HStack {
                                Text(item.title)
                                    .font(.system(size: 14.5))
                                    .foregroundStyle(item.index == currentIndex ? Palette.accent : Palette.ink2)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 17)
                            .background(item.index == currentIndex ? Palette.accentSoft.opacity(0.5) : Color.clear)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color(hex: 0xF3F6F9)).frame(height: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .id(item.index)
                    }
                }
            }
            .onAppear { proxy.scrollTo(currentIndex, anchor: .center) }
        }
    }

    private var bookmarkList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if bookmarks.isEmpty {
                    EmptyStateView(symbol: "bookmark", title: "还没有书签", message: "在阅读时点右侧书签按钮")
                } else {
                    ForEach(bookmarks) { bookmark in
                        Button { onSelect(bookmark.chapterIndex) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("第 \(bookmark.chapterIndex + 1) 章 · 第 \(bookmark.offset + 1) 页")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Palette.ink3)
                                Text(bookmark.excerpt ?? "书签")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Palette.ink2)
                                    .lineLimit(2)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color(hex: 0xF3F6F9)).frame(height: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
