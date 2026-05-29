//
//  ContentView.swift
//  SacredBillTracker
//
//  Root TabView: Dashboard · Bills · Calendar · Reports · Settings
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject private var store: BillStore

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.2x2.fill") }

            BillsView()
                .tabItem { Label("Bills", systemImage: "list.bullet.rectangle.fill") }

            CalendarView()
                .tabItem { Label("Calendar", systemImage: "calendar") }

            ReportsView()
                .tabItem { Label("Reports", systemImage: "chart.pie.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(BillStore())
        .environmentObject(IncomeStore())
        .environmentObject(NotificationManager.shared)
        .environmentObject(AuthService.shared)
        .environmentObject(SubscriptionManager())
}
