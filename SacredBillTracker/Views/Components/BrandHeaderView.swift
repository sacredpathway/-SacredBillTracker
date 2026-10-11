//
//  BrandHeaderView.swift
//  SacredBillTracker
//
//  Sacred black header with the Tree-of-Life logo. Uses `Image("AppLogo")`
//  when the asset is bundled; falls back to a gold tree symbol on black
//  with a lime ring so the layout never breaks.
//

import SwiftUI

struct BrandHeaderView: View {
    var title: String = "Sacred Bill Tracker"
    var subtitle: String = "Rooted in what matters."
    var compact: Bool = false

    var body: some View {
        HStack(spacing: compact ? 12 : 16) {
            logo
                .frame(width: compact ? 44 : 56, height: compact ? 44 : 56)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Color.appLime.opacity(0.85), lineWidth: 1.25)
                )
                .shadow(color: Color.appLime.opacity(0.25), radius: 6, y: 0)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font((compact ? Font.headline : Font.title3).bold())
                    .foregroundStyle(Color.appAccentText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, compact ? 12 : 14)
        .background(
            LinearGradient(
                colors: [Color.appSacredBlack, Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.appAccent.opacity(0.30), lineWidth: 0.5)
        )
    }

    // MARK: - Logo

    /// Uses the `AppLogo` asset catalog imageset. If no PNG is present in
    /// the imageset, SwiftUI's `Image(_:)` renders empty — we detect that
    /// via `UIImage(named:)` and render a polished fallback instead.
    @ViewBuilder
    private var logo: some View {
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)    // preserve aspect ratio, no stretching
                .background(Color.appSacredBlack)   // matches logo black bg
        } else {
            ZStack {
                Circle().fill(Color.appSacredBlack)
                Image(systemName: "leaf.fill")
                    .font(.system(size: compact ? 20 : 26, weight: .semibold))
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
}

#Preview {
    VStack {
        BrandHeaderView()
        Spacer()
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
