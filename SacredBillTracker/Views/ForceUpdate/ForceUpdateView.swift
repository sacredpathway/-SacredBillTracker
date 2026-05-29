//
//  ForceUpdateView.swift
//  SacredBillTracker
//
//  Two surfaces driven by VersionGateService:
//
//   1. ForceUpdateView — full-screen, NON-DISMISSIBLE block screen
//      shown when the running build is below
//      `minimum_supported_build` AND `is_force_update_enabled = true`.
//
//   2. UpdateAvailableSheet — dismissible "soft" prompt shown when
//      the running build is below `latest_build` but still at/above
//      the minimum.
//
//  Wording and styling are intentionally production-clean — no
//  TestFlight / beta language so this is App Review safe.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Hard block (full-screen)

struct ForceUpdateView: View {

    let message: String
    let appStoreURL: URL

    var body: some View {
        ZStack {
            // Solid background — covers ANY content underneath. Cannot
            // be dismissed by swipe / gesture.
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)

                Text("Update Required")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 32)

                Spacer()

                Button {
                    UIApplication.shared.open(appStoreURL)
                } label: {
                    Text("Update App")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
        // Lock the screen — no swipe-down dismissal possible because
        // this view is rendered as the ROOT, not a sheet.
        .interactiveDismissDisabled(true)
    }
}

// MARK: - Soft prompt (dismissible)

struct UpdateAvailableSheet: View {

    let latestBuild: Int
    let appStoreURL: URL
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 24)
                .accessibilityHidden(true)

            Text("Update Available")
                .font(.title2.weight(.bold))

            Text("A newer version of Sacred Bill Tracker is available with the latest improvements.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

            Spacer(minLength: 8)

            VStack(spacing: 10) {
                Button {
                    UIApplication.shared.open(appStoreURL)
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Update Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button {
                    onDismiss()
                    dismiss()
                } label: {
                    Text("Not Now")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Force Update") {
    ForceUpdateView(
        message: "A newer version of Sacred Bill Tracker is required to continue. Please update the app to keep using your account safely.",
        appStoreURL: URL(string: "https://apps.apple.com/app/id6762890363")!
    )
}

#Preview("Optional Update") {
    Color.gray.opacity(0.2)
        .ignoresSafeArea()
        .sheet(isPresented: .constant(true)) {
            UpdateAvailableSheet(
                latestBuild: 18,
                appStoreURL: URL(string: "https://apps.apple.com/app/id6762890363")!,
                onDismiss: {}
            )
        }
}
#endif
