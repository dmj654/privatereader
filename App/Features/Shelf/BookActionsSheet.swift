import SwiftUI
import ReaderCore

/// 长按书封弹出的操作面板。
///
/// 之前用的是系统 `contextMenu`：长按会先把整个书架模糊压暗，再盖一个系统菜单上来，
/// 那是文件管理器的语言。这里是自绘的底部面板，跟 App 其他面板同一套圆角和配色。
struct BookActionsSheet: View {
    let book: Book
    let coverURL: URL?
    let groups: [BookGroup]
    let currentGroupID: String?

    let onDetail: () -> Void
    let onMove: (String) -> Void
    let onFinished: () -> Void
    let onToggleDropped: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    private var currentGroupName: String {
        groups.first { $0.id == currentGroupID }?.name ?? "未分组"
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            VStack(spacing: 0) {
                row(icon: "info.circle", title: "查看详情", action: onDetail)

                Menu {
                    ForEach(groups) { group in
                        Button {
                            onMove(group.id)
                        } label: {
                            if group.id == currentGroupID {
                                Label(group.name, systemImage: "checkmark")
                            } else {
                                Text(group.name)
                            }
                        }
                    }
                } label: {
                    rowLabel(icon: "folder", title: "移到分组", trailing: currentGroupName, chevron: true)
                }

                row(icon: "checkmark.circle",
                    title: book.status == .finished ? "标记为在读" : "标记已读完",
                    action: onFinished)

                row(icon: "xmark.circle",
                    title: currentGroupID == BookGroup.builtinDroppedID ? "移回在追" : "标记弃读",
                    action: onToggleDropped)

                row(icon: "trash", title: "删除", destructive: true, action: onDelete)
            }
            .background(Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.line, lineWidth: 1)
            }
            .padding(.horizontal, Spacing.xl)

            Spacer(minLength: 0)
        }
        .background(Palette.bg)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            BookCoverView(book: book, coverURL: coverURL)
                .frame(width: 44, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(book.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                Text("\(book.author ?? "未知作者") · \(currentGroupName)")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.ink3)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func row(icon: String,
                     title: String,
                     trailing: String? = nil,
                     destructive: Bool = false,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            rowLabel(icon: icon, title: title, trailing: trailing, destructive: destructive, chevron: false)
        }
        .buttonStyle(.plain)
    }

    private func rowLabel(icon: String,
                          title: String,
                          trailing: String? = nil,
                          destructive: Bool = false,
                          chevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(destructive ? Palette.danger : Palette.ink2)
                .frame(width: 22)

            Text(title)
                .font(.system(size: 14.5))
                .foregroundStyle(destructive ? Palette.danger : Palette.ink)

            Spacer(minLength: 0)

            if let trailing {
                Text(trailing)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.ink3)
            }
            if chevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.ink3.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(hex: 0xF3F6F9)).frame(height: 1)
        }
    }
}
