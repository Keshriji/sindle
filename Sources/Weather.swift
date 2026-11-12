import Foundation
import CoreLocation

struct HourTemp: Identifiable { let id = UUID(); let hour: String; let temp: Int }

/// Weather from MET Norway (free; requires a descriptive User-Agent and credit "Weather: MET Norway").
final class WeatherStore: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var now: Int?
    @Published var hours: [HourTemp] = []
    private let lm = CLLocationManager()

    func start() {
        lm.delegate = self
        lm.desiredAccuracy = kCLLocationAccuracyKilometer   // approximate is enough
        lm.requestWhenInUseAuthorization()
        lm.startUpdatingLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations l: [CLLocation]) {
        guard let c = l.last?.coordinate else { return }
        m.stopUpdatingLocation()
        fetch(c)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1800) { m.startUpdatingLocation() }
    }
    func locationManager(_ m: CLLocationManager, didFailWithError e: Error) {}

    private func fetch(_ c: CLLocationCoordinate2D) {
        let url = URL(string: String(format: "https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=%.2f&lon=%.2f", c.latitude, c.longitude))!
        var req = URLRequest(url: url)
        req.setValue("Spindle/1.0 (replace-with-your-email@example.com)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, _ in
            guard let data, let r = try? JSONDecoder().decode(MET.self, from: data) else { return }
            let iso = ISO8601DateFormatter()
            let hourFmt = DateFormatter(); hourFmt.dateFormat = "HH"
            let rows = r.properties.timeseries.compactMap { ts -> (Date, Int)? in
                guard let d = iso.date(from: ts.time) else { return nil }
                return (d, Int(ts.data.instant.details.air_temperature.rounded()))
            }.filter { $0.0 > Date().addingTimeInterval(-3600) }
            DispatchQueue.main.async {
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
