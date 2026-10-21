import SwiftUI

/// Observable tab selection (avoids the `@State` macro, which the Command Line
/// Tools toolchain cannot expand).
final class TabSelection: ObservableObject {
    @Published var selectedTab: ContentView.Tab = .dashboard
}

struct ContentView: View {
    @StateObject private var dashboard = DashboardViewModel()
    @StateObject private var tabs = TabSelection()

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case install = "Install"
        case genres = "Genres"
        case nowPlaying = "Now Playing"
        case library = "Library"
        case extras = "Extras"
        case settings = "Settings"
        case status = "Status"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $tabs.selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("FreeTube")
        } detail: {
            Group {
                switch tabs.selectedTab {
                case .dashboard:
                    DashboardView(viewModel: dashboard)
                case .install:
                    InstallView(viewModel: InstallViewModel())
                case .genres:
                    GenresView(viewModel: GenresViewModel())
                case .nowPlaying:
                    NowPlayingView()
                case .library:
                    LibraryView(viewModel: LibraryViewModel())
                case .extras:
                    ExtrasView(viewModel: ExtrasViewModel())
                case .settings:
                    SettingsView(viewModel: SettingsViewModel())
                case .status:
                    StatusView(viewModel: StatusViewModel())
                }
            }
            .navigationTitle(tabs.selectedTab.rawValue)
        }
        .frame(minWidth: 960, minHeight: 680)
        .onAppear {
            dashboard.checkSystemHealth()
            FreeTubeDataService.shared.reload()
        }
    }
}

private extension ContentView.Tab {
    var icon: String {
        switch self {
        case .dashboard: return "house.fill"
        case .install: return "arrow.down.circle.fill"
        case .genres: return "music.note.list.fill"
        case .nowPlaying: return "play.circle.fill"
        case .library: return "books.vertical.fill"
        case .extras: return "sparkles"
        case .settings: return "gearshape.fill"
        case .status: return "checkmark.shield.fill"
        }
    }
}
