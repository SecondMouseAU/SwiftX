import Foundation
#if canImport(Compression)
import Compression
#endif

/// A native-Swift reader for **DirectX `.x`** model geometry — the legacy Microsoft retained-mode
/// mesh format, still used by tools and simulators such as **RailSim**.
///
/// `.x` comes in four flavours, distinguished by bytes 8–15 of the 16-byte `xof` header:
/// `txt ` (text), `bin ` (binary tokens), `tzip` (MSZip-compressed text), and `bzip` (MSZip-compressed
/// binary). SwiftX reads **all four**, plus 32- and 64-bit float variants. It extracts **geometry only**
/// — vertex positions and triangle faces (polygon faces are fan-triangulated) — across every `Mesh`
/// object in the file, and skips templates, frames' non-geometry data, normals, materials and textures.
///
/// ```swift
/// let mesh = try X.read(contentsOf: url)
/// print(mesh.vertexCount, mesh.triangleCount)
/// ```
///
/// Pure Swift, no third-party dependencies. The compressed flavours (`tzip`/`bzip`) use Apple's
/// `Compression` framework for raw-DEFLATE on Apple platforms; on platforms without it, compressed
/// files throw ``Error/compressionUnavailable`` while text/binary `.x` still work.
public enum X {

    // MARK: Result

    /// An indexed triangle mesh: unique `positions` and a flat `indices` buffer (three per triangle).
    public struct Mesh: Equatable, Sendable {
        public var positions: [SIMD3<Float>]
        public var indices: [UInt32]

        public init(positions: [SIMD3<Float>], indices: [UInt32]) {
            self.positions = positions
            self.indices = indices
        }

        public var vertexCount: Int { positions.count }
        public var triangleCount: Int { indices.count / 3 }

        public var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)? {
            guard var lo = positions.first else { return nil }
            var hi = lo
            for p in positions {
                lo = SIMD3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = SIMD3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo, hi)
        }
    }

    // MARK: Options

    public struct Options: Sendable {
        /// Merge vertices closer than this (model units) — `.x` files duplicate positions at material
        /// seams and between the file's multiple `Mesh` blocks; welding restores connectivity. `nil`
        /// keeps every authored vertex. Default `1e-4`.
        public var weldEpsilon: Float?
        /// Drop zero-area triangles. Default `true`.
        public var dropDegenerate: Bool
        /// Uniform scale applied to every coordinate. `.x` carries no unit; RailSim authors in metres.
        /// Default `1`.
        public var scale: Float
        /// Negate Z and reverse winding. DirectX is nominally left-handed, but `.x` files are authored
        /// in many conventions — leave `false` (faithful) unless your target needs the flip. Default `false`.
        public var flipZ: Bool

        public init(weldEpsilon: Float? = 1e-4, dropDegenerate: Bool = true, scale: Float = 1, flipZ: Bool = false) {
            self.weldEpsilon = weldEpsilon
            self.dropDegenerate = dropDegenerate
            self.scale = scale
            self.flipZ = flipZ
        }

        public static var `default`: Options { Options() }
    }

    // MARK: Errors

    public enum Error: Swift.Error, Equatable, Sendable {
        case empty
        case truncated
        case badMagic                       // missing the "xof " signature
        case unsupportedFormat(String)      // header format field not txt/bin/tzip/bzip
        case compressionUnavailable         // tzip/bzip on a platform without raw-DEFLATE
    }

    // MARK: Entry points

    public static func read(contentsOf url: URL, options: Options = .default) throws -> Mesh {
        try read(data: try Data(contentsOf: url), options: options)
    }

    public static func read(data: Data, options: Options = .default) throws -> Mesh {
        guard data.count >= 16 else { throw data.isEmpty ? Error.empty : Error.truncated }
        let bytes = [UInt8](data)
        guard bytes[0] == 0x78, bytes[1] == 0x6F, bytes[2] == 0x66, bytes[3] == 0x20 else { throw Error.badMagic }  // "xof "

        let format = String(decoding: bytes[8..<12], as: UTF8.self)   // "txt ","bin ","tzip","bzip"
        let floatBytes = String(decoding: bytes[12..<16], as: UTF8.self) == "0064" ? 8 : 4

        func parseText(_ src: [UInt8], _ s: Int) -> [RawMesh] { var p = TextParser(bytes: src, start: s); return p.parse() }
        func parseBin(_ src: [UInt8], _ s: Int) -> [RawMesh] { var p = BinaryParser(bytes: src, start: s, floatBytes: floatBytes); return p.parse() }

        let meshes: [RawMesh]
        switch format {
        case "txt ":
            meshes = parseText(bytes, 16)
        case "bin ":
            meshes = parseBin(bytes, 16)
        case "tzip", "bzip":
            let inner = try mszipDecompress(bytes, start: 16)
            meshes = format == "tzip" ? parseText(inner, 0) : parseBin(inner, 0)
        default:
            throw Error.unsupportedFormat(format)
        }
        return assemble(meshes, options: options)
    }

    /// Cheap signature sniff — `true` when `data` begins with the `.x` magic `"xof "`.
    public static func looksLikeX(_ data: Data) -> Bool {
        data.count >= 4 && data[data.startIndex] == 0x78 && data[data.startIndex + 1] == 0x6F
            && data[data.startIndex + 2] == 0x66 && data[data.startIndex + 3] == 0x20
    }

    // MARK: Mesh assembly + post-processing

    /// A single `.x` `Mesh` block before welding: raw positions and fan-triangulated faces.
    struct RawMesh { var positions: [SIMD3<Float>] = []; var tris: [(Int, Int, Int)] = [] }

    static func assemble(_ meshes: [RawMesh], options: Options) -> Mesh {
        // Concatenate every Mesh block into one soup (offsetting indices), apply scale/flip, then weld.
        var soup = [SIMD3<Float>]()
        for m in meshes {
            for (a, b, c) in m.tris {
                guard a < m.positions.count, b < m.positions.count, c < m.positions.count else { continue }
                let tri = options.flipZ ? [m.positions[a], m.positions[c], m.positions[b]]
                                        : [m.positions[a], m.positions[b], m.positions[c]]
                for var p in tri {
                    if options.flipZ { p.z = -p.z }
                    soup.append(p * options.scale)
                }
            }
        }
        var mesh = options.weldEpsilon.map { weld(soup, epsilon: $0) } ?? indexedSoup(soup)
        if options.dropDegenerate { mesh = dropDegenerateTriangles(mesh) }
        return mesh
    }

    static func weld(_ soup: [SIMD3<Float>], epsilon: Float) -> Mesh {
        let inv = 1.0 / Swift.max(epsilon, .leastNormalMagnitude)
        var map = [SIMD3<Int32>: UInt32](minimumCapacity: soup.count / 2)
        var positions = [SIMD3<Float>](); positions.reserveCapacity(soup.count / 2)
        var indices = [UInt32](); indices.reserveCapacity(soup.count)
        for v in soup {
            let key = SIMD3<Int32>(Int32((v.x * inv).rounded()), Int32((v.y * inv).rounded()), Int32((v.z * inv).rounded()))
            if let idx = map[key] { indices.append(idx) }
            else { let idx = UInt32(positions.count); map[key] = idx; positions.append(v); indices.append(idx) }
        }
        return Mesh(positions: positions, indices: indices)
    }

    static func indexedSoup(_ soup: [SIMD3<Float>]) -> Mesh {
        Mesh(positions: soup, indices: (0..<UInt32(soup.count)).map { $0 })
    }

    static func dropDegenerateTriangles(_ m: Mesh) -> Mesh {
        var indices = [UInt32](); indices.reserveCapacity(m.indices.count)
        var t = 0
        while t + 2 < m.indices.count {
            let a = m.indices[t], b = m.indices[t + 1], c = m.indices[t + 2]; t += 3
            if a != b, b != c, a != c { indices.append(a); indices.append(b); indices.append(c) }
        }
        return Mesh(positions: m.positions, indices: indices)
    }

    // MARK: MSZip (raw DEFLATE blocks)

    /// Decompress an MSZip body: after a 6-byte master head, repeated blocks of `[u16 size][u16 'CK']
    /// [raw DEFLATE]`, each inflating to ≤32 KB. `size` counts the 'CK' marker + the DEFLATE payload.
    ///
    /// Note: MSZip blocks may back-reference the previous block's 32 KB. Apple's `Compression` exposes
    /// no preset-dictionary API, so each block is inflated independently — correct for any file ≤32 KB
    /// uncompressed (a single block), which is the overwhelming majority of `.x` parts. Larger
    /// multi-block files would need a streaming inflater with dictionary carryover (a future addition).
    static func mszipDecompress(_ b: [UInt8], start: Int) throws -> [UInt8] {
        var p = start + 6
        var out = [UInt8]()
        while p + 4 <= b.count {
            let size = Int(b[p]) | (Int(b[p + 1]) << 8); p += 2
            let magic = Int(b[p]) | (Int(b[p + 1]) << 8); p += 2
            guard magic == 0x4B43 else { break }                  // 'CK'
            let dl = size - 2
            guard dl >= 0, p + dl <= b.count else { throw Error.truncated }
            out += try inflateRaw(Array(b[p ..< p + dl]), cap: 32 * 1024)
            p += dl
        }
        return out
    }

    /// Raw DEFLATE (RFC 1951) via Apple's `Compression` framework (`COMPRESSION_ZLIB` is headerless raw
    /// DEFLATE). Unavailable on non-Apple platforms.
    static func inflateRaw(_ src: [UInt8], cap: Int) throws -> [UInt8] {
        #if canImport(Compression)
        var dst = [UInt8](repeating: 0, count: cap)
        let n = dst.withUnsafeMutableBufferPointer { d in
            src.withUnsafeBufferPointer { s in
                compression_decode_buffer(d.baseAddress!, cap, s.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard n > 0 else { throw Error.truncated }
        return Array(dst.prefix(n))
        #else
        throw Error.compressionUnavailable
        #endif
    }
}
