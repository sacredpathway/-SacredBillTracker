#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CHECKS = [
    (
        "App init configures AppsFlyer",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        "AppsFlyerManager.shared.configure()",
    ),
    (
        "Active scene starts AppsFlyer",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        "AppsFlyerManager.shared.requestATTThenStart()",
    ),
    (
        "Registration event uses AppsFlyer standard name",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        'logEvent("af_complete_registration"',
    ),
    (
        "Bill event uses custom app name",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        'logEvent("bill_created"',
    ),
    (
        "Income event uses custom app name",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        'logEvent("income_created"',
    ),
    (
        "Subscription event uses AppsFlyer standard name",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        'logEvent("af_subscribe"',
    ),
    (
        "Purchase event uses AppsFlyer standard name",
        ROOT / "SacredBillTracker" / "SacredBillTrackerApp.swift",
        'logEvent("af_purchase"',
    ),
    (
        "Signup flow logs registration",
        ROOT / "SacredBillTracker" / "Services" / "AuthService.swift",
        "AppsFlyerManager.shared.logAccountCreated()",
    ),
    (
        "Bill creation flow logs bill_created",
        ROOT / "SacredBillTracker" / "Services" / "BillStore.swift",
        "AppsFlyerManager.shared.logBillCreated()",
    ),
    (
        "Income creation flow logs income_created",
        ROOT / "SacredBillTracker" / "Services" / "IncomeStore.swift",
        "AppsFlyerManager.shared.logIncomeCreated()",
    ),
    (
        "Subscription purchase flow logs af_subscribe",
        ROOT / "SacredBillTracker" / "Services" / "StoreKit" / "SubscriptionManager.swift",
        "AppsFlyerManager.shared.logSubscriptionStarted(",
    ),
    (
        "Subscription purchase flow logs af_purchase",
        ROOT / "SacredBillTracker" / "Services" / "StoreKit" / "SubscriptionManager.swift",
        "AppsFlyerManager.shared.logPurchase(",
    ),
]


def main() -> int:
    failures = []
    for label, path, needle in CHECKS:
        text = path.read_text()
        if needle not in text:
            failures.append(f"{label}: missing {needle!r} in {path.relative_to(ROOT)}")

    if failures:
        print("AppsFlyer local validation FAILED")
        for failure in failures:
            print(f"- {failure}")
        return 1

    print("AppsFlyer local validation PASSED")
    for label, _, _ in CHECKS:
        print(f"- {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
