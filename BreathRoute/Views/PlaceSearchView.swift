import SwiftUI
import MapKit

struct PlaceSearch: View {
    let title: String
    let region: MKCoordinateRegion
    var nearby: [NearbyPlace] = []
    let select: (MKMapItem) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var service = PlaceSearchService()
    @State private var searchTask: Task<Void, Never>?
    @State private var submittedQuery: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            List {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Section("Explore this area") {
                        ForEach(NearbyCategory.allCases) { category in
                            Button { query = category.query; submit() } label: {
                                Label(category.rawValue, systemImage: category.symbol).foregroundStyle(Palette.forest).padding(.vertical, 5)
                            }
                        }
                    }
                    if !nearby.isEmpty {
                        Section("Nearby matches") {
                            ForEach(nearby.prefix(5)) { place in
                                Button { choose(place.item) } label: {
                                    resultRow(place.item, detail: "\(place.distanceLabel) straight-line distance")
                                }
                            }
                        }
                    }
                } else {
                    Section {
                        Button(action: submit) { Label("Search for “\(query)”", systemImage: "magnifyingglass").font(.subheadline).padding(.vertical, 5) }
                            .disabled(service.searching)
                        if service.searching || service.suggesting { ProgressView(service.searching ? "Finding places…" : "Finding suggestions…") }
                        if let message = service.message { Text(message).font(.caption).foregroundStyle(.secondary) }
                    }
                    if !service.results.isEmpty {
                        Section("Places") {
                            ForEach(Array(service.results.enumerated()), id: \.offset) { _, place in
                                Button { choose(place) } label: { resultRow(place) }
                            }
                        }
                    } else if !service.suggestions.isEmpty && !service.searching {
                        Section("Suggested searches") {
                            ForEach(Array(service.suggestions.enumerated()), id: \.offset) { _, suggestion in
                                Button { resolve(suggestion) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "mappin.and.ellipse").foregroundStyle(Palette.forest).frame(width: 25)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(suggestion.title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                                            if !suggestion.subtitle.isEmpty { Text(suggestion.subtitle).font(.caption).foregroundStyle(.secondary) }
                                        }
                                        Spacer(minLength: 0); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
                                    }.padding(.vertical, 7)
                                }
                            }
                        }
                    }
                }
                Section { Text("Suggestions and place information: Apple Maps. Results are biased toward the map area.").font(.caption2).foregroundStyle(.secondary) }
            }
            .scrollContentBackground(.hidden).background(Palette.canvas)
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Palette.forest)
                    TextField("Place, street or city", text: $query).focused($focused).submitLabel(.search).autocorrectionDisabled().onSubmit(submit)
                    if !query.isEmpty {
                        Button { query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary).frame(width: 32, height: 44) }.accessibilityLabel("Clear search")
                    }
                }.padding(.horizontal, 16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 16)).padding(.horizontal, 20).padding(.vertical, 10).background(Palette.canvas)
            }
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: query) { _, newQuery in if submittedQuery != newQuery { submittedQuery = nil } }
            .task(id: query) {
                if submittedQuery == query { return }
                service.prepareForQuery()
                guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                do { try await Task.sleep(for: .milliseconds(250)); try Task.checkCancellation() }
                catch { return }
                service.suggest(query, region: region)
            }
            .onDisappear { searchTask?.cancel(); service.cancel() }
        }
    }
    private func resultRow(_ place: MKMapItem, detail: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin.circle.fill").foregroundStyle(Palette.forest).frame(width: 25)
            VStack(alignment: .leading, spacing: 6) {
                Text(place.name ?? "Place").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                Text(detail ?? place.placemark.title ?? "").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
        }.padding(.vertical, 7)
    }
    private func choose(_ place: MKMapItem) { select(place); dismiss() }
    private func submit() {
        let submitted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !submitted.isEmpty else { return }
        submittedQuery = query; focused = false; searchTask?.cancel()
        searchTask = Task { _ = await service.find(query: submitted, region: region) }
    }
    private func resolve(_ completion: MKLocalSearchCompletion) {
        focused = false; searchTask?.cancel()
        searchTask = Task {
            let items = await service.find(completion: completion, region: region)
            guard !Task.isCancelled else { return }
            if items.count == 1, let place = items.first { choose(place) }
        }
    }
}
