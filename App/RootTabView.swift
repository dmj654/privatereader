import SwiftUI

struct RootTabView: View {
    @StateObject private var router = TabRouter()

    private var selection: AppTab { router.selection }

    var body: some View {
        ZStack(alignment: .bottom) {
            Palette.bg.ignoresSafeArea()

            ZStack {
                ForEach(AppTab.allCases) { tab in
                    NavigationStack {
                        rootView(for: tab)
                    }
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
                }
            }

            if !router.hidesTabBar {
                GlassTabBar(selection: $router.selection)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .tint(Palette.accent)
        .environmentObject(router)
        .animation(.easeInOut(duration: 0.18), value: router.hidesTabBar)
    }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView()
        case .shelf: ShelfView()
        case .discover: DiscoverView()
        case .search: SearchView()
        }
    }
}

struct GlassTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 21, weight: .regular))
                            .frame(height: 22)
                        Text(tab.title)
                            .font(.system(size: 10, weight: selection == tab ? .semibold : .regular))
                    }
                    .foregroundStyle(selection == tab ? Palette.accent : Palette.ink3)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(.top, 9)
        .padding(.bottom, 22)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Palette.surface.opacity(0.72)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            Rectangle().fill(Palette.line).frame(height: 0.5)
        }
    }
}
