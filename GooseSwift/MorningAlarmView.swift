import SwiftUI

enum AlarmStorage {
  static let enabled = "goose.swift.morningAlarm.enabled"
  static let hour    = "goose.swift.morningAlarm.hour"
  static let minute  = "goose.swift.morningAlarm.minute"
}

struct MorningAlarmView: View {
  @ObservedObject var ble: WhoofBLEClient
  @AppStorage(AlarmStorage.enabled) private var alarmEnabled = false
  @AppStorage(AlarmStorage.hour)    private var alarmHour = 7
  @AppStorage(AlarmStorage.minute)  private var alarmMinute = 0

  @State private var alarmTime: Date = {
    Calendar.current.date(bySettingHour: 7, minute: 0, second: 0, of: Date()) ?? Date()
  }()
  @State private var showTimePicker = false

  var body: some View {
    List {
      Section {
        Toggle("Morning Alarm", isOn: $alarmEnabled)
          .onChange(of: alarmEnabled) { _, enabled in
            if !enabled, ble.canWriteAlarm {
              ble.disableWhoopAlarms()
            }
          }
      } footer: {
        Text("Whoof keeps this alarm active on your WHOOP band. The band vibrates at the configured time each morning.")
      }

      if alarmEnabled {
        Section {
          Button {
            withAnimation(.easeOut(duration: 0.2)) { showTimePicker.toggle() }
          } label: {
            HStack {
              Text("Wake-up time")
                .foregroundStyle(.primary)
              Spacer()
              Text(timeLabel)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
              Image(systemName: showTimePicker ? "chevron.up" : "chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)

          if showTimePicker {
            DatePicker(
              "Wake-up time",
              selection: $alarmTime,
              displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            .onChange(of: alarmTime) { _, new in
              let cal = Calendar.current
              alarmHour   = cal.component(.hour,   from: new)
              alarmMinute = cal.component(.minute, from: new)
            }
          }
        }

        Section {
          Button {
            ble.setWhoopAlarm(at: alarmDateForToday)
          } label: {
            Label("Sync to Band", systemImage: "wave.3.right.circle")
          }
          .disabled(!ble.canWriteAlarm)
        } header: {
          Text("Band")
        } footer: {
          Text(
            ble.canWriteAlarm
              ? ble.alarmCommandStatus
              : "Connect your WHOOP band to sync the alarm."
          )
        }
      }
    }
    .listStyle(.insetGrouped)
    .navigationTitle("Morning Alarm")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if let d = Calendar.current.date(
        bySettingHour: alarmHour, minute: alarmMinute, second: 0, of: Date()
      ) {
        alarmTime = d
      }
    }
  }

  private var timeLabel: String {
    var comps = DateComponents()
    comps.hour   = alarmHour
    comps.minute = alarmMinute
    guard let d = Calendar.current.date(from: comps) else {
      return String(format: "%d:%02d", alarmHour, alarmMinute)
    }
    return d.formatted(date: .omitted, time: .shortened)
  }

  private var alarmDateForToday: Date {
    Calendar.current.date(
      bySettingHour: alarmHour, minute: alarmMinute, second: 0, of: Date()
    ) ?? Date()
  }
}
