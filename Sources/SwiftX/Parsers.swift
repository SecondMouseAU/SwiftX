import Foundation

// MARK: - Text .x parser

/// Tokenizes a text `.x` body and extracts every `Mesh` block's vertices + fan-triangulated faces.
/// Templates / `Header` / nested non-geometry (`MeshNormals`, `MeshMaterialList`, …) are skipped.
struct TextParser {
    let b: [UInt8]
    var i: Int

    init(bytes: [UInt8], start: Int) { b = bytes; i = start }

    private func isWS(_ c: UInt8) -> Bool { c == 32 || c == 9 || c == 10 || c == 13 }
    private func isPunct(_ c: UInt8) -> Bool { c == 123 || c == 125 || c == 59 || c == 44 } // { } ; ,

    private mutating func next() -> String? {
        while i < b.count {
            let c = b[i]
            if isWS(c) { i += 1; continue }
            if c == 35 || (c == 47 && i + 1 < b.count && b[i + 1] == 47) {   // # or // comment
                while i < b.count && b[i] != 10 { i += 1 }; continue
            }
            if isPunct(c) { i += 1; return String(UnicodeScalar(c)) }
            if c == 34 {   // "quoted"
                i += 1; var s = [UInt8]()
                while i < b.count && b[i] != 34 { s.append(b[i]); i += 1 }
                i += 1; return "\"" + String(decoding: s, as: UTF8.self)
            }
            var w = [UInt8]()
            while i < b.count && !isWS(b[i]) && !isPunct(b[i]) { w.append(b[i]); i += 1 }
            return String(decoding: w, as: UTF8.self)
        }
        return nil
    }

    private mutating func nextValueWord() -> String? {       // skip ; , separators
        while let t = next() { if t == ";" || t == "," { continue }; return t }
        return nil
    }
    private mutating func readInt() -> Int? { nextValueWord().flatMap { Int($0) } }
    private mutating func readFloat() -> Float? { nextValueWord().flatMap { Float($0) } }

    private mutating func skipBlock() {                      // consume up to & including the matching }
        var depth = 0, opened = false
        while let t = next() {
            if t == "{" { opened = true; depth += 1 }
            else if t == "}" { depth -= 1; if opened && depth == 0 { return } }
        }
    }

    private mutating func parseMesh(_ meshes: inout [X.RawMesh]) {
        var t = next()
        if t != "{" { t = next() }                          // optional mesh name
        guard t == "{" else { return }
        guard let nv = readInt() else { return }
        var m = X.RawMesh()
        m.positions.reserveCapacity(nv)
        for _ in 0..<nv {
            guard let x = readFloat(), let y = readFloat(), let z = readFloat() else { return }
            m.positions.append(SIMD3(x, y, z))
        }
        guard let nf = readInt() else { return }
        for _ in 0..<nf {
            guard let k = readInt(), k >= 1 else { return }
            var idx = [Int](); idx.reserveCapacity(k)
            for _ in 0..<k { guard let v = readInt() else { return }; idx.append(v) }
            if k >= 3 { for j in 1..<(k - 1) { m.tris.append((idx[0], idx[j], idx[j + 1])) } }   // fan; skip lines/points
        }
        var depth = 1                                       // skip remainder of the Mesh block
        while depth > 0, let tk = next() { if tk == "{" { depth += 1 } else if tk == "}" { depth -= 1 } }
        meshes.append(m)
    }

    mutating func parse() -> [X.RawMesh] {
        var meshes = [X.RawMesh]()
        while let t = next() {
            switch t {
            case "template": _ = next(); skipBlock()        // template <name> { ... }
            case "Mesh": parseMesh(&meshes)
            default: break                                  // descend through frames/headers
            }
        }
        return meshes
    }
}

// MARK: - Binary .x parser

/// Reads the binary `.x` token stream and extracts every `Mesh` object's geometry. Integers and floats
/// arrive batched in INTEGER_LIST / FLOAT_LIST tokens; `readInt`/`readFloat` drain those buffers,
/// refilling from the next list token, so the same count-driven Mesh logic as the text path applies.
struct BinaryParser {
    let b: [UInt8]
    var p: Int
    let floatBytes: Int

    init(bytes: [UInt8], start: Int, floatBytes: Int) { b = bytes; p = start; self.floatBytes = floatBytes }

    private enum Tok { case name(String), int(Int), intList([Int]), floatList([Float]), obrace, cbrace, template, end, other }

    private mutating func u16() -> Int { let v = Int(b[p]) | (Int(b[p + 1]) << 8); p += 2; return v }
    private mutating func u32() -> Int {
        let v = Int(b[p]) | (Int(b[p + 1]) << 8) | (Int(b[p + 2]) << 16) | (Int(b[p + 3]) << 24); p += 4; return v
    }
    private mutating func f32() -> Float {
        let bits = UInt32(b[p]) | (UInt32(b[p + 1]) << 8) | (UInt32(b[p + 2]) << 16) | (UInt32(b[p + 3]) << 24)
        p += 4; return Float(bitPattern: bits)
    }
    private mutating func f64() -> Float {
        var bits: UInt64 = 0
        for k in 0..<8 { bits |= UInt64(b[p + k]) << (8 * k) }
        p += 8; return Float(Double(bitPattern: bits))
    }

    private mutating func token() -> Tok {
        guard p + 2 <= b.count else { return .end }
        let t = u16()
        switch t {
        case 1:  let n = u32(); let s = String(decoding: b[p..<min(p + n, b.count)], as: UTF8.self); p += n; return .name(s)
        case 2:  let n = u32(); p += n; if p + 2 <= b.count { _ = u16() }; return .other        // STRING + terminator
        case 3:  return .int(u32())
        case 5:  p += 16; return .other                                                          // GUID
        case 6:  let n = u32(); var a = [Int](); a.reserveCapacity(n); for _ in 0..<n { a.append(u32()) }; return .intList(a)
        case 7:  let n = u32(); var a = [Float](); a.reserveCapacity(n)
                 for _ in 0..<n { a.append(floatBytes == 8 ? f64() : f32()) }; return .floatList(a)
        case 10: return .obrace
        case 11: return .cbrace
        case 31: return .template
        default: return .other
        }
    }

    // Value buffers drained by readInt / readFloat.
    private var intBuf = [Int](); private var ii = 0
    private var fBuf = [Float](); private var fi = 0
    private mutating func resetBuffers() { intBuf = []; ii = 0; fBuf = []; fi = 0 }

    private mutating func readInt() -> Int? {
        while ii >= intBuf.count {
            switch token() {
            case .int(let v): return v
            case .intList(let a) where !a.isEmpty: intBuf = a; ii = 0
            case .end: return nil
            default: continue
            }
        }
        defer { ii += 1 }; return intBuf[ii]
    }
    private mutating func readFloat() -> Float? {
        while fi >= fBuf.count {
            switch token() {
            case .floatList(let a) where !a.isEmpty: fBuf = a; fi = 0
            case .end: return nil
            default: continue
            }
        }
        defer { fi += 1 }; return fBuf[fi]
    }

    private mutating func skipBlock() {                      // up to & including matching }
        var depth = 0, opened = false
        while true {
            switch token() {
            case .obrace: opened = true; depth += 1
            case .cbrace: depth -= 1; if opened && depth == 0 { return }
            case .end: return
            default: break
            }
        }
    }

    private mutating func parseMesh(_ meshes: inout [X.RawMesh]) {
        resetBuffers()
        var t = token()
        if case .name = t { t = token() }                   // optional mesh name
        guard case .obrace = t else { return }
        guard let nv = readInt() else { return }
        var m = X.RawMesh(); m.positions.reserveCapacity(nv)
        for _ in 0..<nv {
            guard let x = readFloat(), let y = readFloat(), let z = readFloat() else { return }
            m.positions.append(SIMD3(x, y, z))
        }
        guard let nf = readInt() else { return }
        for _ in 0..<nf {
            guard let k = readInt(), k >= 1 else { return }
            var idx = [Int](); idx.reserveCapacity(k)
            for _ in 0..<k { guard let v = readInt() else { return }; idx.append(v) }
            if k >= 3 { for j in 1..<(k - 1) { m.tris.append((idx[0], idx[j], idx[j + 1])) } }
        }
        var depth = 1
        while depth > 0 {                                   // skip remainder of the Mesh block
            switch token() { case .obrace: depth += 1; case .cbrace: depth -= 1; case .end: depth = 0; default: break }
        }
        meshes.append(m)
    }

    mutating func parse() -> [X.RawMesh] {
        var meshes = [X.RawMesh]()
        loop: while true {
            switch token() {
            case .end: break loop
            case .template: skipBlock()                     // template <name> { ... }
            case .name(let s): if s == "Mesh" { parseMesh(&meshes) }   // else: descend to find nested Meshes
            default: break
            }
        }
        return meshes
    }
}
