import SwiftUI
import ReaderCore

struct BookCell: View {
    let book: Book
    let coverURL: URL?
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                BookCoverView(book: book, coverURL: coverURL)
                    .aspectRatio(3.0 / 4.15, contentMode: .fit)

                if book.newChapterCount > 0 {
                    badge(text: "\(book.newChapterCount)")
                }
            }

            Text(book.title)
                .font(.system(size: 12.5))
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
                .padding(.top, 8)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEDF0F3))
                    Capsule().fill(Palette.accent)
                        .frame(width: max(0, min(1, progress)) * proxy.size.width)
                }
            }
            .frame(height: 2.5)
            .padding(.top, 6)
        }
    }

    private func badge(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(Palette.accent)
            .clipShape(Capsule())
            .padding(6)
    }
}
