//
//  ManagedProfilesView.swift
//  SacredBillTracker
//
//  UI for switching and managing account-owned financial profiles.
//

import SwiftUI

struct ProfileSwitcherBar: View {
    @EnvironmentObject private var profiles: ManagedProfileStore
    @EnvironmentObject private var subs: SubscriptionManager
    @State private var showManageProfiles = false
    @State private var showPaywall = false

    var body: some View {
        HStack(spacing: 10) {
            if subs.isPro {
                Menu {
                    Button {
                        profiles.selectAllProfiles()
                    } label: {
                        Label("All Profiles", systemImage: "square.grid.2x2.fill")
                    }

                    Divider()

                    ForEach(profiles.profiles) { profile in
                        Button {
                            profiles.select(profileID: profile.id)
                        } label: {
                            Label(profile.name, systemImage: profile.iconSystemName)
                        }
                    }

                    Divider()

                    Button {
                        showManageProfiles = true
                    } label: {
                        Label("Manage Profiles", systemImage: "person.2.badge.gearshape")
                    }
                } label: {
                    switcherLabel(locked: false)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    profiles.applyPremiumAccess(false)
                    showPaywall = true
                } label: {
                    switcherLabel(locked: true)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            profiles.applyPremiumAccess(subs.isPro)
        }
        .onChange(of: subs.isPro) { _, isPro in
            profiles.applyPremiumAccess(isPro)
        }
        .sheet(isPresented: $showManageProfiles) {
            ManagedProfilesView()
                .environmentObject(profiles)
                .environmentObject(subs)
        }
        .paywallSheet(isPresented: $showPaywall,
                      reason: PremiumMessaging.managedProfiles)
    }

    private func switcherLabel(locked: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: locked ? "lock.fill" : profiles.selectionIcon)
                .font(.subheadline.weight(.semibold))
                .frame(width: 28, height: 28)
                .foregroundStyle(Color.appAccentText)
                .background(
                    Circle().fill(Color.appAccent.opacity(0.16))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Profile")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(profiles.selectionTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer()
            if profiles.isLoading {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: locked ? "lock.circle.fill" : "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.appAccent.opacity(0.14), lineWidth: 1)
        )
    }
}

struct ManagedProfilesView: View {
    @EnvironmentObject private var profiles: ManagedProfileStore
    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    @State private var editingProfile: ManagedProfile?
    @State private var addingProfile = false
    @State private var showPaywall = false

    var body: some View {
        NavigationStack {
            List {
                if !subs.isPro {
                    Section {
                        ProLockCard(
                            icon: "person.3.sequence.fill",
                            title: "Managed Profiles are Premium",
                            message: PremiumMessaging.managedProfiles,
                            onUpgrade: { showPaywall = true }
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                if subs.isPro {
                    Section {
                    Button {
                        profiles.selectAllProfiles()
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            ProfileIcon(systemImage: "square.grid.2x2.fill", tint: .appAccentText)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("All Profiles")
                                    .font(.subheadline.weight(.semibold))
                                Text("Combined bills, income, expenses, dashboard, and reports")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if profiles.selection == .allProfiles {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    }
                }

                Section {
                    ForEach(profiles.profiles) { profile in
                        Button {
                            if subs.isPro {
                                editingProfile = profile
                            } else if profile.id != profiles.defaultProfile?.id {
                                showPaywall = true
                            }
                        } label: {
                            profileRow(profile)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Managed Accounts")
                } footer: {
                    Text("Manage multiple financial profiles under one account and subscription. Extra profiles do not need separate emails or passwords.")
                        .font(.footnote)
                }

                if let message = profiles.lastError {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Profiles")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                profiles.applyPremiumAccess(subs.isPro)
            }
            .onChange(of: subs.isPro) { _, isPro in
                profiles.applyPremiumAccess(isPro)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        if subs.isPro {
                            addingProfile = true
                        } else {
                            showPaywall = true
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Add profile")
                }
            }
            .sheet(isPresented: $addingProfile) {
                AddEditManagedProfileSheet(mode: .add)
                    .environmentObject(profiles)
                    .environmentObject(subs)
            }
            .sheet(item: $editingProfile) { profile in
                AddEditManagedProfileSheet(mode: .edit(profile))
                    .environmentObject(profiles)
                    .environmentObject(subs)
            }
            .paywallSheet(isPresented: $showPaywall,
                          reason: PremiumMessaging.managedProfiles)
        }
    }

    private func profileRow(_ profile: ManagedProfile) -> some View {
        HStack(spacing: 12) {
            ProfileIcon(
                systemImage: profile.iconSystemName,
                tint: Color(hex: profile.colorHex) ?? .appAccentText
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if profile.isDefault {
                        Text("Default")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.appAccent.opacity(0.14)))
                            .foregroundStyle(Color.appAccent)
                    }
                }
                Text(profile.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if profiles.selectedProfile?.id == profile.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.appAccent)
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

private struct ProfileIcon: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: 42, height: 42)
            Image(systemName: systemImage)
                .font(.headline)
                .foregroundStyle(tint)
        }
    }
}

private struct AddEditManagedProfileSheet: View {
    enum Mode {
        case add
        case edit(ManagedProfile)
    }

    @EnvironmentObject private var profiles: ManagedProfileStore
    @EnvironmentObject private var subs: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    let mode: Mode

    @State private var name: String
    @State private var kind: ManagedProfileKind
    @State private var showArchiveConfirmation = false

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .add:
            _name = State(initialValue: "")
            _kind = State(initialValue: .personal)
        case .edit(let profile):
            _name = State(initialValue: profile.name)
            _kind = State(initialValue: profile.kind)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Profile")) {
                    TextField("Profile name", text: $name)
                        .textInputAutocapitalization(.words)

                    Picker("Type", selection: $kind) {
                        ForEach(ManagedProfileKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.systemImage)
                                .tag(kind)
                        }
                    }
                }

                if case .edit(let profile) = mode, !profile.isDefault {
                    Section {
                        Button {
                            Task {
                                await profiles.setDefaultProfile(profile)
                                dismiss()
                            }
                        } label: {
                            Label("Make Default Profile", systemImage: "star.fill")
                        }
                    } footer: {
                        Text("New bills and income use the default profile when All Profiles is selected.")
                            .font(.footnote)
                    }
                }

                if case .edit = mode, profiles.profiles.count > 1 {
                    Section {
                        Button(role: .destructive) {
                            showArchiveConfirmation = true
                        } label: {
                            Label("Archive Profile", systemImage: "archivebox.fill")
                        }
                    } footer: {
                        Text("Archiving removes this profile from active pickers. Existing bills, income, reports, exports, and trash history stay preserved.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                profiles.applyPremiumAccess(subs.isPro)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { await save() }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Archive this profile?",
                isPresented: $showArchiveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Archive Profile", role: .destructive) {
                    Task { await archiveProfile() }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This does not delete historical bills or income. You can still see archived profile data in All Profiles totals and exports.")
            }
        }
    }

    private var navigationTitle: String {
        switch mode {
        case .add:  return "New Profile"
        case .edit: return "Edit Profile"
        }
    }

    private func save() async {
        guard subs.isPro else {
            profiles.applyPremiumAccess(false)
            return
        }
        switch mode {
        case .add:
            _ = await profiles.createProfile(name: name, kind: kind)
        case .edit(let profile):
            await profiles.updateProfile(profile, name: name, kind: kind)
        }
        if profiles.lastError == nil {
            dismiss()
        }
    }

    private func archiveProfile() async {
        guard subs.isPro else {
            profiles.applyPremiumAccess(false)
            return
        }
        guard case .edit(let profile) = mode else { return }
        await profiles.archiveProfile(profile)
        if profiles.lastError == nil {
            dismiss()
        }
    }
}

private extension Color {
    init?(hex: String) {
        let cleaned = hex
            .trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            return nil
        }
        let red = Double((value >> 16) & 0xFF) / 255.0
        let green = Double((value >> 8) & 0xFF) / 255.0
        let blue = Double(value & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue)
    }
}

#Preview {
    ProfileSwitcherBar()
        .environmentObject(ManagedProfileStore.shared)
        .environmentObject(SubscriptionManager())
        .padding()
}
