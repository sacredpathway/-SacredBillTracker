//
//  TodoItemEditView.swift
//  SacredBillTracker
//

import SwiftUI

struct TodoItemEditView: View {

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss

    private let existing: FocusTodo?

    @State private var title: String
    @State private var notes: String
    @State private var dueDate: Date
    @State private var hasTime: Bool
    @State private var priority: TodoPriority
    @State private var repeatRule: FocusRepeatRule
    @State private var customWeekdays: Set<Int>
    @State private var reminderEnabled: Bool
    @State private var reminderDate: Date

    @State private var showDelete = false

    init(existing: FocusTodo? = nil) {
        self.existing = existing
        if let e = existing {
            _title          = State(initialValue: e.title)
            _notes          = State(initialValue: e.notes)
            _dueDate        = State(initialValue: e.dueDate)
            _hasTime        = State(initialValue: e.hasTime)
            _priority       = State(initialValue: e.priority)
            _repeatRule     = State(initialValue: e.repeatRule)
            _customWeekdays = State(initialValue: e.customWeekdays)
            _reminderEnabled = State(initialValue: e.reminderDate != nil)
            _reminderDate   = State(initialValue: e.reminderDate ?? Self.defaultReminderDate(for: e.dueDate))
        } else {
            _title          = State(initialValue: "")
            _notes          = State(initialValue: "")
            _dueDate        = State(initialValue: Date())
            _hasTime        = State(initialValue: false)
            _priority       = State(initialValue: .medium)
            _repeatRule     = State(initialValue: .oneTime)
            _customWeekdays = State(initialValue: [])
            _reminderEnabled = State(initialValue: false)
            _reminderDate   = State(initialValue: Self.defaultReminderDate(for: Date()))
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("Title", text: $title)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Due") {
                    Toggle("Include time", isOn: $hasTime)
                    DatePicker(
                        "Due",
                        selection: $dueDate,
                        displayedComponents: hasTime ? [.date, .hourAndMinute] : .date
                    )
                }

                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases) { p in
                            Label(p.title, systemImage: p.systemImage)
                                .tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
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
                    Toggle("Alert me", isOn: $reminderEnabled)
                    if reminderEnabled {
                        DatePicker(
                            "Alert",
                            selection: $reminderDate,
                            displayedComponents: [.date, .hourAndMinute]
                        )
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
                            Label("Delete task", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New Task" : "Edit Task")
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
                "Delete this task?",
                isPresented: $showDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            }
            .onChange(of: dueDate) { _, newDate in
                if !reminderEnabled {
                    reminderDate = Self.defaultReminderDate(for: newDate)
                }
            }
        }
    }

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

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
            && (repeatRule != .custom || !customWeekdays.isEmpty)
    }

    private func save() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanReminder = reminderEnabled ? reminderDate : nil
        if var e = existing {
            e.title = cleanTitle
            e.notes = cleanNotes
            e.dueDate = dueDate
            e.hasTime = hasTime
            e.priority = priority
            e.repeatRule = repeatRule
            e.customWeekdays = customWeekdays
            e.reminderDate = cleanReminder
            store.update(e)
        } else {
            let new = FocusTodo(
                title: cleanTitle,
                notes: cleanNotes,
                dueDate: dueDate,
                hasTime: hasTime,
                priority: priority,
                repeatRule: repeatRule,
                customWeekdays: customWeekdays,
                reminderDate: cleanReminder
            )
            store.add(new)
        }
        dismiss()
    }

    private static func defaultReminderDate(for date: Date) -> Date {
        let calendar = Calendar.current
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: date) ?? date
    }
}

#Preview {
    TodoItemEditView()
        .environmentObject(TodoStore())
}
