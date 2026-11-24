import SwiftUI
import Combine

// MARK: - 翻页动画

enum PageTurnMode: String, CaseIterable, Codable, Identifiable {
    case none
    case fade
    case slide
    case follow

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "无动画"
        case .fade: return "淡入淡出"
        case .slide: return "平移"
        case .follow: return "跟手滑动"
        }
    }

    var detail: String {
        switch self {
        case .none: return "立刻换页，最省电，眼睛不累"
        case .fade: return "旧页淡出、新页淡入，最安静"
        case .slide: return "新页从侧面推进来，方向感明确"
        case .follow: return "拖动时页面跟手指走，松手才翻"
        }
    }
}

// MARK: - 点击区域

enum TapAction: String, CaseIterable, Codable, Identifiable {
    case previousPage
    case nextPage
    case toggleMenu
    case previousChapter
    case nextChapter
    case none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .previousPage: return "上一页"
        case .nextPage: return "下一页"
        case .toggleMenu: return "呼出 / 收起菜单"
        case .previousChapter: return "上一章"
        case .nextChapter: return "下一章"
        case .none: return "无动作"
        }
    }
}

enum TapZone: String, CaseIterable {
    case left
    case center
    case right

    var title: String {
        switch self {
        case .left: return "左侧 1/3"
        case .center: return "中间 1/3"
        case .right: return "右侧 1/3"
        }
    }
}

struct TapZoneConfig: Codable, Equatable {
    var left: TapAction = .previousPage
    var center: TapAction = .toggleMenu
    var right: TapAction = .nextPage

    func action(for zone: TapZone) -> TapAction {
        switch zone {
        case .left: return left
        case .center: return center
        case .right: return right
        }
    }

    /// 三个区域不能全设成「无动作」，否则点哪儿都没反应，用户会以为卡住。
    var isUsable: Bool {
        [left, center, right].contains { $0 != .none }
    }
}

// MARK: - 持久化

/// 阅读器的交互偏好。放 UserDefaults，不进数据库——它不是书的内容，重装也愿意重设。
final class ReaderPreferences: ObservableObject {
    private static let storageKey = "reader.preferences.v1"

    private struct Snapshot: Codable {
        var pageTurn: PageTurnMode
        var zones: TapZoneConfig
    }

    @Published var pageTurn: PageTurnMode {
        didSet { persist() }
    }

    @Published var zones: TapZoneConfig {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            self.pageTurn = snapshot.pageTurn
            self.zones = snapshot.zones
        } else {
            self.pageTurn = .slide
            self.zones = TapZoneConfig()
        }
    }

    private func persist() {
        let snapshot = Snapshot(pageTurn: pageTurn, zones: zones)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
