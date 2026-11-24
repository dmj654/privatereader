import SwiftUI

/// 统一的毛玻璃底：材质 + 薄色罩，保证「透色不透字」。
struct GlassBackground: View {
    var tint: Color = Palette.bg
    var tintOpacity: Double = 0.74

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle().fill(tint.opacity(tintOpacity))
        }
    }
}

extension View {
    /// 顶部导航毛玻璃：下方一条 0.5pt 分隔线。
    func glassTopBar(tint: Color = Palette.bg, tintOpacity: Double = 0.74) -> some View {
        self
            .background(GlassBackground(tint: tint, tintOpacity: tintOpacity))
            .overlay(alignment: .bottom) {
                Rectangle().fill(Palette.line).frame(height: 0.5)
            }
    }

    /// 底部面板毛玻璃：上方一条 0.5pt 分隔线。
    func glassBottomPanel(tint: Color = Palette.surface, tintOpacity: Double = 0.92) -> some View {
        self
            .background(GlassBackground(tint: tint, tintOpacity: tintOpacity))
            .overlay(alignment: .top) {
                Rectangle().fill(Palette.line).frame(height: 0.5)
            }
    }
}
