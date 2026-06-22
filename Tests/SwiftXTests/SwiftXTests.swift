import Testing
import Foundation
#if canImport(Compression)
import Compression
#endif
@testable import SwiftX

@Suite("DirectX .x reading")
struct SwiftXTests {

    // MARK: Text

    static let textQuad = """
    xof 0302txt 0064
    template Vector {
     <3D82AB5E-62DA-11cf-AB39-0020AF71E433>
     FLOAT x; FLOAT y; FLOAT z;
    }
    Mesh cube {
     4;
     0.0;0.0;0.0;,
     1.0;0.0;0.0;,
     1.0;1.0;0.0;,
     0.0;1.0;3.0;;
     1;
     4;0,1,2,3;;
    }
    """

    @Test("text: parses Mesh, fan-triangulates the quad, skips the template")
    func textBasic() throws {
        let m = try X.read(data: Data(Self.textQuad.utf8))
        #expect(m.vertexCount == 4)
        #expect(m.triangleCount == 2)               // one quad → two triangles
        let b = try #require(m.bounds)
        #expect(abs(b.max.z - 3) < 1e-5)
    }

    @Test("text: scale and flipZ apply")
    func textOptions() throws {
        var o = X.Options(); o.scale = 10; o.flipZ = true
        let m = try X.read(data: Data(Self.textQuad.utf8), options: o)
        let b = try #require(m.bounds)
        #expect(abs(b.min.z - (-30)) < 1e-3)        // z=3 → flipped/scaled → -30
    }

    @Test("text: welding merges the duplicate corner across two Mesh blocks")
    func textWeld() throws {
        // two triangles sharing an edge, authored as separate vertices in separate Mesh blocks
        let s = """
        xof 0302txt 0064
        Mesh a { 3; 0;0;0;, 1;0;0;, 1;1;0;; 1; 3;0,1,2;; }
        Mesh b { 3; 0;0;0;, 1;1;0;, 0;1;0;; 1; 3;0,1,2;; }
        """
        #expect(try X.read(data: Data(s.utf8)).vertexCount == 4)              // 6 authored → 4 welded
        var raw = X.Options(); raw.weldEpsilon = nil
        #expect(try X.read(data: Data(s.utf8), options: raw).vertexCount == 6)
    }

    // MARK: Binary

    /// Build a minimal binary .x: header + `Mesh { 3 verts; 1 triangle }`.
    static func makeBinary() -> Data {
        var d = Data("xof 0302bin 0032".utf8)
        func u16(_ v: Int) { d.append(UInt8(v & 0xFF)); d.append(UInt8((v >> 8) & 0xFF)) }
        func u32(_ v: Int) { for k in 0..<4 { d.append(UInt8((v >> (8*k)) & 0xFF)) } }
        func f32(_ v: Float) { withUnsafeBytes(of: v.bitPattern.littleEndian) { d.append(contentsOf: $0) } }
        // NAME "Mesh"
        u16(1); u32(4); d.append(contentsOf: Array("Mesh".utf8))
        u16(10)                                     // OBRACE
        u16(6); u32(1); u32(3)                      // INTEGER_LIST [nVertices = 3]
        u16(7); u32(9)                              // FLOAT_LIST, 9 floats
        for v in [(0,0,0),(1,0,0),(0,2,0)] as [(Float,Float,Float)] { f32(v.0); f32(v.1); f32(v.2) }
        u16(6); u32(5); u32(1); u32(3); u32(0); u32(1); u32(2)   // INT_LIST [nFaces=1, k=3, 0,1,2]
        u16(11)                                     // CBRACE
        return d
    }

    @Test("binary: token stream parses one triangle")
    func binaryBasic() throws {
        let m = try X.read(data: Self.makeBinary())
        #expect(m.vertexCount == 3)
        #expect(m.triangleCount == 1)
        let b = try #require(m.bounds)
        #expect(abs(b.max.y - 2) < 1e-5)
    }

    // MARK: MSZip

    #if canImport(Compression)
    @Test("mszip: a single deflate block round-trips")
    func mszip() throws {
        let payload = Array("the quick brown fox jumps over the lazy dog, twice over.".utf8)
        var deflated = [UInt8](repeating: 0, count: payload.count * 2 + 64)
        let n = deflated.withUnsafeMutableBufferPointer { dst in
            payload.withUnsafeBufferPointer { src in
                compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, src.count, nil, COMPRESSION_ZLIB)
            }
        }
        deflated = Array(deflated.prefix(n))
        var body = [UInt8](repeating: 0, count: 6)             // master head (ignored)
        let size = deflated.count + 2
        body += [UInt8(size & 0xFF), UInt8((size >> 8) & 0xFF), 0x43, 0x4B]  // [u16 size][CK]
        body += deflated
        #expect(try X.mszipDecompress(body, start: 0) == payload)
    }
    #endif

    // MARK: Errors + sniff

    @Test("rejects bad magic and unsupported format")
    func rejects() {
        #expect(throws: X.Error.self) { try X.read(data: Data("not an x file at all".utf8)) }
        #expect(throws: X.Error.self) { try X.read(data: Data("xof 0302zzz 0064\n".utf8)) }
    }

    @Test("looksLikeX sniffs the signature")
    func sniff() {
        #expect(X.looksLikeX(Data("xof 0302txt 0064".utf8)))
        #expect(!X.looksLikeX(Data("PMX ".utf8)))
    }
}
