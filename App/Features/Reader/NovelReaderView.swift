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
    case voice

    var id: String {
        switch self {
        case .catalog: return "catalog"
        case .settings(let focus): return "settings-\(focus == .theme ? "theme" : "full")"
        case .voice: return "voice"
        }
    }
}

struct NovelReaderView: View {
    @StateObject private var model: NovelReaderViewModel
    @StateObject private var prefs = ReaderPreferences()
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var sheet: ReaderSheet?
    @State private var pending: PendingFeature?
    @State private var contentOffset: CGFloat = 0
    @State private var contentOpacity: Double = 1
    @State private var incomingText: NSAttributedString?
    @State private var incomingDirection: Int = 1
    @State private var viewWidth: CGFloat = 390
    @State private var scrubValue: Double?
    @State private var editingZones = false
    @StateObject private var speech = SpeechEngine()
    @StateObject private var battery = BatteryMonitor()
    @State private var sleepMinutes: Int?
    @State private var sleepWorkItem: DispatchWorkItem?
    @State private var showingTimerMenu = false

    /// 右边缘右滑退出：整页跟手位移，松手过了阈值就关掉阅读器。
    @State private var exitOffset: CGFloat = 0
    @State private var isEdgeExit = false

    init(book: Book, env: AppEnvironment, initialChapter: Int? = nil) {
        _model = StateObject(wrappedValue: NovelReaderViewModel(
            book: book,
            provider: env.chapterProvider,
            progressRepo: env.progress,
            bookmarkRepo: env.bookmarks,
            booksRepo: env.books,
            initialChapter: initialChapter,
            log: env.importLog
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

                if model.isMenuVisible && !editingZones {
                    menuLayer(size: proxy.size)
                }

                if editingZones {
                    zoneEditor
                }
            }
            .statusBarHidden(model.isMenuVisible == false && !editingZones)
            .onAppear { viewWidth = proxy.size.width }
            .onChange(of: proxy.size) { viewWidth = $0.width }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(model.theme.chromeStyle)
        .onAppear {
            // 先接偏好再加载：分页要用上次的字号，否则第一屏会按默认排版闪一下再重排。
            model.attach(preferences: prefs)
            model.load()
        }
        // 切后台也落一次盘：用户常常按 Home 键离开，而不是点返回。
        .onChange(of: scenePhase) { phase in
            if phase != .active { model.persistProgress(force: true) }
        }
        .onDisappear {
            stopSpeech()
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
                    onSelect: { index in
                        model.jump(toChapter: index)
                        // 正在听书时跳章，朗读必须跟着跳；否则它会继续念原来那一章。
                        restartSpeechFromCurrentPage()
                    },
                    onDeleteBookmark: { model.removeBookmark($0) }
                )
                .presentationDetents([.fraction(0.72), .large])
                .presentationDragIndicator(.visible)

            case .voice:
                VoiceSheet(engine: speech)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)

            case .settings(let focus):
                TypographySheet(
                    style: $model.style,
                    theme: $model.theme,
                    focus: focus,
                    prefs: prefs,
                    onChange: { model.repaginate() },
                    onEditZones: {
                        sheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            withAnimation(.easeInOut(duration: 0.2)) { editingZones = true }
                        }
                    }
                )
                .presentationDetents(detents(for: focus))
                .presentationDragIndicator(.visible)
            }
        }
        .confirmationDialog("定时停止", isPresented: $showingTimerMenu, titleVisibility: .visible) {
            ForEach([5, 15, 30, 60], id: \.self) { minutes in
                Button("\(minutes) 分钟后停止") { scheduleSleepTimer(minutes: minutes) }
            }
            Button("关闭定时") { scheduleSleepTimer(minutes: nil) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("到点会停下朗读，正文停在原处。")
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
        focus == .theme ? [.height(210)] : [.fraction(0.9), .large]
    }

    // MARK: 正文

    private func pageArea(size: CGSize) -> some View {
        VStack(spacing: 0) {
            ZStack {
                // 只有正文参与翻页位移；信息栏在下面固定着，翻页时一动不动。
                ZStack {
                    // 正在读的这一页
                    pageLayer(model.currentPageText)
                        .offset(x: contentOffset)

                    // 下一页提前画好，跟着一起动，中间不会露白
                    if let incoming = incomingText {
                        pageLayer(incoming)
                            .offset(x: contentOffset + CGFloat(incomingDirection) * max(viewWidth, 1))
                    }
                }
                .opacity(contentOpacity)
                .offset(x: exitOffset)

                // 点击区固定在屏幕上，不跟着退出动画走
                tapGrid
            }
            .simultaneousGesture(swipeGesture)
            .onChange(of: model.style) { _ in model.repaginate() }

            infoBar
        }
    }

    private func pageLayer(_ text: NSAttributedString) -> some View {
        GeometryReader { content in
            ReaderTextView(
                attributedText: text,
                background: UIColor(model.theme.background)
            )
            .padding(.horizontal, model.style.marginHorizontal)
            .padding(.top, model.style.marginTop)
            .onAppear { model.repaginateIfNeeded(size: pageInnerSize(content.size)) }
            .onChange(of: content.size) { newValue in
                model.repaginateIfNeeded(size: pageInnerSize(newValue))
            }
        }
    }

    /// 固定在底部的信息栏：左上是书名，书名下面是电量，中间章号，右侧页码。
    /// 三个位置宽度都写死，翻页只换数字，不会因为「第 9 页」变「第 10 页」就整排挪一下。
    private var infoBar: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.book.title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(model.theme.textColor.opacity(0.58))
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 3) {
                    Image(systemName: battery.symbolName)
                        .font(.system(size: 9))
                    Text(battery.percentText)
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                }
                .foregroundStyle(battery.isLow
                                 ? Color(hex: 0xC65B4E)
                                 : model.theme.textColor.opacity(0.42))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("第 \(model.chapterIndex + 1) 章")
                .font(.system(size: 10))
                .foregroundStyle(model.theme.textColor.opacity(0.42))
                .lineLimit(1)
                .frame(width: 78)

            Text("\(model.displayPage) / \(model.pageCount)")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(model.theme.textColor.opacity(0.42))
                .frame(width: 58, alignment: .trailing)
        }
        .padding(.horizontal, model.style.marginHorizontal)
        .padding(.top, 2)
        .padding(.bottom, 5)
        .frame(height: 32)
    }

    private func pageInnerSize(_ size: CGSize) -> CGSize {
        CGSize(width: max(size.width - model.style.marginHorizontal * 2, 40),
               height: max(size.height - 8, 40))
    }

    // MARK: 点击区域（九宫格）

    private var tapGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { column in
                        tapZone(TapZone.grid[row][column])
                    }
                }
            }
        }
    }

    private func tapZone(_ zone: TapZone) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { perform(prefs.zones[zone]) }
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
            followSpeechAfterManualMove()
        case .fade:
            crossFade(direction)
        case .slide, .follow:
            slideTurn(direction)
        }
    }

    /// 淡出 → 换页 → 淡入。UIKit 视图做位移容易抖，透明度最稳。
    private func crossFade(_ direction: Int) {
        guard contentOpacity > 0.5 else { return }
        withAnimation(.easeInOut(duration: 0.12)) { contentOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            model.turnPage(by: direction)
            withAnimation(.easeInOut(duration: 0.16)) { contentOpacity = 1 }
            followSpeechAfterManualMove()
        }
    }

    /// 两页同时动：旧页滑出去的同时，新页从另一侧补上。
    /// 上一版是「旧页滑走 → 停顿 → 新页进来」，中间必然露一段白，那张截图就是这么来的。
    private func slideTurn(_ direction: Int) {
        guard let next = model.pageText(offset: direction) else {
            // 全书第一页往前 / 最后一页往后：没有相邻页可画，退化成淡入淡出
            crossFade(direction)
            return
        }

        incomingDirection = direction
        incomingText = next
        contentOffset = 0

        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.26)) {
                contentOffset = -CGFloat(direction) * max(viewWidth, 1)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.27) {
            model.turnPage(by: direction)
            incomingText = nil
            contentOffset = 0
            followSpeechAfterManualMove()
        }
    }

    private func snapBack() {
        withAnimation(.easeOut(duration: 0.2)) {
            contentOffset = 0
            exitOffset = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { incomingText = nil }
    }

    /// 跟手滑动：拖动时两页一起走，松手按位移决定落地还是弹回。
    /// 右边缘往里滑交给退出：这是手机上一个很顺手的动作，翻页手势不该把它吃掉。
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !model.isMenuVisible, !editingZones else { return }

                // 先判退出，再判翻页。否则默认「平移」模式下边缘右滑会被当成上一页。
                if isEdgeExit || startsAtRightEdge(value) {
                    isEdgeExit = true
                    exitOffset = max(0, min(value.translation.width, max(viewWidth, 1)))
                    return
                }

                guard prefs.pageTurn == .follow || prefs.pageTurn == .slide else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }

                let width = value.translation.width
                let direction = width < 0 ? 1 : -1
                let atBoundary = !model.canTurn(by: direction)

                if atBoundary {
                    incomingText = nil
                    contentOffset = width * 0.22
                } else {
                    if incomingDirection != direction || incomingText == nil {
                        incomingText = model.pageText(offset: direction)
                        incomingDirection = direction
                    }
                    contentOffset = width
                }
            }
            .onEnded { value in
                if isEdgeExit {
                    finishEdgeExit(value)
                    return
                }

                guard !model.isMenuVisible, !editingZones else {
                    snapBack()
                    return
                }
                let width = value.translation.width
                guard abs(width) > abs(value.translation.height), abs(width) > 56 else {
                    snapBack()
                    return
                }

                let direction = width < 0 ? 1 : -1
                guard model.canTurn(by: direction) else {
                    snapBack()
                    return
                }

                // 无动画与淡入淡出本来就没有"下一页"可预渲染，硬走滑动会露白。
                // 交给各自的翻页实现，滑动只负责识别方向。
                if prefs.pageTurn == .none {
                    contentOffset = 0
                    model.turnPage(by: direction)
                    followSpeechAfterManualMove()
                    return
                }
                if prefs.pageTurn == .fade {
                    contentOffset = 0
                    crossFade(direction)
                    return
                }

                guard incomingText != nil else {
                    snapBack()
                    return
                }

                withAnimation(.easeOut(duration: 0.2)) {
                    contentOffset = -CGFloat(direction) * max(viewWidth, 1)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.21) {
                    model.turnPage(by: direction)
                    incomingText = nil
                    contentOffset = 0
                    followSpeechAfterManualMove()
                }
            }
    }

    /// 起点在屏幕最右侧 28pt 内、向右拖，才算退出。
    private func startsAtRightEdge(_ value: DragGesture.Value) -> Bool {
        value.startLocation.x > viewWidth - 28
            && value.translation.width > 6
            && abs(value.translation.width) > abs(value.translation.height)
    }

    private func finishEdgeExit(_ value: DragGesture.Value) {
        isEdgeExit = false
        let distance = value.translation.width
        let projected = value.predictedEndTranslation.width
        let shouldClose = distance > 96 || (distance > 40 && projected > 200)

        if shouldClose {
            withAnimation(.easeOut(duration: 0.18)) {
                exitOffset = max(viewWidth, 1)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                closeReader()
            }
        } else {
            withAnimation(.easeOut(duration: 0.22)) { exitOffset = 0 }
        }
    }

    /// 关阅读器前先把声音停干净。只 dismiss 不 stop，排队中的回调会把下一章念出来。
    private func closeReader() {
        stopSpeech()
        dismiss()
    }

    // MARK: 区域编辑

    private var zoneEditor: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .onTapGesture { }   // 吃掉点击，避免穿透到正文

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("屏幕区域功能")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                        Text("点一个区域，选它做什么")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    Spacer()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { editingZones = false }
                    } label: {
                        Text("完成")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 15)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 58)
                .padding(.bottom, 16)

                GeometryReader { proxy in
                    VStack(spacing: 6) {
                        ForEach(0..<3, id: \.self) { row in
                            HStack(spacing: 6) {
                                ForEach(0..<3, id: \.self) { column in
                                    zoneCell(TapZone.grid[row][column])
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: min(proxy.size.height - 40, 520))
                }

                Spacer(minLength: 0)
            }
        }
        .transition(.opacity)
    }

    private func zoneCell(_ zone: TapZone) -> some View {
        Menu {
            ForEach(TapAction.allCases) { action in
                Button {
                    prefs.zones[zone] = action
                } label: {
                    if prefs.zones[zone] == action {
                        Label(action.title, systemImage: "checkmark")
                    } else {
                        Text(action.title)
                    }
                }
            }
        } label: {
            VStack(spacing: 7) {
                Text(zone.title)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.6))
                Text(prefs.zones[zone].title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(prefs.zones[zone] == .none ? Color.white.opacity(0.38) : Color.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        Color.white.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            }
        }
    }

    // MARK: 朗读控制

    private func startSpeech() {
        guard let text = model.prepareSpeech() else {
            pending = PendingFeature(
                title: "这一章没有可朗读的文字",
                detail: "章节内容可能是空的，或者还没加载完。"
            )
            return
        }
        wireSpeechCallbacks()
        speech.updateMetadata(title: model.book.title, subtitle: model.chapterTitle)
        speech.speak(text)
        withAnimation(.easeInOut(duration: 0.18)) { model.isMenuVisible = true }
    }

    /// 一句念完后自动接下一句；本章念完自动接下一章；全书念完就停。
    ///
    /// 所有回调都对 engine / viewModel 弱引用：闭包挂在 engine 自己身上，
    /// 强引用会形成自循环，阅读器关掉后 SpeechEngine 还活着，声音就一直停不下来。
    private func wireSpeechCallbacks() {
        let engine = speech
        let viewModel = model

        engine.onFinishUtterance = { [weak engine, weak viewModel] in
            guard let engine, let viewModel else { return }
            if let next = viewModel.advanceSpeechText() {
                engine.updateMetadata(title: viewModel.book.title, subtitle: viewModel.chapterTitle)
                engine.speak(next)
            } else if let nextChapter = viewModel.beginNextChapterForSpeech() {
                engine.updateMetadata(title: viewModel.book.title, subtitle: viewModel.chapterTitle)
                engine.speak(nextChapter)
            } else {
                engine.stop()
                viewModel.endSpeech()
            }
        }
        engine.onRemotePlay = { [weak engine] in
            guard let engine else { return }
            if engine.isPaused { engine.resume() }
        }
        engine.onRemotePause = { [weak engine] in engine?.pause() }
        engine.onRemoteNext = { [weak engine, weak viewModel] in
            guard let engine, let viewModel else { return }
            if let next = viewModel.advanceSpeechText() { engine.speak(next) }
        }
        engine.onRemotePrevious = { [weak engine, weak viewModel] in
            guard let engine, let viewModel else { return }
            if let text = viewModel.rewindSpeechText() { engine.speak(text) }
        }
    }

    /// 手动翻页、跳章之后，让朗读跟到新的位置。
    private func followSpeechAfterManualMove() {
        guard model.isSpeechPrepared else { return }
        if let text = model.realignSpeechToCurrentPage() {
            speech.updateMetadata(title: model.book.title, subtitle: model.chapterTitle)
            speech.speak(text)
        }
    }

    /// 面板上的翻页 / 翻章之后，从新页的第一句重新念。
    private func restartSpeechFromCurrentPage() {
        guard model.isSpeechPrepared else { return }
        if let text = model.prepareSpeech(startAtCurrentPage: true) {
            speech.updateMetadata(title: model.book.title, subtitle: model.chapterTitle)
            speech.speak(text)
        }
    }

    private func stopSpeech() {
        speech.stop()
        sleepWorkItem?.cancel()
        sleepWorkItem = nil
        sleepMinutes = nil
        model.endSpeech()
    }

    private func scheduleSleepTimer(minutes: Int?) {
        sleepWorkItem?.cancel()
        sleepMinutes = minutes
        guard let minutes else {
            sleepWorkItem = nil
            return
        }
        let item = DispatchWorkItem { stopSpeech() }
        sleepWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(minutes) * 60, execute: item)
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
            if model.isSpeechPrepared {
                speechPanel
            } else {
                bottomPanel
            }
        }
        .transition(.opacity)
    }

    // MARK: 朗读面板

    private var speechPanel: some View {
        SpeechPanel(
            isPaused: speech.isPaused,
            status: model.speechStatusText,
            detail: sleepLabel ?? model.speechDetailText,
            onPreviousChapter: {
                model.jump(toChapter: model.chapterIndex - 1)
                restartSpeechFromCurrentPage()
            },
            onPreviousPage: {
                model.turnPage(by: -1)
                restartSpeechFromCurrentPage()
            },
            onTogglePlay: {
                if speech.isPaused { speech.resume() } else { speech.pause() }
            },
            onNextPage: {
                model.turnPage(by: 1)
                restartSpeechFromCurrentPage()
            },
            onNextChapter: {
                model.jump(toChapter: model.chapterIndex + 1)
                restartSpeechFromCurrentPage()
            },
            onCatalog: { sheet = .catalog },
            onSettings: { sheet = .settings(.typography) },
            onExit: { stopSpeech() },
            onVoice: { sheet = .voice },
            onTimer: { showingTimerMenu = true }
        )
    }

    private var sleepLabel: String? {
        guard let sleepMinutes else { return nil }
        return "定时 \(sleepMinutes) 分钟后停止"
    }

    private var topBar: some View {
        HStack {
            Button { closeReader() } label: {
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
            sideButton("bookmark") {
                model.addBookmark()
                Haptics.impact(.light)
            }
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
            sideButton("headphones", highlighted: true) { startSpeech() }
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
                panelItem("hand.tap", "区域") {
                    withAnimation(.easeInOut(duration: 0.2)) { editingZones = true }
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
