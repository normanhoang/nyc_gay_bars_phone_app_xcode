import CoreLocation

/// Foreground location, ported from RN lib/useDeviceCoords.ts. Requests
/// when-in-use permission on first use and publishes the device coordinate,
/// degrading gracefully to nil when denied or unavailable.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    /// True when the user has denied/restricted location, so callers can offer
    /// a path to Settings instead of silently dropping distances.
    @Published var denied = false

    private let manager = CLLocationManager()
    private var started = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    /// Ask for permission and a one-time fix. Safe to call repeatedly.
    func start() {
        guard !started else { return }
        started = true
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.requestLocation()
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if let loc = locations.last {
            coordinate = loc.coordinate
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Leave coordinate nil; callers use the location-free fallback.
    }
}
