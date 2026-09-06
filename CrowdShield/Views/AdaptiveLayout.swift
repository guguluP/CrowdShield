import SwiftUI

/// Coarse platform/size classification used to make layout decisions in one
/// place rather than scattering `#if os(...)` and size-class checks across
/// every view. Deliberately simple — three cases cover every layout
/// decision this app actually needs to make (column count, sidebar vs
/// tabs, card density).
enum CrowdShieldPlatform {
    case phone
    case pad
    case mac

    @MainActor
    static func current(horizontalSizeClass: UserInterfaceSizeClass?) -> CrowdShieldPlatform {
#if targetEnvironment(macCatalyst) || os(macOS)
        return .mac
#else
        // On iOS/iPadOS, regular width means iPad (or a large iPhone in
        // landscape, which benefits from the same denser layout).
        return horizontalSizeClass == .regular ? .pad : .phone
#endif
    }
}

/// Environment key so any descendant view can read the current platform
/// classification without every call site needing to compute it via
/// @Environment(\.horizontalSizeClass) itself.
private struct CrowdShieldPlatformKey: EnvironmentKey {
    static let defaultValue: CrowdShieldPlatform = .phone
}

extension EnvironmentValues {
    var crowdShieldPlatform: CrowdShieldPlatform {
        get { self[CrowdShieldPlatformKey.self] }
        set { self[CrowdShieldPlatformKey.self] = newValue }
    }
}

/// Injects the resolved platform into the environment for the view
/// hierarchy below it. Apply once near the root (ContentView) rather than
/// per-screen.
struct CrowdShieldPlatformReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ViewBuilder var content: (CrowdShieldPlatform) -> Content

    var body: some View {
        let platform = CrowdShieldPlatform.current(horizontalSizeClass: horizontalSizeClass)
        content(platform)
            .environment(\.crowdShieldPlatform, platform)
    }
}

/// A responsive card grid: single column on iPhone, 2 columns on iPad,
/// `macColumns` (default 3) on Mac. Cards are expected to manage their own
/// height (this uses `.adaptive`-style fixed column counts rather than a
/// true masonry layout, which keeps card content simple and predictable).
struct AdaptiveCardGrid<Content: View>: View {
    @Environment(\.crowdShieldPlatform) private var platform
    var macColumns: Int = 3
    var spacing: CGFloat = 16
    @ViewBuilder var content: () -> Content

    private var columnCount: Int {
        switch platform {
        case .phone: return 1
        case .pad: return 2
        case .mac: return macColumns
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing, alignment: .top), count: columnCount)
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content()
        }
    }
}

/// Standard content padding that widens on larger platforms rather than
/// letting cards stretch edge-to-edge on a Mac window. Use in place of a
/// bare `.padding()` on screen-level containers.
extension View {
    func crowdShieldScreenPadding() -> some View {
        modifier(ScreenPaddingModifier())
    }
}

private struct ScreenPaddingModifier: ViewModifier {
    @Environment(\.crowdShieldPlatform) private var platform

    func body(content: Content) -> some View {
        switch platform {
        case .phone:
            content.padding(.horizontal, 16)
        case .pad:
            content.padding(.horizontal, 24)
        case .mac:
            content.padding(.horizontal, 32)
        }
    }
}
