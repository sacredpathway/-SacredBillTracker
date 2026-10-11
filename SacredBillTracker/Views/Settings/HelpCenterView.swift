//
//  HelpCenterView.swift
//  SacredBillTracker
//
//  Offline, searchable feature guide for verified app surfaces. Keep this
//  content aligned with the real SwiftUI navigation and release gates.
//

import SwiftUI

enum HelpFeatureStatus: String {
    case live = "Live"
    case gated = "Requires plan or add-on"
    case prepared = "Prepared, not launched"
    case debugOnly = "Debug only"
}

struct HelpArticle: Identifiable, Hashable {
    let id: String
    let title: String
    let category: String
    let icon: String
    let status: HelpFeatureStatus
    let access: String
    let path: String
    let summary: String
    let steps: [String]
    let tips: [String]
    let limitations: [String]
    let relatedDestination: HelpDestination?

    var searchableText: String {
        ([title, category, access, path, summary] + steps + tips + limitations)
            .joined(separator: " ")
            .lowercased()
    }
}

enum HelpDestination: Hashable {
    case dashboard
    case bills
    case budget
    case calendar
    case reports
    case settings
    case income
    case cpaExport
    case profiles
    case partner
    case receiptJar
    case rewards
    case purchases
}

enum SacredBillTrackerTab: Hashable {
    case dashboard
    case bills
    case budget
    case calendar
    case reports
    case settings
}

@MainActor
final class LearningCenterRouter: ObservableObject {
    @Published var selectedTab: SacredBillTrackerTab = .dashboard

    func open(_ tab: SacredBillTrackerTab) {
        selectedTab = tab
    }
}

struct HelpCenterSettingsLink: View {
    var body: some View {
        NavigationLink {
            HelpCenterView()
        } label: {
            Label("Learning Center", systemImage: "graduationcap.fill")
                .foregroundStyle(Color.appAccentText)
        }
    }
}

enum HelpCenterContent {
    static let categories: [(title: String, icon: String)] = [
        ("Getting Started", "sparkles"),
        ("Bills & Payments", "list.bullet.rectangle.fill"),
        ("Dashboard & Reports", "chart.pie.fill"),
        ("Calendar & Notifications", "calendar.badge.clock"),
        ("Budget & Income", "dollarsign.circle.fill"),
        ("Partners & Profiles", "person.2.fill"),
        ("Receipt Jar", "shippingbox.fill"),
        ("AutoTrack", "building.columns.fill"),
        ("Sacred Focus+", "target"),
        ("Plans & Purchases", "creditcard.fill"),
        ("Settings & Account", "gearshape.fill"),
        ("FAQs & Troubleshooting", "questionmark.bubble.fill")
    ]

    static let articles: [HelpArticle] = [
        HelpArticle(
            id: "account-onboarding",
            title: "Account setup and first bill",
            category: "Getting Started",
            icon: "person.crop.circle.badge.checkmark",
            status: .live,
            access: "Free",
            path: "Launch app -> Create Account, Sign In, or Sign in with Apple. First-run onboarding appears after sign-in.",
            summary: "Create or sign into an account, learn the basic app flow, and add the first bill from onboarding or the Dashboard plus button.",
            steps: [
                "Open Sacred Bill Tracker.",
                "Choose Create Account, Sign In, or Sign in with Apple.",
                "Move through the onboarding cards.",
                "Tap Add My First Bill or use Dashboard -> plus.",
                "Enter name, amount, due date, category, recurrence, and status.",
                "Save the bill to unlock the normal Dashboard experience."
            ],
            tips: [
                "The first-bill celebration confirms the setup worked.",
                "The Learning Center is available without a paid subscription."
            ],
            limitations: [
                "A signed-in account is required for synced account features."
            ],
            relatedDestination: .bills
        ),
        HelpArticle(
            id: "main-navigation",
            title: "Main app navigation",
            category: "Getting Started",
            icon: "square.grid.2x2.fill",
            status: .live,
            access: "Free",
            path: "Bottom tab bar -> Dashboard, Bills, Budget, Calendar, Reports, Settings.",
            summary: "The app is organized into six main tabs, each focused on a financial workflow.",
            steps: [
                "Use Dashboard for the daily overview, focus card, upcoming bills, and widgets.",
                "Use Bills for searching, filtering, sorting, editing, and sharing bills.",
                "Use Budget for budgets, goals, and spending health.",
                "Use Calendar for due dates and calendar export.",
                "Use Reports for monthly totals and category breakdowns.",
                "Use Settings for purchases, profiles, account, appearance, exports, and the Learning Center."
            ],
            tips: [
                "Most screens include the profile switcher when profile-scoped data is supported."
            ],
            limitations: [
                "Some tabs show upgrade prompts when a feature requires a paid tier."
            ],
            relatedDestination: .dashboard
        ),
        HelpArticle(
            id: "add-edit-bills",
            title: "Add and edit bills",
            category: "Bills & Payments",
            icon: "plus.circle.fill",
            status: .live,
            access: "Free with bill limit; Essential and higher remove the free bill cap.",
            path: "Dashboard -> plus, Bills -> plus, or onboarding -> Add My First Bill.",
            summary: "Track each bill with amount, due date, recurrence, category, type, status, notes, payment link, sharing, paydown, and payoff details.",
            steps: [
                "Open Dashboard or Bills.",
                "Tap the plus button.",
                "Enter the bill name, amount, and due date.",
                "Choose Personal or Business, then pick a category.",
                "Choose recurrence and whether the bill uses auto-pay.",
                "Choose unpaid or paid status.",
                "Optionally add notes, a payment link, partner sharing, 15/3 paydown, or payoff tracking.",
                "Tap Save."
            ],
            tips: [
                "Tap an existing bill row to edit it directly.",
                "Business classification requires Business access unless the app's free-limit flags allow it.",
                "Payment links open in Safari; the app never auto-pays."
            ],
            limitations: [
                "Partner-owned shared bills are read-only.",
                "Free users are capped by the current free bill limit."
            ],
            relatedDestination: .bills
        ),
        HelpArticle(
            id: "bills-list",
            title: "Bills list, search, filters, and Trash",
            category: "Bills & Payments",
            icon: "line.3.horizontal.decrease.circle.fill",
            status: .live,
            access: "Free for available bills; paid tiers expand usage.",
            path: "Bills tab.",
            summary: "Search bills, switch between personal and business filters, view My Bills or Shared Bills, sort the list, mark paid, and recover deleted bills.",
            steps: [
                "Open Bills.",
                "Use the Scope picker to switch between My Bills and Shared Bills.",
                "Use the type filter to narrow Personal or Business bills.",
                "Use the Status filter for all, unpaid, paid, or overdue.",
                "Use search to find a bill by text.",
                "Use the sort button to change ordering.",
                "Swipe your own bills to mark paid, mark unpaid, or delete.",
                "Open Settings -> Data -> Trash to review deleted bills."
            ],
            tips: [
                "The share button creates a professional bill summary PDF from the currently visible bills.",
                "Deleted bills are soft-deleted first so they can be restored."
            ],
            limitations: [
                "Shared partner bills hide destructive swipe actions because the other account owns them."
            ],
            relatedDestination: .bills
        ),
        HelpArticle(
            id: "paydown-payoff",
            title: "15/3 paydown and payoff tracking",
            category: "Bills & Payments",
            icon: "creditcard.fill",
            status: .live,
            access: "Available inside the bill form; plan access follows bill access.",
            path: "Add/Edit Bill -> Payoff Tracking and 15/3 Paydown Plan sections.",
            summary: "Track debt balances and optionally split a bill into two planned payments before the due date.",
            steps: [
                "Open a bill or create a new one.",
                "Enable payoff tracking to store original balance, remaining balance, payment amount, interest rate, goal date, and payoff category.",
                "Enable the 15/3 paydown plan to create first and second payment targets.",
                "Save the bill.",
                "Use reminders so the two payment dates do not sneak up on you."
            ],
            tips: [
                "The 15/3 plan can be used on any recurring expense in the current implementation.",
                "Payoff categories include mortgage, auto loan, credit card, personal loan, student loan, and other."
            ],
            limitations: [
                "These tools plan and track payments; they do not move money."
            ],
            relatedDestination: .bills
        ),
        HelpArticle(
            id: "dashboard",
            title: "Dashboard and widgets",
            category: "Dashboard & Reports",
            icon: "rectangle.grid.2x2.fill",
            status: .live,
            access: "Free core dashboard; some cards reflect paid features.",
            path: "Dashboard tab.",
            summary: "See your daily financial overview, focus card, bill health, income, cash flow, and customizable widgets.",
            steps: [
                "Open Dashboard.",
                "Review the daily focus card and financial overview.",
                "Tap plus to add a bill.",
                "Tap the ticket icon to enter a signup or promo code.",
                "Tap the sliders icon when bills exist to customize dashboard widgets.",
                "Tap supported cards to drill into details such as attention items or Focus+."
            ],
            tips: [
                "Long-press a widget to open the customization sheet.",
                "AutoTrack customers can refresh bank income into dashboard totals."
            ],
            limitations: [
                "Advanced widgets and insights can depend on paid tiers or add-ons."
            ],
            relatedDestination: .dashboard
        ),
        HelpArticle(
            id: "reports",
            title: "Reports and category drill-downs",
            category: "Dashboard & Reports",
            icon: "chart.pie.fill",
            status: .gated,
            access: "Reports require the app's report entitlement unless the free-report flag is enabled.",
            path: "Reports tab.",
            summary: "Review monthly personal and business totals, unpaid amounts, and category breakdowns.",
            steps: [
                "Open Reports.",
                "Use the month arrows to pick the reporting month.",
                "Review Personal and Business total cards.",
                "Switch the type selector between Personal and Business.",
                "Tap a category row to view the bills behind that total."
            ],
            tips: [
                "Reports use the same bill classifications from the bill form.",
                "Category drill-downs keep the month and type filter you were viewing."
            ],
            limitations: [
                "If your current plan does not include reports, the app shows an upgrade card."
            ],
            relatedDestination: .reports
        ),
        HelpArticle(
            id: "calendar",
            title: "Bill calendar",
            category: "Calendar & Notifications",
            icon: "calendar",
            status: .live,
            access: "Free for visible bills.",
            path: "Calendar tab.",
            summary: "View bills on a monthly grid and open bills due on a selected day.",
            steps: [
                "Open Calendar.",
                "Use the month arrows to move between months.",
                "Look for dots under days that have due bills.",
                "Tap a day to view the bills due on that date.",
                "Tap a bill row to edit it."
            ],
            tips: [
                "The calendar honors the active bill type filter."
            ],
            limitations: [
                "The app displays due dates; it does not confirm external payment status unless you update the bill."
            ],
            relatedDestination: .calendar
        ),
        HelpArticle(
            id: "calendar-export",
            title: "Send bills to Calendar",
            category: "Calendar & Notifications",
            icon: "calendar.badge.plus",
            status: .live,
            access: "Free for visible bills.",
            path: "Calendar tab -> calendar plus button.",
            summary: "Export bills to writable calendars on the device, including Apple Calendar, Google Calendar, Outlook, or shared calendars configured in iOS.",
            steps: [
                "Open Calendar.",
                "Tap the calendar plus button.",
                "Choose a writable destination calendar.",
                "Tap Add.",
                "Check the status message for success or failure."
            ],
            tips: [
                "Calendar accounts must already be added in iOS Settings.",
                "Only writable calendars appear as destinations."
            ],
            limitations: [
                "Calendar permissions are controlled by iOS."
            ],
            relatedDestination: .calendar
        ),
        HelpArticle(
            id: "notifications",
            title: "Bill reminders and notifications",
            category: "Calendar & Notifications",
            icon: "bell.badge.fill",
            status: .live,
            access: "Free.",
            path: "Settings -> Notifications.",
            summary: "Enable notifications and choose when bill reminders fire before due dates.",
            steps: [
                "Open Settings.",
                "Find the Notifications section.",
                "Enable notifications if iOS has not granted permission yet.",
                "Choose due date, 1 day before, 3 days before, or 7 days before.",
                "The app reschedules reminders for stored bills."
            ],
            tips: [
                "Focus and to-do reminders also use the notification system.",
                "Denied permission must be changed in iOS Settings."
            ],
            limitations: [
                "Notifications depend on iOS permission and delivery behavior."
            ],
            relatedDestination: .settings
        ),
        HelpArticle(
            id: "income",
            title: "Income tracking",
            category: "Budget & Income",
            icon: "dollarsign.circle.fill",
            status: .live,
            access: "Business-oriented income features depend on plan entitlement.",
            path: "Settings -> Financial -> Income Overview, or Dashboard income cards.",
            summary: "Track business and personal income, source names, dates, notes, and totals by period.",
            steps: [
                "Open Settings -> Income Overview.",
                "Tap plus to add an income entry.",
                "Enter amount, date, source name, type, and optional notes.",
                "Save the entry.",
                "Review current-period, last-30-days, all-time, Business, and Personal totals.",
                "Use Settings -> Income Tracking to change period and week start day."
            ],
            tips: [
                "Business and Personal income are stored separately even when dashboard totals are combined.",
                "AutoTrack can add bank income when the user has AutoTrack access."
            ],
            limitations: [
                "Unknown bank income is excluded from Business and Personal split cards until classified."
            ],
            relatedDestination: .income
        ),
        HelpArticle(
            id: "budget",
            title: "Budget dashboard and goals",
            category: "Budget & Income",
            icon: "chart.bar.fill",
            status: .gated,
            access: "Budget capabilities are premium and may depend on Business or Unlimited access.",
            path: "Budget tab.",
            summary: "Plan monthly spending by category, compare budgeted vs actual amounts, monitor health, and track financial goals.",
            steps: [
                "Open Budget.",
                "Choose All, Personal, or Business scope.",
                "Review budget categories and health status.",
                "Create or update category budget amounts.",
                "Create goals such as emergency fund, vacation, house, debt payoff, business expansion, or custom.",
                "Use insights to spot over-budget and warning categories."
            ],
            tips: [
                "Actuals combine paid bills and, where available, Plaid spending.",
                "Goal progress updates against the stored current amount."
            ],
            limitations: [
                "Plaid-derived actuals require AutoTrack connections and backend data."
            ],
            relatedDestination: .budget
        ),
        HelpArticle(
            id: "cpa-export",
            title: "CPA Ready Export",
            category: "Budget & Income",
            icon: "doc.text.magnifyingglass",
            status: .live,
            access: "Available from Settings; advanced export access may depend on tier.",
            path: "Settings -> Financial -> CPA Ready Export.",
            summary: "Generate an accountant-ready PDF covering bills, expenses, income, and profit for a selected date range.",
            steps: [
                "Open Settings.",
                "Tap CPA Ready Export.",
                "Choose the date range and report options.",
                "Include income when needed.",
                "Generate the PDF.",
                "Use the share sheet to send or save it."
            ],
            tips: [
                "This is useful before tax time or accountant meetings.",
                "The export uses bill and income data already stored in the app."
            ],
            limitations: [
                "The report is informational and is not tax advice."
            ],
            relatedDestination: .cpaExport
        ),
        HelpArticle(
            id: "profiles",
            title: "Managed profiles",
            category: "Partners & Profiles",
            icon: "person.3.sequence.fill",
            status: .gated,
            access: "Unlimited/managed-profile entitlement.",
            path: "Settings -> Profiles -> Manage Profiles.",
            summary: "Manage multiple financial profiles such as personal, family, business, property, spouse, or child profiles under one account.",
            steps: [
                "Open Settings.",
                "Use the Profile switcher to choose a working profile.",
                "Tap Manage Profiles if your plan includes it.",
                "Create or edit profiles.",
                "When adding bills or income, choose the profile when the picker is shown."
            ],
            tips: [
                "Profile-scoped views keep data separated while still using one account.",
                "Switch to All Profiles when you want a combined view."
            ],
            limitations: [
                "Profile management is gated for paid tiers."
            ],
            relatedDestination: .profiles
        ),
        HelpArticle(
            id: "partner",
            title: "Partner Budgeting",
            category: "Partners & Profiles",
            icon: "person.2.fill",
            status: .live,
            access: "Available from Settings; each partner uses their own account.",
            path: "Settings -> Partner -> Partner Budgeting.",
            summary: "Invite a partner to budget together and share selected bills between accounts.",
            steps: [
                "Open Settings -> Partner Budgeting.",
                "Create or review a partner invite.",
                "Ask your partner to sign in with their own account.",
                "Open a bill you own and enable Share with partner.",
                "Use Bills -> Shared Bills to view bills shared with you."
            ],
            tips: [
                "Shared bills are intentionally selected bill by bill.",
                "Partner-owned bills are read-only in your account."
            ],
            limitations: [
                "Partner sync depends on the backend being available."
            ],
            relatedDestination: .partner
        ),
        HelpArticle(
            id: "receipt-jar",
            title: "Receipt Jar",
            category: "Receipt Jar",
            icon: "shippingbox.fill",
            status: .gated,
            access: "Separate one-time Receipt Jar add-on.",
            path: "Settings -> Receipts -> Receipt Jar.",
            summary: "Store receipt photos, PDFs, manual entries, OCR text, notes, and bill links in a private receipt cabinet.",
            steps: [
                "Open Settings -> Receipt Jar.",
                "Unlock or restore the Receipt Jar purchase if needed.",
                "Tap Add Manual Receipt, import a photo or file, or use the camera.",
                "Review OCR results before saving.",
                "Link the receipt to a bill when helpful.",
                "Open a receipt detail to edit, delete, view, or share the original."
            ],
            tips: [
                "Receipt metadata is saved with the app's small synced data store.",
                "Original files stay inside the app container.",
                "Payment card text is redacted from recognized OCR text."
            ],
            limitations: [
                "Email receipt finder is documented as a planned workflow and requires production setup before use.",
                "Receipt Jar is a separate add-on from the core subscription plans."
            ],
            relatedDestination: .receiptJar
        ),
        HelpArticle(
            id: "autotrack",
            title: "AutoTrack Premium",
            category: "AutoTrack",
            icon: "building.columns.fill",
            status: .gated,
            access: "Separate AutoTrack subscription/add-on.",
            path: "Settings -> AutoTrack Premium.",
            summary: "Connect a bank account with Plaid to support automatic bill, spending, subscription, and income detection.",
            steps: [
                "Open Settings.",
                "Tap AutoTrack Premium.",
                "Subscribe or manage the AutoTrack add-on if needed.",
                "When active, tap Connect a bank account.",
                "Complete the Plaid connection flow.",
                "Review detected items before treating them as confirmed bills or income."
            ],
            tips: [
                "AutoTrack is separate from the core Essential, Business, and Unlimited plan group.",
                "Dashboard bank income refreshes when AutoTrack is active."
            ],
            limitations: [
                "AutoTrack depends on paid bank-linking and automation services, so it remains separate from core subscription plans."
            ],
            relatedDestination: .settings
        ),
        HelpArticle(
            id: "focus-plus",
            title: "Sacred Focus+",
            category: "Sacred Focus+",
            icon: "target",
            status: .gated,
            access: "Separate Focus+ subscription/add-on.",
            path: "Dashboard -> Daily Focus card or Focus+ paywall entry points.",
            summary: "Use daily plans, schedules, to-dos, focus quotes, reminders, progress tracking, and saved favorite quotes.",
            steps: [
                "Open Dashboard.",
                "Tap the Sacred Daily Focus card.",
                "If subscribed, use Daily Focus Center.",
                "Create schedule items and to-dos.",
                "Set reminders for focus tasks.",
                "Save favorite quotes and review progress."
            ],
            tips: [
                "Focus+ is sold separately from the core plan tiers.",
                "Focus reminders use the same iOS notification permission system."
            ],
            limitations: [
                "Focus+ remains a separate add-on from the core bill-tracking plans."
            ],
            relatedDestination: .dashboard
        ),
        HelpArticle(
            id: "plans",
            title: "Plans, offers, and restore purchases",
            category: "Plans & Purchases",
            icon: "creditcard.fill",
            status: .live,
            access: "Free to view.",
            path: "Settings -> Subscription and privacy -> Purchases, offers and recovery.",
            summary: "Review subscriptions, restore purchases, manage Apple subscriptions, and understand plan access.",
            steps: [
                "Open Settings.",
                "Use Subscription to upgrade, restore, or manage subscriptions.",
                "Open Purchases, offers and recovery for purchase preferences.",
                "Use Restore Purchases after reinstalling or switching devices.",
                "Use Manage Subscription to open Apple's subscription management."
            ],
            tips: [
                "Essential covers manual bill and income basics.",
                "Business adds business/personal separation and business reporting.",
                "Unlimited adds profiles, advanced analytics, goals, exports, and premium themes.",
                "SAVE20 and SAVE40 are promotional offer code campaigns configured in App Store Connect."
            ],
            limitations: [
                "Apple controls subscription cancellation and billing management.",
                "Promo code redemption and eligibility are governed by Apple's rules."
            ],
            relatedDestination: .purchases
        ),
        HelpArticle(
            id: "settings-account",
            title: "Settings, account, support, and appearance",
            category: "Settings & Account",
            icon: "gearshape.fill",
            status: .live,
            access: "Free.",
            path: "Settings tab.",
            summary: "Control notifications, purchases, profiles, income preferences, appearance, rewards, legal links, support, sign out, and account deletion.",
            steps: [
                "Open Settings.",
                "Use Notifications to control reminder timing.",
                "Use Subscription and purchase sections to restore or manage purchases.",
                "Use Financial for income overview and CPA export.",
                "Use Appearance to choose system, light, or dark mode.",
                "Use About for version, website, privacy, terms, and support email.",
                "Use Sign Out or Delete Account only when needed."
            ],
            tips: [
                "Delete Account is intentionally placed near the bottom as a destructive action.",
                "Support opens an email to sacredbilltracker@gmail.com."
            ],
            limitations: [
                "Deleting an account permanently removes sign-in and account data copies."
            ],
            relatedDestination: .settings
        ),
        HelpArticle(
            id: "rewards",
            title: "Earn Rewards",
            category: "Settings & Account",
            icon: "gift.fill",
            status: .live,
            access: "Free to view.",
            path: "Settings -> Help and referrals -> Earn Rewards.",
            summary: "Referral surface for sharing the app and earning rewards when friends subscribe with your code.",
            steps: [
                "Open Settings.",
                "Tap Earn Rewards.",
                "Review your referral information.",
                "Share your code using the available share options."
            ],
            tips: [
                "The current Settings copy describes Give $5, get $5 when friends subscribe with your code."
            ],
            limitations: [
                "Actual reward eligibility depends on the referral service configuration."
            ],
            relatedDestination: .rewards
        ),
        HelpArticle(
            id: "feature-directory",
            title: "Feature directory and plan labels",
            category: "FAQs & Troubleshooting",
            icon: "list.bullet.rectangle.portrait.fill",
            status: .live,
            access: "Free to view. Feature access follows each article's label.",
            path: "Settings -> Help and referrals -> Learning Center.",
            summary: "Use Learning Center search, categories, and access labels to find every verified app feature and understand whether it is Free, Essential, Business, Unlimited, or an add-on.",
            steps: [
                "Open Settings.",
                "Tap Learning Center.",
                "Search for words like budget, receipts, AutoTrack, profiles, reports, reminder, or offer code.",
                "Browse categories when you are not sure what a feature is called.",
                "Open an article and read the access line before following the steps.",
                "Use Take Me There only when it points to a supported in-app destination."
            ],
            tips: [
                "Learning Center content is bundled in the app and remains available offline.",
                "Prepared features are marked as prepared instead of being advertised as live."
            ],
            limitations: [
                "The Learning Center cannot override subscription, sign-in, Apple billing, or backend availability rules."
            ],
            relatedDestination: .settings
        ),
        HelpArticle(
            id: "faq-upgrade-restore",
            title: "FAQ: upgrades, restores, and offer codes",
            category: "FAQs & Troubleshooting",
            icon: "creditcard.trianglebadge.exclamationmark",
            status: .live,
            access: "Free to read. Purchases and eligibility are controlled by Apple.",
            path: "Settings -> Subscription and privacy -> Purchases, offers and recovery.",
            summary: "Know what to do after upgrading, reinstalling, changing phones, or redeeming a promotional offer.",
            steps: [
                "Open Settings.",
                "Tap Restore Purchases after reinstalling or switching devices.",
                "Use Manage Subscription when you need to cancel, renew, or review Apple's billing status.",
                "Enter signup or promo codes only through supported purchase or offer-code entry points.",
                "If access does not update immediately, restore purchases and reopen the app.",
                "Contact support if Apple shows an active purchase but the app still does not unlock after restore."
            ],
            tips: [
                "SAVE20 and SAVE40 are Apple promotional offer-code campaigns, so eligibility can depend on Apple's subscription history rules."
            ],
            limitations: [
                "The app cannot cancel an Apple subscription for you.",
                "The app cannot force Apple to make a promotional code eligible for every account."
            ],
            relatedDestination: .purchases
        ),
        HelpArticle(
            id: "troubleshooting-common",
            title: "Troubleshooting common issues",
            category: "FAQs & Troubleshooting",
            icon: "wrench.and.screwdriver.fill",
            status: .live,
            access: "Free.",
            path: "Settings -> Help and referrals -> Learning Center, Settings -> About -> Support.",
            summary: "Fix the most common issues with missing bills, reminders, reports, receipts, bank connections, and account access.",
            steps: [
                "If a bill is missing, check Bills filters, Shared Bills, profile selection, and Trash.",
                "If reminders are missing, check Settings -> Notifications and iOS notification permission.",
                "If reports are locked, confirm your plan includes reports or restore purchases.",
                "If Receipt Jar is locked, restore the Receipt Jar add-on purchase.",
                "If AutoTrack is unavailable, confirm the AutoTrack add-on is active and the bank connection is working.",
                "If profile data looks incomplete, switch back to All Profiles or the correct profile.",
                "If none of that works, use Settings -> About -> Support."
            ],
            tips: [
                "Filters and profile selection are the most common reason data looks missing.",
                "Apple billing changes can take a moment to sync; Restore Purchases is the safest first step."
            ],
            limitations: [
                "Support cannot see private financial records unless you choose to share details."
            ],
            relatedDestination: .settings
        ),
        HelpArticle(
            id: "faq-data-privacy",
            title: "FAQ: data, privacy, and safety",
            category: "FAQs & Troubleshooting",
            icon: "hand.raised.fill",
            status: .live,
            access: "Free.",
            path: "Settings -> About -> Privacy Policy, Terms of Use, and Support.",
            summary: "Understand what the app does and does not do with bills, bank connections, receipts, exports, and payment links.",
            steps: [
                "Use payment links as shortcuts only; the app does not pay bills automatically.",
                "Review Receipt Jar OCR text before saving.",
                "Use CPA Ready Export when you intentionally want to share a PDF with an accountant or advisor.",
                "Use AutoTrack only when you want to connect a bank account through Plaid.",
                "Open Privacy Policy and Terms from Settings before sharing sensitive data."
            ],
            tips: [
                "Receipt Jar redacts recognized payment-card text from OCR results.",
                "Partner Budgeting shares only selected bills."
            ],
            limitations: [
                "CPA exports and in-app insights are informational and are not tax, legal, or financial advice."
            ],
            relatedDestination: .settings
        )
    ]
}

struct HelpCenterView: View {
    @State private var searchText = ""

    private var groupedArticles: [(category: String, icon: String, articles: [HelpArticle])] {
        let filtered = filteredArticles
        return HelpCenterContent.categories.compactMap { category in
            let items = filtered.filter { $0.category == category.title }
            guard !items.isEmpty else { return nil }
            return (category.title, category.icon, items)
        }
    }

    private var filteredArticles: [HelpArticle] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return HelpCenterContent.articles }
        return HelpCenterContent.articles.filter { $0.searchableText.contains(query) }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Sacred Bill Tracker Learning Center", systemImage: "graduationcap.fill")
                        .font(.headline)
                        .foregroundStyle(Color.appAccentText)
                        .accessibilityIdentifier("learningCenterHeroTitle")
                    Text("Search verified instructions, plan access, navigation paths, FAQs, and troubleshooting for released, gated, and prepared app features.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        Label("\(HelpCenterContent.articles.count) topics", systemImage: "book.closed.fill")
                        Spacer(minLength: 12)
                        Label("\(HelpCenterContent.categories.count) categories", systemImage: "square.grid.2x2.fill")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section {
                TextField("Search features", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("helpCenterSearchField")
            }
            .accessibilityIdentifier("helpCenterSearchSection")

            Section("Feature directory") {
                ForEach(HelpCenterContent.categories, id: \.title) { category in
                    let count = HelpCenterContent.articles.filter { $0.category == category.title }.count
                    HStack {
                        Label(category.title, systemImage: category.icon)
                        Spacer()
                        Text("\(count)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("learningCenterDirectory-\(Self.identifierSlug(category.title))")
                }
            }

            if groupedArticles.isEmpty {
                ContentUnavailableView(
                    "No Help Topics",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different search term.")
                )
                .accessibilityIdentifier("helpCenterEmptyResults")
            } else {
                ForEach(groupedArticles, id: \.category) { group in
                    Section {
                        ForEach(group.articles) { article in
                            NavigationLink {
                                HelpArticleDetailView(article: article)
                            } label: {
                                HelpArticleRow(article: article)
                            }
                            .accessibilityIdentifier("helpCenterArticleRow-\(article.id)")
                        }
                    } header: {
                        Label(group.category, systemImage: group.icon)
                            .accessibilityIdentifier("helpCenterCategory-\(Self.identifierSlug(group.category))")
                    }
                }
            }
        }
        .accessibilityIdentifier("helpCenterList")
        .navigationTitle("Learning Center")
    }

    private static func identifierSlug(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }
}

private struct HelpArticleRow: View {
    let article: HelpArticle

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: article.icon)
                .font(.title3)
                .foregroundStyle(Color.appAccentText)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(article.title)
                    .font(.subheadline.weight(.semibold))
                Text(article.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(article.status.rawValue)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
                Text(article.access)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch article.status {
        case .live: return .green
        case .gated: return Color.appAccentText
        case .prepared: return .orange
        case .debugOnly: return .secondary
        }
    }
}

private struct HelpArticleDetailView: View {
    @EnvironmentObject private var learningRouter: LearningCenterRouter
    @EnvironmentObject private var store: BillStore
    @EnvironmentObject private var incomeStore: IncomeStore
    @EnvironmentObject private var profileStore: ManagedProfileStore
    @EnvironmentObject private var subs: SubscriptionManager
    @EnvironmentObject private var auth: AuthService

    let article: HelpArticle

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label(article.title, systemImage: article.icon)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(Color.appAccentText)
                        .accessibilityIdentifier("helpArticleTitle-\(article.id)")
                    Text(article.summary)
                        .font(.body)
                    statusLine
                }
                .padding(.vertical, 4)
            }

            Section("Where to find it") {
                Text(article.path)
            }

            Section("Access") {
                statusLine
            }

            Section("How to use it") {
                ForEach(Array(article.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.appOnGold)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Color.appAccentText))
                        Text(step)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("helpArticleStep-\(article.id)-\(index + 1)")
                }
            }

            if !article.tips.isEmpty {
                Section("Tips") {
                    ForEach(article.tips, id: \.self) { tip in
                        Label(tip, systemImage: "lightbulb.fill")
                    }
                }
            }

            if !article.limitations.isEmpty {
                Section("Limitations") {
                    ForEach(article.limitations, id: \.self) { limitation in
                        Label(limitation, systemImage: "exclamationmark.triangle.fill")
                    }
                }
            }

            if let destination = article.relatedDestination {
                Section("Take Me There") {
                    relatedLink(destination)
                }
            }
        }
        .accessibilityIdentifier("helpArticleDetail-\(article.id)")
        .navigationTitle(article.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusLine: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(article.status.rawValue, systemImage: "checkmark.seal.fill")
            Label(article.access, systemImage: "lock.open.fill")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func relatedLink(_ destination: HelpDestination) -> some View {
        switch destination {
        case .dashboard:
            Button {
                learningRouter.open(.dashboard)
            } label: {
                Label("Open Dashboard", systemImage: "square.grid.2x2.fill")
            }
        case .bills:
            Button {
                learningRouter.open(.bills)
            } label: {
                Label("Open Bills", systemImage: "list.bullet.rectangle.fill")
            }
        case .budget:
            Button {
                learningRouter.open(.budget)
            } label: {
                Label("Open Budget", systemImage: "chart.bar.fill")
            }
        case .calendar:
            Button {
                learningRouter.open(.calendar)
            } label: {
                Label("Open Calendar", systemImage: "calendar")
            }
        case .reports:
            Button {
                learningRouter.open(.reports)
            } label: {
                Label("Open Reports", systemImage: "chart.pie.fill")
            }
        case .settings:
            Button {
                learningRouter.open(.settings)
            } label: {
                Label("Open Settings", systemImage: "gearshape.fill")
            }
        case .income:
            NavigationLink("Open Income Overview") {
                IncomeListView()
                    .environmentObject(incomeStore)
            }
        case .cpaExport:
            NavigationLink("Open CPA Ready Export") {
                CPAReadyExportView()
                    .environmentObject(store)
                    .environmentObject(incomeStore)
            }
        case .profiles:
            NavigationLink("Open Manage Profiles") {
                ManagedProfilesView()
                    .environmentObject(profileStore)
                    .environmentObject(subs)
            }
        case .partner:
            NavigationLink("Open Partner Budgeting") {
                PartnerBudgetingView(
                    service: PartnerService(
                        currentUserId: auth.currentUserID?.uuidString ?? ""
                    )
                )
            }
        case .receiptJar:
            NavigationLink("Open Receipt Jar") {
                ReceiptJarView()
                    .environmentObject(subs)
                    .environmentObject(store)
            }
        case .rewards:
            NavigationLink("Open Earn Rewards") {
                EarnRewardsView()
            }
        case .purchases:
            NavigationLink("Open Purchases, offers and recovery") {
                SBTAccountPreferences()
            }
        }
    }
}

#Preview {
    NavigationStack {
        HelpCenterView()
    }
    .environmentObject(BillStore())
    .environmentObject(IncomeStore())
    .environmentObject(ManagedProfileStore.shared)
    .environmentObject(NotificationManager.shared)
    .environmentObject(AuthService.shared)
    .environmentObject(SubscriptionManager())
    .environmentObject(LearningCenterRouter())
}
