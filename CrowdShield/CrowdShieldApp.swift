import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct CrowdShieldApp: App {
    @StateObject private var crowdService = CrowdSimulationService()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var session = UserSession()
    @State private var didConfigureFirebase = false
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(crowdService)
                .environmentObject(locationManager)
                .environmentObject(session)
                .preferredColorScheme(.dark) // Safety-focused dark theme by default
                .onAppear {
                    if !didConfigureFirebase {
                        #if canImport(FirebaseCore)
                        FirebaseApp.configure()
                        didConfigureFirebase = true
                        #else
                        #if DEBUG
                        print("[CrowdShield] FirebaseCore not available. Skipping FirebaseApp.configure(). Add Firebase via SPM to enable.")
                        #endif
                        #endif
                    }
                }
                .onAppear {
                    crowdService.userSession = session
                    Task {
                        await session.restoreSession()
                    }
                }
                .onChange(of: session.isSignedIn) { _, isSignedIn in
                    if !isSignedIn {
                        crowdService.stopRealtimeUpdates()
                    }
                }
                .onChange(of: session.selectedVenue) { _, venue in
                    if venue != nil {
                        crowdService.startRealtimeUpdates()
                    } else {
                        crowdService.stopRealtimeUpdates()
                    }
                }
        }
    }
}

