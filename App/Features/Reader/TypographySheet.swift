import SwiftUI
import ReaderCore

struct TypographySheet: View {
    /// 同一张抽屉两种入口：主题只管背景，设置管排版。
    /// 分开的理由是动作性质不同——换背景是随手动作，调字号是坐下来慢慢调。
    enum Focus: Equatable {
        case theme
        case typography
    }

    @Binding var style: ReaderStyle
    @Binding var theme: ReaderTheme
    var focus: Focus = .typography
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color(hex: 0xD3DAE2)).frame(width: 36, height: 4).padding(.vertical, 12)

            if focus == .typography {
                row("字号") {
                stepper("A−") { update { $0.fontSize = max(12, $0.fontSize - 1) } }
                Text("\(Int(style.fontSize))").font(.system(size: 13, weight: .semibold)).frame(width: 34)
                    stepper("A+") { update { $0.fontSize = min(28, $0.fontSize + 1) } }
                }
            }

            if focus == .typography {
                row("行距") {
                stepper("紧") { update { $0.lineHeightMultiple = max(1.4, $0.lineHeightMultiple - 0.15) } }
                stepper("中") { update { $0.lineHeightMultiple = 2.05 } }
                    stepper("松") { update { $0.lineHeightMultiple = min(2.8, $0.lineHeightMultiple + 0.15) } }
                }
            }

            row("背景") {
                HStack(spacing: 10) {
                    ForEach(ReaderTheme.allCases) { item in
                        Button {
                            theme = item
                            onChange()
                        } label: {
                            Circle()
                                .fill(item.background)
                                .frame(width: 26, height: 26)
                                .overlay {
                                    Circle().strokeBorder(theme == item ? Palette.accent : Palette.line, lineWidth: theme == item ? 2 : 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .background(Palette.surface)
    }

    private func update(_ mutate: (inout ReaderStyle) -> Void) {
        var copy = style
        mutate(&copy)
        style = copy
        onChange()
    }

    private func stepper(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink2)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(Color(hex: 0xEDF0F3))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 13.5)).foregroundStyle(Palette.ink2)
            Spacer()
            content()
        }
        .padding(.vertical, 9)
    }
}
