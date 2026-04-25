import Foundation
import simd

public enum LUTParser {

    // MARK: - .cube (Adobe / Iridas / Resolve)

    public static func parseCube(_ text: String) throws -> LUT3D {
        var size: Int? = nil
        var title: String? = nil
        var domainMin = SIMD3<Float>(0, 0, 0)
        var domainMax = SIMD3<Float>(1, 1, 1)
        var data: [SIMD3<Float>] = []

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            if trimmed.uppercased().hasPrefix("TITLE") {
                if let q1 = trimmed.firstIndex(of: "\""),
                   let q2 = trimmed.lastIndex(of: "\""),
                   q1 < q2 {
                    title = String(trimmed[trimmed.index(after: q1)..<q2])
                }
                continue
            }

            if trimmed.uppercased().hasPrefix("LUT_3D_SIZE") {
                let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
                guard parts.count >= 2, let n = Int(parts[1]) else {
                    throw LUTError.parseFailure("Invalid LUT_3D_SIZE: \(trimmed)")
                }
                size = n
                continue
            }

            if trimmed.uppercased().hasPrefix("LUT_1D_SIZE") {
                throw LUTError.unsupportedFormat("1D .cube LUTs are not supported")
            }

            if trimmed.uppercased().hasPrefix("DOMAIN_MIN") {
                domainMin = try parseTriple(trimmed)
                continue
            }
            if trimmed.uppercased().hasPrefix("DOMAIN_MAX") {
                domainMax = try parseTriple(trimmed)
                continue
            }

            // Data line: three floats separated by whitespace.
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            if parts.count == 3,
               let r = Float(parts[0]), let g = Float(parts[1]), let b = Float(parts[2]) {
                data.append(SIMD3<Float>(r, g, b))
            }
        }

        guard let n = size else { throw LUTError.parseFailure("Missing LUT_3D_SIZE") }
        let expected = n * n * n
        guard data.count == expected else {
            throw LUTError.dataCountMismatch(expected: expected, got: data.count)
        }
        return try LUT3D(size: n, data: data, title: title, domainMin: domainMin, domainMax: domainMax)
    }

    private static func parseTriple(_ line: String) throws -> SIMD3<Float> {
        let parts = line.split(whereSeparator: { $0.isWhitespace })
        guard parts.count >= 4,
              let x = Float(parts[1]), let y = Float(parts[2]), let z = Float(parts[3]) else {
            throw LUTError.parseFailure("Invalid triple: \(line)")
        }
        return SIMD3<Float>(x, y, z)
    }

    public static func encodeCube(_ lut: LUT3D) -> String {
        var out = ""
        if let title = lut.title { out += "TITLE \"\(title)\"\n" }
        out += "LUT_3D_SIZE \(lut.size)\n"
        if lut.domainMin != SIMD3<Float>(0, 0, 0) {
            out += "DOMAIN_MIN \(lut.domainMin.x) \(lut.domainMin.y) \(lut.domainMin.z)\n"
        }
        if lut.domainMax != SIMD3<Float>(1, 1, 1) {
            out += "DOMAIN_MAX \(lut.domainMax.x) \(lut.domainMax.y) \(lut.domainMax.z)\n"
        }
        out += "\n"
        for entry in lut.data {
            out += String(format: "%.6f %.6f %.6f\n", entry.x, entry.y, entry.z)
        }
        return out
    }

    // MARK: - .3dl (Lustre / Discreet)

    /// Parse a Lustre-format .3dl file. The first non-comment numeric line is treated as
    /// the input mesh (its length determines `size`). Subsequent lines are size^3 RGB
    /// integer triples; the maximum value across all triples determines bit depth
    /// (1023 → 10-bit, 4095 → 12-bit, 65535 → 16-bit).
    public static func parse3DL(_ text: String) throws -> LUT3D {
        var meshSize: Int? = nil
        var ints: [SIMD3<Int>] = []
        var maxValue = 0

        for rawLine in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            // First numeric line is the input mesh; its count is the LUT size.
            if meshSize == nil {
                let mesh = parts.compactMap { Int($0) }
                if mesh.count == parts.count, mesh.count >= 2 {
                    meshSize = mesh.count
                    continue
                }
            }
            if parts.count == 3, let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]) {
                ints.append(SIMD3<Int>(r, g, b))
                maxValue = max(maxValue, r, g, b)
            }
        }

        guard let n = meshSize else { throw LUTError.parseFailure("Missing mesh header in .3dl") }
        let expected = n * n * n
        guard ints.count == expected else {
            throw LUTError.dataCountMismatch(expected: expected, got: ints.count)
        }

        let scale: Float
        if maxValue <= 1023 { scale = 1023 }
        else if maxValue <= 4095 { scale = 4095 }
        else { scale = 65535 }

        let data: [SIMD3<Float>] = ints.map {
            SIMD3<Float>(Float($0.x) / scale, Float($0.y) / scale, Float($0.z) / scale)
        }
        return try LUT3D(size: n, data: data, title: nil)
    }

    // MARK: - File I/O helpers

    public static func loadCube(at url: URL) throws -> LUT3D {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseCube(text)
    }

    public static func saveCube(_ lut: LUT3D, to url: URL) throws {
        let text = encodeCube(lut)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func load3DL(at url: URL) throws -> LUT3D {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse3DL(text)
    }
}
