//
//  ScheduleItemEditView.swift
//  SacredBillTracker
//
//  Sheet for adding or editing a single ScheduleItem. Presented via
//  `sheet(item:)` so tapping the same row twice never stacks.
//

import SwiftUI

struct ScheduleItemEditView: View {

    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss

    private let existing: ScheduleItem?

    // Form state
    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var location: String
    @State private var notes: String
    @State private var repeatRule: FocusRepeatRule
    @State private var customWeekdays: Set<Int>
    @State private var reminderEnabled: Bool
    @State private var reminderMinutesBefore: Int

    @State private var showDelete = false

    init(existing: ScheduleItem? = nil, defaultDate: Date = Date()) {
        self.existing = existing
        if let e = existing {
            _title          = State(initialValue: e.title)
            _startTime      = State(initialValue: e.startTime)
            _endTime        = State(initialValue: e.endTime)
            _location       = State(initialValue: e.location)
            _notes          = State(initialValue: e.notes)
            _repeatRule     = State(initialValue: e.repeatRule)
            _customWeekdays = State(initialValue: e.customWeekdays)
            _reminderEnabled = State(initialValue: e.reminderMinutesBefore != nil)
            _reminderMinutesBefore = State(initialValue: e.reminderMinutesBefore ?? 15)
        } else {
            // Default to "now" rounded up to next 15-min mark, 1-hour duration.
            let cal = Calendar.current
            let now = Date()
            let minute = cal.component(.minute, from: now)
            let rounded = cal.date(byAdding: .minute, value: 15 - (minute % 15), to: now) ?? now
            let day = cal.startOfDay(for: defaultDate)
            let comp = cal.dateComponents([.hour, .minute], from: rounded)
            let start = cal.date(bySettingHour: comp.hour ?? 9, minute: comp.minute ?? 0, second: 0, of: day) ?? rounded
            let end = cal.date(byAdding: .hour, value: 1, to: start) ?? start

            _title          = State(initialValue: "")
            _startTime      = State(initialValue: start)
            _endTime        = State(initialValue: end)
            _location       = State(initialValue: "")
            _notes          = State(initialValue: "")
            _repeatRule     = State(initialValue: .oneTime)
            _customWeekdays = State(initialValue: [])
            _reminderEnabled = State(initialValue: false)
            _reminderMinutesBefore = State(initialValue: 15)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Schedule item") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                    DatePicker("Start", selection: $startTime)
                    DatePicker("End", selection: $endTime, in: startTime...)
                    TextField("Location (optional)", text: $location)
                        .textInputAutocapitalization(.words)
                    HStack {
                        Text("Duration")
                        Spacer()
                        Text(durationLabel)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Section("Repeat") {
                    Picker("Repeats", selection: $repeatRule) {
                        ForEach(FocusRepeatRule.allCases) { rule in
                            Label(rule.title, systemImage: rule.systemImage).tag(rule)
                        }
                    }
                    if repeatRule == .custom {
                        customWeekdayPicker
                    }
                }

                Section("Reminder") {
                    Toggle("Remind me before", isOn: $reminderEnabled)
                    if reminderEnabled {
                        Picker("Lead time", selection: $reminderMinutesBefore) {
                            Text("5 min before").tag(5)
                            Text("10 min before").tag(10)
                            Text("15 min before").tag(15)
                            Text("30 min before").tag(30)
                            Text("1 hour before").tag(60)
                            Text("1 day before").tag(60 * 24)
                        }
                    }
                }

                Section("Notes (optional)") {
                    TextField("Anything to remember…", text: $notes, axis: .vertical)
                        .lineLimit(1...4)
                }

                if existing != nil {
                    Section {
                        Button(role: .destructive) {
                            showDelete = true
                        } label: {
                            Label("Delete schedule item", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") { save() }
                        .disabled(!isValid)
                }
            }
            .confirmationDialog(
                "Delete this schedule item?",
                isPresented: $showDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Custom weekdays

    private var customWeekdayPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Days of week")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach(FocusWeekday.allCases) { day in
                    let isOn = customWeekdays.contains(day.rawValue)
                    Button {
                        if isOn { customWeekdays.remove(day.rawValue) }
                        else    { customWeekdays.insert(day.rawValue) }
                    } label: {
                        Text(day.shortLabel)
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isOn ? Color.appAccent.opacity(0.25) : Color.secondary.opacity(0.12))
                            )
                            .foregroundStyle(isOn ? Color.appAccentText : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var durationLabel: String {
        let secs = max(0, Int(endTime.timeIntervalSince(startTime)))
        let h = secs / 3600
        let m = (secs % 3600) / 60
        if h > 0 && m > 0 { return "\(h)h \(m)m" }
        if h > 0          { return "\(h)h" }
        return "\(m)m"
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && endTime >= startTime
            && (repeatRule != .custom || !customWeekdays.isEmpty)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let reminder: Int? = reminderEnabled ? reminderMinutesBefore : nil

        if var e = existing {
            e.title = cleanTitle
            e.startTime = startTime
            e.endTime = endTime
            e.location = cleanLocation
            e.notes = cleanNotes
            e.repeatRule = repeatRule
            e.customWeekdays = customWeekdays
            e.reminderMinutesBefore = reminder
            store.update(e)
        } else {
            let new = ScheduleItem(
                title: cleanTitle,
                startTime: startTime,
                endTime: endTime,
                location: cleanLocation,
                notes: cleanNotes,
                repeatRule: repeatRule,
                customWeekdays: customWeekdays,
                reminderMinutesBefore: reminder
            )
            store.add(new)
        }
        dismiss()
    }
}

#Preview {
    ScheduleItemEditView()
        .environmentObject(ScheduleStore())
}
