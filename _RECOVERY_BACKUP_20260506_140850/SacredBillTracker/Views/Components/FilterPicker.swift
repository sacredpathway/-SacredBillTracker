//
//  FilterPicker.swift
//  SacredBillTracker
//

import SwiftUI

struct FilterPicker: View {
    @Binding var selection: BillTypeFilter

    var body: some View {
        Picker("Filter", selection: $selection) {
            ForEach(BillTypeFilter.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}

#Preview {
    @Previewable @State var sel: BillTypeFilter = .all
    return FilterPicker(selection: $sel).padding()
}
