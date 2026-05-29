//
//  FocusPlusEntryCard.swift
//  SacredBillTracker
//
//  Hosts `DailyFocusCenterView` — the Sacred Focus add-on home. This
//  used to be a placeholder marketing list; v1.0.9.x replaces it with
//  a working productivity hub:
//
//    • Focus quote (with favorites)
//    • Today's schedule (real ScheduleItem list, tap to edit)
//    • Today's to-dos (real FocusTodo list, tap to edit)
//    • Schedule Buddy reminders sourced from real bills
//
//  Every item presented via `sheet(item:)` to avoid stacked-navigation
//  bugs.
//

import SwiftUI

struct DailyFocusCenterView: View {

    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var todoStore: TodoStore
    @StateObject private var quotes = QuoteService.shared

    @AppStorage("sbt.focusplus.favorites.v1") private var favoritesCSV: String = ""

    // Sheets
    @State private var newSchedule = false
    @State private var newTodo = false
    @State private var editingSchedule: ScheduleItem?
    @State private var editingTodo: FocusTodo?
    @State private var showAllSchedule = false
    @State private var showAllTodos = false

    private let today = Calendar.current.startOfDay(for: Date())

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                quoteCard
                scheduleSection
                todoSection
                scheduleBuddyCard
                if !favoriteQuotes.isEmpty { favoritesCard }
                Text("Schedule Buddy provides general suggestions only and is not professional financial advice.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Theme.Color.background)
        .navigationTitle("Daily Focus")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $newSchedule) {
            ScheduleItemEditView()
                .environmentObject(scheduleStore)
        }
        .sheet(item: $editingSchedule) { item in
            ScheduleItemEditView(existing: item)
                .environmentObject(scheduleStore)
        }
        .sheet(isPresented: $newTodo) {
            TodoItemEditView()
                .environmentObject(todoStore)
        }
        .sheet(item: $editingTodo) { item in
            TodoItemEditView(existing: item)
                .environmentObject(todoStore)
        }
        .sheet(isPresented: $showAllSchedule) {
            NavigationStack {
                ScheduleAllListView()
                    .environmentObject(scheduleStore)
            }
        }
        .sheet(isPresented: $showAllTodos) {
            NavigationStack {
                TodoAllListView()
                    .environmentObject(todoStore)
            }
        }
    }

    // MARK: - Quote

    private var quoteCard: some View {
        let q = quotes.quote
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Today's Focus", systemImage: "quote.opening")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appAccentText)
                Spacer()
                Button {
                    toggleFavoriteLine(q.text)
                } label: {
                    Image(systemName: isFavorite(q.text) ? "star.fill" : "star")
                        .font(.subheadline)
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }
            Text(q.text)
                .font(.body.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if !q.author.trimmingCharacters(in: .whitespaces).isEmpty {
                Text("— \(q.author)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.appAccent.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.45), lineWidth: 1.5)
        )
    }

    // MARK: - Schedule section (today only)

    private var scheduleSection: some View {
        let todays = scheduleStore.items(on: today)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Today's Schedule",
                icon: "calendar.badge.clock",
                addAction: { newSchedule = true },
                viewAllAction: { showAllSchedule = true }
            )
            if todays.isEmpty {
                emptyHint("No items scheduled today. Tap + to add one.")
            } else {
                VStack(spacing: 0) {
                    ForEach(todays) { item in
                        Button { editingSchedule = item } label: {
                            scheduleRow(item)
                        }
                        .buttonStyle(.plain)
                        if item.id != todays.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func scheduleRow(_ item: ScheduleItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { scheduleStore.toggleComplete(item) } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isComplete ? Color.appHouseholdText : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(item.isComplete, color: .secondary)
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(item.timeRangeLabel)
                    if item.repeatRule != .oneTime {
                        Text("• \(item.repeatRule.title)")
                    }
                    if item.reminderMinutesBefore != nil {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appSubtleText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(Color.appAccentText.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Todo section (today only)

    private var todoSection: some View {
        let todays = todoStore.items(for: today)
        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "Today's To-Do",
                icon: "checklist",
                addAction: { newTodo = true },
                viewAllAction: { showAllTodos = true }
            )
            if todays.isEmpty {
                emptyHint("No tasks for today. Tap + to add one.")
            } else {
                VStack(spacing: 0) {
                    ForEach(todays) { item in
                        Button { editingTodo = item } label: {
                            todoRow(item)
                        }
                        .buttonStyle(.plain)
                        if item.id != todays.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func todoRow(_ item: FocusTodo) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button { todoStore.toggleComplete(item) } label: {
                Image(systemName: item.isComplete ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(item.isComplete ? Color.appHouseholdText : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .strikethrough(item.isComplete, color: .secondary)
                    .foregroundStyle(item.isComplete ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Label(item.priority.title, systemImage: item.priority.systemImage)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(item.priority.color)
                    if item.hasTime {
                        Text("•")
                        Text(timeLabel(item.dueDate))
                    }
                    if item.repeatRule != .oneTime {
                        Text("• \(item.repeatRule.title)")
                    }
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.appSubtleText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(Color.appAccentText.opacity(0.65))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    // MARK: - Schedule Buddy

    private var scheduleBuddyCard: some View {
        let items = scheduleBuddyItems
        return VStack(alignment: .leading, spacing: 10) {
            Label("Schedule Buddy", systemImage: "calendar.badge.checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appHouseholdText)
            if items.isEmpty {
                Text("Nothing to act on today. Enjoy the breathing room.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appSubtleText)
            } else {
                ForEach(items, id: \.self) { line in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .foregroundStyle(Color.appHouseholdText)
                            .font(.subheadline.weight(.semibold))
                            .padding(.top, 1)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var scheduleBuddyItems: [String] {
        var out: [String] = []
        let overdue = store.bills.filter { $0.isOverdue }
        let dueToday = store.bills.filter { !$0.isPaid && $0.isDueToday }
        let dueSoon = store.bills.filter { !$0.isPaid && !$0.isOverdue && !$0.isDueToday && $0.daysUntilDue <= 3 }
        if !overdue.isEmpty {
            out.append("Review \(overdue.count) overdue bill\(overdue.count == 1 ? "" : "s") and mark anything paid.")
        }
        if !dueToday.isEmpty {
            out.append("\(dueToday.count) bill\(dueToday.count == 1 ? " is" : "s are") due today.")
        }
        if !dueSoon.isEmpty {
            out.append("\(dueSoon.count) bill\(dueSoon.count == 1 ? "" : "s") due within 3 days.")
        }
        if out.isEmpty {
            out.append("No urgent bills today — consider logging any income earned this week.")
        }
        return out
    }

    // MARK: - Favorites

    private var favoritesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Saved Favorites", systemImage: "star.fill")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appAccentText)
            ForEach(favoriteQuotes, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Text("“\(line)”")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button {
                        toggleFavoriteLine(line)
                    } label: {
                        Image(systemName: "star.slash")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
                Divider()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
    }

    private var favoriteQuotes: [String] {
        favoritesCSV.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func isFavorite(_ line: String) -> Bool { favoriteQuotes.contains(line) }

    private func toggleFavoriteLine(_ line: String) {
        var lines = favoriteQuotes
        if let i = lines.firstIndex(of: line) { lines.remove(at: i) }
        else { lines.insert(line, at: 0) }
        favoritesCSV = lines.joined(separator: "\n")
    }

    // MARK: - Section header

    private func sectionHeader(
        title: String,
        icon: String,
        addAction: @escaping () -> Void,
        viewAllAction: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.appAccentText)
            Spacer()
            Button("View all") { viewAllAction() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.appAccentText)
            Button {
                addAction()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.appAccentText)
            }
            .buttonStyle(.plain)
        }
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(Color.appSubtleText)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .background(Color.appCard, in: RoundedRectangle(cornerRadius: 12))
    }

    private func timeLabel(_ date: Date) -> String {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }
}

// MARK: - All-schedule list (View all sheet)

struct ScheduleAllListView: View {

    @EnvironmentObject private var store: ScheduleStore
    @Environment(\.dismiss) private var dismiss
    @State private var newSchedule = false
    @State private var editing: ScheduleItem?

    var body: some View {
        Group {
            if store.items.isEmpty {
                EmptyStateView(
                    systemImage: "calendar",
                    title: "No schedule items",
                    message: "Tap + to add your first item."
                )
                .padding(.top, 40)
            } else {
                List {
                    ForEach(store.items) { item in
                        Button { editing = item } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.title)
                                    .font(.subheadline.weight(.semibold))
                                Text(item.timeRangeLabel)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if item.repeatRule != .oneTime {
                                    Text(item.repeatRule.title)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("All Schedule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newSchedule = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $newSchedule) {
            ScheduleItemEditView().environmentObject(store)
        }
        .sheet(item: $editing) { item in
            ScheduleItemEditView(existing: item).environmentObject(store)
        }
    }
}

// MARK: - All-todo list (View all sheet)

struct TodoAllListView: View {

    @EnvironmentObject private var store: TodoStore
    @Environment(\.dismiss) private var dismiss
    @State private var newTodo = false
    @State private var editing: FocusTodo?

    var body: some View {
        Group {
            if store.items.isEmpty {
                EmptyStateView(
                    systemImage: "checklist",
                    title: "No tasks",
                    message: "Tap + to add your first task."
                )
                .padding(.top, 40)
            } else {
                List {
                    ForEach(store.items) { item in
                        Button { editing = item } label: {
                            HStack(spacing: 10) {
                                Image(systemName: item.priority.systemImage)
                                    .foregroundStyle(item.priority.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .strikethrough(item.isComplete, color: .secondary)
                                        .foregroundStyle(item.isComplete ? .secondary : .primary)
                                    Text(item.repeatRule.title)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                store.delete(item)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                store.toggleComplete(item)
                            } label: {
                                Label(item.isComplete ? "Mark Undone" : "Mark Done",
                                      systemImage: item.isComplete ? "arrow.uturn.backward" : "checkmark")
                            }
                            .tint(.green)
                        }
                    }
                }
            }
        }
        .navigationTitle("All Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { newTodo = true } label: {
                    Image(systemName: "plus.circle.fill")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .sheet(isPresented: $newTodo) {
            TodoItemEditView().environmentObject(store)
        }
        .sheet(item: $editing) { item in
            TodoItemEditView(existing: item).environmentObject(store)
        }
    }
}

#Preview {
    NavigationStack {
        DailyFocusCenterView()
            .environmentObject(SubscriptionManager())
            .environmentObject(BillStore())
            .environmentObject(ScheduleStore())
            .environmentObject(TodoStore())
    }
}
