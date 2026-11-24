import SwiftUI
import UIKit
import ReaderCore

/// 封面缩略图。带一层内存缓存，避免滚动时反复解码。
struct BookCoverView: View {
    let book: Book
    let coverURL: URL?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = CoverImageCache.shared.image(for: book.id, url: coverURL) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    LinearGradient(
                        colors: [Color(hex: 0xD9E3EC), Color(hex: 0xC3D2E0)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text(String(book.title.prefix(2)))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.85))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
    }
}

final class CoverImageCache {
    static let shared = CoverImageCache()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
    }

    func image(for id: String, url: URL?) -> UIImage? {
        guard let url else { return nil }
        let key = id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}
