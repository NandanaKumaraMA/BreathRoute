import MapKit
import Observation

enum NearbyCategory: String, CaseIterable, Identifiable {
    case parks = "Parks", cafes = "Cafés", culture = "Culture", essentials = "Essentials"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .parks: "tree.fill"; case .cafes: "cup.and.saucer.fill"; case .culture: "building.columns.fill"; case .essentials: "cross.case.fill" }
    }
    var query: String {
        switch self { case .parks: "parks"; case .cafes: "cafes"; case .culture: "museums libraries"; case .essentials: "pharmacies" }
    }
    var filters: [MKPointOfInterestCategory] {
        switch self {
        case .parks: [.park, .nationalPark]
        case .cafes: [.cafe]
        case .culture: [.museum, .library]
        case .essentials: [.pharmacy]
        }
    }
}

struct NearbyPlace: Identifiable {
    let id: String
    let item: MKMapItem
    let metres: Double
    let category: NearbyCategory
    var coordinate: CLLocationCoordinate2D { item.placemark.coordinate }
    var name: String { item.name ?? "Place" }
    var distanceLabel: String { metres < 1000 ? "\(Int(metres.rounded())) m" : String(format: "%.1f km", metres / 1000) }
}

@MainActor @Observable
final class NearbyDiscovery {
    private(set) var places: [NearbyPlace] = []
    private(set) var loading = false
    private(set) var message: String?
    private(set) var centre: CLLocationCoordinate2D?
    private(set) var scope = "Colombo map preview"
    private(set) var category: NearbyCategory = .parks
    private(set) var radius = 3000.0
    private(set) var updated: Date?
    var airByPlace: [String: AirReading] = [:]
    private var search: MKLocalSearch?
    private var generation = 0

    func cancel() { generation += 1; search?.cancel(); search = nil; loading = false }

    func load(around coordinate: CLLocationCoordinate2D, category: NearbyCategory, radius: Double, scope: String) async {
        generation += 1
        let ticket = generation
        search?.cancel()
        self.centre = coordinate; self.category = category; self.radius = radius; self.scope = scope
        places = []; message = nil; loading = true
        defer { if ticket == generation { loading = false; search = nil } }
        do {
            let request = MKLocalPointsOfInterestRequest(center: coordinate, radius: radius)
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: category.filters)
            let operation = MKLocalSearch(request: request); search = operation
            var items: [MKMapItem] = []
            do { items = matchingCategories(try await operation.start().mapItems, category: category, allowUncategorised: false) }
            catch { try Task.checkCancellation(); guard ticket == generation else { return } }
            try Task.checkCancellation()
            guard ticket == generation else { return }
            // Category indexing varies by region. Natural-language search is a fallback.
            if items.isEmpty {
                let fallback = MKLocalSearch.Request()
                fallback.naturalLanguageQuery = category.query
                fallback.resultTypes = .pointOfInterest
                fallback.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
                fallback.pointOfInterestFilter = MKPointOfInterestFilter(including: category.filters)
                let operation = MKLocalSearch(request: fallback); search = operation
                items = matchingCategories(try await operation.start().mapItems, category: category, allowUncategorised: true)
            }
            try Task.checkCancellation()
            guard ticket == generation else { return }
            let candidates = items.filter { !($0.name ?? "").isEmpty }
            var byID: [String: MKMapItem] = [:]
            for item in candidates { byID[Self.identifier(item)] = item }
            let ranked = NearbyRanking.rank(candidates.map {
                NearbyCandidate(id: Self.identifier($0), latitude: $0.placemark.coordinate.latitude, longitude: $0.placemark.coordinate.longitude)
            }, latitude: coordinate.latitude, longitude: coordinate.longitude, radius: radius)
            places = ranked.prefix(12).compactMap { match in
                byID[match.id].map { NearbyPlace(id: match.id, item: $0, metres: match.metres, category: category) }
            }
            updated = Date()
            if places.isEmpty { message = "No \(category.rawValue.lowercased()) returned within \(Int(radius / 1000)) km. Try a larger radius, another category or a different map area." }
        } catch {
            guard ticket == generation, !Task.isCancelled else { return }
            places = []; message = "Nearby search could not be completed. Check your connection and try again."
        }
    }

    private static func identifier(_ item: MKMapItem) -> String {
        "\((item.name ?? "").lowercased())|\(String(format: "%.6f", item.placemark.coordinate.latitude))|\(String(format: "%.6f", item.placemark.coordinate.longitude))"
    }
    private func matchingCategories(_ items: [MKMapItem], category: NearbyCategory, allowUncategorised: Bool) -> [MKMapItem] {
        items.filter { item in
            // Some regions omit categories. Exclude explicit mismatches even if the provider ignored its request filter.
            guard let actual = item.pointOfInterestCategory else { return allowUncategorised }
            return category.filters.contains(actual)
        }
    }
}
