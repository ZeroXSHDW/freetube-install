import SwiftUI

struct ContentView: View {
    @StateObject private var dashboard = DashboardViewModel()
    @State private var selectedTab: Tab = .dashboard

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case install = "Install"
        case genres = "Genres"
        case nowPlaying = "Now Playing"
        case settings = "Settings"
        case status = "Status"
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("FreeTube")
        } detail: {
            Group {
                switch selectedTab {
                case .dashboard:
                    DashboardView(viewModel: dashboard)
                case .install:
                    InstallView(viewModel: InstallViewModel())
                case .genres:
                    GenresView(viewModel: GenresViewModel())
                case .nowPlaying:
                    NowPlayingView(viewModel: NowPlayingViewModel())
                case .settings:
                    SettingsView(viewModel: SettingsViewModel())
                case .status:
                    StatusView(viewModel: StatusViewModel())
                }
            }
            .navigationTitle(selectedTab.rawValue)
        }
        .frame(minWidth: 900, minHeight: 700)
        .onAppear {
            dashboard.checkSystemHealth()
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
        case .settings: return "gearshape.fill"
        case .status: return "checkmark.shield.fill"
        }
    }
}
