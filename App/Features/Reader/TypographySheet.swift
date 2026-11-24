import SwiftUI
import ReaderCore

/// 排版 / 交互设置。
/// 主题入口只显示背景，设置入口显示全部——换背景是随手动作，调字号是坐下来慢慢调。
struct TypographySheet: View {
    enum Focus: Equatable {
        case theme
        case typography
    }

    @Binding var style: ReaderStyle
    @Binding var theme: ReaderTheme
    var focus: Focus = .typography
    @ObservedObject var prefs: ReaderPreferences
    let onChange: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                if focus == .typography {
                    row("字号") {
                        HStack(spacing: 8) {
                            stepper("A−") { update { $0.fontSize = max(12, $0.fontSize - 1) } }
                            Text("\(Int(style.fontSize))")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.ink)
                                .frame(width: 30)
                            stepper("A+") { update { $0.fontSize = min(28, $0.fontSize + 1) } }
                        }
                    }

                    row("行距") {
                        HStack(spacing: 8) {
                            stepper("紧") { update { $0.lineHeightMultiple = max(1.4, $0.lineHeightMultiple - 0.15) } }
                            stepper("中") { update { $0.lineHeightMultiple = 2.05 } }
                            stepper("松") { update { $0.lineHeightMultiple = min(2.8, $0.lineHeightMultiple + 0.15) } }
                        }
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
                                        Circle().strokeBorder(
                                            theme == item ? Palette.accent : Palette.line,
                                            lineWidth: theme == item ? 2 : 1
                                        )
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if focus == .typography {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("翻页动画")
                            .font(.system(size: 13.5))
                            .foregroundStyle(Palette.ink2)

                        HStack(spacing: 8) {
                            ForEach(PageTurnMode.allCases) { mode in
                                Button {
                                    prefs.pageTurn = mode
                                } label: {
                                    Text(mode.title)
                                        .font(.system(size: 12, weight: prefs.pageTurn == mode ? .semibold : .regular))
                                        .foregroundStyle(prefs.pageTurn == mode ? Color.white : Palette.ink2)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 32)
                                        .background(prefs.pageTurn == mode ? Palette.ink : Color(hex: 0xF0F3F6))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Text(prefs.pageTurn.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(.vertical, 12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                    .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("点击区域")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Palette.ink2)
                            Spacer()
                            Text("左右各占 1/3")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.ink3)
                        }
                        .padding(.bottom, 2)

                        zoneRow("左侧", selection: $prefs.zones.left)
                        zoneRow("中间", selection: $prefs.zones.center)
                        zoneRow("右侧", selection: $prefs.zones.right)

                        if !prefs.zones.isUsable {
                            Text("三个区域都设成「无动作」了，点屏幕不会有反应。")
                                .font(.system(size: 11))
                                .foregroundStyle(Palette.danger)
                                .padding(.top, 4)
                        }
                    }
                    .padding(.top, 12)
                    .overlay(alignment: .top) {
                        Rectangle().fill(Palette.line).frame(height: 1)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(Palette.surface)
    }

    // MARK: 组件

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

    private func zoneRow(_ title: String, selection: Binding<TapAction>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Palette.ink3)
            Spacer()
            Picker("", selection: selection) {
                ForEach(TapAction.allCases) { action in
                    Text(action.title).tag(action)
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.accent)
        }
        .padding(.vertical, 2)
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.ink2)
            Spacer()
            content()
        }
        .padding(.vertical, 9)
    }
}
