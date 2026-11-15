/// A small, seedable random generator (SplitMix64). The same seed always gives the same run,
/// which is what lets the test bot replay a run exactly, and lets a saved run continue the same way.
public struct RNG: Codable, Equatable, Sendable {
    public private(set) var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< 1
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }

    public mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + (hi - lo) * unit() }

    /// lo ... hi, both included.
    public mutating func int(_ lo: Int, _ hi: Int) -> Int { lo + Int(next() % UInt64(hi - lo + 1)) }

    public mutating func chance(_ p: Double) -> Bool { unit() < p }

    public mutating func pick<T>(_ items: [T]) -> T { items[int(0, items.count - 1)] }

    public mutating func side() -> Side { chance(0.5) ? .left : .right }

    /// Picks by weight. Weights must not all be zero.
    public mutating func weighted<T>(_ items: [(T, Double)]) -> T {
        let total = items.reduce(0) { $0 + $1.1 }
        var roll = unit() * total
        for (item, w) in items {
            if roll < w { return item }
            roll -= w
        }
        return items[items.count - 1].0
    }
}
