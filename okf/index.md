---
type: repo
title: SwiftX
resource: https://github.com/SecondMouseAU/SwiftX
tags: [directx, x-file, mesh, geometry, import, railsim, swift]
description: Native-Swift reader for DirectX .x model geometry.
timestamp: 2026-06-25
---

# SwiftX

A small, native-Swift reader for **DirectX `.x`** model geometry — the legacy Microsoft retained-mode
mesh format, still used by tools and simulators such as **RailSim**. `.x` ships in four flavours
(`txt`, `bin`, `tzip`, `bzip`); SwiftX reads all four (32- and 64-bit floats), extracting geometry
only — vertices and triangle faces (polygons fan-triangulated) across every `Mesh` — and skipping
templates, frames, normals, materials and textures. Pure Swift, no dependencies; validated bbox-exact
against Assimp on a 116-file RailSim corpus.

## Role in the ecosystem

- **Cluster:** kernel
- **Depends on:** nothing (leaf — pure Swift, Linux + Apple)
- **Feeds products:** DirectX `.x` mesh import (e.g. OCCTReconstruct's `--x2stl` / `--railsim` path)

## Components

See [`components/`](components/index.md) for the public surface.

## References

See [`references/`](references/index.md) for the `.x` format references.
