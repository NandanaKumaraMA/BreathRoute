import MapKit
import Observation

/// Separate completers and request tickets prevent old queries replacing newer results.
@MainActor @Observable
final class PlaceSearchService: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [MKLocalSearchCompletion] = []
    private(set) var results: [MKMapItem] = []
    private(set) var suggesting = false
    private(set) var searching = false
    private(set) var message: String?
    private var completer: MKLocalSearchCompleter?
    private var operation: MKLocalSearch?
    private var generation = 0

    func prepareForQuery() {
        cancel(); suggestions = []; results = []; message = nil
    }
    func suggest(_ query: String, region: MKCoordinateRegion) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let completer = MKLocalSearchCompleter()
        completer.region = region; completer.resultTypes = [.address, .pointOfInterest]
        completer.delegate = self; self.completer = completer; suggesting = true
        completer.queryFragment = query
    }
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        guard completer === self.completer else { return }
        suggesting = false; suggestions = Array(completer.results.prefix(10))
        if suggestions.isEmpty { message = "No suggestions yet. Search the full name or add a city." }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        guard completer === self.completer else { return }
        suggesting = false; suggestions = []; message = "Suggestions are unavailable. You can still submit a search."
    }
    func find(query: String? = nil, completion: MKLocalSearchCompletion? = nil, region: MKCoordinateRegion) async -> [MKMapItem] {
        generation += 1; let ticket = generation
        operation?.cancel(); completer?.cancel(); completer = nil; suggesting = false
        searching = true; message = nil; results = []
        defer { if ticket == generation { searching = false; operation = nil } }
        let request = completion.map { MKLocalSearch.Request(completion: $0) } ?? MKLocalSearch.Request()
        if let query { request.naturalLanguageQuery = query }
        request.region = region
        let search = MKLocalSearch(request: request); operation = search
        do {
            let items = try await search.start().mapItems
            try Task.checkCancellation()
            guard ticket == generation else { return [] }
            results = items
            if items.isEmpty { message = "No matching places. Try another name or include the city." }
            return items
        } catch {
            guard ticket == generation, !Task.isCancelled else { return [] }
            message = "Search could not be completed. Check your connection and try again."
            return []
        }
    }
    func cancel() {
        generation += 1; operation?.cancel(); operation = nil
        completer?.cancel(); completer = nil; suggesting = false; searching = false
    }
}
