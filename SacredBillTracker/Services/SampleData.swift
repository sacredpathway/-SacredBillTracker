//
//  SampleData.swift
//  SacredBillTracker
//
//  DEBUG-only fixtures used for SwiftUI previews and local development.
//
//  ⚠️ This entire file is wrapped in `#if DEBUG` so the symbols literally
//  do not exist in App Store / TestFlight (Release) builds. There is no
//  way for production code to accidentally seed these bills into a real
//  user's account, because the type is not present at link time.
//
//  Curated for App Store screenshot capture: a clean 7-bill household
//  set with a balanced mix of Paid / Upcoming / Overdue and amounts in
//  the $45–$1,650 range so the Dashboard reads visually balanced
//  (not empty, not chaotic).
//

import Foundation

#if DEBUG

enum SampleData {

    static func bills(relativeTo today: Date = Date()) -> [Bill] {
        let cal = Calendar.current
        func date(_ offsetDays: Int) -> Date {
            cal.date(byAdding: .day, value: offsetDays, to: today) ?? today
        }

        return [
            // 1. Rent — biggest line item, unpaid, due next week
            Bill(
                name: "Rent",
                amount: 1650.00,
                dueDate: date(5),
                category: .rent,
                recurrence: .monthly,
                type: .household,
                autoPay: false,
                notes: "",
                status: .unpaid
            ),

            // 2. Auto Loan — unpaid, mid-month
            Bill(
                name: "Auto Loan",
                amount: 548.50,
                dueDate: date(12),
                category: .transportation,
                recurrence: .monthly,
                type: .household,
                autoPay: false,
                notes: "",
                status: .unpaid,
                isPayoffTrackingEnabled: true,
                payoffOriginalBalance: 28500.00,
                payoffRemainingBalance: 22000.00,
                payoffPaymentAmount: 548.50,
                payoffInterestRate: 6.49,
                payoffCategory: .autoLoan
            ),

            // 3. Car Insurance — paid recently (within last 7 days for the
            //    "Paid recently" insight tag).
            Bill(
                name: "Car Insurance",
                amount: 182.40,
                dueDate: date(8),
                category: .insurance,
                recurrence: .monthly,
                type: .household,
                autoPay: true,
                notes: "",
                status: .paid,
                lastPaidDate: date(-2)
            ),

            // 4. Phone — paid recently, autopay
            Bill(
                name: "Phone",
                amount: 89.99,
                dueDate: date(15),
                category: .phone,
                recurrence: .monthly,
                type: .household,
                autoPay: true,
                notes: "",
                status: .paid,
                lastPaidDate: date(-3)
            ),

            // 5. Electric — overdue (3 days past due, unpaid). Drives the
            //    Overdue stat card to a non-zero value.
            Bill(
                name: "Electric",
                amount: 156.78,
                dueDate: date(-3),
                category: .utilities,
                recurrence: .monthly,
                type: .household,
                autoPay: false,
                notes: "",
                status: .unpaid
            ),

            // 6. Internet — unpaid, upcoming
            Bill(
                name: "Internet",
                amount: 79.99,
                dueDate: date(7),
                category: .internet,
                recurrence: .monthly,
                type: .household,
                autoPay: false,
                notes: "",
                status: .unpaid
            ),

            // 7. Streaming — paid recently, smallest line item
            Bill(
                name: "Streaming",
                amount: 45.99,
                dueDate: date(20),
                category: .subscriptions,
                recurrence: .monthly,
                type: .household,
                autoPay: true,
                notes: "",
                status: .paid,
                lastPaidDate: date(-1)
            )
        ]
    }
}

#endif
