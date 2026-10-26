import Foundation
import Observation
import HealthKit

struct HealthDailyActivity {
    let start: Date
    let end: Date
    let steps: Double?
    let walkingRunningMetres: Double?
}
struct HealthVitalRecord: Sendable {
    let value: Double
    let date: Date
    let source: String
    let manuallyEntered: Bool
}

@MainActor @Observable
final class HealthService {
    private let store = HKHealthStore()
    private(set) var dailyActivity: HealthDailyActivity?
    private(set) var activityMessage = "Read today's available steps and walking/running distance. An Apple Watch is optional."
    private(set) var summary = "Optional stored records. No readings imported."
    private(set) var heartRecord: HealthVitalRecord?
    private(set) var respiratoryRecord: HealthVitalRecord?
    private(set) var vitalsCheckedAt: Date?
    private(set) var isReadingActivity = false
    private(set) var isReadingVitals = false
    private var accountGeneration = 0
    func resetForAccountChange() {
        accountGeneration += 1
        dailyActivity = nil; heartRecord = nil; respiratoryRecord = nil; vitalsCheckedAt = nil
        isReadingActivity = false; isReadingVitals = false
        activityMessage = "Read today's available steps and walking/running distance. An Apple Watch is optional."
        summary = "Optional stored records. No readings imported."
    }

    func readToday() async {
        guard !isReadingActivity, !isReadingVitals else { return }
        dailyActivity = nil
        guard HKHealthStore.isHealthDataAvailable(),
              let steps = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let distance = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) else {
            activityMessage = "Apple Health is unavailable here. Your walk and journal remain usable."; return
        }
        let generation = accountGeneration
        isReadingActivity = true; defer { if accountGeneration == generation { isReadingActivity = false } }
        do {
            try await store.requestAuthorization(toShare: [], read: [steps, distance])
            guard accountGeneration == generation else { return }
            let end = Date(), start = Calendar.current.startOfDay(for: end)
            async let stepTotal = total(steps, unit: .count(), start: start, end: end)
            async let distanceTotal = total(distance, unit: .meter(), start: start, end: end)
            let values = try await (stepTotal, distanceTotal)
            guard accountGeneration == generation else { return }
            dailyActivity = HealthDailyActivity(start: start, end: end, steps: values.0, walkingRunningMetres: values.1)
            activityMessage = values.0 == nil && values.1 == nil
                ? "No readable activity samples for today. The data may be missing or access may not have been granted."
                : "Apple Health totals across readable sources. They can differ from this app's recorded walks."
        } catch { if accountGeneration == generation { activityMessage = "Activity could not be read. Check Health access and try again." } }
    }
    func readRecentVitals() async {
        guard !isReadingActivity, !isReadingVitals else { return }
        heartRecord = nil; respiratoryRecord = nil; vitalsCheckedAt = nil
        guard HKHealthStore.isHealthDataAvailable(),
              let heart = HKQuantityType.quantityType(forIdentifier: .heartRate),
              let respiration = HKQuantityType.quantityType(forIdentifier: .respiratoryRate) else {
            summary = "Apple Health is unavailable on this device."; return
        }
        let generation = accountGeneration
        isReadingVitals = true; defer { if accountGeneration == generation { isReadingVitals = false } }
        do {
            try await store.requestAuthorization(toShare: [], read: [heart, respiration])
            guard accountGeneration == generation else { return }
            async let heartValue = latest(heart)
            async let respirationValue = latest(respiration)
            let records = try await (heartValue, respirationValue)
            guard accountGeneration == generation else { return }
            vitalsCheckedAt = Date()
            heartRecord = records.0; respiratoryRecord = records.1
            summary = heartRecord == nil && respiratoryRecord == nil
                ? "No recent readable records. A compatible data source is needed; this app does not measure heart or breathing rate."
                : "Records from the hour before your last check, with their source and recording time. This is a snapshot, not a live monitor."
        } catch { if accountGeneration == generation { summary = "Health records could not be read. Check Health access and try again." } }
    }
    private func total(_ type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> Double? {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                // Use HealthKit's aggregate instead of summing samples from overlapping devices ourselves.
                let value = statistics?.sumQuantity()?.doubleValue(for: unit)
                continuation.resume(returning: value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil })
            }
            store.execute(query)
        }
    }
    private func latest(_ type: HKQuantityType) async throws -> HealthVitalRecord? {
        try await withCheckedThrowingContinuation { continuation in
            let now = Date(), predicate = HKQuery.predicateForSamples(withStart: Date().addingTimeInterval(-3600), end: Date(), options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error); return }
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                let value = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                guard value.isFinite, value > 0, sample.endDate <= now else { continuation.resume(returning: nil); return }
                continuation.resume(returning: HealthVitalRecord(value: value, date: sample.endDate,
                    source: sample.sourceRevision.source.name, manuallyEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool == true))
            }
            store.execute(query)
        }
    }
}
