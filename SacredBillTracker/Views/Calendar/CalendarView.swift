//
//  CalendarView.swift
//  SacredBillTracker
//
//  Monthly calendar grid with dots for days that have bills.
//

import SwiftUI

struct CalendarView: View {

    @EnvironmentObject private var store: BillStore
    @State private var displayedMonth: Date = Date()
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    /// v1.0.9 — Single-source edit trigger.
    @State private var billToEdit: Bill?

    private let calendar = Calendar.current

    /// Weekday labels rotated so they start on `calendar.firstWeekday`.
    private var weekdaySymbols: [String] {
        let raw = calendar.veryShortStandaloneWeekdaySymbols // starts at Sunday (index 0)
        let start = calendar.firstWeekday - 1                // 0-based
        guard start > 0, start < raw.count else { return raw }
        return Array(raw[start...] + raw[..<start])
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                FilterPicker(selection: $store.filter)
                    .padding(.horizontal)

                monthHeader

                weekdayHeader
                daysGrid

                Divider().padding(.horizontal)

                billsForSelectedDay
            }
            .padding(.vertical)
            .background(Theme.Color.background)
            .navigationTitle("Calendar")
            .sheet(item: $billToEdit) { bill in
                AddEditBillView(mode: .edit(bill))
                    .environmentObject(store)
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            Button {
                shiftMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            Spacer()
            Text(displayedMonth.longMonthYear)
                .font(.title3.bold())
            Spacer()
            Button {
                shiftMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
        }
        .padding(.horizontal)
    }

    private var weekdayHeader: some View {
        HStack {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Grid

    private var daysGrid: some View {
        let days = makeDays()
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                dayCell(for: day)
            }
        }
        .padding(.horizontal)
    }

    private func dayCell(for day: Date?) -> some View {
        guard let day else {
            return AnyView(Color.clear.frame(height: 46))
        }
        let bills = store.bills(on: day)
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)

        return AnyView(
            Button {
                selectedDate = day
            } label: {
                VStack(spacing: 4) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.callout)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle(isSelected ? .white : .primary)
                    HStack(spacing: 2) {
                        ForEach(Array(bills.prefix(3).enumerated()), id: \.offset) { _, bill in
                            Circle()
                                .fill(isSelected ? Color.white : bill.type.accentColor)
                                .frame(width: 5, height: 5)
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.appAccent : (isToday ? Color.appAccent.opacity(0.12) : Color.clear))
                )
            }
            .buttonStyle(.plain)
        )
    }

    // MARK: - Day detail

    private var billsForSelectedDay: some View {
        let bills = store.bills(on: selectedDate)
        return VStack(alignment: .leading, spacing: 8) {
            Text(selectedDate.mediumFormatted)
                .font(.headline)
                .padding(.horizontal)

            if bills.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: "No bills",
                    message: "Nothing due on this day."
                )
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(bills) { bill in
                            Button {
                                billToEdit = bill
                            } label: {
                                BillRowView(bill: bill)
                                    .padding(.horizontal)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if bill.id != bills.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .background(Color.appCard, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal)
                }
            }
        }
    }

    // MARK: - Computation

    private func makeDays() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: displayedMonth) else { return [] }
        let firstOfMonth = monthInterval.start

        // Weekday of first of month (1 = Sunday by default on iOS)
        let weekdayOfFirst = calendar.component(.weekday, from: firstOfMonth)
        let leadingEmpties = (weekdayOfFirst - calendar.firstWeekday + 7) % 7

        let daysInMonth = calendar.range(of: .day, in: .month, for: firstOfMonth)?.count ?? 30

        var days: [Date?] = Array(repeating: nil, count: leadingEmpties)
        for offset in 0..<daysInMonth {
            days.append(calendar.date(byAdding: .day, value: offset, to: firstOfMonth))
        }
        // Pad to complete final week
        while days.count % 7 != 0 { days.append(nil) }
        return days
    }

    private func shiftMonth(by months: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: months, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }
}

#Preview {
    CalendarView()
        .environmentObject(BillStore())
        .environmentObject(NotificationManager.shared)
}
