//
//  SacredLeafScrollBackground.swift
//  SacredBillTracker
//
//  Premium animated leaf field that drifts subtly as the user scrolls.
//  - Pure SwiftUI Shape (no image assets).
//  - Pointer-transparent; never covers tappable UI.
//  - Respects Reduce Motion (stays static).
//  - GPU-composited (`.drawingGroup()`) for cheap scroll performance.
//
//  USAGE (drop behind a ScrollView):
//
//      ZStack {
//          SacredLeafScrollBackground(scrollOffset: scrollOffset)
//              .background(Color(.systemGroupedBackground).ignoresSafeArea())
//          ScrollView {
//              content
//                  .background(GeometryReader { p in
//                      Color.clear.preference(
//                          key: SacredScrollOffsetKey.self,
//                          value: -p.frame(in: .named("sbtLeaf")).minY)
//                  })
//          }
//          .coordinateSpace(name: "sbtLeaf")
//          .scrollContentBackground(.hidden)   // for List-backed screens
//          .onPreferenceChange(SacredScrollOffsetKey.self) { scrollOffset = $0 }
//      }
//
//  USAGE (modifier, for ScrollView-based screens):
//
//      ScrollView { ... }
//          .sacredLeafBackground()
//

import SwiftUI

struct SacredLeafScrollBackground: View {

    /// Current scroll offset in points (positive when scrolled down).
    var scrollOffset: CGFloat = 0

    /// Override the leaf count. Default scales with screen size.
    var leafCount: Int? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geo in
            let leaves = SacredLeafLayout.generate(
                in: geo.size,
                count: leafCount ?? defaultLeafCount(for: geo.size)
            )
            ZStack {
                LinearGradient(
                    colors: [
                        Theme.Color.accentGold.opacity(colorScheme == .dark ? 0.04 : 0.05),
                        SwiftUI.Color.clear,
                        Theme.Color.accentGreen.opacity(colorScheme == .dark ? 0.05 : 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint:   .bottomTrailing
                )
                .ignoresSafeArea()

                ForEach(leaves) { leaf in
                    SacredLeafShape()
                        .fill(leaf.tint.opacity(leaf.opacity))
                        .frame(width: leaf.size, height: leaf.size * 1.6)
                        .rotationEffect(.degrees(leaf.rotation + driftRotation(for: leaf)))
                        .position(
                            x: leaf.position.x + driftX(for: leaf),
                            y: leaf.position.y + driftY(for: leaf)
                        )
                        .blur(radius: 0.4)
                }
            }
            .drawingGroup()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .ignoresSafeArea()
    }

    private func driftY(for leaf: SacredLeaf) -> CGFloat {
        guard !reduceMotion else { return 0 }
        return -scrollOffset * leaf.parallax * 0.18
    }

    private func driftX(for leaf: SacredLeaf) -> CGFloat {
        guard !reduceMotion else { return 0 }
        let sway = sin(scrollOffset * 0.004 + leaf.phase) * 6
        return CGFloat(sway) * leaf.parallax
    }

    private func driftRotation(for leaf: SacredLeaf) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(scrollOffset) * 0.04 * Double(leaf.parallax) * leaf.spinDirection
    }

    private func defaultLeafCount(for size: CGSize) -> Int {
        // v1.0.9 — fewer, more intentional leaves. Was up to 22, now
        // capped at 6 (anchored to corners/edges by the layout). The
        // pre-1.0.9 scattered field hurt readability behind numbers.
        return 6
    }
}

// MARK: - PreferenceKey for scroll offset

struct SacredScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Convenience modifier

extension View {
    /// Adds the Sacred leaf background behind a scrolling view and tracks
    /// scroll offset automatically. Works for `ScrollView` content; for
    /// `List`-based screens, set `.scrollContentBackground(.hidden)` and
    /// drop `SacredLeafScrollBackground` in a ZStack manually.
    func sacredLeafBackground(leafCount: Int? = nil) -> some View {
        modifier(SacredLeafBackgroundModifier(leafCount: leafCount))
    }
}

struct SacredLeafBackgroundModifier: ViewModifier {
    let leafCount: Int?
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        ZStack {
            SacredLeafScrollBackground(scrollOffset: offset, leafCount: leafCount)
                .background(Theme.Color.background.ignoresSafeArea())
            content
                .background(
                    GeometryReader { proxy in
                        SwiftUI.Color.clear.preference(
                            key: SacredScrollOffsetKey.self,
                            value: -proxy.frame(in: .named("sbtLeaf")).minY
                        )
                    }
                )
                .coordinateSpace(name: "sbtLeaf")
                .onPreferenceChange(SacredScrollOffsetKey.self) { newValue in
                    offset = newValue
                }
        }
    }
}

// MARK: - Leaf shape

struct SacredLeafShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let mid = rect.midX
        p.move(to: CGPoint(x: mid, y: rect.minY))
        p.addQuadCurve(
            to:      CGPoint(x: mid, y: rect.maxY),
            control: CGPoint(x: rect.maxX + w * 0.05, y: rect.midY)
        )
        p.addQuadCurve(
            to:      CGPoint(x: mid, y: rect.minY),
            control: CGPoint(x: rect.minX - w * 0.05, y: rect.midY)
        )
        p.closeSubpath()
        var vein = Path()
        vein.move(to: CGPoint(x: mid, y: rect.minY + h * 0.05))
        vein.addLine(to: CGPoint(x: mid, y: rect.maxY - h * 0.05))
        p.addPath(vein)
        return p
    }
}

// MARK: - Internal leaf model + layout

struct SacredLeaf: Identifiable {
    let id: Int
    let position: CGPoint
    let size: CGFloat
    let rotation: Double
    let opacity: Double
    let tint: SwiftUI.Color
    let parallax: CGFloat
    let phase: CGFloat
    let spinDirection: Double
}

enum SacredLeafLayout {
    /// v1.0.9 — Anchored layout. Instead of a random scatter that
    /// landed leaves directly behind numbers, we place each leaf at a
    /// fixed compass anchor (top corners, mid-edges, bottom corners)
    /// well outside the central read-zone where dashboard totals live.
    /// Result: fewer, cleaner, more intentional leaves that read as a
    /// design element instead of background noise.
    static func generate(in size: CGSize, count: Int) -> [SacredLeaf] {
        var rng = SacredSeededRNG(
            seed: UInt64(size.width.rounded()) &* 31 &+ UInt64(size.height.rounded())
        )

        let w = size.width
        let h = size.height

        // Compass anchors expressed as proportional offsets. All
        // anchors sit outside the horizontal central band (15%-85%
        // of width) so they never land behind centered numbers.
        let anchors: [(x: CGFloat, y: CGFloat, rotBase: Double, parallax: CGFloat)] = [
            (0.08, 0.06, -25, 0.35),   // top-left
            (0.92, 0.10,  20, 0.50),   // top-right
            (0.05, 0.42, -10, 0.65),   // mid-left
            (0.95, 0.58,  12, 0.75),   // mid-right
            (0.10, 0.92, -30, 0.55),   // bottom-left
            (0.90, 0.95,  28, 0.45),   // bottom-right
        ]

        let palette: [SwiftUI.Color] = [
            Theme.Color.accentGreen,
            Theme.Color.accentGold,
        ]

        let used = min(count, anchors.count)
        return (0..<used).map { i in
            let a = anchors[i]
            // Slightly larger than the old random field, still subtle.
            let leafSize = CGFloat(rng.uniform(36...58))
            // Slight jitter on rotation so paired corners aren't mirror
            // images of each other.
            let rot = a.rotBase + rng.uniform(-6.0...6.0)
            // Opacity bumped slightly — visible enough to feel like
            // intentional decoration, low enough to stay subtle.
            let opacity = rng.uniform(0.10...0.16)
            let phase   = CGFloat(i) * 0.9
            let spin    = i % 2 == 0 ? 1.0 : -1.0
            return SacredLeaf(
                id: i,
                position: CGPoint(x: a.x * w, y: a.y * h),
                size: leafSize,
                rotation: rot,
                opacity: opacity,
                tint: palette[i % palette.count],
                parallax: a.parallax,
                phase: phase,
                spinDirection: spin
            )
        }
    }
}

struct SacredSeededRNG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }

    mutating func uniform(_ range: ClosedRange<Double>) -> Double {
        let r = Double(next() % 1_000_000) / 1_000_000.0
        return range.lowerBound + r * (range.upperBound - range.lowerBound)
    }
}
