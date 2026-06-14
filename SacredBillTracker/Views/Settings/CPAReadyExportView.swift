//
//  CPAReadyExportView.swift
//  SacredBillTracker
//
//  Premium settings screen that lets the user generate an
//  accountant-ready PDF of their bills + income for a chosen date
//  range. Built to feel native to the existing Sacred Bill Tracker
//  premium UI (matte cards, gold accent, native form animations).
//

import SwiftUI
import UIKit

struct CPAReadyExportView: View {

    @EnvironmentObject private var billStore: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore
    @EnvironmentObject private var profileStore: ManagedProfileStore

    // MARK: - Range

    @State private var rangeOption: CPADateRangeOption = .yearToDate
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    // MARK: - Toggles

    @AppStorage("sbt.cpa.businessMode.v1") private var businessMode: Bool = false
    @AppStorage("sbt.cpa.businessName.v1") private var businessName: String = ""
    @AppStorage("sbt.cpa.includeIncome.v1") private var includeIncome: Bool = true
    @AppStorage("sbt.cpa.includePersonal.v1") private var includePersonalBills: Bool = true
    @AppStorage("sbt.cpa.includeBusiness.v1") private var includeBusinessBills: Bool = true

    // MARK: - Generation state

    @State private var isGenerating: Bool = false
    @State private var generatedURL: URL?
    @State private var showShare: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            heroSection

            Section(header: Text("Managed Profile")) {
                ProfileSwitcherBar()
                    .environmentObject(profileStore)
            }

            Section("Export Range") {
                Picker("Range", selection: $rangeOption) {
                    ForEach(CPADateRangeOption.allCases) { opt in
                        Text(opt.title).tag(opt)
                    }
                }
                .pickerStyle(.menu)

                if rangeOption == .custom {
                    DatePicker("Start",
                               selection: $customStart,
                               displayedComponents: .date)
                    DatePicker("End",
                               selection: $customEnd,
                               in: customStart...,
                               displayedComponents: .date)
                }

                Text(resolvedRange.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(header: Text("Tax Profile")) {
                Toggle("Business mode", isOn: $businessMode)
                if businessMode {
                    TextField("Business name", text: $businessName)
                        .textInputAutocapitalization(.words)
                }
            }

            Section("What to include") {
                Toggle("Personal / household bills", isOn: $includePersonalBills)
                Toggle("Business bills", isOn: $includeBusinessBills)
                Toggle("Weekly income totals", isOn: $includeIncome)
            }

            Section("Preview Numbers") {
                previewRow("Bills in range",
                           "\(filteredBills.count)")
                previewRow("Income entries in range",
                           "\(filteredIncome.count)")
                previewRow("Estimated net",
                           formatted(estimatedNet))
            }

            Section {
                Button {
                    generate()
                } label: {
                    HStack {
                        if isGenerating {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.text.fill")
                        }
                        Text(isGenerating ? "Generating…" : "Generate CPA PDF")
                            .font(.body.weight(.semibold))
                        Spacer()
                        Image(systemName: "arrow.up.right.square")
                    }
                }
                .disabled(isGenerating || !canGenerate)
            } footer: {
                Text("Generates a multi-page PDF you can share via AirDrop, email, or save to Files. This report is informational only and does not constitute tax advice.")
                    .font(.footnote)
            }
        }
        .navigationTitle("CPA Ready Export")
        .navigationBarTitleDisplayMode(.large)
        .alert("Couldn't generate PDF",
               isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
               ),
               presenting: errorMessage) { _ in
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showShare) {
            if let url = generatedURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    // MARK: - Hero

    private var heroSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.appAccent.opacity(0.18))
                            .frame(width: 48, height: 48)
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.title2)
                            .foregroundStyle(Color.appAccent)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPA Ready Tax Package")
                            .font(.headline)
                        Text("Bills, expenses, income & write-offs in one accountant-ready PDF.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preview

    private func previewRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    // MARK: - Derived

    private var resolvedRange: CPADateRange {
        CPADateRange.resolve(option: rangeOption,
                             customStart: customStart,
                             customEnd: customEnd)
    }

    private var filteredBills: [Bill] {
        let range = resolvedRange.closedRange
        return billStore.bills.filter { bill in
            guard range.contains(bill.dueDate) else { return false }
            switch bill.type {
            case .household: return includePersonalBills
            case .business:  return includeBusinessBills
            }
        }
    }

    private var filteredIncome: [WeeklyIncome] {
        let range = resolvedRange.closedRange
        return incomeStore.profileEntries.filter { range.contains($0.weekStart) }
    }

    private var estimatedNet: Decimal {
        let income = includeIncome
            ? filteredIncome.reduce(Decimal(0)) { $0 + $1.amount }
            : Decimal(0)
        let expenses = filteredBills.reduce(Decimal(0)) { $0 + $1.amount }
        return income - expenses
    }

    private var canGenerate: Bool {
        includePersonalBills || includeBusinessBills || includeIncome
    }

    private var taxYear: Int {
        Calendar.current.component(.year, from: resolvedRange.start)
    }

    // MARK: - Generate

    private func generate() {
        isGenerating = true
        errorMessage = nil

        let range = resolvedRange
        let bills = filteredBills
        let income = filteredIncome
        let monthlyIncome = incomeStore.monthlyBreakdown(in: range.closedRange)
        let options = CPAReportOptions(
            businessMode: businessMode,
            businessName: businessName,
            includeIncome: includeIncome,
            includePersonal: includePersonalBills,
            includeBusinessBills: includeBusinessBills
        )
        let slug = rangeOption.filenameSlug
        let year = taxYear

        // Run on the next runloop tick so the spinner can render
        // first. Typical bill sets render in well under 100ms, so
        // a main-thread call keeps the code simple and avoids
        // Sendable warnings from capturing the View into a detached Task.
        DispatchQueue.main.async {
            do {
                let url = try CPAReportGenerator.generate(
                    bills: bills,
                    income: income,
                    monthlyIncome: monthlyIncome,
                    range: range,
                    options: options,
                    rangeOptionSlug: slug,
                    taxYear: year
                )
                self.generatedURL = url
                self.isGenerating = false
                self.showShare = true
            } catch {
                self.isGenerating = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    private func formatted(_ value: Decimal) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = .current
        return f.string(from: value as NSDecimalNumber) ?? "$0"
    }
}

// MARK: - ShareSheet

/// Thin UIViewControllerRepresentable wrapper for UIActivityViewController.
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems,
                                 applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        CPAReadyExportView()
            .environmentObject(BillStore())
            .environmentObject(IncomeStore())
            .environmentObject(ManagedProfileStore.shared)
    }
}
