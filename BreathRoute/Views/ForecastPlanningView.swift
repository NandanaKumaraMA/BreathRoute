import SwiftUI
import Charts

struct ForecastLauncher: View {
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: "clock.badge.checkmark").font(.title2).foregroundStyle(Palette.forest)
                    .frame(width: 46, height: 46).background(Palette.lime.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
                VStack(alignment: .leading, spacing: 5) {
                    Text("When to walk").font(.headline).foregroundStyle(Palette.ink)
                    Text(active ? "Departure planning is available after this walk." : "Hourly forecasts · compare departure times").font(.caption).foregroundStyle(Palette.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.forest)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line))
        }.buttonStyle(PressStyle()).disabled(active)
    }
}

struct ForecastEntryView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        if let route = model.selected, model.activeRoute == nil, model.pendingRecovery == nil, !model.unreadableRecovery {
            ForecastPlanningView(model: model, route: route.snapshot)
        } else {
            NavigationStack {
                Page {
                    PageHeader(title: "When to walk", subtitle: "Forecast planning", symbol: "clock.badge.checkmark")
                    Surface {
                        SectionHeading(title: model.pendingRecovery != nil || model.unreadableRecovery ? "Resolve your unfinished walk" : "Choose a path first")
                        Text("Departure forecasts compare the same route, duration and sample positions at different times. Find a walking path in Explore to begin.").font(.subheadline).foregroundStyle(Palette.muted)
                        PrimaryButton(title: "Open Explore", symbol: "map") { model.section = .routes; dismiss() }
                        if model.pendingRecovery == nil && !model.unreadableRecovery && model.activeRoute == nil {
                            Button("Preview with an example path") { model.loadDemo() }.font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                            InfoNote(symbol: "sparkles", text: "The example opens clearly labelled synthetic forecasts. No API or sensors are used until you explicitly load provider forecasts.")
                        }
                    }
                }.navigationTitle("When to walk").navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            }
        }
    }
}

struct ForecastPlanningView: View {
    @Bindable var model: AppModel
    let route: SavedRoute
    @State private var batch: ForecastBatch?
    @State private var usingExample = false
    @State private var loading = false
    @State private var notice: String?
    @State private var loadTask: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var startHours = 0
    @State private var customStart = Date().addingTimeInterval(3600)
    @State private var windowHours = 12
    @State private var selectedIndex = 0
    @State private var reminding = false
    @State private var reminderMessage: String?
    @AppStorage("departureReminderTime") private var reminderTime = 0.0
    @Environment(\.dismiss) private var dismiss
    private var points: [GeoCoordinate] { route.airSamples.map(\.coordinate) }
    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Page {
                    PageHeader(title: "A better time\nto walk.", subtitle: "Departure forecast", symbol: "clock.badge.checkmark")
                    routeCard
                    controls
                    if loading {
                        Surface {
                            HStack(spacing: 12) { ProgressView(); Text("Loading hourly forecasts…").font(.headline) }
                            Text("At most \(points.count) point requests. Changing the departure window reuses these results.").font(.caption).foregroundStyle(Palette.muted)
                            Button("Cancel forecast request") { cancelLoad() }.frame(minHeight: 44)
                        }
                    }
                    if let notice { InfoNote(symbol: "exclamationmark.circle", text: notice) }
                    if let batch {
                        let options = estimates(batch, now: context.date)
                        adviceCard(options)
                        forecastChart(options)
                        departureList(options, now: context.date)
                        dataCard(batch, now: context.date)
                    } else if !loading {
                        Surface {
                            SectionHeading(title: "Compare when to leave")
                            Text("Load the available hourly PM2.5 forecasts for this path, then compare departure times using the same route and breathing-volume assumption.").font(.subheadline).foregroundStyle(Palette.muted)
                            InfoNote(text: "Requests send the retained sample coordinates to OpenWeather. Your journal and phone activity are not sent.")
                        }
                    }
                    if reminderTime > context.date.timeIntervalSince1970 {
                        Surface {
                            SectionHeading(title: "Departure reminder")
                            Text(Date(timeIntervalSince1970: reminderTime).formatted(date: .abbreviated, time: .shortened)).font(.headline)
                            Text("A local reminder to review conditions. A changed forecast does not automatically reschedule it.").font(.caption).foregroundStyle(Palette.muted)
                            Button("Cancel departure reminder") { ReminderService().cancelDeparture(); reminderTime = 0 }.frame(minHeight: 44)
                        }
                    }
                    InfoNote(text: "Forecasts are modelled estimates, not measured future conditions or a guarantee that a time is safe. Recheck current routes and air before leaving. This planner does not start a walk or replace current samples.")
                    Link("OpenWeather forecast documentation", destination: URL(string: "https://openweathermap.org/api/air-pollution")!).font(.caption)
                }
            }
            .navigationTitle("When to walk").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { if route.demo && batch == nil { loadExample() } }
            .onChange(of: windowHours) { _, _ in selectedIndex = 0 }
            .onChange(of: startHours) { _, _ in selectedIndex = 0 }
            .onChange(of: customStart) { _, _ in selectedIndex = 0 }
            .onDisappear { cancelLoad() }
            .alert("Departure reminder", isPresented: Binding(get: { reminderMessage != nil }, set: { if !$0 { reminderMessage = nil } })) {
                Button("OK") { reminderMessage = nil }
            } message: { Text(reminderMessage ?? "") }
        }
    }
    private var routeCard: some View {
        Surface {
            SectionHeading(title: route.name.isEmpty ? "Selected walking path" : route.name, detail: route.demo ? "Illustrative path" : "Selected path")
            HStack { Metric(title: "Walking time", value: "\(Int(route.seconds / 60)) min"); Metric(title: "Distance", value: String(format: "%.2f km", route.metres / 1000)) }
            Text("\(points.count) retained sample points · \(Int(model.intensity.ventilation * 1000)) L/min assumed ventilation").font(.caption).foregroundStyle(Palette.muted)
            if route.demo { InfoNote(symbol: "sparkles", text: "The path and travel time are illustrative. Loading real provider forecasts here does not establish walking access for this example path.") }
        }
    }
    private var controls: some View {
        Surface {
            SectionHeading(title: "Your departure window")
            Picker("Start comparing", selection: $startHours) {
                Text("Now").tag(0); Text("In 24 hours").tag(24); Text("In 48 hours").tag(48); Text("In 72 hours").tag(72); Text("Choose date & time").tag(-1)
            }.font(.subheadline)
            if startHours == -1 {
                DatePicker("First departure", selection: $customStart, in: Date()...Date().addingTimeInterval(96 * 3600), displayedComponents: [.date, .hourAndMinute]).font(.subheadline)
                Text("Departures that have passed are removed from the comparison. Options beyond the returned forecast horizon remain unavailable.").font(.caption).foregroundStyle(Palette.muted)
            }
            Picker("Compare departures over", selection: $windowHours) {
                Text("6 hours").tag(6); Text("12 hours").tag(12); Text("24 hours").tag(24)
            }.font(.subheadline)
            Text("Times use your device’s time zone. Relative windows advance each minute; a chosen date stays fixed. Provider data keeps its own fetch timestamp.").font(.caption).foregroundStyle(Palette.muted)
            Button { loadLive(force: batch != nil && !usingExample) } label: {
                Label(batch != nil && !usingExample ? "Refresh OpenWeather forecasts" : (route.demo ? "Load live forecasts for this example path" : "Load OpenWeather forecasts"), systemImage: "cloud.sun")
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }.disabled(loading || points.isEmpty)
            if route.demo {
                Button(usingExample ? "Reset synthetic forecast example" : "Use synthetic forecast example") { cancelLoad(); loadExample() }
                    .font(.caption).frame(minHeight: 44).disabled(loading)
            }
        }
    }
    private func estimates(_ batch: ForecastBatch, now: Date) -> [DepartureEstimate] {
        let samples = zip(route.airSamples, batch.series).map { ForecastSample(timeFraction: $0.0.timeFraction, series: $0.1) }
        let start = startHours == -1 ? customStart : now.addingTimeInterval(Double(startHours) * 3600)
        return (0...windowHours).compactMap { hour in
            let departure = start.addingTimeInterval(Double(hour) * 3600)
            guard departure >= now else { return nil }
            return DepartureForecastCalculator.evaluate(id: hour, departure: departure,
                                                 seconds: route.seconds, ventilation: model.intensity.ventilation, samples: samples, now: now)
        }
    }
    private func adviceCard(_ options: [DepartureEstimate]) -> some View {
        let complete = options.filter { $0.estimate.isComplete }.count
        return Surface {
            HStack { StatusPill(title: usingExample ? "Synthetic forecast example" : "OpenWeather forecasts", symbol: usingExample ? "sparkles" : "cloud.sun"); Spacer() }
            switch DepartureForecastCalculator.advice(options) {
            case .insufficient:
                Text("More complete data is needed.").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("At least two fully covered departure options are needed for a comparison. Missing, expired and out-of-horizon intervals remain unknown.").font(.subheadline).foregroundStyle(Palette.muted)
            case .similar:
                Text("These departure times have similar estimates.").font(.title3.weight(.semibold)).foregroundStyle(Palette.ink)
                Text("The fully covered options differ by no more than the larger of 0.1 µg or 1%. No preferred time is claimed.").font(.subheadline).foregroundStyle(Palette.muted)
            case .lowest(let id):
                if let best = options.first(where: { $0.id == id }) {
                    Text(best.departure.formatted(date: .abbreviated, time: .shortened)).font(.title2.weight(.semibold)).foregroundStyle(Palette.forest)
                    Text("Lowest estimated dose among the \(complete) fully covered options shown.").font(.subheadline).foregroundStyle(Palette.muted)
                    if let baseline = options.first, baseline.estimate.isComplete, let first = baseline.estimate.observedDose, let dose = best.estimate.observedDose, first > dose {
                        Text(String(format: "%.1f µg lower than the first departure (%.0f%%).", first - dose, (first - dose) / first * 100)).font(.caption).foregroundStyle(Palette.forest)
                    }
                }
            }
            if complete < options.count { InfoNote(text: "\(options.count - complete) incomplete options are excluded from ranking. Their partial dose cannot be compared as if it were complete.") }
        }
    }
    private func forecastChart(_ options: [DepartureEstimate]) -> some View {
        Surface {
            SectionHeading(title: "Estimated dose by departure")
            Chart(options.filter { $0.estimate.observedDose != nil }) { option in
                BarMark(x: .value("Departure", option.departure), y: .value("Estimated dose (µg)", option.estimate.observedDose!))
                    .foregroundStyle(option.estimate.isComplete ? Palette.forest : Palette.muted.opacity(0.4))
                    .accessibilityLabel(option.departure.formatted(date: .abbreviated, time: .shortened))
                    .accessibilityValue("\(doseText(option.estimate.observedDose)), \(Int(option.estimate.coverage * 100))% forecast time coverage")
            }.chartXScale(range: .plotDimension(padding: 18))
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let date = value.as(Date.self) { Text(date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))).font(.caption2) } }
                } }
                .chartYAxisLabel("Estimated dose · µg").frame(height: 210)
            Text("Green: fully covered · grey: partial, excluded from ranking. No bar means unavailable, not zero. The list below provides the same values in text.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
    }
    private func departureList(_ options: [DepartureEstimate], now: Date) -> some View {
        Surface {
            SectionHeading(title: "Choose a departure", detail: "\(options.count) options")
            ForEach(options) { option in
                Button { selectedIndex = option.id } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: option.id == selectedIndex ? "checkmark.circle.fill" : "circle").foregroundStyle(Palette.forest)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(option.departure.formatted(date: .abbreviated, time: .shortened)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                            Text("\(doseText(option.estimate.observedDose)) · \(Int(option.estimate.coverage * 100))% time coverage\(option.estimate.isComplete ? "" : " · partial")").font(.caption).foregroundStyle(Palette.muted)
                            if let mean = option.meanPM25 { Text(String(format: "%.1f µg/m³ mean PM2.5 over covered time · arrive %@", mean, option.arrival.formatted(date: .omitted, time: .shortened))).font(.caption2).foregroundStyle(Palette.muted) }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(.vertical, 7)
                }.buttonStyle(.plain).accessibilityAddTraits(option.id == selectedIndex ? .isSelected : [])
                if option.id != options.last?.id { Divider() }
            }
            if let chosen = options.first(where: { $0.id == selectedIndex }) {
                Button { schedule(chosen.departure) } label: {
                    Label(reminding ? "Saving reminder…" : "Remind me at this departure", systemImage: "bell.badge")
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
                }.disabled(usingExample || reminding || chosen.departure.timeIntervalSince(now) < 60 || !chosen.estimate.isComplete)
                Text(usingExample ? "Synthetic forecasts cannot schedule reminders." : "Choose a fully covered future option. This schedules one local reminder; it does not monitor changing forecasts or start recording.")
                    .font(.caption).foregroundStyle(Palette.muted)
            } else if !options.isEmpty {
                Text("Select a future departure above to plan its reminder.").font(.caption).foregroundStyle(Palette.muted)
            }
        }
    }
    private func dataCard(_ batch: ForecastBatch, now: Date) -> some View {
        return Surface {
            SectionHeading(title: "Forecast data & assumptions")
            ForEach(Array(batch.series.enumerated()), id: \.offset) { index, item in
                if let series = item, let first = series.hours.first, let last = series.hours.last {
                    Text("Point \(index + 1) · \(first.date.formatted(date: .abbreviated, time: .shortened)) → \(last.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(Palette.muted)
                    Text("Fetched \(series.fetchedAt.formatted(date: .abbreviated, time: .shortened))\(series.isFresh(at: now) ? "" : " · expired, refresh to compare")").font(.caption2).foregroundStyle(Palette.muted)
                }
            }
            if let message = batch.notice { InfoNote(text: message) }
            InfoNote(text: "The same fixed route and travel time are used for every departure. A uniform walking speed assigns time to retained spatial samples. Between adjacent hourly forecasts, PM2.5 is linearly interpolated and integrated at anticipated arrival times. Gaps larger than one hour, invalid values and times outside the returned horizon are excluded. Forecasts expire here after 30 minutes; this is an app freshness policy.")
        }
    }
    private func loadLive(force: Bool) {
        cancelLoad(); let id = UUID(); requestID = id; loading = true; notice = nil
        if usingExample { batch = nil }; usingExample = false
        loadTask = Task { @MainActor in
            defer { if requestID == id { loading = false; loadTask = nil } }
            do {
                let result = try await model.forecasts.load(points, key: KeyStore.read("openweather"), force: force)
                try Task.checkCancellation(); guard requestID == id else { return }
                batch = result
            } catch is CancellationError { }
            catch { if requestID == id { notice = error.localizedDescription } }
        }
    }
    private func cancelLoad() { requestID = UUID(); loadTask?.cancel(); loadTask = nil; loading = false }
    private func loadExample() {
        let now = Date(), anchor = Date(timeIntervalSince1970: floor(now.timeIntervalSince1970 / 3600) * 3600 - 3600)
        batch = ForecastBatch(series: points.enumerated().map { index, coordinate in
            AirForecastSeries(coordinate: coordinate, fetchedAt: now, hours: (0...97).map { hour in
                ForecastHour(date: anchor.addingTimeInterval(Double(hour) * 3600), pm25: 8 + Double(index) * 2 + 12 * (1 + sin(Double(hour) / 24 * 2 * .pi)), aqi: nil)
            })
        }, notice: nil)
        usingExample = true; notice = nil
    }
    private func schedule(_ date: Date) {
        reminding = true
        Task { @MainActor in
            defer { reminding = false }
            do {
                if try await ReminderService().setDeparture(at: date) {
                    reminderTime = date.timeIntervalSince1970; reminderMessage = "Departure reminder saved on this device. Review current conditions before walking."
                } else { reminderMessage = "Notifications are unavailable. You can enable them in device Settings." }
            } catch { reminderMessage = "The departure reminder could not be saved. Choose a future time and try again." }
        }
    }
}
