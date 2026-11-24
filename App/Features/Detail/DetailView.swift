import SwiftUI
import ReaderCore

struct DetailView: View {
    let book: Book
    @EnvironmentObject private var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var progress: Progress?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    actions
                    summary
                    chapters
                }
                .padding(.bottom, 60)
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { progress = try? env.progress.fetch(bookId: book.id) }
        .confirmationDialog("删除这本书？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("只删记录，保留文件") { deleteBook(removeFiles: false) }
            Button("删除记录和文件", role: .destructive) { deleteBook(removeFiles: true) }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删记录时，原文件仍留在 App 内，可以从备份或文件里找回。")
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 16) {
            BookCoverView(book: book, coverURL: env.library.absoluteCoverURL(for: book))
                .frame(width: 88, height: 124)

            VStack(alignment: .leading, spacing: 6) {
                Text(book.title)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)

                Text(subtitle)
                    .font(Typo.caption)
                    .foregroundStyle(Palette.ink3)

                HStack(spacing: 6) {
                    tag(book.type == .novel ? "小说" : "漫画")
                    tag(book.origin == .local ? "本地" : "在线")
                    if book.chapterCount > 0 {
                        tag("\(book.chapterCount) 章")
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.top, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }

    private var subtitle: String {
        if let author = book.author, !author.isEmpty {
            return "\(author) · \(book.origin == .local ? "本地文件" : "在线书源")"
        }
        return book.origin == .local ? "本地文件" : "在线书源"
    }

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(Color(hex: 0xF0F3F6))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                // 阅读器在 M4 接入
            } label: {
                Text(primaryTitle)
            }
            .buttonStyle(PrimaryButtonStyle())

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 48, height: 46)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Palette.lineStrong, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Palette.danger)
                    .frame(width: 48, height: 46)
                    .background(Palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.button, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
                            .strokeBorder(Palette.lineStrong, lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }

    private var primaryTitle: String {
        guard let progress, progress.chapterIndex > 0 else { return "开始阅读" }
        return "继续阅读 · 第 \(progress.chapterIndex + 1) 章"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("简介")
                .font(Typo.headline)
                .foregroundStyle(Palette.ink)
            Text("这本书还没有填写简介。本地导入的书通常没有简介，在线书源会在详情页显示源站内容。")
                .font(Typo.caption)
                .foregroundStyle(Palette.ink2)
                .lineSpacing(4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.l)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Palette.line, lineWidth: 1)
        }
        .padding(.horizontal, Spacing.xl)
        .padding(.bottom, Spacing.l)
    }

    private var chapters: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("目录").font(Typo.headline).foregroundStyle(Palette.ink)
                Spacer()
                Text("共 \(book.chapterCount) 章").font(Typo.micro).foregroundStyle(Palette.ink3)
            }
            .padding(.horizontal, Spacing.xl)
            .padding(.bottom, 10)

            ForEach(0..<min(book.chapterCount, 5), id: \.self) { index in
                HStack {
                    Text("第 \(index + 1) 章")
                        .font(Typo.body)
                        .foregroundStyle(Palette.ink2)
                    Spacer()
                }
                .padding(.horizontal, Spacing.xl)
                .padding(.vertical, 14)
                .background(Palette.surface)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Color(hex: 0xF3F6F9)).frame(height: 1)
                }
            }

            if book.chapterCount > 5 {
                Text("目录浏览在 M4 的阅读器中提供")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .padding(.horizontal, Spacing.xl)
                    .padding(.top, 12)
            }
        }
    }

    private func deleteBook(removeFiles: Bool) {
        try? env.library.delete(book, removeFiles: removeFiles)
        dismiss()
    }
}
