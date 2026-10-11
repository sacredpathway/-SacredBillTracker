//
//  EmptyStateView.swift
//  SacredBillTracker
//

import SwiftUI

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    EmptyStateView(
        systemImage: "tray",
        title: "No bills yet",
        message: "Tap + to add your first bill."
    )
}

// MARK: - Premium zero-state (v1.1 Milestone 1)

/// Benefit-led first-run surface shown on the Dashboard when the account has
/// no bills yet. Gives a fast path to the first bill (reuses `QuickAddView`)
/// and an optional, clearly-labeled sample-data preview that is rendered
/// entirely in memory and is never persisted to the store or Supabase.
struct PremiumZeroStateView: View {
    @State private var showQuickAdd = false
    @State private var showSample = false

    private let benefits: [(icon: String, text: String)] = [
        ("calendar", "See upcoming payments before they're due"),
        ("exclamationmark.triangle", "Catch overdue bills before they cost you"),
        ("wallet.pass", "Know how much is left after bills")
    ]

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(Color.appAccentText)
                    .accessibilityHidden(true)
                Text("Start with one bill")
                    .font(.title3.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Add your first bill to see what's due, what's paid, and what needs attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(benefits, id: \.text) { benefit in
                    HStack(spacing: 12) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.appAccentText)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        Text(benefit.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Color.appCardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appHairline, lineWidth: 1))

            VStack(spacing: 10) {
                Button {
                    AnalyticsService.shared.track(.firstBillStarted, source: "zero_state")
                    showQuickAdd = true
                } label: {
                    Text("Add your first bill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.appAccent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .foregroundStyle(Color.appOnGold)
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeInOut) { showSample.toggle() }
                    if showSample {
                        AnalyticsService.shared.track(.sampleDataPreviewed, source: "zero_state")
                    }
                } label: {
                    Text(showSample ? "Hide sample preview" : "Preview with sample bills")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.appAccentText)
                }
                .buttonStyle(.plain)
            }

            if showSample {
                ZeroStateSamplePreview()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .sheet(isPresented: $showQuickAdd) {
            QuickAddView()
        }
    }
}

/// In-memory, clearly-labeled sample of a populated dashboard. Never touches
/// `BillStore` or Supabase — purely illustrative so a new user can see what
/// the app looks like once real bills are added.
private struct ZeroStateSamplePreview: View {
    private struct SampleBill: Identifiable {
        let id = UUID()
        let name: String
        let amount: String
        let due: String
        let overdue: Bool
    }

    private let sample: [SampleBill] = [
        .init(name: "Rent", amount: "$1,450", due: "Due in 3 days", overdue: false),
        .init(name: "Electric", amount: "$120", due: "Due today", overdue: false),
        .init(name: "Phone", amount: "$85", due: "5 days overdue", overdue: true),
        .init(name: "Internet", amount: "$70", due: "Due in 9 days", overdue: false)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("SAMPLE")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.18), in: Capsule())
                    .foregroundStyle(Color.appAccentText)
                Text("A preview — add a real bill to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }

            HStack(spacing: 12) {
                sampleMetric(title: "Due this month", value: "$1,725")
                sampleMetric(title: "Overdue", value: "$85")
                sampleMetric(title: "Left after bills", value: "$980")
            }

            VStack(spacing: 8) {
                ForEach(Array(sample.enumerated()), id: \.element.id) { index, bill in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bill.name).font(.subheadline.weight(.semibold))
                            Text(bill.due)
                                .font(.caption)
                                .foregroundStyle(bill.overdue ? Color.appDangerText : Color.appSubtleText)
                        }
                        Spacer()
                        Text(bill.amount).font(.subheadline.weight(.semibold))
                    }
                    .padding(.vertical, 6)
                    if index < sample.count - 1 { Divider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color.appCardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.appHairline, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sample preview of a populated dashboard")
    }

    private func sampleMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
