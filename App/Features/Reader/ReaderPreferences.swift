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
        case .none: return "立刻换页，最省电"
        case .fade: return "旧页淡出、新页淡入，最安静"
        case .slide: return "新页从侧面推进来，方向感明确"
        case .follow: return "拖动时两页一起跟手指走，松手才落地"
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

/// 屏幕九宫格。每个格子可以单独指定功能。
enum TapZone: String, CaseIterable, Codable, Identifiable {
    case topLeft, topCenter, topRight
    case middleLeft, center, middleRight
    case bottomLeft, bottomCenter, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: return "左上"
        case .topCenter: return "中上"
        case .topRight: return "右上"
        case .middleLeft: return "中左"
        case .center: return "正中"
        case .middleRight: return "中右"
        case .bottomLeft: return "左下"
        case .bottomCenter: return "中下"
        case .bottomRight: return "右下"
        }
    }

    var column: Int {
        switch self {
        case .topLeft, .middleLeft, .bottomLeft: return 0
        case .topCenter, .center, .bottomCenter: return 1
        case .topRight, .middleRight, .bottomRight: return 2
        }
    }

    static let grid: [[TapZone]] = [
        [.topLeft, .topCenter, .topRight],
        [.middleLeft, .center, .middleRight],
        [.bottomLeft, .bottomCenter, .bottomRight]
    ]
}

struct TapZoneConfig: Codable, Equatable {
    private var actions: [String: TapAction]

    init() {
        var map: [String: TapAction] = [:]
        for zone in TapZone.allCases {
            map[zone.rawValue] = Self.defaultAction(for: zone)
        }
        actions = map
    }

    /// 默认：左列翻上一页、右列翻下一页、中列呼菜单。
    /// 中间一整列都给菜单，是因为九宫格中间那一格很小，要求用户精确点在中心不现实。
    static func defaultAction(for zone: TapZone) -> TapAction {
        switch zone.column {
        case 0: return .previousPage
        case 2: return .nextPage
        default: return .toggleMenu
        }
    }

    subscript(zone: TapZone) -> TapAction {
        get { actions[zone.rawValue] ?? .none }
        set { actions[zone.rawValue] = newValue }
    }

    var isUsable: Bool {
        TapZone.allCases.contains { self[$0] != .none }
    }

    // 手写 Codable：某个键缺失时补默认值，而不是整份配置解码失败。
    private enum CodingKeys: String, CodingKey {
        case actions
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let stored = (try? container.decode([String: TapAction].self, forKey: .actions)) ?? [:]
        var map: [String: TapAction] = [:]
        for zone in TapZone.allCases {
            map[zone.rawValue] = stored[zone.rawValue] ?? Self.defaultAction(for: zone)
        }
        actions = map
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(actions, forKey: .actions)
    }
}

// MARK: - 持久化

/// 阅读器的交互偏好。放 UserDefaults，不进数据库——它不是书的内容，重装也愿意重设。
///
/// 这里必须包含**所有**会在阅读器里被调、并且下次进来还应当保持的东西：
/// 翻页动画、九宫格、排版参数、背景主题。少存一样，用户就要每天重调一遍。
final class ReaderPreferences: ObservableObject {
    private static let keyV2 = "reader.preferences.v2"
    private static let keyV1 = "reader.preferences.v1"

    private struct Snapshot: Codable {
        var pageTurn: PageTurnMode
        var zones: TapZoneConfig
        var style: ReaderStyle?
        var theme: ReaderTheme?
    }

    /// 第一版的旧结构：三个横向大区。用来做一次迁移。
    private struct SnapshotV1: Codable {
        struct Zones: Codable {
            var left: TapAction
            var center: TapAction
            var right: TapAction
        }
        var pageTurn: PageTurnMode
        var zones: Zones
    }

    @Published var pageTurn: PageTurnMode {
        didSet { persist() }
    }

    @Published var zones: TapZoneConfig {
        didSet { persist() }
    }

    /// 字号、行距、字间距、段间距、页边距、字体、缩进、对齐。
    @Published var style: ReaderStyle {
        didSet { persist() }
    }

    /// 背景主题（日间/护眼/夜间/纯黑）。
    @Published var theme: ReaderTheme {
        didSet { persist() }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.keyV2),
           let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            pageTurn = snapshot.pageTurn
            zones = snapshot.zones
            style = snapshot.style ?? .default
            theme = snapshot.theme ?? .day
            return
        }

        if let data = UserDefaults.standard.data(forKey: Self.keyV1),
           let old = try? JSONDecoder().decode(SnapshotV1.self, from: data) {
            pageTurn = old.pageTurn
            var migrated = TapZoneConfig()
            for zone in TapZone.allCases {
                switch zone.column {
                case 0: migrated[zone] = old.zones.left
                case 2: migrated[zone] = old.zones.right
                default: migrated[zone] = old.zones.center
                }
            }
            zones = migrated
            style = .default
            theme = .day
            persist()
            return
        }

        pageTurn = .slide
        zones = TapZoneConfig()
        style = .default
        theme = .day
    }

    private func persist() {
        let snapshot = Snapshot(pageTurn: pageTurn, zones: zones, style: style, theme: theme)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.keyV2)
    }
}
