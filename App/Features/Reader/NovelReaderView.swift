import SwiftUI
import ReaderCore

/// 还没实现的入口，点了要给一句人话，不能静默。
/// 判定标准很简单：**界面上出现的按钮就是承诺**。做不到就该说出来，而不是让你怀疑是手滑还是卡住。
private struct PendingFeature: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
}

/// 阅读器里的弹出层，合成一个状态机，避免多个 sheet 互相抢占。
private enum ReaderSheet: Identifiable {
    case catalog
    case settings(TypographySheet.Focus)

    var id: String {
        switch self {
        case .catalog: return "catalog"
        case .settings(let focus): return "settings-\(focus == .theme ? "theme" : "full")"
        }
    }
}

struct NovelReaderView: View {
    @StateObject private var model: NovelReaderViewModel
    @StateObject private var prefs = ReaderPreferences()
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var sheet: ReaderSheet?
    @State private var pending: PendingFeature?
    @State private var contentOffset: CGFloat = 0
    @State private var contentOpacity: Double = 1
    @State private var viewWidth: CGFloat = 390
    @State private var scrubValue: Double?

    init(book: Book, env: AppEnvironment, initialChapter: Int? = nil) {
        _model = StateObject(wrappedValue: NovelReaderViewModel(
            book: book,
            provider: env.chapterProvider,
            progressRepo: env.progress,
            bookmarkRepo: env.bookmarks,
            booksRepo: env.books,
            initialChapter: initialChapter
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
            .onAppear { viewWidth = proxy.size.width }
            .onChange(of: proxy.size) { viewWidth = $0.width }
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
        .sheet(item: $sheet) { item in
            switch item {
            case .catalog:
                CatalogSheet(
                    book: model.book,
                    coverURL: env.library.absoluteCoverURL(for: model.book),
                    chapters: model.chapters,
                    currentIndex: model.chapterIndex,
                    progressPercent: model.progressPercent,
                    bookmarks: model.bookmarks,
                    onSelect: { index in model.jump(toChapter: index) },
                    onDeleteBookmark: { model.removeBookmark($0) }
                )
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)

            case .settings(let focus):
                TypographySheet(style: $model.style, theme: $model.theme, focus: focus, prefs: prefs) {
                    model.repaginate()
                }
                .presentationDetents(detents(for: focus))
                .presentationDragIndicator(.visible)
            }
        }
        .alert(
            pending?.title ?? "",
            isPresented: Binding(
                get: { pending != nil },
                set: { if !$0 { pending = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { pending = nil }
        } message: {
            Text(pending?.detail ?? "")
        }
    }

    private func detents(for focus: TypographySheet.Focus) -> Set<PresentationDetent> {
        focus == .theme ? [.height(210)] : [.fraction(0.82), .large]
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
        .opacity(contentOpacity)
        .offset(x: contentOffset)
        .overlay(alignment: .center) {
            HStack(spacing: 0) {
                tapZone(.left)
                tapZone(.center)
                tapZone(.right)
            }
        }
        .simultaneousGesture(swipeGesture)
        .onChange(of: model.style) { _ in model.repaginate() }
    }

    private func innerSize(_ size: CGSize) -> CGSize {
        CGSize(width: size.width - 44, height: size.height - 8)
    }

    // MARK: 点击区域

    private func tapZone(_ zone: TapZone) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { perform(prefs.zones.action(for: zone)) }
    }

    private func perform(_ action: TapAction) {
        switch action {
        case .previousPage:
            turn(by: -1)
        case .nextPage:
            turn(by: 1)
        case .toggleMenu:
            withAnimation(.easeInOut(duration: 0.18)) { model.isMenuVisible.toggle() }
        case .previousChapter:
            model.jump(toChapter: model.chapterIndex - 1)
        case .nextChapter:
            model.jump(toChapter: model.chapterIndex + 1)
        case .none:
            break
        }
    }

    // MARK: 翻页

    private func turn(by direction: Int) {
        guard model.canTurn(by: direction) else { return }

        switch prefs.pageTurn {
        case .none:
            model.turnPage(by: direction)
        case .fade:
            crossFade(direction)
        case .slide, .follow:
            slideIn(direction)
        }
    }

    /// 淡出 → 换页 → 淡入。UIKit 视图不适合做位移动画，透明度过得最稳。
    private func crossFade(_ direction: Int) {
        guard contentOpacity > 0.5 else { return }
        withAnimation(.easeInOut(duration: 0.12)) { contentOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            model.turnPage(by: direction)
            withAnimation(.easeInOut(duration: 0.16)) { contentOpacity = 1 }
        }
    }

    /// 先在屏幕外放好新页，再推进来。
    private func slideIn(_ direction: Int) {
        model.turnPage(by: direction)
        contentOffset = CGFloat(direction) * max(viewWidth, 1)
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.22)) { contentOffset = 0 }
        }
    }

    /// 滑动手势松手后：先把当前页送出去，再从另一侧接上新页。
    /// 两段动画分两个 runloop，避免"文字在屏幕中间突然变掉"的观感。
    private func commitSwipe(direction: Int) {
        guard model.canTurn(by: direction) else {
            withAnimation(.easeOut(duration: 0.18)) { contentOffset = 0 }
            return
        }

        switch prefs.pageTurn {
        case .none:
            withAnimation(.easeOut(duration: 0.12)) { contentOffset = 0 }
            model.turnPage(by: direction)

        case .fade:
            withAnimation(.easeOut(duration: 0.12)) { contentOffset = 0 }
            crossFade(direction)

        case .slide, .follow:
            let width = max(viewWidth, 1)
            withAnimation(.easeOut(duration: 0.16)) {
                contentOffset = -CGFloat(direction) * width
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                model.turnPage(by: direction)
                contentOffset = CGFloat(direction) * width
                DispatchQueue.main.async {
                    withAnimation(.easeOut(duration: 0.2)) { contentOffset = 0 }
                }
            }
        }
    }

    /// 左右滑。竖直方向不拦，留给系统手势。
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !model.isMenuVisible else { return }
                guard prefs.pageTurn == .slide || prefs.pageTurn == .follow else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let width = value.translation.width
                let atStart = !model.canTurn(by: -1)
                let atEnd = !model.canTurn(by: 1)
                if (width > 0 && atStart) || (width < 0 && atEnd) {
                    contentOffset = width * 0.22
                } else {
                    contentOffset = width
                }
            }
            .onEnded { value in
                guard !model.isMenuVisible else {
                    withAnimation(.easeOut(duration: 0.2)) { contentOffset = 0 }
                    return
                }
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height), abs(width) > 56 else {
                    withAnimation(.easeOut(duration: 0.18)) { contentOffset = 0 }
                    return
                }
                commitSwipe(direction: width < 0 ? 1 : -1)
            }
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
                pending = PendingFeature(
                    title: "净化还没接上",
                    detail: "净化规则是书源自带的——滤掉站点塞进正文的广告和水印、还原被替换的字。等书源接进来，它会自动生效。"
                )
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
            sideButton("magnifyingglass") {
                pending = PendingFeature(
                    title: "全书搜索还没接上",
                    detail: "现在可以搜目录：点目录按钮，里面有搜索框。正文全文搜索会跟书源搜索一起做。"
                )
            }
            sideButton("list.bullet") { sheet = .catalog }
            sideButton("play") {
                pending = PendingFeature(
                    title: "自动阅读还没接上",
                    detail: "计划里是 3 / 5 / 10 秒自动翻页，条漫模式也会一起做。"
                )
            }
            sideButton("headphones", highlighted: true) {
                pending = PendingFeature(
                    title: "朗读就是下一步",
                    detail: "M5 做：本地系统语音、逐句高亮跟随、点中间收面板、章末自动续读、锁屏可控。用系统音色，不联网、不上传正文。"
                )
            }
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
                        get: { scrubValue ?? model.progressPercent },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        guard !editing, let value = scrubValue else { return }
                        scrubValue = nil
                        model.seek(toPercent: value)
                    }
                )
                .tint(Palette.accent)

                Button("下一章") { model.jump(toChapter: model.chapterIndex + 1) }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink2)
            }
            .padding(.horizontal, 20)

            HStack {
                panelItem("list.bullet", "目录") { sheet = .catalog }
                panelItem("sun.max", "白天") {
                    model.theme = model.theme.isDark ? .day : .night
                }
                panelItem("circle.lefthalf.filled", "主题") {
                    sheet = .settings(.theme)
                }
                panelItem("slider.horizontal.3", "设置") {
                    sheet = .settings(.typography)
                }
                panelItem("arrow.down.to.line", "缓存") {
                    pending = PendingFeature(
                        title: "缓存还没接上",
                        detail: "本地书本来就在手机上，不需要再缓存一份。这个按钮要等在线书源接进来才有意义。"
                    )
                }
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
