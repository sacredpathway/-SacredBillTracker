//
//  IncomeOwnershipAuthLoadingTests.swift
//  SacredBillTrackerTests
//
//  Regression lock for the second "$0 income" bug.
//
//  `IncomeStore.profileEntries` used to open with:
//
//      guard profileContext.ownerID != nil else { return [] }
//
//  `ownerID` is nil for the *entire* cold-launch window while
//  `AuthService.bootstrap()` awaits the Supabase session — not just when
//  signed out. So every monthly income total rendered $0 on launch, while
//  bills stayed visible (`BillStore.isOwnedByCurrentAccount` returns `true`
//  when `currentUserID` is nil).
//
//  The fix introduces a tri-state: unresolved / signedOut / signedIn.
//  These tests pin all three, and in particular pin that the permissive
//  branch exists ONLY in `.unresolved` — never after auth resolves.
//
//  Pure logic against `ManagedProfileContext.canRead`. No store, no
//  UserDefaults, no Supabase, no MainActor.
//

import XCTest
@testable import SacredBillTracker

final class IncomeOwnershipAuthLoadingTests: XCTestCase {

    // MARK: - Fixture

    private let ownerA = UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!
    private let ownerB = UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000002")!

    /// `.allProfiles` so `includes(profileID:)` never interferes — these
    /// tests are about ownership, not profile partitioning.
    private func context(ownerID: UUID?, resolved: Bool) -> ManagedProfileContext {
        ManagedProfileContext(
            ownerID: ownerID,
            selection: .allProfiles,
            defaultProfileID: nil,
            isOwnerResolved: resolved
        )
    }

    private var unresolved: ManagedProfileContext { context(ownerID: nil, resolved: false) }
    private var signedOut: ManagedProfileContext { context(ownerID: nil, resolved: true) }
    private var signedInAsA: ManagedProfileContext { context(ownerID: ownerA, resolved: true) }

    // MARK: - Owner state mapping

    func test_ownerState_distinguishesUnresolvedFromSignedOut() {
        XCTAssertEqual(unresolved.ownerState, .unresolved)
        XCTAssertEqual(signedOut.ownerState, .signedOut)
        XCTAssertEqual(signedInAsA.ownerState, .signedIn(ownerA))
    }

    // MARK: - 1. Cold launch must not zero the current user's income

    func test_coldLaunch_unresolvedOwner_keepsLastKnownOwnersIncome() {
        XCTAssertTrue(
            unresolved.canRead(rowOwnerID: ownerA, lastKnownOwnerID: ownerA),
            "During session restore the signed-in user's income MUST stay visible — this is the $0 bug"
        )
    }

    func test_coldLaunch_unresolvedOwner_keepsUnownedLocalRows() {
        XCTAssertTrue(
            unresolved.canRead(rowOwnerID: nil, lastKnownOwnerID: ownerA),
            "Legacy / local-only entries have no owner stamp and must never disappear"
        )
        XCTAssertTrue(
            unresolved.canRead(rowOwnerID: nil, lastKnownOwnerID: nil),
            "…even on a device that has never signed in"
        )
    }

    // MARK: - 2. The restore window is still not a free-for-all

    func test_coldLaunch_unresolvedOwner_hidesOtherUsersIncome() {
        XCTAssertFalse(
            unresolved.canRead(rowOwnerID: ownerB, lastKnownOwnerID: ownerA),
            "Restore window admits only the LAST KNOWN owner's rows, not any owner's"
        )
    }

    func test_coldLaunch_withNoLastKnownOwner_hidesAllOwnedRows() {
        XCTAssertFalse(
            unresolved.canRead(rowOwnerID: ownerA, lastKnownOwnerID: nil),
            "No cached owner → no owned rows may be read"
        )
    }

    // MARK: - 3. Once resolved, strict filtering still protects data

    func test_signedIn_readsOwnRows() {
        XCTAssertTrue(signedInAsA.canRead(rowOwnerID: ownerA, lastKnownOwnerID: ownerA))
    }

    func test_signedIn_cannotReadAnotherUsersRows() {
        XCTAssertFalse(
            signedInAsA.canRead(rowOwnerID: ownerB, lastKnownOwnerID: ownerA),
            "Owner filtering MUST stay strict after auth resolves"
        )
    }

    /// The restore-window hint must not be able to widen a resolved session.
    /// Even if `lastKnownOwnerID` names user B, a session owned by A sees only A.
    func test_signedIn_lastKnownOwnerCannotWidenAccess() {
        XCTAssertFalse(signedInAsA.canRead(rowOwnerID: ownerB, lastKnownOwnerID: ownerB))
        XCTAssertTrue(signedInAsA.canRead(rowOwnerID: ownerA, lastKnownOwnerID: ownerB))
    }

    /// Unowned rows are adopted by the signed-in user — pre-existing behavior,
    /// unchanged by this fix. Locks it so the refactor didn't drift.
    func test_signedIn_adoptsUnownedLegacyRows() {
        XCTAssertTrue(signedInAsA.canRead(rowOwnerID: nil, lastKnownOwnerID: nil))
        XCTAssertTrue(signedInAsA.owns(ownerID: nil))
        XCTAssertTrue(signedInAsA.owns(ownerID: ownerA))
        XCTAssertFalse(signedInAsA.owns(ownerID: ownerB))
    }

    // MARK: - 4. Sign-out must not leak the previous owner's income

    func test_signedOut_hidesPreviousOwnersIncome() {
        XCTAssertFalse(
            signedOut.canRead(rowOwnerID: ownerA, lastKnownOwnerID: nil),
            "signOut() clears the cache; the prior user's income must vanish"
        )
    }

    /// Defense in depth: even if `SessionOwnerCache.clear()` were somehow
    /// skipped, a *resolved* signed-out context must still refuse owned rows.
    /// The permissive branch lives only in `.unresolved`.
    func test_signedOut_ignoresStaleLastKnownOwner() {
        XCTAssertFalse(
            signedOut.canRead(rowOwnerID: ownerA, lastKnownOwnerID: ownerA),
            "A stale cached owner must NOT resurrect the previous user's rows"
        )
    }

    func test_signedOut_stillShowsUnownedLocalRows() {
        XCTAssertTrue(
            signedOut.canRead(rowOwnerID: nil, lastKnownOwnerID: nil),
            "Income entered before ever signing in belongs to this device"
        )
    }

    // MARK: - 5. `owns()` is untouched — bill ownership cannot have regressed

    /// `BillStore.isOwnedByCurrentAccount` reads `AuthService.currentUserID`
    /// directly and never calls `canRead` / `ownerState`. The only shared
    /// surface is `owns(ownerID:)`, whose contract is pinned here: nil owner
    /// context denies everything, exactly as before.
    func test_owns_contractUnchanged_forNilOwnerContext() {
        XCTAssertFalse(unresolved.owns(ownerID: ownerA))
        XCTAssertFalse(unresolved.owns(ownerID: nil))
        XCTAssertFalse(signedOut.owns(ownerID: ownerA))
        XCTAssertFalse(signedOut.owns(ownerID: nil))
    }

    /// `isOwnerResolved` defaults to `true`, so every pre-existing
    /// construction site keeps strict behavior without being updated.
    func test_isOwnerResolved_defaultsToTrue() {
        let legacy = ManagedProfileContext(
            ownerID: ownerA,
            selection: .allProfiles,
            defaultProfileID: nil
        )
        XCTAssertTrue(legacy.isOwnerResolved)
        XCTAssertEqual(legacy.ownerState, .signedIn(ownerA))
    }

    // MARK: - 6. The profile partition must not re-introduce the $0 bug

    private let localProfile  = UUID(uuidString: "CCCCCCCC-0000-0000-0000-000000000003")!
    private let serverProfile = UUID(uuidString: "DDDDDDDD-0000-0000-0000-000000000004")!

    /// Cold launch: `ManagedProfileStore` has only the device-local default
    /// profile, so selection collapses to `.profile(localProfile)`. An income
    /// row saved in a previous signed-in session carries `serverProfile`.
    private var restoringWithLocalProfileOnly: ManagedProfileContext {
        ManagedProfileContext(
            ownerID: nil,
            selection: .profile(localProfile),
            defaultProfileID: localProfile,
            isOwnerResolved: false
        )
    }

    /// Regression: ownership alone is not enough. `includes(profileID:)`
    /// rejects the server-stamped row during restore, which would leave
    /// monthly income at $0 even with `canRead` returning true.
    func test_restoreWindow_profileFilterWouldDropServerStampedRow() {
        XCTAssertTrue(
            restoringWithLocalProfileOnly.canRead(rowOwnerID: ownerA, lastKnownOwnerID: ownerA),
            "Ownership permits the row…"
        )
        XCTAssertFalse(
            restoringWithLocalProfileOnly.includes(profileID: serverProfile),
            "…but the profile partition would still drop it — this is the trap"
        )
    }

    func test_restoreWindow_canReadIncome_keepsServerStampedRow() {
        XCTAssertTrue(
            restoringWithLocalProfileOnly.canReadIncome(
                rowOwnerID: ownerA,
                rowProfileID: serverProfile,
                lastKnownOwnerID: ownerA
            ),
            "Monthly income MUST survive cold launch even for server-profile rows"
        )
    }

    /// Relaxing the partition must not relax ownership.
    func test_restoreWindow_canReadIncome_stillRejectsOtherOwners() {
        XCTAssertFalse(
            restoringWithLocalProfileOnly.canReadIncome(
                rowOwnerID: ownerB,
                rowProfileID: serverProfile,
                lastKnownOwnerID: ownerA
            ),
            "Another user's row stays hidden regardless of profile"
        )
    }

    /// Once resolved, the profile partition is enforced again.
    func test_resolved_canReadIncome_enforcesProfilePartition() {
        let signedInOnLocalProfile = ManagedProfileContext(
            ownerID: ownerA,
            selection: .profile(localProfile),
            defaultProfileID: localProfile,
            isOwnerResolved: true
        )
        XCTAssertTrue(signedInOnLocalProfile.canReadIncome(
            rowOwnerID: ownerA, rowProfileID: localProfile, lastKnownOwnerID: ownerA))
        XCTAssertFalse(
            signedInOnLocalProfile.canReadIncome(
                rowOwnerID: ownerA, rowProfileID: serverProfile, lastKnownOwnerID: ownerA),
            "After auth resolves, a row in a non-selected profile is filtered out again"
        )
    }

    func test_signedOut_canReadIncome_hidesPriorOwnerRegardlessOfProfile() {
        let out = ManagedProfileContext(
            ownerID: nil,
            selection: .allProfiles,
            defaultProfileID: nil,
            isOwnerResolved: true
        )
        XCTAssertFalse(out.canReadIncome(
            rowOwnerID: ownerA, rowProfileID: serverProfile, lastKnownOwnerID: ownerA))
        XCTAssertTrue(out.canReadIncome(
            rowOwnerID: nil, rowProfileID: nil, lastKnownOwnerID: nil))
    }
}
