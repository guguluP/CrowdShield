import SwiftUI

/// Command & Control's root navigation. Deliberately diverges by platform:
/// - Mac: NavigationSplitView sidebar, since a persistent sidebar with more
///   destinations is the idiomatic desktop pattern and Mac windows have the
///   horizontal room for it without cramming.
/// - iPhone/iPad: TabView, consistent with the rest of the app and with
///   platform convention for touch navigation.
///
/// Both platforms show the same five destinations; only the chrome differs.
struct CommandRootView: View {
    @Environment(\.crowdShieldPlatform) private var platform

    var body: some View {
        switch platform {
        case .mac:
            CommandSidebarLayout()
        case .pad, .phone:
            CommandTabLayout()
        }
    }
}

/// The set of top-level destinations Command & Control can navigate to.
/// Shared between the sidebar (Mac) and tab (iOS/iPad) layouts so adding a
/// destination only requires updating this enum plus its `destination`
/// view, not two separate navigation structures.
enum CommandDestination: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case alerts = "Alerts"
    case recommendations = "Actions"
    case liveMap = "Live Map"
    case digitalTwin = "Digital Twin"
    case account = "Account"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "shield.checkered"
        case .alerts: return "bell.badge.fill"
        case .recommendations: return "lightbulb.fill"
        case .liveMap: return "map.fill"
        case .digitalTwin: return "cube.transparent"
        case .account: return "person.crop.circle"
        }
    }

    @ViewBuilder
    var destination: some View {
        switch self {
        case .overview: CommandDashboardView()
        case .alerts: AlertsView()
        case .recommendations: RecommendationsView()
        case .liveMap: MapHeatView()
        case .digitalTwin: DigitalTwinView()
        case .account: CommandAccountView()
        }
    }
}

private struct CommandSidebarLayout: View {
    @State private var selection: CommandDestination? = .overview

    var body: some View {
        NavigationSplitView {
            List(CommandDestination.allCases, selection: $selection) { destination in
                Label(destination.rawValue, systemImage: destination.icon)
                    .tag(destination)
            }
            .navigationTitle("CrowdShield")
            .listStyle(.sidebar)
        } detail: {
            (selection ?? .overview).destination
        }
        .tint(CrowdShieldTheme.commandAccent)
    }
}

private struct CommandTabLayout: View {
    @State private var selectedTab: CommandDestination = .overview

    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(CommandDestination.allCases) { destination in
                destination.destination
                    .tabItem { Label(destination.rawValue, systemImage: destination.icon) }
                    .tag(destination)
            }
        }
        .tint(CrowdShieldTheme.commandAccent)
    }
}
