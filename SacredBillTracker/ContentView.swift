//
//  ContentView.swift
//  SacredBillTracker
//
//  Root TabView: Dashboard · Bills · Calendar · Reports · Settings
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var learningRouter: LearningCenterRouter

    // v1.1 (Milestone 1) — one-time first-run onboarding. This lives on the
    // signed-in root, so it only ever presents to an authenticated user, once
    // per install (flag persisted in @AppStorage).
    @AppStorage("sbt.onboarding.seen.v1") private var onboardingSeen: Bool = false
    @State private var showOnboarding = false
    @State private var showCelebration = false
    @State private var showQuickAddFromOnboarding = false

    var body: some View {
        TabView(selection: $learningRouter.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }
                .tag(SacredBillTrackerTab.dashboard)

            BillsView()
                .tabItem { Label("Bills", systemImage: "list.bullet.rectangle.fill") }
                .tag(SacredBillTrackerTab.bills)

            BudgetDashboardView()
                .tabItem { Label("Budget", systemImage: "chart.bar.fill") }
                .tag(SacredBillTrackerTab.budget)

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(SacredBillTrackerTab.calendar)

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.pie.fill") }
                .tag(SacredBillTrackerTab.reports)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
                .tag(SacredBillTrackerTab.settings)
        }
        // First-run onboarding carousel — shown once per install.
        .fullScreenCover(isPresented: $showOnboarding, onDismiss: { onboardingSeen = true }) {
            OnboardingCarouselView(
                onAddFirstBill: {
                    AnalyticsService.shared.track(.onboardingCompleted, source: "first_run")
                    AnalyticsService.shared.track(.firstBillStarted, source: "onboarding")
                    showOnboarding = false
                    // Hand off to the existing Quick Add flow once the
                    // onboarding cover has finished dismissing.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        showQuickAddFromOnboarding = true
                    }
                },
                onSkip: {
                    AnalyticsService.shared.track(.onboardingSkipped, source: "first_run")
                    showOnboarding = false
                }
            )
        }
        // One-time celebration after the account's first bill is created.
        // Presented after a short delay so the add sheet finishes dismissing.
        .sheet(isPresented: $showCelebration, onDismiss: { store.didCreateFirstBill = false }) {
            FirstBillCelebrationView { showCelebration = false }
        }
        // "Add My First Bill" from onboarding routes into the existing Quick Add flow.
        .sheet(isPresented: $showQuickAddFromOnboarding) {
            QuickAddView()
        }
        .onChange(of: store.didCreateFirstBill) { _, created in
            guard created else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showCelebration = true }
        }
        .onAppear {
            if !onboardingSeen {
                AnalyticsService.shared.track(.onboardingStarted, source: "first_run")
                showOnboarding = true
            }
        }
    }
}

// MARK: - First-run onboarding (v1.1 Milestone 1)

private struct OnboardingPageData: Identifiable {
    let id = UUID()
    let systemImage: String
    let title: String
    let message: String
}

/// A premium, brand-styled onboarding carousel shown once to a new user.
/// Copy is bill/finance-focused: keep every bill in one place, see what's due,
/// get reminders before bills are due, and understand money left after bills.
struct OnboardingCarouselView: View {
    let onAddFirstBill: () -> Void
    let onSkip: () -> Void

    @State private var index = 0

    private let pages: [OnboardingPageData] = [
        .init(systemImage: "tray.full.fill",
              title: "Track bills in one place",
              message: "Keep rent, utilities, insurance, and subscriptions together — household and business — so nothing slips through the cracks."),
        .init(systemImage: "calendar.badge.clock",
              title: "See what's due soon",
              message: "Your dashboard shows what's coming up and what's overdue, so you always know what needs attention."),
        .init(systemImage: "bell.badge.fill",
              title: "Get reminders before bills are due",
              message: "A gentle reminder lands before each bill is due, so a late fee never sneaks up on you again."),
        .init(systemImage: "chart.pie.fill",
              title: "Understand money left after bills",
              message: "See what's due, what's paid, and how much is left after bills — at a glance, every day.")
    ]

    private var isLastPage: Bool { index >= pages.count - 1 }

    var body: some View {
        ZStack {
            Color.appSacredBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Skip for Now") { onSkip() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding()
                }

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                        VStack(spacing: 22) {
                            Spacer()
                            Image(systemName: page.systemImage)
                                .font(.system(size: 66, weight: .semibold))
                                .foregroundStyle(Color.appAccentText)
                                .accessibilityHidden(true)
                            Text(page.title)
                                .font(.title.weight(.bold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                            Text(page.message)
                                .font(.body)
                                .foregroundStyle(.white.opacity(0.75))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))

                VStack(spacing: 12) {
                    // Primary CTA: advance on early pages; on the final page it
                    // hands straight off to the existing Add Bill / Quick Add flow.
                    Button {
                        if isLastPage {
                            onAddFirstBill()
                        } else {
                            withAnimation { index += 1 }
                        }
                    } label: {
                        Text(isLastPage ? "Add My First Bill" : "Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .foregroundStyle(Color.appOnGold)
                    }
                    .buttonStyle(.plain)

                    // Final page also lets the user finish without adding yet.
                    if isLastPage {
                        Button("Skip for Now") { onSkip() }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - First-bill celebration (v1.1 Milestone 1)

/// A lightweight, celebratory confirmation shown once, right after the
/// account's first bill is created — reinforcing the first "aha" moment.
struct FirstBillCelebrationView: View {
    var onDone: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var pop = false

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.15))
                    .frame(width: 128, height: 128)
                    .scaleEffect(pop ? 1 : 0.6)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72, weight: .bold))
                    .foregroundStyle(Color.appAccentText)
                    .scaleEffect(pop ? 1 : 0.5)
                    .accessibilityHidden(true)
            }
            .padding(.top, 24)

            Text("First bill added")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            Text("You're ready to start tracking what's due.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            Spacer(minLength: 8)

            Button {
                onDone()
                dismiss()
            } label: {
                Text("See my dashboard")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .foregroundStyle(Color.appOnGold)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) { pop = true }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SubscriptionManager())
        .environmentObject(LearningCenterRouter())
}
