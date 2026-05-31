//
//  SacredBillTrackerWidgetBundle.swift
//  SacredBillTrackerWidgets
//
//  Entry point — Apple's plist points NSExtensionPrincipalClass at the
//  WidgetBundle's auto-generated objc class.
//

import SwiftUI
import WidgetKit

@main
struct SacredBillTrackerWidgetBundle: WidgetBundle {
    var body: some Widget {
        SacredBillTrackerWidget()
        BillsDueTodayWidget()
        UpcomingBillsWidget()
        BillHealthScoreHomeWidget()
        MonthlySpendingWidget()
        IncomeTrackerWidget()
    }
}
