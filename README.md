# F3DEX3

Modern graphics microcode for N64 romhacks. Will make you want to finally ditch
HLE. Heavily modified version of F3DEX2, with all vertex and lighting code
rewritten from scratch.

**F3DEX3 is in beta. The GBI should be relatively stable but may change if there
is a good reason.**

[View the documentation here](https://hackern64.github.io/F3DEX3/) (or just look
through the docs folder).

[Sauraen's videos on F3DEX3](https://www.youtube.com/playlist?list=PLU2OUGtyQi6QswDQOXWIMaYFUcgQ9Psvm)

## Features

Compared to F3DEX2 or any other F3D family microcode, F3DEX3 is...
- faster on the RDP
- in ([`NOC` configuration](https://hackern64.github.io/F3DEX3/configuration.html)) and/or when using point lights, [also faster on the RSP](https://hackern64.github.io/F3DEX3/performance.html)
- more accurate
- full of new visual features
- [measurable in performance](https://hackern64.github.io/F3DEX3/counters.html)

all at the same time!

### New visual features

- New geometry mode bit `G_PACKED_NORMALS` enables **simultaneous vertex colors
  and normals/lighting on the same mesh**, by encoding the normals in the unused
  2 bytes of each vertex using the 5-6-5 bit encoding by HailToDodongo from
  [Tiny3D](https://github.com/HailToDodongo/tiny3d). Model-space precision of
  the normals is reduced, but this is rarely noticeable, and the performance is
  nearly identical to vanilla normals (without simultaneous vertex colors).
- New geometry mode bit `G_AMBOCCLUSION` enables **ambient occlusion** for
  opaque materials. Paint the shadow map into the vertex alpha channel; separate
  factors (set with `SPAmbOcclusion`) control how much this affects the ambient
  light, all directional lights, and all point lights.
- New geometry mode bit `G_LIGHTTOALPHA` moves light intensity (maximum of R, G,
  and B of what would normally be the shade color after lighting) to shade
  alpha. Then, if `G_PACKED_NORMALS` is also enabled, the shade RGB is set to
  the vertex RGB. Together with alpha compare and some special display lists
  from fast64 which draw triangles two or more times with different CC settings,
  this enables **cel shading**. Besides cel shading, `G_LIGHTTOALPHA` can also
  be used for [bump mapping](https://renderu.com/en/spookyiluhablog/post/23631)
  or other unusual CC effects (e.g. texture minus vertex color times lighting).
- New geometry mode bits `G_FRESNEL_COLOR` or `G_FRESNEL_ALPHA` enable
  **Fresnel**. The dot product between a vertex normal and the vector from the
  vertex to the camera is computed; this is then scaled and offset with settable
  factors. The resulting value is then stored to shade color or shade alpha.
  This is useful for:
    - making surfaces like water and glass fade between transparent when viewed
      straight-on and opaque when viewed at a large angle
    - applying a fake "outline" around the border of meshes
    - the N64 bump mapping implementation mentioned above
- New geometry mode bit `G_LIGHTING_SPECULAR` changes lighting computation from
  diffuse to **specular**. If enabled, the vertex normal for lighting is
  replaced with the reflection of the vertex-to-camera vector over the vertex
  normal. Also, a new size value for each light controls how large the light
  reflection appears to be. This technique is lower fidelity in some ways than
  the vanilla `hilite` system, as it is per-vertex rather than per-pixel, but it
  allows the material to be textured normally. Plus, it supports all scene
  lights (including point) with different dynamic colors, whereas the vanilla
  system supports up to two directional lights and more than one dynamic color
  is difficult.
- New geometry mode bit `G_ATTROFFSET_ST_ENABLE` applies a settable offset to
  vertex ST (`SPAttrOffsetST`) after the texture scale. This enables **UV
  scrolling** without CPU intervention.

### Performance improvements

- **56 verts** can fit into DMEM at once, up from 32 verts in F3DEX2, and only
  13% below the 64 verts of reject microcodes. This reduces DRAM traffic and
  RSP time as fewer verts have to be reloaded and re-transformed, and also makes
  display lists shorter.
- New **occlusion plane** system allows the placement of a 3D quadrilateral
  where triangles behind this plane in screen space are culled. This can
  dramatically improve RDP performance by reducing overdraw in scenes with walls
  in the middle, such as a city or an indoor scene.
- If a material display list being drawn is the same as the last material, the
  texture loads in the material are skipped (the second time). This effectively
  results in **auto-batched rendering** of repeated objects, as long as each
  only uses one material. This system supports multitexture and all types of
  loads. If this system incorrectly culls supposedly repeated texture loads
  which actually differ due to segment manipulation, you can locally disable it
  using the new `SPDontSkipTexLoadsAcross` command.
- New `SPTriSnake` command provides a flexible, generalized triangle strip
  primitive, which can better leverage the vertex cache than a traditional
  triangle strip. This packs up to 8 tris per display list command, for up to
  4x less memory bandwidth for loading tris; typical meshes should see a **2-3x
  memory bandwidth reduction** for this step.
- New `SPAlphaCompareCull` command enables culling of triangles whose computed
  shade alpha values are all below or above a settable threshold. This
  **substantially reduces the performance penalty of cel shading**--only tris
  which "straddle" the cel threshold are drawn twice, the others are only drawn
  once. This can also be used to **cull tris which are fully in fog**, replacing
  far clipping which is removed in F3DEX3.
- A new "hints" system encodes the expected size of the target display list into
  call, branch, and return DL commands. This allows only the needed number of DL
  commands in the next DL to be fetched, rather than always fetching full
  buffers, **saving some DRAM traffic** (maybe around 100 us per frame). The
  bits used for this are ignored by HLE.
- **Point lighting is much faster** than in F3DEX2: F3DEX3 takes 77 cycles per
  point light per vertex pair, while F3DEX2_PL takes 144. This is still much
  slower than directional lighting, where both microcodes take about 7 cycles
  per directional light per vertex pair.
- Segment addresses are now resolved relative to other segments (feature by
  Tharo). This enables a strategy for **skipping repeated material DLs**: call
  a segment to run the material, remap the segment in the material to a
  display list that immediately returns, and so if the material is called again
  it won't run.
- New `SPMemset` command fills a specified RDRAM region with a repeated 16-bit
  value. This can be used for clearing the Z buffer or filling the framebuffer
  or the letterbox with a solid color **faster than the RDP can in fill mode**.
  Practical performance may vary due to scheduling constraints.
- New `SPFlush` command can ensure that the RDP starts clearing the framebuffer
  as soon as possible during the frame, instead of waiting a short time for
  further RSP processing.
- The key codepaths for command dispatch, triangle draw, and vertex processing
  (assuming lighting enabled and the occlusion plane disabled with the `NOC`
  configuration) are **slightly faster than in F3DEX2**.

### Miscellaneous

- **Z-fighting of decals has been nearly eliminated**, with only a modest
  increase in overdraw onto the decal of very close occluding geometry. This is
  based on a technique developed by SGI, neglected and removed by Nintendo, and
  re-added by Rare; the F3DEX3 version improves upon it by choosing optimal
  parameters and automatically enabling it for all decals with no code or DL
  changes.
- The reduction in Z buffer precision from F3DEX(1) to F3DEX2 has been reversed,
  and **additional Z buffer precision** beyond F3DEX(1) has been added.
- **Point lighting** has been redesigned. The appearance when a light is close
  to an object has been improved. Fixed a bug in F3DEX2/ZEX point lighting where
  a Z component was accidentally doubled in the point lighting calculations. The
  quadratic point light attenuation factor is now an E3M5 floating-point number
  for a wider representable range.
- Maximum number of directional / point lights **raised from 7 to 9**. Minimum
  number of directional / point lights lowered from 1 to 0 (F3DEX2 required at
  least one). Also supports loading all lights in one DMA transfer
  (`SPSetLights`), rather than one per light.
- New `SPLightToRDP` family of commands (e.g. `SPLightToPrimColor`) writes a
  selectable RDP command (e.g. `DPSetPrimColor`) with the RGB color of a
  selectable light (any including ambient). The alpha channel and any other
  parameters are encoded in the command. With some limitations, this allows the
  tint colors of cel shading to **match scene lighting** with no code
  intervention. Also useful for other lighting-dependent effects.
- The microcode automatically switches between **two lighting implementations**
  depending on which visual features are selected in the particular material.
  The "basic lighting" codepath--which is roughly the same speed as F3DEX2--
  supports all F3DEX2 features (directional lights, texgen), plus packed
  normals, ambient occlusion, and light-to-alpha. The "advanced lighting"
  codepath adds support for point lights, specular, and Fresnel, but is slower
  (though still much faster than F3DEX2 point lighting). You only pay the
  performance penalty for the objects which use these advanced features.


### Profiling

F3DEX3 introduces a suite of performance profiling capabilities. These take the
form of performance counters, which report cycle counts for various operations
or the number of items processed of a given type. There are a total of 21
performance counters across multiple microcode versions. See the Performance
Counters page in the docs.


## Credits

F3DEX3 modifications from F3DEX2 are by Sauraen and are dedicated to the public
domain. `cpu/` C code is entirely by Sauraen and also dedicated to the public
domain.

If you use F3DEX3 in a romhack, please credit "F3DEX3 Microcode - Sauraen" in
your project's in-game Staff Roll or wherever other contributors to your project
are credited.

Other contributors:
- Wiseguy: large chunk of F3DEX2 disassembly documentation and first version of
  build system
- Tharo: relative segment resolution feature, other feature discussions
- Kaze Emanuar: several feature suggestions, testing
- thecozies: Fresnel feature suggestion
- Rasky: memset feature suggestion
- HailToDodongo: packed normals encoding
- coco875: Doxygen / GitHub Pages setup
- ThePerfectLuigi64: CI build setup
- neoshaman: feature discussions
