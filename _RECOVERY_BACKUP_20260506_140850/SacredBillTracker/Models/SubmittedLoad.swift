//
//  SubmittedLoad.swift
//  SacredBillTracker
//
//  A load submitted by a driver for payroll processing.
//  Maps to the `submitted_loads` Supabase table.
//
//  Supabase schema (run once in SQL editor):
//
//  CREATE TABLE public.submitted_loads (
//      id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
//      driver_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
//      driver_name     text NOT NULL DEFAULT '',
//      load_number     text NOT NULL,
//      pickup          text NOT NULL,
//      delivery        text NOT NULL,
//      load_date       timestamptz NOT NULL,
//      gross_amount    numeric(14,2),          -- nullable: admin can fill in later
//      miles           numeric(10,1) NOT NULL DEFAULT 0,
//      status          text NOT NULL DEFAULT 'submitted',
//      notes           text NOT NULL DEFAULT '',
//      created_at      timestamptz NOT NULL DEFAULT now(),
//      updated_at      timestamptz NOT NULL DEFAULT now()
//  );
//
//  ALTER TABLE public.submitted_loads ENABLE ROW LEVEL SECURITY;
//
//  -- Drivers see only their own loads
//  CREATE POLICY "Drivers read own loads"
//      ON public.submitted_loads FOR SELECT
//      USING (auth.uid() = driver_id);
//
//  -- Drivers can insert their own loads
//  CREATE POLICY "Drivers insert own loads"
//      ON public.submitted_loads FOR INSERT
//      WITH CHECK (auth.uid() = driver_id);
//
//  -- Admin/dispatcher can read all loads (add admin role check as needed)
//  -- CREATE POLICY "Admin reads all loads"
//  --     ON public.submitted_loads FOR SELECT
//  --     USING (is_admin(auth.uid()));
//
//  CREATE INDEX submitted_loads_driver_idx ON public.submitted_loads(driver_id, load_date);
//  CREATE INDEX submitted_loads_status_idx ON public.submitted_loads(status);
//

import Foundation

struct SubmittedLoad: Identifiable, Codable, Hashable {

    // MARK: - Stored

    var id: UUID
    var driverId: UUID
    var driverName: String
    var loadNumber: String
    var pickup: String
    var delivery: String
    var loadDate: Date
    var grossAmount: Decimal?       // nil when driver doesn't know the amount
    var miles: Double
    var status: LoadStatus
    var notes: String
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Init

    init(
        id: UUID = UUID(),
        driverId: UUID,
        driverName: String,
        loadNumber: String,
        pickup: String,
        delivery: String,
        loadDate: Date = Date(),
        grossAmount: Decimal? = nil,
        miles: Double = 0,
        status: LoadStatus = .submitted,
        notes: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.driverId = driverId
        self.driverName = driverName
        self.loadNumber = loadNumber
        self.pickup = pickup
        self.delivery = delivery
        self.loadDate = loadDate
        self.grossAmount = grossAmount
        self.miles = miles
        self.status = status
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed

    /// Driver pay at 5% of gross (v1 flat rate).
    /// Returns nil if gross is unknown.
    var driverPay: Decimal? {
        guard let gross = grossAmount else { return nil }
        return gross * Decimal(0.05)
    }

    /// Formatted gross amount, or "TBD" if unknown.
    var formattedGross: String {
        guard let gross = grossAmount else { return "TBD" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: gross as NSDecimalNumber) ?? "$\(gross)"
    }

    /// Formatted driver pay, or "TBD" if gross is unknown.
    var formattedDriverPay: String {
        guard let pay = driverPay else { return "TBD" }
        let fmt = NumberFormatter()
        fmt.numberStyle = .currency
        fmt.locale = .current
        return fmt.string(from: pay as NSDecimalNumber) ?? "$\(pay)"
    }

    /// Formatted miles.
    var formattedMiles: String {
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 1
        return (fmt.string(from: NSNumber(value: miles)) ?? "\(miles)") + " mi"
    }

    /// Whether the load can be approved (has a gross amount).
    var canBeApproved: Bool {
        grossAmount != nil && status == .submitted
    }

    /// Route summary.
    var routeSummary: String {
        "\(pickup) → \(delivery)"
    }
}
