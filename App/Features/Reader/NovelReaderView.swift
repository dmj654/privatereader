import SwiftUI
import ReaderCore

struct NovelReaderView: View {
    @StateObject private var model: NovelReaderViewModel
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var showTypography = false
    @State private var showCatalog = false

    init(book: Book, env: AppEnvironment) {
        _model = StateObject(wrappedValue: NovelReaderViewModel(
            book: book,
            provider: env.chapterProvider,
            progressRepo: env.progress,
            bookmarkRepo: env.bookmarks,
            booksRepo: env.books
        ))
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                model.theme.background.ignoresSafeArea()

                if model.isLoading {
                    ProgressView().tint(Palette.accent)
                } else if let error = model.errorMessage {
                    EmptyStateView(symbol: "exclamationmark.triangle", title: "打不开这本书", message: error)
                } else {
                    pageArea(size: proxy.size)
                }

                if model.isMenuVisible {
                    menuLayer(size: proxy.size)
                }
            }
            .statusBarHidden(model.isMenuVisible == false)
        }
        .navigationBarHidden(true)
        .preferredColorScheme(model.theme.chromeStyle)
        .onAppear { model.load() }
        .onDisappear {
            model.finishSession()
            if let seconds = model.pendingSessionDuration {
                try? env.sessions.record(ReadingSession(bookId: model.book.id,
                                                        startedAt: Int(Date().timeIntervalSince1970) - seconds,
                                                        durationSec: seconds))
            }
        }
        .sheet(isPresented: $showTypography) {
            TypographySheet(style: $model.style, theme: $model.theme) {
                model.repaginate()
            }
            .presentationDetents([.height(300)])
        }
        .overlay {
            if showCatalog {
                CatalogDrawer(
                    chapters: model.chapters,
                    currentIndex: model.chapterIndex,
                    bookmarks: model.bookmarks,
                    onSelect: { index in
                        model.jump(toChapter: index)
                        showCatalog = false
                    },
                    onClose: { showCatalog = false }
                )
            }
        }
    }

    // MARK: 正文

    private func pageArea(size: CGSize) -> some View {
        VStack(spacing: 0) {
            GeometryReader { content in
                ReaderTextView(
                    attributedText: model.currentPageText,
                    background: UIColor(model.theme.background)
                )
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .onAppear { model.repaginateIfNeeded(size: innerSize(content.size)) }
                .onChange(of: content.size) { newValue in
                    model.repaginateIfNeeded(size: innerSize(newValue))
                }
            }

            HStack {
                Text("第 \(model.chapterIndex + 1) 章")
                Spacer()
                Text("\(model.displayPage) / \(model.pageCount)")
            }
            .font(.system(size: 10))
            .foregroundStyle(model.theme.textColor.opacity(0.45))
            .padding(.horizontal, 22)
            .padding(.bottom, 8)
        }
        .overlay(alignment: .center) {
            HStack(spacing: 0) {
                tapZone { model.turnPage(by: -1) }
                tapZone { withAnimation(.easeInOut(duration: 0.18)) { model.isMenuVisible.toggle() } }
                tapZone { model.turnPage(by: 1) }
            }
        }
        .onChange(of: model.style) { _ in model.repaginate() }
    }

    private func innerSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width - 44, height: size.height - 8)
    }

    private func tapZone(action: @escaping () -> Void) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }

    // MARK: 菜单

    private func menuLayer(size: CGSize) -> some View {
        VStack {
            topBar
            Spacer()
            HStack {
                Spacer()
                sideButtons
                    .padding(.trailing, 15)
                    .padding(.bottom, 14)
            }
            bottomPanel
        }
        .transition(.opacity)
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 36, height: 36)
            }
            Text(model.chapterTitle)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink3)
                .lineLimit(1)
            Spacer()
            Button {
                model.isMenuVisible = false
            } label: {
                Text("净化")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .glassTopBar()
    }

    private var sideButtons: some View {
        VStack(spacing: 11) {
            sideButton("bookmark") { model.addBookmark() }
            sideButton("magnifyingglass") {}
            sideButton("list.bullet") { showCatalog = true }
            sideButton("play") {}
            sideButton("headphones", highlighted: true) {}
        }
    }

    private func sideButton(_ symbol: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(highlighted ? Color.white : Palette.ink2)
                .frame(width: 40, height: 40)
                .background(highlighted ? Palette.accent : Palette.surface.opacity(0.94))
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(highlighted ? Color.clear : Palette.line, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button("上一章") { model.jump(toChapter: model.chapterIndex - 1) }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)

                Slider(
                    value: Binding(
                        get: { model.progressPercent },
                        set: { _ in }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        if !editing { model.persistProgress(force: true) }
                    }
                )
                .tint(Palette.accent)
                .disabled(true)

                Button("下一章") { model.jump(toChapter: model.chapterIndex + 1) }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 20)

            HStack {
                panelItem("list.bullet", "目录") { showCatalog = true }
                panelItem("sun.max", "白天") {
                    model.theme = model.theme.isDark ? .day : .night
                }
                panelItem("circle.lefthalf.filled", "主题") { showTypography = true }
                panelItem("slider.horizontal.3", "设置") { showTypography = true }
                panelItem("arrow.down.to.line", "缓存") {}
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 30)
        .glassBottomPanel()
    }

    private func panelItem(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 19))
                Text(title).font(.system(size: 10))
            }
            .foregroundStyle(Palette.ink2)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
