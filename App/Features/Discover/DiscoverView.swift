import SwiftUI
import ReaderCore

/// 发现页。M6 阶段只承担一件事：让书源能被导入、被看到、被管理。
/// 榜单和分类要等源里的 exploreUrl 规则跑通再上，这里先不铺空架子。
struct DiscoverView: View {
    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var router: TabRouter

    @State private var sourceCount = 0
    @State private var enabledCount = 0
    @State private var showingImport = false
    @State private var loadError: String?

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    if let loadError {
                        Card {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("读取书源失败")
                                    .font(Typo.headline)
                                    .foregroundStyle(Palette.danger)
                                Text(loadError)
                                    .font(Typo.micro)
                                    .foregroundStyle(Palette.ink3)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if sourceCount == 0 {
                        importGuide
                    } else {
                        sourceCard
                        searchHint
                    }

                    rulesCard
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("发现")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SourcesView()
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                }
                .accessibilityLabel("书源管理")
            }
        }
        .sheet(isPresented: $showingImport) {
            SourceImportSheet { _ in reload() }
                .presentationDetents([.medium, .large])
        }
        .onAppear(perform: reload)
    }

    // MARK: 块

    private var importGuide: some View {
        Card(padding: 18) {
            VStack(spacing: 14) {
                Image(systemName: "books.vertical")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Palette.accent)
                    .padding(.top, 4)

                VStack(spacing: 5) {
                    Text("先导入一份书源")
                        .font(Typo.headline)
                        .foregroundStyle(Palette.ink)
                    Text("书源决定了能搜到哪些站的书。支持 legado 导出的 JSON，一次可以导入几千条。")
                        .font(Typo.caption)
                        .foregroundStyle(Palette.ink3)
                        .multilineTextAlignment(.center)
                }

                Button("导入书源") { showingImport = true }
                    .buttonStyle(PrimaryButtonStyle())

                NavigationLink {
                    SourcesView()
                } label: {
                    Text("先看看书源管理")
                        .font(Typo.micro)
                        .foregroundStyle(Palette.accent)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var sourceCard: some View {
        NavigationLink {
            SourcesView()
        } label: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(Palette.accent)
                        .frame(width: 42, height: 42)
                        .background(Palette.accentSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("书源")
                            .font(Typo.headline)
                            .foregroundStyle(Palette.ink)
                        Text("已导入 \(sourceCount) 条 · 启用 \(enabledCount) 条")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.ink3)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var searchHint: some View {
        Button {
            router.selection = .search
        } label: {
            Card {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .light))
                        .foregroundStyle(Palette.ink2)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("去「搜索」找书")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Palette.ink)
                        Text("搜索结果按源分组，谁先回谁先出")
                            .font(Typo.micro)
                            .foregroundStyle(Palette.ink3)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.ink3)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var rulesCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("关于书源")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                Text("书源是社区维护的站点解析规则。源站改版会导致规则失效，这时「测一下」会显示超时或失败——关掉它就行，不影响其他源。")
                    .font(Typo.micro)
                    .foregroundStyle(Palette.ink3)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 数据

    private func reload() {
        do {
            let all = try env.sources.all()
            sourceCount = all.count
            enabledCount = all.filter(\.enabled).count
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}
