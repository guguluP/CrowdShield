import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var locationError: String?
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        #if os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
        manager.requestWhenInUseAuthorization()
        #endif
    }
    
    func requestLocation() {
        manager.requestLocation()
    }
    
    func startUpdating() {
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.userLocation = location.coordinate
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.locationError = error.localizedDescription
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async {
            // Update published status using the manager's authorizationStatus when available
            if #available(iOS 14.0, tvOS 14.0, watchOS 7.0, macOS 11.0, visionOS 1.0, *) {
                self.authorizationStatus = manager.authorizationStatus
            } else {
                self.authorizationStatus = type(of: manager).authorizationStatus()
            }

            // Start updates based on platform-appropriate authorized states
            #if os(macOS)
            if self.authorizationStatus == .authorized {
                manager.startUpdatingLocation()
            }
            #else
            if self.authorizationStatus == .authorizedWhenInUse || self.authorizationStatus == .authorizedAlways {
                manager.startUpdatingLocation()
            }
            #endif
        }
    }
}
