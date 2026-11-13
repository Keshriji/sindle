import Foundation
import CoreLocation

struct HourTemp: Identifiable { let id = UUID(); let hour: String; let temp: Int }

/// Weather from MET Norway (free; needs an identifying User-Agent and credit "Weather: MET Norway").
/// Location: uses macOS Location Services; if that is denied or slow, falls back to an approximate IP-based city.
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var now: Int?
    @Published var hours: [HourTemp] = []
    @Published var place: String?
    @Published var error: String?
    private let lm = CLLocationManager()
    private var coord: CLLocationCoordinate2D?
    private var retrying = false
    private var timer: Timer?

    func start() {
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer
        if lm.authorizationStatus == .notDetermined { lm.requestWhenInUseAuthorization() }
        lm.startUpdatingLocation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.ipFallback() }   // no GPS fix in 5 s? use IP
        timer = Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        if let c = coord { fetch(c) } else { ipFallback() }
    }

    // MARK: location
    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .denied || m.authorizationStatus == .restricted { ipFallback() }
    }
    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        m.stopUpdatingLocation()
        place = nil
        fetch(c)
    }
    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) { ipFallback() }

    private func ipFallback() {
        guard coord == nil, let url = URL(string: "https://ipwho.is/") else { return }
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data,
                  let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let lat = j["latitude"] as? Double, let lon = j["longitude"] as? Double else {
                DispatchQueue.main.async { self.failed("Couldn't find your location") }
                return
            }
            DispatchQueue.main.async {
                if self.coord == nil { self.place = j["city"] as? String; self.fetch(CLLocationCoordinate2D(latitude: lat, longitude: lon)) }
            }
        }.resume()
    }

    // MARK: forecast
    private func failed(_ msg: String) {
        error = msg
        guard !retrying else { return }
        retrying = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { self.retrying = false; self.refresh() }
    }

    private func fetch(_ c: CLLocationCoordinate2D) {
        coord = c
        let url = URL(string: String(format: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=%.2f&lon=%.2f", c.latitude, c.longitude))!
        var req = URLRequest(url: url)
        // MET Norway blocks requests without an identifying User-Agent. Use your own app name + site or email.
        req.setValue("Spindle/1.0 github.com/Keshriji/sindle", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            guard code == 200, let data, let r = try? JSONDecoder().decode(MET.self, from: data) else {
                DispatchQueue.main.async { self.failed(code == 0 ? "No internet connection" : "Weather service error \(code)") }
                return
            }
            let iso = ISO8601DateFormatter()
            let hourFmt = DateFormatter(); hourFmt.dateFormat = "HH"
            let rows = r.properties.timeseries.compactMap { ts -> (Date, Int)? in
                guard let d = iso.date(from: ts.time) else { return nil }
                return (d, Int(ts.data.instant.details.air_temperature.rounded()))
            }.filter { $0.0 > Date().addingTimeInterval(-3600) }
            DispatchQueue.main.async {
                self.error = nil
                self.now = rows.first?.1
                self.hours = rows.dropFirst().prefix(6).map { HourTemp(hour: hourFmt.string(from: $0.0), temp: $0.1) }
            }
        }.resume()
    }
}

struct MET: Decodable {
    let properties: P
    struct P: Decodable { let timeseries: [TS] }
    struct TS: Decodable { let time: String; let data: D }
    struct D: Decodable { let instant: I }
    struct I: Decodable { let details: Det }
    struct Det: Decodable { let air_temperature: Double }
}
