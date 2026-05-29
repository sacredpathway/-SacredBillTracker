//
//  Date+Helpers.swift
//  SacredBillTracker
//

import Foundation

extension Date {
    var shortDayMonth: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: self)
    }

    var longMonthYear: String {
        let f = DateFormatter()
        f.dateFormat = "LLLL yyyy"
        return f.string(from: self)
    }

    var mediumFormatted: String {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: self)
    }

    func isSameDay(as other: Date) -> Bool {
        Calendar.current.isDate(self, inSameDayAs: other)
    }

    func isSameMonth(as other: Date) -> Bool {
        let cal = Calendar.current
        return cal.component(.year, from: self)  == cal.component(.year, from: other)
            && cal.component(.month, from: self) == cal.component(.month, from: other)
    }
}
