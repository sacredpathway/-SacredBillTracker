import SwiftUI

// Existing type name retained internally to avoid project-file churn. No quote APIs.
@MainActor
final class QuoteService: ObservableObject {
    static let shared = QuoteService()
    @Published private(set) var quote: FinancialLesson
    private init() {
        UserDefaults.standard.removeObject(forKey: "sbt.quote.cached.v1")
        quote = FinancialEducation.lesson(day: FinancialEducation.day())
    }
    func refreshInBackground() {
        quote = FinancialEducation.lesson(day: FinancialEducation.day())
    }
}

struct FinancialEducationView: View {
    @State private var category = "All categories"
    @State private var savedOnly = false
    @AppStorage("sbt.education.favorites.v1") private var savedIDs = ""
    private var saved: Set<String> { Set(savedIDs.split(separator: ",").map(String.init)) }
    private var lessons: [FinancialLesson] {
        FinancialEducation.all.filter {
            (category == "All categories" || $0.category == category) && (!savedOnly || saved.contains($0.id))
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Financial Education").font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text(FinancialEducation.lesson(day: FinancialEducation.day()).text)
                .font(.body).fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("Browse and save lessons") {
            Picker("Category", selection: $category) {
                Text("All categories").tag("All categories")
                ForEach(FinancialEducation.categories, id: \.self) { Text($0).tag($0) }
            }
            Toggle("Saved lessons only", isOn: $savedOnly)
            DisclosureGroup("About Financial Education") {
                Text(FinancialEducation.disclosure)
                    .font(.body).fixedSize(horizontal: false, vertical: true)
                Link("Learn more at the CFPB", destination: URL(string: "https://www.consumerfinance.gov/consumer-tools/")!)
                Link("Investing basics at Investor.gov", destination: URL(string: "https://www.investor.gov/introduction-investing")!)
            }
            if lessons.isEmpty { Text("No saved lessons in this category yet.").foregroundStyle(.secondary) }
            LazyVStack(alignment: .leading, spacing: 16) {
            ForEach(lessons) { lesson in
                VStack(alignment: .leading, spacing: 10) {
                    Text(lesson.category).font(.caption.bold())
                    Text(lesson.text).font(.body).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(saved.contains(lesson.id) ? "Unsave lesson" : "Save lesson") {
                            var values = saved
                            if !values.insert(lesson.id).inserted { values.remove(lesson.id) }
                            savedIDs = values.sorted().joined(separator: ",")
                            if values.contains(lesson.id) { AnalyticsService.shared.track(.educationSaved, source: "education") }
                        }
                        .accessibilityLabel(saved.contains(lesson.id) ? "Unsave \(lesson.category) lesson" : "Save \(lesson.category) lesson")
                        Spacer()
                        ShareLink(item: lesson.shareText) { Label("Share", systemImage: "square.and.arrow.up") }
                            .simultaneousGesture(TapGesture().onEnded {
                                AnalyticsService.shared.track(.educationShared, source: "education")
                            })
                    }.buttonStyle(.bordered)
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
            }
            }
        }
        .onAppear { AnalyticsService.shared.track(.educationViewed, source: "education") }
    }
}
