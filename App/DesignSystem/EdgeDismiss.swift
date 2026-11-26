import SwiftUI

/// 从左边缘右滑关闭当前全屏页。
/// 只负责位移与判定，不处理菜单；阅读器可以按需开关。
struct EdgeDismissModifier: ViewModifier {
    var enabled: Bool = true

    @Environment(\.dismiss) private var dismiss
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var active = false

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(gesture(width: proxy.size.width))
                .onAppear { width = proxy.size.width }
                .onChange(of: proxy.size) { width = $0.width }
        }
    }

    private func gesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard enabled else { return }
                let fromEdge = value.startLocation.x < 30
                    && value.translation.width > 6
                    && abs(value.translation.width) > abs(value.translation.height)
                guard active || fromEdge else { return }
                active = true
                offset = max(0, min(value.translation.width, max(width, 1)))
            }
            .onEnded { value in
                guard active else { return }
                active = false
                let projected = value.predictedEndTranslation.width
                if value.translation.width > 96 || (value.translation.width > 40 && projected > 200) {
                    withAnimation(.easeOut(duration: 0.18)) { offset = max(width, 1) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { dismiss() }
                } else {
                    withAnimation(.easeOut(duration: 0.22)) { offset = 0 }
                }
            }
    }
}

extension View {
    func edgeDismiss(enabled: Bool = true) -> some View {
        modifier(EdgeDismissModifier(enabled: enabled))
    }
}
