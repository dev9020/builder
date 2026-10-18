import Foundation

typealias V2 = SIMD2<Double>

extension SIMD2 where Scalar == Double {
    var len: Double { (x * x + y * y).squareRoot() }
    var unit: V2 { let l = len; return l > 1e-12 ? self / l : self }
}

@inline(__always) func dot2(_ a: V2, _ b: V2) -> Double { a.x * b.x + a.y * b.y }

/// Округление вверх до шага (0.05 м и т.п.)
func roundUp(_ x: Double, _ step: Double) -> Double { (x / step - 1e-9).rounded(.up) * step }
func roundDown(_ x: Double, _ step: Double) -> Double { (x / step + 1e-9).rounded(.down) * step }
func fmt(_ x: Double, _ d: Int = 2) -> String { String(format: "%.\(d)f", x) }

enum Geo {
    /// Пересечение отрезков: доля t вдоль первого (0…1), если отрезки не параллельны и пересекаются
    static func segmentIntersection(_ a: V2, _ b: V2, _ c: V2, _ d: V2) -> Double? {
        let r = b - a, s = d - c
        let den = r.x * s.y - r.y * s.x
        guard abs(den) > 1e-9 else { return nil }
        let q = c - a
        let t = (q.x * s.y - q.y * s.x) / den, u = (q.x * r.y - q.y * r.x) / den
        return t >= -1e-6 && t <= 1 + 1e-6 && u >= -1e-6 && u <= 1 + 1e-6 ? t : nil
    }

    static func distToSegment(_ p: V2, _ a: V2, _ b: V2) -> Double {
        let ab = b - a
        let l2 = dot2(ab, ab)
        if l2 < 1e-12 { return (p - a).len }
        let t = max(0, min(1, dot2(p - a, ab) / l2))
        return (p - (a + ab * t)).len
    }

    static func project(_ p: V2, _ a: V2, _ b: V2) -> V2 {
        let ab = b - a
        let l2 = dot2(ab, ab)
        if l2 < 1e-12 { return a }
        let t = max(0, min(1, dot2(p - a, ab) / l2))
        return a + ab * t
    }

    static func signedArea(_ r: [V2]) -> Double {
        var s = 0.0
        for i in r.indices {
            let a = r[i], b = r[(i + 1) % r.count]
            s += a.x * b.y - b.x * a.y
        }
        return s / 2
    }

    /// Площадь: первое кольцо — наружный контур, остальные — отверстия.
    static func area(_ rings: [[V2]]) -> Double {
        guard let first = rings.first else { return 0 }
        var a = abs(signedArea(first))
        for r in rings.dropFirst() { a -= abs(signedArea(r)) }
        return a
    }

    static func perimeter(_ r: [V2]) -> Double {
        var s = 0.0
        for i in r.indices { s += (r[(i + 1) % r.count] - r[i]).len }
        return s
    }

    static func contains(_ p: V2, _ rings: [[V2]]) -> Bool {
        var inside = false
        for r in rings {
            var j = r.count - 1
            for i in 0..<r.count {
                let a = r[i], b = r[j]
                if (a.y > p.y) != (b.y > p.y) {
                    let x = a.x + (p.y - a.y) * (b.x - a.x) / (b.y - a.y)
                    if p.x < x { inside.toggle() }
                }
                j = i
            }
        }
        return inside
    }

    static func bbox(_ rings: [[V2]]) -> (lo: V2, hi: V2) {
        var lo = V2(Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude)
        var hi = -lo
        for r in rings { for v in r { lo = pointwiseMin(lo, v); hi = pointwiseMax(hi, v) } }
        if rings.isEmpty { return (V2(0, 0), V2(1, 1)) }
        return (lo, hi)
    }

    /// Смещение контура: dist > 0 расширяет область, ограниченную кольцом.
    static func offset(_ r: [V2], by dist: Double) -> [V2] {
        let ccw = signedArea(r) > 0
        let n = r.count
        var out: [V2] = []
        for i in 0..<n {
            let p = r[i], prev = r[(i - 1 + n) % n], next = r[(i + 1) % n]
            let d1 = (p - prev).unit, d2 = (next - p).unit
            var n1 = V2(d1.y, -d1.x), n2 = V2(d2.y, -d2.x)
            if !ccw { n1 = -n1; n2 = -n2 }
            let denom = 1 + dot2(n1, n2)
            out.append(abs(denom) < 1e-6 ? p + n1 * dist : p + (n1 + n2) * (dist / denom))
        }
        return out
    }

    /// Интервалы, где прямая (y = c при horizontal, иначе x = c) лежит внутри области.
    static func scan(_ rings: [[V2]], at c: Double, horizontal: Bool) -> [(Double, Double)] {
        var xs: [Double] = []
        for r in rings {
            for i in 0..<r.count {
                var a = r[i], b = r[(i + 1) % r.count]
                if !horizontal { a = V2(a.y, a.x); b = V2(b.y, b.x) }
                if (a.y > c) != (b.y > c) {
                    xs.append(a.x + (c - a.y) * (b.x - a.x) / (b.y - a.y))
                }
            }
        }
        xs.sort()
        var out: [(Double, Double)] = []
        var i = 0
        while i + 1 < xs.count { out.append((xs[i], xs[i + 1])); i += 2 }
        return out
    }
}
