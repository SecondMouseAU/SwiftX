---
title: SwiftX
nav_order: 1
---

# SwiftX

A small, **native-Swift reader for DirectX `.x`** model geometry — the legacy Microsoft retained-mode
mesh format, still used by tools and simulators such as **RailSim**.

`.x` ships in four flavours, distinguished by bytes 8–15 of the 16-byte `xof` header:

| Header field | Flavour | Supported |
|---|---|---|
| `txt ` | text | ✅ |
| `bin ` | binary tokens | ✅ |
| `tzip` | MSZip-compressed text | ✅ (Apple platforms) |
| `bzip` | MSZip-compressed binary | ✅ (Apple platforms) |

…plus 32- and 64-bit float variants. SwiftX extracts **geometry only** — vertex positions and triangle
faces (polygon faces are fan-triangulated) across every `Mesh` object in the file — and skips
templates, frames' non-geometry data, normals, materials and textures.

- Pure Swift, **no third-party dependencies**.
- Validated against a **116-file RailSim corpus**: geometry bounding-box-exact vs Assimp on every file,
  across all three flavours (text, binary, MSZip).

---

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/SecondMouseAU/SwiftX.git", from: "1.0.0"),
],
```

```swift
.target(
    name: "YourTarget",
    dependencies: [.product(name: "SwiftX", package: "SwiftX")]
),
```

---

## Quick start

```swift
import SwiftX

// Defaults: welded, degenerate faces dropped, scale 1, no handedness flip.
let mesh = try X.read(contentsOf: url)
print(mesh.vertexCount, mesh.triangleCount)

for t in 0..<mesh.triangleCount {
    let i = t * 3
    let a = mesh.positions[Int(mesh.indices[i])]
    let b = mesh.positions[Int(mesh.indices[i + 1])]
    let c = mesh.positions[Int(mesh.indices[i + 2])]
    // … use the triangle (a, b, c)
}
```

Detect the format before reading:

```swift
let data = try Data(contentsOf: url)
guard X.looksLikeX(data) else { return }   // not an .x file
let mesh = try X.read(data: data)
```

---

## API reference

### `X.read`

```swift
static func read(contentsOf url: URL, options: Options = .default) throws -> Mesh
static func read(data: Data,        options: Options = .default) throws -> Mesh
```

Reads any of the four `.x` flavours and returns a [`X.Mesh`](#xmesh). Throws [`X.Error`](#xerror).

### `X.looksLikeX`

```swift
static func looksLikeX(_ data: Data) -> Bool   // true if data begins with "xof "
```

### `X.Mesh`

```swift
struct Mesh: Equatable, Sendable {
    var positions: [SIMD3<Float>]
    var indices:   [UInt32]

    var vertexCount: Int
    var triangleCount: Int
    var bounds: (min: SIMD3<Float>, max: SIMD3<Float>)?
}
```

`SIMD3<Float>` is the Swift standard-library type — SwiftX does **not** import the Apple-only `simd`
module, keeping it Linux-portable.

### `X.Options`

| Field | Type | Default | Meaning |
|---|---|---|---|
| `weldEpsilon` | `Float?` | `1e-4` | Merge vertices closer than this. `.x` duplicates positions at material seams and between a file's multiple `Mesh` blocks; welding restores connectivity. `nil` keeps every authored vertex. |
| `dropDegenerate` | `Bool` | `true` | Drop zero-area triangles. |
| `scale` | `Float` | `1` | Uniform coordinate scale. `.x` carries no unit; RailSim authors in metres. |
| `flipZ` | `Bool` | `false` | Negate Z and reverse winding. DirectX is nominally left-handed, but `.x` files are authored in many conventions — leave `false` (faithful) unless your target needs the flip. |

```swift
var opts = X.Options()
opts.weldEpsilon = nil       // keep raw per-Mesh indexing
let raw = try X.read(contentsOf: url, options: opts)
```

### `X.Error`

```swift
enum Error: Swift.Error, Equatable, Sendable {
    case empty
    case truncated
    case badMagic                    // missing the "xof " signature
    case unsupportedFormat(String)   // header format field not txt/bin/tzip/bzip
    case compressionUnavailable      // tzip/bzip on a platform without raw-DEFLATE
}
```

---

## Behaviour notes

### Flavours and floats

The format and float width are read from the 16-byte header. Text and binary `.x` are pure Swift and
work on every platform. The compressed flavours (`tzip`/`bzip`) inflate via Apple's `Compression`
framework (`COMPRESSION_ZLIB` is headerless raw DEFLATE); on platforms without it they throw
`compressionUnavailable` while text/binary still read. **Multi-block MSZip** (files larger than 32 KB
uncompressed) is a planned addition — single-block files, which are the overwhelming majority of parts,
are fully supported today.

### Faces and meshes

Every `Mesh` object in the file is read and concatenated into one result. Polygon faces (quads and
n-gons) are **fan-triangulated**. A file's separate `Mesh` blocks often re-use vertex positions at their
shared boundaries; the default welding stitches them back into one connected mesh.

### Coordinates and units

`.x` carries no unit and no canonical handedness. SwiftX extracts coordinates **faithfully** by default
(`flipZ = false`, `scale = 1`) — verified to match Assimp's geometry on the RailSim corpus. Apply
`scale` / `flipZ` if your downstream needs a different convention.

---

## Scope

SwiftX is a **geometry reader**. It does not load rig/animation data, materials, textures, or names,
and it does not write any format. It turns a `.x` part into a plain indexed mesh for your own pipeline.

> **Assemblies live elsewhere.** In simulators such as RailSim, each `.x` file is one *part*; which
> parts make up a vehicle, how many instances, and where they sit are defined in separate **text
> definition files**, not in the `.x`. SwiftX reads the parts — assembly is a separate concern.

## License

MIT.
