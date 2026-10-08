import SwiftUI
import MapKit

struct NearbyPlacesView: View {
    @Bindable var discovery: NearbyDiscovery
    @Binding var category: NearbyCategory
    @Binding var radius: Double
    let useLocation: () -> Void
    let refresh: () -> Void
    let select: (NearbyPlace) -> Void
    @State private var showAll = false
    @State private var pendingPlace: NearbyPlace?
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow(text: "A reason to step outside")
                    Text("Places to explore.").font(.system(.title2, design: .serif)).foregroundStyle(Palette.ink)
                    Text(discovery.scope).font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer()
                Menu {
                    Picker("Search radius", selection: $radius) {
                        Text("1 km").tag(1000.0); Text("3 km").tag(3000.0); Text("5 km").tag(5000.0)
                    }
                    Button("Use my current location", systemImage: "location", action: useLocation)
                    Button("Refresh places", systemImage: "arrow.clockwise", action: refresh)
                } label: {
                    Label("\(Int(radius / 1000)) km", systemImage: "slider.horizontal.3").font(.caption.weight(.semibold)).padding(12).background(Palette.surface, in: Capsule())
                }.accessibilityLabel("Nearby search options, radius \(Int(radius / 1000)) kilometres")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 9) {
                    ForEach(NearbyCategory.allCases) { option in
                        Button { category = option } label: {
                            Label(option.rawValue, systemImage: option.symbol).font(.caption.weight(.semibold)).padding(.horizontal, 14).padding(.vertical, 12)
                                .foregroundStyle(category == option ? Palette.lime : Palette.forest)
                                .background(category == option ? Palette.deep : Palette.surface, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(category == option ? .isSelected : [])
                    }
                }
            }.scrollIndicators(.hidden)
            if discovery.loading {
                HStack(spacing: 12) { ProgressView().tint(Palette.forest); Text("Finding \(category.rawValue.lowercased()) around this area…").font(.subheadline).foregroundStyle(Palette.muted) }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            } else if let message = discovery.message {
                Surface {
                    Label("Try another search", systemImage: "magnifyingglass").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Text(message).font(.caption).foregroundStyle(Palette.muted)
                    Button("Try again", action: refresh).font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            } else if !discovery.places.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 12) {
                        ForEach(Array(discovery.places.prefix(6).enumerated()), id: \.element.id) { index, place in
                            Button { select(place) } label: {
                                VStack(alignment: .leading, spacing: 13) {
                                    HStack {
                                        Image(systemName: place.category.symbol).font(.title2).foregroundStyle(Palette.forest)
                                        Spacer()
                                        Text(String(format: "%02d", index + 1)).font(.system(.caption, design: .monospaced)).foregroundStyle(Palette.muted)
                                    }.padding(16).frame(maxWidth: .infinity).background(Palette.forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))
                                    Text(place.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(typeSize.isAccessibilitySize ? nil : 2).frame(minHeight: 36, alignment: .topLeading)
                                    HStack { Text(place.distanceLabel).font(.caption.weight(.semibold)); Text("away").font(.caption); Spacer(); Image(systemName: "arrow.up.right").font(.caption) }.foregroundStyle(Palette.forest)
                                    if let reading = discovery.airByPlace[place.id] {
                                        Label("PM2.5 \(String(format: "%.1f", reading.pm25)) · \(reading.isFresh ? "recent" : "stale")", systemImage: "wind").font(.caption2).foregroundStyle(Palette.muted)
                                    }
                                }.padding(14).frame(width: typeSize.isAccessibilitySize ? 275 : 210, alignment: .leading)
                                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22)).overlay(RoundedRectangle(cornerRadius: 22).stroke(Palette.line, lineWidth: 0.7))
                            }.buttonStyle(PressStyle()).accessibilityLabel("\(place.name), \(place.distanceLabel) straight-line distance from search centre. Show place details")
                        }
                    }.padding(.bottom, 3)
                }.scrollIndicators(.hidden)
                HStack {
                    Text("Closest matches · straight-line distance").font(.caption2).foregroundStyle(Palette.muted)
                    Spacer()
                    Button("See all \(discovery.places.count)") { showAll = true }.font(.caption.weight(.semibold)).frame(minHeight: 44)
                }
            }
            Text("Zoom in to reveal nearby pins that overlap. All returned matches appear in the list.").font(.caption2).foregroundStyle(Palette.muted)
            if discovery.scope != "Near your current location" {
                Button(action: useLocation) { Label("Find places near me", systemImage: "location.fill").font(.subheadline.weight(.semibold)) }.frame(minHeight: 44)
            }
            Text("Place information: Apple Maps. Nearby does not establish walking access, opening hours or lower pollution.").font(.caption2).foregroundStyle(Palette.muted)
        }
        .sheet(isPresented: $showAll, onDismiss: {
            if let pendingPlace { self.pendingPlace = nil; select(pendingPlace) }
        }) {
            NavigationStack {
                List(discovery.places) { place in
                    Button { pendingPlace = place; showAll = false } label: {
                        HStack(spacing: 14) {
                            Image(systemName: place.category.symbol).foregroundStyle(Palette.forest).frame(width: 30)
                            VStack(alignment: .leading, spacing: 6) { Text(place.name).font(.headline); Text(place.item.placemark.title ?? "").font(.caption).foregroundStyle(.secondary) }
                            Spacer(); Text(place.distanceLabel).font(.caption.weight(.semibold))
                        }.padding(.vertical, 6)
                    }
                }.navigationTitle(category.rawValue).navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .bottom) { Text("Distances from the search centre, not walking-route distances.").font(.caption).padding().frame(maxWidth: .infinity).background(.regularMaterial) }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { showAll = false } } }
            }
        }
    }
}

struct NearbyPlaceDetail: View {
    let place: NearbyPlace
    @Bindable var discovery: NearbyDiscovery
    let choose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var checking = false
    @State private var error: String?
    @State private var airTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Page {
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: place.category.symbol).font(.title).foregroundStyle(Palette.forest).padding(18).background(Palette.forest.opacity(0.08), in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 9) {
                        Eyebrow(text: place.category.rawValue)
                        Text(place.name).font(.system(.title2, design: .serif)).foregroundStyle(Palette.ink)
                        Text("\(place.distanceLabel) straight-line distance").font(.caption).foregroundStyle(Palette.muted)
                    }
                }
                Surface {
                    Label(place.item.placemark.title ?? place.name, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Palette.ink)
                    if let phone = place.item.phoneNumber { Label(phone, systemImage: "phone").font(.caption).foregroundStyle(Palette.muted) }
                    if let url = place.item.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link(destination: url) { Label("Place website", systemImage: "arrow.up.right.square").font(.subheadline) } }
                    Text("Listed by Apple Maps. Verify access and opening times before visiting.").font(.caption2).foregroundStyle(Palette.muted)
                }
                Surface {
                    SectionHeading(title: "Air at this place", detail: "OpenWeather")
                    if let reading = discovery.airByPlace[place.id] {
                        HStack { Metric(title: "PM2.5 · µg/m³", value: String(format: "%.1f", reading.pm25)); Metric(title: "Overall AQI · 1–5", value: "\(reading.aqi) · \(reading.label)") }
                        Text("Provider sample \(reading.date.formatted(date: .abbreviated, time: .shortened)) · \(reading.isFresh ? "recent" : "stale")").font(.caption).foregroundStyle(Palette.muted)
                        InfoNote(text: "Modelled point reading. The map’s 250 m sample circle is an illustrative display area, not a measured pollution boundary.")
                    } else { Text("Check a modelled reading at the place’s coordinates. Nearby places may share the same values.").font(.caption).foregroundStyle(Palette.muted) }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button(action: checkAir) {
                        HStack { if checking { ProgressView() }; Label(checking ? "Checking air…" : "Check air quality here", systemImage: "wind") }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                    }.disabled(checking)
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryButton(title: "Use as my destination", symbol: "flag.fill") { choose(); dismiss() }.padding(20).background(.regularMaterial)
            }
            .navigationTitle("Place details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.large])
        .onDisappear { airTask?.cancel() }
    }
    private func checkAir() {
        checking = true; error = nil
        airTask = Task {
            defer { checking = false }
            do {
                let reading = try await AirService().fetch(at: place.coordinate, key: KeyStore.read("openweather"))
                try Task.checkCancellation()
                discovery.airByPlace[place.id] = reading
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
}

enum AirMapStyle {
    static func colour(_ reading: AirReading?) -> Color {
        guard let reading, reading.isFresh else { return .gray }
        return switch reading.aqi { case 1, 2: Palette.forest; case 3: Color(hex: 0xB88320); default: Color(hex: 0xB34C46) }
    }
}
