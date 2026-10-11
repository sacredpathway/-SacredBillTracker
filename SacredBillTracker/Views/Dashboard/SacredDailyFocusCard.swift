//
//  SacredDailyFocusCard.swift
//  SacredBillTracker
//
//  v1.0.9 — Combined hero card. Replaces the separate `DailyQuoteBanner`
//  + `BrandHeaderView` stack at the top of the Dashboard with one
//  premium productivity hub titled "Sacred Focus".
//
//  Contains:
//    • Sacred Bill Tracker logo (Tree of Life)
//    • App name
//    • Today's quote
//    • Author
//    • Share button
//    • Notes / Schedule / To-Do previews
//
//  The header opens the Focus+ center/paywall. Each productivity
//  preview opens its own full screen.
//

import SwiftUI

private enum SacredFocusDestination: String, Identifiable {
    case notes
    case schedule
    case todo

    var id: String { rawValue }
}

struct SacredDailyFocusCard: View {

    let quote: FinancialLesson

    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var noteStore: NoteStore
    @EnvironmentObject private var scheduleStore: ScheduleStore
    @EnvironmentObject private var todoStore: TodoStore

    /// v1.0.9 — When the user has Focus+, tap pushes the Focus+ center
    /// in this sheet. When they don't, tap opens the Focus+ paywall.
    /// One state covers both modes so the card is the SINGLE entry
    /// point and there is no second dashboard card.
    @State private var showFocusCenter = false
    @State private var showEducation = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPaywall = false
    @State private var destination: SacredFocusDestination?
    @State private var quickNoteText = ""
    @AppStorage("sbt.dashboard.sacredFocusExpanded") private var isExpanded = false

    private static let appStoreURL: String =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 14 : 0) {
            focusHeader
            Button("Explore Financial Education") { showEducation = true }
                .font(.subheadline).foregroundStyle(.white).padding(.top, 8)

            if isExpanded {
                VStack(spacing: 8) {
                    previewButton(
                        destination: .notes,
                        title: "Notes Preview",
                        systemImage: "note.text",
                        primary: notesPrimary,
                        secondary: notesSecondary,
                        detail: notesDetail
                    )

                    quickNoteInput

                    previewButton(
                        destination: .schedule,
                        title: "Schedule Preview",
                        systemImage: "calendar.badge.clock",
                        primary: schedulePrimary,
                        secondary: scheduleSecondary,
                        detail: scheduleDetail
                    )
                    previewButton(
                        destination: .todo,
                        title: "To-Do Preview",
                        systemImage: "checklist",
                        primary: todoPrimary,
                        secondary: todoSecondary,
                        detail: todoDetail
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color.appSacredBlack, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.appAccent.opacity(0.30), lineWidth: 0.5)
        )
        .accessibilityElement(children: .contain)
        .sheet(isPresented: $showEducation) {
            NavigationStack {
                ScrollView { FinancialEducationView().padding() }
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showEducation = false } } }
            }
        }
        .sheet(isPresented: $showFocusCenter) {
            NavigationStack {
                DailyFocusCenterView()
                    .environmentObject(subs)
                    .environmentObject(store)
                    .environmentObject(noteStore)
                    .environmentObject(scheduleStore)
                    .environmentObject(todoStore)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showFocusCenter = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showPaywall) {
            FocusPlusPaywallView()
                .environmentObject(subs)
        }
        .sheet(item: $destination) { destination in
            NavigationStack {
                switch destination {
                case .notes:
                    NotesListView()
                        .environmentObject(noteStore)
                case .schedule:
                    ScheduleAllListView()
                        .environmentObject(scheduleStore)
                case .todo:
                    TodoAllListView()
                        .environmentObject(todoStore)
                }
            }
        }
    }

    private var focusHeader: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                toggleExpanded()
            } label: {
                HStack(alignment: .center, spacing: 14) {
                    logo
                        .frame(width: 50, height: 50)
                        .clipShape(Circle())
                        .overlay(
                            Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.25)
                        )
                        .shadow(color: Color.appLime.opacity(0.25), radius: 6, y: 0)

                    VStack(alignment: .leading, spacing: 4) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Financial Education")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Color.appAccentText)
                                .fixedSize(horizontal: false, vertical: true)
                            if isExpanded { focusPlusBadge }
                        }

                        Text(quote.text)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.white)
                            .lineLimit(isExpanded ? nil : 4)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)

                        if isExpanded, !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("— \(quote.author)")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Financial Education. \(quote.text).")
            .accessibilityHint(isExpanded ? "Collapses Sacred Focus." : "Expands Sacred Focus.")

            Spacer(minLength: 6)

            if isExpanded {
                ShareLink(
                    item: shareText,
                    subject: Text("Financial Education — Sacred Bill Tracker")
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccentText)
                        .frame(width: 38, height: 38)
                        .background(
                            Circle().fill(Color.appAccent.opacity(0.15))
                        )
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Share today's money lesson")
            }

            Button {
                toggleExpanded()
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color.appAccent.opacity(0.12)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse Sacred Focus" : "Expand Sacred Focus")
        }
    }

    private var quickNoteInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Quick Note", systemImage: "square.and.pencil")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.appAccent.opacity(0.92))

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a quick note...", text: $quickNoteText, axis: .vertical)
                    .textInputAutocapitalization(.sentences)
                    .lineLimit(1...3)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.appAccent.opacity(0.18), lineWidth: 0.5)
                    )
                    .submitLabel(.done)

                Button {
                    saveQuickNote()
                } label: {
                    Text("Add")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.appSacredBlack)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            Capsule().fill(canSaveQuickNote ? Color.appAccent : Color.appAccent.opacity(0.35))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSaveQuickNote)
                .accessibilityLabel("Add quick note")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.appAccent.opacity(0.14), lineWidth: 0.5)
        )
    }

    private func previewButton(
        destination: SacredFocusDestination,
        title: String,
        systemImage: String,
        primary: String,
        secondary: String,
        detail: String?
    ) -> some View {
        Button {
            self.destination = destination
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.appAccentText)
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.appAccent.opacity(0.92))
                        .lineLimit(1)

                    Text(primary)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.appAccent.opacity(0.75))
                    .padding(.top, 4)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.055))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.appAccent.opacity(0.16), lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(primary). \(secondary)")
    }

    private func openFocus() {
        if subs.hasFocusPlus {
            showFocusCenter = true
        } else {
            showPaywall = true
        }
    }

    private func toggleExpanded() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            isExpanded.toggle()
        }
    }

    private var canSaveQuickNote: Bool {
        !quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveQuickNote() {
        let cleanText = quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { return }

        let lines = cleanText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let title = lines.first ?? "Untitled Note"
        let body = lines.dropFirst().joined(separator: "\n")

        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.85)) {
            noteStore.add(FocusNote(title: title, body: body))
            quickNoteText = ""
        }
    }

    private var notesPrimary: String {
        guard let note = noteStore.mostRecent else { return "No notes yet" }
        return note.title.nilIfBlank ?? "Untitled note"
    }

    private var notesSecondary: String {
        guard let note = noteStore.mostRecent else { return "Tap to create your first note" }
        return mediumDateFormatter.string(from: note.updatedAt)
    }

    private var notesDetail: String? {
        noteStore.mostRecent?.body.nilIfBlank
    }

    private var schedulePrimary: String {
        guard let next = nextSchedule else { return "No upcoming events" }
        return next.item.title.nilIfBlank ?? "Untitled event"
    }

    private var scheduleSecondary: String {
        guard let next = nextSchedule else { return "Tap to schedule one" }
        return timeFormatter.string(from: next.date)
    }

    private var scheduleDetail: String? {
        guard let next = nextSchedule else { return nil }
        return mediumDateFormatter.string(from: next.date)
    }

    private var todoPrimary: String {
        let count = openTodos.count
        return count == 0 ? "No tasks yet" : "\(count) open task\(count == 1 ? "" : "s")"
    }

    private var todoSecondary: String {
        guard let next = nextTodo else { return "Tap to add one" }
        return next.title.nilIfBlank ?? "Untitled task"
    }

    private var todoDetail: String? {
        guard let next = nextTodo else { return nil }
        return "Due \(mediumDateFormatter.string(from: next.dueDate))"
    }

    private var openTodos: [FocusTodo] {
        todoStore.items
            .filter { !$0.isComplete }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var nextTodo: FocusTodo? {
        openTodos.first
    }

    private var nextSchedule: (item: ScheduleItem, date: Date)? {
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        var matches: [(ScheduleItem, Date)] = []

        for offset in 0..<366 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            for item in scheduleStore.items(on: day, calendar: calendar) where !item.isComplete {
                let start = occurrenceStart(for: item, on: day, calendar: calendar)
                if start >= now {
                    matches.append((item, start))
                }
            }
            if !matches.isEmpty {
                if let match = matches.min(by: { $0.1 < $1.1 }) {
                    return (item: match.0, date: match.1)
                }
            }
        }

        return nil
    }

    private func occurrenceStart(for item: ScheduleItem, on day: Date, calendar: Calendar) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: item.startTime)
        return calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? item.startTime
    }

    private var mediumDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }

    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    // MARK: - Focus+ badge

    /// Small pill inside the card. Reads "Focus+" with the brand gold
    /// when locked, switches to a check-marked unlocked style when
    /// the user has the add-on. Subtle by design — keeps the card
    /// premium and minimal.
    @ViewBuilder
    private var focusPlusBadge: some View {
        if subs.hasFocusPlus {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2.weight(.bold))
                Text("Focus+")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appLime.opacity(0.30)))
            .foregroundStyle(Color.appLimeText)
        } else {
            HStack(spacing: 3) {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                Text("Focus+")
                    .font(.caption2.weight(.bold))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.appAccent.opacity(0.22)))
            .foregroundStyle(Color.appAccentText)
        }
    }

    // MARK: - Logo (mirrors BrandHeaderView)

    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color.appSacredBlack)
        } else {
            ZStack {
                Circle().fill(Color.appSacredBlack)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appLime, Color.appAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var shareText: String {
        return quote.shareText
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Detail sheet

struct DailyFocusDetailView: View {

    let quote: FinancialLesson

    @Environment(\.dismiss) private var dismiss

    private static let appStoreURL: String =
        "https://apps.apple.com/us/app/sacred-bill-tracker/id6762890363"

    /// Money-focus prompt of the day. Keep it short, calm, and
    /// action-oriented. Cycle through a small pool by day-of-year so
    /// the prompt feels alive without going off-brand.
    private var moneyFocus: String {
        let prompts = [
            "Review what is due today and mark anything paid.",
            "Glance at your overdue list. Knock out one bill if you can.",
            "Log any income you earned this week. Small wins count.",
            "Check your business profit margin for the month so far.",
            "Open one bill detail and double-check the due date.",
            "Mark one paid bill as paid so your dashboard is honest.",
            "Add an upcoming bill before it sneaks up on you."
        ]
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        return prompts[(day - 1) % prompts.count]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Brand block.
                    HStack(spacing: 12) {
                        logo
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                            .overlay(Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.25))
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Sacred Bill Tracker")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("Rooted in what matters.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    // Full quote.
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: "book")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(Color.appAccentText)
                        Text(quote.text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        if !quote.author.trimmingCharacters(in: .whitespaces).isEmpty {
                            Text("— \(quote.author)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.appAccent.opacity(0.10))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(Color.appAccent.opacity(0.20), lineWidth: 1)
                    )

                    // Money focus prompt.
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Today's Money Focus", systemImage: "target")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Color.appHouseholdText)
                        Text(moneyFocus)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.appCard)
                    )

                    // Share button.
                    ShareLink(
                        item: shareText,
                        subject: Text("Financial Education — Sacred Bill Tracker")
                    ) {
                        Label("Share Lesson", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.appAccent.opacity(0.18))
                            )
                            .foregroundStyle(Color.appAccentText)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
            }
            .background(Theme.Color.background)
            .navigationTitle("Daily Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .background(Color.appSacredBlack)
        } else {
            ZStack {
                Circle().fill(Color.appSacredBlack)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appLime, Color.appAccent],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
        }
    }

    private var shareText: String {
        return quote.shareText
    }
}

#Preview {
    SacredDailyFocusCard(
        quote: FinancialEducation.lesson(day: 0)
    )
    .environmentObject(SubscriptionManager())
    .padding()
    .background(Color(.systemGroupedBackground))
}
