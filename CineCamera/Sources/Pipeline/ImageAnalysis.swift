import Foundation
import simd

public enum WaveformChannel: String, CaseIterable {
    case luma, red, green, blue
}

public struct Waveform {
    public let columns: Int   // matches frame width
    public let bins: Int      // vertical resolution
    public let channel: WaveformChannel
    /// Counts laid out as `bins` rows × `columns` columns, row-major.
    /// `data[bin * columns + column]` = number of pixels in that column at that intensity bin.
    public let data: [UInt32]
}

public enum WaveformAnalyzer {

    public static func compute(_ pixels: [SIMD3<Float>],
                               width: Int,
                               height: Int,
                               bins: Int = 256,
                               channel: WaveformChannel) -> Waveform {
        precondition(pixels.count == width * height, "pixel count != width*height")
        precondition(bins >= 2, "bins must be >= 2")
        var data = [UInt32](repeating: 0, count: bins * width)
        let lastBin = bins - 1
        for y in 0..<height {
            for x in 0..<width {
                let p = pixels[y * width + x]
                let v = sample(p, channel: channel)
                let clamped = max(0, min(1, v))
                let bin = min(lastBin, Int(clamped * Float(lastBin) + 0.5))
                data[bin * width + x] &+= 1
            }
        }
        return Waveform(columns: width, bins: bins, channel: channel, data: data)
    }

    @inline(__always)
    private static func sample(_ rgb: SIMD3<Float>, channel: WaveformChannel) -> Float {
        switch channel {
        case .luma:  return simd_dot(simd_max(rgb, SIMD3<Float>(repeating: 0)), SIMD3<Float>(0.2126, 0.7152, 0.0722))
        case .red:   return rgb.x
        case .green: return rgb.y
        case .blue:  return rgb.z
        }
    }
}

public struct Histogram {
    public let bins: Int
    public let red: [UInt32]
    public let green: [UInt32]
    public let blue: [UInt32]
    public let luma: [UInt32]

    public func channel(_ ch: WaveformChannel) -> [UInt32] {
        switch ch {
        case .red:   return red
        case .green: return green
        case .blue:  return blue
        case .luma:  return luma
        }
    }
}

public enum HistogramAnalyzer {

    public static func compute(_ pixels: [SIMD3<Float>], bins: Int = 256) -> Histogram {
        precondition(bins >= 2)
        var r = [UInt32](repeating: 0, count: bins)
        var g = [UInt32](repeating: 0, count: bins)
        var b = [UInt32](repeating: 0, count: bins)
        var l = [UInt32](repeating: 0, count: bins)
        let lastBin = bins - 1
        let lumaW = SIMD3<Float>(0.2126, 0.7152, 0.0722)
        for p in pixels {
            r[bin(p.x, lastBin: lastBin)] &+= 1
            g[bin(p.y, lastBin: lastBin)] &+= 1
            b[bin(p.z, lastBin: lastBin)] &+= 1
            let luma = simd_dot(simd_max(p, SIMD3<Float>(repeating: 0)), lumaW)
            l[bin(luma, lastBin: lastBin)] &+= 1
        }
        return Histogram(bins: bins, red: r, green: g, blue: b, luma: l)
    }

    @inline(__always)
    private static func bin(_ v: Float, lastBin: Int) -> Int {
        let clamped = max(0, min(1, v))
        return min(lastBin, Int(clamped * Float(lastBin) + 0.5))
    }
}

public struct VectorscopeData {
    public let bins: Int                  // bins × bins grid
    public let counts: [UInt32]            // bins * bins entries, row-major
}

public enum VectorscopeAnalyzer {

    /// 2D histogram of (Cb, Cr) chroma in BT.709. Output grid is bins × bins,
    /// centered at (bins/2, bins/2). Provides input for a vectorscope view.
    public static func compute(_ pixels: [SIMD3<Float>], bins: Int = 256) -> VectorscopeData {
        precondition(bins >= 2)
        var counts = [UInt32](repeating: 0, count: bins * bins)
        let half = Float(bins) * 0.5
        for p in pixels {
            let r = max(0, min(1, p.x))
            let g = max(0, min(1, p.y))
            let b = max(0, min(1, p.z))
            // BT.709 Cb / Cr (centered at 0, range ~ -0.5 ... +0.5)
            let y = 0.2126 * r + 0.7152 * g + 0.0722 * b
            let cb = (b - y) / 1.8556
            let cr = (r - y) / 1.5748
            // Map [-0.5, 0.5] → [0, bins)
            let bx = min(bins - 1, max(0, Int(half + cb * Float(bins))))
            let by = min(bins - 1, max(0, Int(half - cr * Float(bins)))) // y-flipped
            counts[by * bins + bx] &+= 1
        }
        return VectorscopeData(bins: bins, counts: counts)
    }
}
