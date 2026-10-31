import CoreLocation
import SwiftUI

// MARK: - Model (same names as NotchNook's WeatherStore / WeatherSnapshot)

enum WeatherCondition: String, Codable, CaseIterable {
    case clear, mostlyClear, partlyCloudy, cloudy, fog, drizzle, rain, heavyRain, freezingRain, snow, heavySnow, thunderstorm

    /// WMO weather interpretation code (Open-Meteo `weather_code`).
    init(wmo: Int) {
        switch wmo {
        case 0: self = .clear
        case 1: self = .mostlyClear
        case 2: self = .partlyCloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .freezingRain
        case 61, 63, 80, 81: self = .rain
        case 65, 82: self = .heavyRain
        case 71, 73, 77, 85: self = .snow
        case 75, 86: self = .heavySnow
        case 95, 96, 99: self = .thunderstorm
        default: self = .cloudy
        }
    }

    func symbol(isDay: Bool) -> String {
        switch self {
        case .clear: isDay ? "sun.max.fill" : "moon.stars.fill"
        case .mostlyClear: isDay ? "sun.min.fill" : "moon.fill"
        case .partlyCloudy: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case .cloudy: "cloud.fill"
        case .fog: "cloud.fog.fill"
        case .drizzle: "cloud.drizzle.fill"
        case .rain: "cloud.rain.fill"
        case .heavyRain: "cloud.heavyrain.fill"
        case .freezingRain: "cloud.sleet.fill"
        case .snow: "cloud.snow.fill"
        case .heavySnow: "snowflake"
        case .thunderstorm: "cloud.bolt.rain.fill"
        }
    }
}

enum WeatherLocationMode: String, Codable, CaseIterable { case auto, custom }

enum WeatherTemperatureUnit: String, Codable, CaseIterable {
    case automatic, celsius, fahrenheit
    func format(_ celsius: Double) -> String {
        let f = self == .fahrenheit || (self == .automatic && Locale.current.measurementSystem == .us)
        return "\(Int((f ? celsius * 9 / 5 + 32 : celsius).rounded()))°"
    }
}

struct WeatherWidgetSettings: Codable, Equatable {
    var locationMode: WeatherLocationMode = .auto
    var customPlace = ""
    var unit: WeatherTemperatureUnit = .automatic
    var refreshMinutes = 30
}

struct WeatherSnapshot: Codable, Equatable {
    struct Hour: Codable, Equatable {
        var date: Date
        var temperatureC: Double
        var condition: WeatherCondition
        var isDay: Bool
    }
    var placeName: String
    var isCurrentLocation: Bool
    var timeZoneID: String
    var fetchedAt: Date
    var temperatureC: Double
    var condition: WeatherCondition
    var isDay: Bool
    var highC: Double
    var lowC: Double
    var hours: [Hour]
    var sunrise: Date?
    var sunset: Date?

    func nextHours(_ n: Int, after now: Date = .now) -> [Hour] { Array(hours.filter { $0.date > now }.prefix(n)) }
}

private struct GeocodingResponse: Decodable {
    struct Result: Decodable { let name: String; let latitude: Double; let longitude: Double }
    let results: [Result]?
}

struct ForecastResponse: Decodable {
    struct Current: Decodable {
        let temperature: Double, weatherCode: Int, isDay: Int
        enum CodingKeys: String, CodingKey { case temperature = "temperature_2m", weatherCode = "weather_code", isDay = "is_day" }
    }
    struct Hourly: Decodable {
        let time: [String], temperature: [Double], weatherCode: [Int], isDay: [Int]
        enum CodingKeys: String, CodingKey { case time, temperature = "temperature_2m", weatherCode = "weather_code", isDay = "is_day" }
    }
    struct Daily: Decodable {
        let max: [Double], min: [Double], sunrise: [String], sunset: [String]
        enum CodingKeys: String, CodingKey { case max = "temperature_2m_max", min = "temperature_2m_min", sunrise, sunset }
    }
    let timezone: String
    let current: Current
    let hourly: Hourly
    let daily: Daily
}

extension WeatherSnapshot {
    init(_ r: ForecastResponse, place: String, isCurrentLocation: Bool, now: Date = .now) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: r.timezone) ?? .current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        let h = r.hourly
        let n = Swift.min(h.time.count, h.temperature.count, h.weatherCode.count, h.isDay.count)
        self.init(placeName: place, isCurrentLocation: isCurrentLocation, timeZoneID: r.timezone, fetchedAt: now,
                  temperatureC: r.current.temperature, condition: WeatherCondition(wmo: r.current.weatherCode), isDay: r.current.isDay == 1,
                  highC: r.daily.max.first ?? r.current.temperature, lowC: r.daily.min.first ?? r.current.temperature,
                  hours: (0..<n).compactMap { i in
                      f.date(from: h.time[i]).map { Hour(date: $0, temperatureC: h.temperature[i], condition: WeatherCondition(wmo: h.weatherCode[i]), isDay: h.isDay[i] == 1) }
                  },
                  sunrise: r.daily.sunrise.first.flatMap(f.date(from:)), sunset: r.daily.sunset.first.flatMap(f.date(from:)))
    }
}

// MARK: - Store (Open-Meteo, no key)

@MainActor @Observable
final class WeatherStore: NSObject, CLLocationManagerDelegate {
    static let shared = WeatherStore()
    static let settings = Setting("weatherWidgetSettings", default: WeatherWidgetSettings())

    private(set) var snapshot = DataFile.load("weather.json", as: WeatherSnapshot.self)
    private(set) var failed = false
    @ObservationIgnored private let manager = CLLocationManager()
    @ObservationIgnored private var started = false

    func start() {
        guard !started else { return }
        started = true
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        manager.delegate = self
        Task {
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(Double(max(5, Self.settings.value.refreshMinutes)) * 60))
            }
        }
    }

    private var locationAuthorized: Bool { [.authorizedAlways, .authorized].contains(manager.authorizationStatus) }

    /// CoreLocation when allowed, else the custom place, else Cupertino.
    func refresh() {
        if Self.settings.value.locationMode == .auto {
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization(); return }
            if locationAuthorized { manager.requestLocation(); return }   // delegate fetches
        }
        refreshByPlace()
    }

    private func refreshByPlace() {
        let place = Self.settings.value.customPlace.trimmingCharacters(in: .whitespaces)
        Task { await fetch(place: place.isEmpty ? "Cupertino" : place) }
    }

    private func fetch(place: String) async {
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: place), .init(name: "count", value: "1")]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let r = (try? JSONDecoder().decode(GeocodingResponse.self, from: data))?.results?.first
        else { failed = true; return }
        await fetch(latitude: r.latitude, longitude: r.longitude, name: r.name, isCurrentLocation: false)
    }

    private func fetch(latitude: Double, longitude: Double, name: String, isCurrentLocation: Bool) async {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(latitude)), .init(name: "longitude", value: String(longitude)),
            .init(name: "current", value: "temperature_2m,weather_code,is_day"),
            .init(name: "hourly", value: "temperature_2m,weather_code,is_day"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,sunrise,sunset"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "2"),
        ]
        guard let (data, _) = try? await URLSession.shared.data(from: c.url!),
              let r = try? JSONDecoder().decode(ForecastResponse.self, from: data)
        else { failed = true; return }
        let snap = WeatherSnapshot(r, place: name, isCurrentLocation: isCurrentLocation)
        snapshot = snap
        failed = false
        DataFile.save(snap, to: "weather.json")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        Task { @MainActor in await self.fetch(latitude: c.latitude, longitude: c.longitude, name: "My Location", isCurrentLocation: true) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.refreshByPlace() }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in if self.started && manager.authorizationStatus != .notDetermined { self.refresh() } }
    }

    static func selfTest() {
        let wmo: [Int: (WeatherCondition, String)] = [
            0: (.clear, "sun.max.fill"), 1: (.mostlyClear, "sun.min.fill"), 2: (.partlyCloudy, "cloud.sun.fill"), 3: (.cloudy, "cloud.fill"),
            45: (.fog, "cloud.fog.fill"), 48: (.fog, "cloud.fog.fill"), 53: (.drizzle, "cloud.drizzle.fill"), 56: (.freezingRain, "cloud.sleet.fill"),
            63: (.rain, "cloud.rain.fill"), 65: (.heavyRain, "cloud.heavyrain.fill"), 67: (.freezingRain, "cloud.sleet.fill"),
            73: (.snow, "cloud.snow.fill"), 75: (.heavySnow, "snowflake"), 81: (.rain, "cloud.rain.fill"), 82: (.heavyRain, "cloud.heavyrain.fill"),
            86: (.heavySnow, "snowflake"), 95: (.thunderstorm, "cloud.bolt.rain.fill"), 99: (.thunderstorm, "cloud.bolt.rain.fill"),
        ]
        for (code, (cond, symbol)) in wmo {
            precondition(WeatherCondition(wmo: code) == cond, "wmo \(code)")
            precondition(cond.symbol(isDay: true) == symbol, "symbol \(code)")
            precondition(NSImage(systemSymbolName: cond.symbol(isDay: false), accessibilityDescription: nil) != nil, "night symbol \(cond)")
            precondition(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "symbol \(symbol)")
        }
        precondition(WeatherCondition.clear.symbol(isDay: false) == "moon.stars.fill")
        precondition(WeatherTemperatureUnit.celsius.format(18.4) == "18°")
        precondition(WeatherTemperatureUnit.fahrenheit.format(0) == "32°")
        precondition(WeatherTemperatureUnit.fahrenheit.format(18.4) == "65°")

        let json = """
        {"timezone":"America/Los_Angeles","current":{"time":"2026-10-31T10:15","interval":900,"temperature_2m":18.4,"weather_code":2,"is_day":1},
         "hourly":{"time":["2026-10-31T10:00","2026-10-31T11:00","2026-10-31T12:00","2026-10-31T13:00","2026-10-31T14:00","2026-10-31T15:00"],
                   "temperature_2m":[18,19,20,21,20,19],"weather_code":[0,1,3,61,95,71],"is_day":[1,1,1,1,1,0]},
         "daily":{"time":["2026-10-31","2026-11-01"],"temperature_2m_max":[22.1,20],"temperature_2m_min":[11.3,10],
                  "sunrise":["2026-10-31T07:27","2026-11-01T06:28"],"sunset":["2026-10-31T18:07","2026-11-01T17:06"]}}
        """
        let r = try! JSONDecoder().decode(ForecastResponse.self, from: Data(json.utf8))
        let now = ISO8601DateFormatter().date(from: "2026-10-31T17:30:00Z")!     // 10:30 in Los Angeles (PDT)
        let s = WeatherSnapshot(r, place: "Cupertino", isCurrentLocation: false, now: now)
        precondition(s.condition == .partlyCloudy && s.isDay && s.highC == 22.1 && s.lowC == 11.3 && s.hours.count == 6)
        precondition(s.nextHours(4, after: now).map(\.condition) == [.mostlyClear, .cloudy, .rain, .thunderstorm])
        precondition(s.sunset == ISO8601DateFormatter().date(from: "2026-11-01T01:07:00Z"))
    }
}

// MARK: - Nook widget (3 units)

struct WeatherWidget: View {
    var body: some View {
        let store = WeatherStore.shared
        let unit = WeatherStore.settings.value.unit
        WidgetCard {
            if let w = store.snapshot {
                let hourFormat = Self.hourFormat(w.timeZoneID)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 3) {
                        if w.isCurrentLocation { Image(systemName: "location.fill").font(.system(size: 8, weight: .bold)) }
                        Text(w.placeName).lineLimit(1)
                    }
                    .font(Theme.caption.weight(.semibold)).foregroundStyle(Theme.secondaryText)
                    HStack(spacing: 2) {
                        Text(unit.format(w.temperatureC)).font(.system(size: 30, weight: .semibold, design: .rounded)).minimumScaleFactor(0.6).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: w.condition.symbol(isDay: w.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 20))
                    }
                    Text("H:\(unit.format(w.highC))  L:\(unit.format(w.lowC))").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.secondaryText)
                    Spacer(minLength: 0)
                    HStack(spacing: 0) {
                        ForEach(w.nextHours(4), id: \.date) { h in
                            VStack(spacing: 3) {
                                Text(h.date.formatted(hourFormat)).font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tertiaryText)
                                Image(systemName: h.condition.symbol(isDay: h.isDay)).symbolRenderingMode(.multicolor).font(.system(size: 11)).frame(height: 13)
                                Text(unit.format(h.temperatureC)).font(.system(size: 10, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                EmptyState(symbol: store.failed ? "wifi.slash" : "cloud.sun", title: store.failed ? "No weather" : "Loading…")
            }
        }
    }

    private static func hourFormat(_ zone: String) -> Date.FormatStyle {
        var f = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .narrow))
        f.timeZone = TimeZone(identifier: zone) ?? .current
        return f
    }
}
