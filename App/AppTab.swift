import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home, shelf, discover, search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "主页"
        case .shelf: return "书架"
        case .discover: return "发现"
        case .search: return "搜索"
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house"
        case .shelf: return "books.vertical"
        case .discover: return "safari"
        case .search: return "magnifyingglass"
        }
    }
}
