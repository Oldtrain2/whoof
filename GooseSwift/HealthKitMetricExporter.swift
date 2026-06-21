import Foundation
import HealthKit

/// Broadcasts WHOOP-derived metrics into Apple Health so the Health app stays up
/// to date, and writes body-mass edits back. Real-data-only: callers pass values
/// they already computed from the band; nothing is synthesized here. Daily
/// rollups use a stable per-day sync identifier so re-broadcasting updates the
/// existing Apple Health sample instead of creating duplicates.
final class HealthKitMetricExporter {
  static let shared = HealthKitMetricExporter()

  private let store = HKHealthStore()
  private var lastLiveHeartRateBroadcastAt: Date?
  private static let liveHeartRateMinInterval: TimeInterval = 10

  private init() {}

  static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  private static let bpmUnit = HKUnit.count().unitDivided(by: .minute())

  private static func quantityType(_ id: HKQuantityTypeIdentifier) -> HKQuantityType? {
    HKObjectType.quantityType(forIdentifier: id)
  }

  static var shareIdentifiers: [HKQuantityTypeIdentifier] {
    [
      .heartRate,
      .heartRateVariabilitySDNN,
      .restingHeartRate,
      .respiratoryRate,
      .stepCount,
      .activeEnergyBurned,
      .bodyMass,
    ]
  }

  static var shareTypes: Set<HKSampleType> {
    var types = Set<HKSampleType>()
    for id in shareIdentifiers {
      if let type = quantityType(id) {
        types.insert(type)
      }
    }
    return types
  }

  /// Request permission to write the broadcast types (and read body mass for the
  /// weight sync). Returns a short status string for surfacing in settings.
  @discardableResult
  func requestWriteAccess() async -> String {
    guard Self.isAvailable else {
      return "Unavailable on this device"
    }
    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        store.requestAuthorization(toShare: Self.shareTypes, read: HealthKitProfileImporter.readTypes) { success, error in
          if let error {
            continuation.resume(throwing: error)
          } else if success {
            continuation.resume()
          } else {
            continuation.resume(throwing: HealthKitProfileImporterError.authorizationDenied)
          }
        }
      }
      return "Broadcast authorized"
    } catch {
      return "Failed: \(error.localizedDescription)"
    }
  }

  private func canWrite(_ id: HKQuantityTypeIdentifier) -> Bool {
    guard let type = Self.quantityType(id) else {
      return false
    }
    return store.authorizationStatus(for: type) == .sharingAuthorized
  }

  /// Save one quantity sample. No-ops on a non-finite/non-positive value or when
  /// sharing is not authorized for the type, so nothing fake is ever written.
  func writeSample(
    _ id: HKQuantityTypeIdentifier,
    unit: HKUnit,
    value: Double,
    start: Date,
    end: Date,
    syncIdentifier: String? = nil
  ) async {
    guard Self.isAvailable, value.isFinite, value > 0,
          let type = Self.quantityType(id), canWrite(id) else {
      return
    }
    var metadata: [String: Any] = [HKMetadataKeyWasUserEntered: false]
    if let syncIdentifier {
      metadata[HKMetadataKeySyncIdentifier] = syncIdentifier
      metadata[HKMetadataKeySyncVersion] = Int(end.timeIntervalSince1970)
    }
    let quantity = HKQuantity(unit: unit, doubleValue: value)
    let sample = HKQuantitySample(type: type, quantity: quantity, start: start, end: end, metadata: metadata)
    do {
      try await store.save(sample)
    } catch {
      // Best-effort broadcast; surfacing per-sample failures would be noise.
    }
  }

  /// Continuously mirror the live band heart rate into Apple Health, throttled so
  /// streaming (~1 Hz) does not flood the store.
  func broadcastLiveHeartRate(bpm: Int, at date: Date) {
    guard Self.isAvailable, (20...240).contains(bpm) else {
      return
    }
    if let last = lastLiveHeartRateBroadcastAt, date.timeIntervalSince(last) < Self.liveHeartRateMinInterval {
      return
    }
    lastLiveHeartRateBroadcastAt = date
    Task { [bpm, date] in
      await writeSample(.heartRate, unit: Self.bpmUnit, value: Double(bpm), start: date, end: date)
    }
  }

  func broadcastBodyMass(grams: Int, at date: Date = Date()) async {
    await writeSample(
      .bodyMass,
      unit: .gramUnit(with: .kilo),
      value: Double(grams) / 1000.0,
      start: date,
      end: date,
      syncIdentifier: "whoof.bodymass.user"
    )
  }

  /// A day's vitals rollup. nil fields are skipped (real-data-only).
  struct DailyMetrics {
    let date: Date
    var restingHeartRateBPM: Double?
    var hrvSDNNms: Double?
    var respiratoryRateRPM: Double?
    var meanHeartRateBPM: Double?
    var steps: Double?
    var activeEnergyKcal: Double?
  }

  func broadcastDailyMetrics(_ metrics: DailyMetrics) async {
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: metrics.date)
    let stamp = metrics.date
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.dateFormat = "yyyy-MM-dd"
    let dayKey = formatter.string(from: dayStart)

    if let value = metrics.restingHeartRateBPM {
      await writeSample(.restingHeartRate, unit: Self.bpmUnit, value: value, start: stamp, end: stamp, syncIdentifier: "whoof.rhr.\(dayKey)")
    }
    if let value = metrics.hrvSDNNms {
      await writeSample(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), value: value, start: stamp, end: stamp, syncIdentifier: "whoof.hrv.\(dayKey)")
    }
    if let value = metrics.respiratoryRateRPM {
      await writeSample(.respiratoryRate, unit: Self.bpmUnit, value: value, start: stamp, end: stamp, syncIdentifier: "whoof.rr.\(dayKey)")
    }
    if let value = metrics.meanHeartRateBPM {
      await writeSample(.heartRate, unit: Self.bpmUnit, value: value, start: stamp, end: stamp, syncIdentifier: "whoof.meanhr.\(dayKey)")
    }
    if let value = metrics.steps {
      await writeSample(.stepCount, unit: .count(), value: value, start: dayStart, end: stamp, syncIdentifier: "whoof.steps.\(dayKey)")
    }
    if let value = metrics.activeEnergyKcal {
      await writeSample(.activeEnergyBurned, unit: .kilocalorie(), value: value, start: dayStart, end: stamp, syncIdentifier: "whoof.energy.\(dayKey)")
    }
  }
}
