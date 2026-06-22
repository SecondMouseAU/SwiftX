# SwiftX

[![Swift](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftX%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/SecondMouseAU/SwiftX)
[![Platforms](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FSecondMouseAU%2FSwiftX%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/SecondMouseAU/SwiftX)
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
[![Docs](https://img.shields.io/badge/docs-page-2ea44f)](https://secondmouseau.github.io/SwiftX/)

📖 **Documentation:** <https://secondmouseau.github.io/SwiftX/>

A small, native-Swift reader for **DirectX `.x`** model geometry — the legacy Microsoft retained-mode
mesh format, still used by tools and simulators such as **RailSim**.

`.x` ships in four flavours, distinguished by the `xof` header: **`txt`** (text), **`bin`** (binary
tokens), **`tzip`** (MSZip-compressed text), and **`bzip`** (MSZip-compressed binary). SwiftX reads
**all four** (32- and 64-bit floats), extracting geometry only — vertices and triangle faces (polygons
are fan-triangulated) across every `Mesh` in the file — and skipping templates, frames, normals,
materials and textures.

- Pure Swift, no third-party dependencies.
- Validated against a 116-file RailSim corpus: geometry bbox-exact vs Assimp on every file.

## Install

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftX.git", from: "1.0.0"),
],
// target:
.target(name: "YourTarget", dependencies: [.product(name: "SwiftX", package: "SwiftX")]),
```

## Use

```swift
import SwiftX

let mesh = try X.read(contentsOf: url)          // welded, degenerate faces dropped
print(mesh.vertexCount, mesh.triangleCount)

for t in 0..<mesh.triangleCount {
    let i = t * 3
    let a = mesh.positions[Int(mesh.indices[i])]
    // …
}
```

Everything is configurable via `X.Options` — `weldEpsilon` (seam welding; `nil` to keep raw indexing),
`dropDegenerate`, `scale`, and `flipZ` (left-/right-handed). `X.looksLikeX(data)` sniffs the `"xof "`
signature.

## Scope & notes

SwiftX is a **geometry reader**: no rig/animation, materials, textures, or writing. The compressed
flavours (`tzip`/`bzip`) use Apple's `Compression` framework for raw-DEFLATE; on platforms without it,
compressed files throw `X.Error.compressionUnavailable` while text/binary `.x` still work. Multi-block
MSZip (files >32 KB uncompressed) is a future addition — single-block (the vast majority of parts) is
fully supported.

> In simulators like RailSim, the **`.x` files are individual parts** and the **assembly** (which parts,
> how many, where placed) lives in separate text definition files. SwiftX reads the parts; the assembly
> is a separate concern.

## License

MIT.
