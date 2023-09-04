# F3DEX3

Modern microcode for N64 romhacks. Will make you want to finally ditch HLE.

## Features

### Most important

- **56 verts** can fit into DMEM at once, up from 32 verts in F3DEX2, and only
  13% below the 64 verts of reject microcodes. This reduces DRAM traffic and
  RSP time as fewer verts have to be reloaded and re-transformed, and also makes
  display lists shorter.

### New visual features

- New geometry mode bit enables simultaneous vertex colors and normals/lighting
  on the same object. There is no loss of color precision, and only a fraction
  of a bit of loss of normals precision in each model space axis. (The competing
  implementation loses no normals precision, but loses 3 bits of each color
  channel.)
- New geometry mode bit enables ambient/directional occlusion for opaque
  materials (vertex alpha multiplies light intensity). Separate factors for how
  much this affects ambient light and how much it affects all directional
  lights. Point lights are never affected by ambient occlusion.
- New geometry mode bit moves light intensity to shade alpha (then shade color
  = vertex color). Useful for cel shading (with alpha compare), bump mapping,
  or unusual CC effects (e.g. vertex color multiplies texture, lighting applied
  after).
- New geometry mode bit enables Fresnel. The dot product between a vertex normal
  and the vector from the vertex to the camera is computed. A settable scale and
  offset converts this to a shade alpha value. This is useful for making
  surfaces fade between transparent when viewed straight-on and opaque when
  viewed at a large angle, or for applying a fake "outline" around the border
  of meshes.
- New geometry mode bits enable attribute offsets (applied after scale) for Z
  and ST. For Z, this fixes decal mode. For ST, this enables UV scrolling
  without CPU intervention.

### Improved existing features

- Point lighting redesigned. Improved appearance when light is close to object.
  Fixed 2*Z bug. Quadratic point light attenuation factor is now an E3M5
  floating-point number. The performance penalty for enabling point lighting,
  and for each additional point light, has been reduced.
- Maximum number of directional / point lights raised from 7 to 9. Minimum
  number of directional / point lights lowered from 1 to 0 (F3DEX2 required at
  least one). Also supports loading all lights in one DMA transfer
  (`SPSetLights`), rather than one per light.
- Clipped triangles are drawn by minimal overlapping scanlines algorithm; this
  slightly improves RDP draw time for large tris.

### New GBI features

- New `SPTriangleStrip` and `SPTriangleFan` commands pack up to 5 tris into one
  64-bit GBI command (up from 2 tris in F3DEX2). In any given object, most tris
  can be drawn with these commands, with only a few at the end drawn with
  `SP2Triangles` or `SP1Triangle`, so this cuts the triangle portion of display
  lists roughly in half.
- New `SPAlphaCompareCull` command enables culling of triangles whose computed
  shade alpha values are all below or above a settable threshold. This
  substantially reduces the performance penalty of cel shading--only tris which
  "straddle" the cel threshold are drawn twice, the others are only drawn once.
- New `SPLightToRDP` family of commands (e.g. `SPLightToPrimColor`) writes a
  selectable RDP command (e.g. `DPSetPrimColor`) with the RGB color of a
  selectable light (any including ambient). The alpha channel and any other
  parameters are encoded in the command. With some limitations, this allows the
  tint colors of cel shading to match scene lighting with no code intervention.
  Possibly useful for other lighting-dependent effects.
- New cull flags system replaces `SPBranchZ` and `SPCullDL` (these are still
  supported, but are slower). This system uses a 24 bit flags value kept in
  DMEM.
    - `SPFlagsVerts`: Loads up to 32 vertex positions, encoded as XYZ0 shorts
      (no ST / RGBA). These do not overwrite or affect the vertex buffer. Sets
      "bit 1" if at least one vert is closer to the camera than the threshold
      in world coords (i.e. object is close, should use higher LoD). Sets
      "bit 0" if "bit 1" is set AND if at least one vert is on the screen side
      of each clip plane (i.e. object is close enough and not culled due to
      offscreen). The shift of "bit 0" / "bit 1" within the flags word is
      selected by a field in the command.
    - `SPFlags1Vert`: Same as `SPFlagsVerts`, but for one vertex only, which is
      encoded in the command instead of taking a DMA transfer.
    - `SPFlagsDist`: Sets the distance threshold in the RDP generic word
      (`G_RDPHALF_1`). The only other commands which overwrite this are
      `SPBranchLessZ*`, `SPLoadUcode*`, `SP*TextureRectangle*`, `DPWord`, and
      `SPPerspNormalize`.
    - `SPFlagsLoad` / `SPFlagsSet` / `SPFlagsClear` / `SPFlagsModify`: All the
      same underlying instruction `SPFlagsMasks`. Instruction contains a 24 bit
      mask which is ANDed with the flags word, and then a 24 bit mask which is
      ORed with the flags word. `SPFlagsLoad` clears all flags then sets
      selected flags. `SPFlagsSet` just sets the selected flags and
      `SPFlagsClear` just clears the selected flags. `SPFlagsModify` sets flags
      within a selectable group.
    - `SPFlagsDram`: Loads 64 bits from the given segmented address, and then
      applies it to the flags as an AND and OR mask like the previous
      instruction.
    - `SPCullFlagsNone`, `SPCullFlagsSome`, `SPCullFlagsAll`, `SPCullFlagsNotAll`:
      24 bit mask. Cull (`SPEndDisplayList`) if none, some (at least one), all,
      or not all (at least one clear) of the flags within the mask are set.
    - `SPBranchFlagsNone`, `SPBranchFlagsSome`, `SPBranchFlagsAll`,
      `SPBranchFlagsNotAll`: same but branch (jump) to segmented address.
    - `SPCallFlagsNone`, `SPCallFlagsSome`, `SPCallFlagsAll`, `SPCallFlagsNotAll`:
      same but call segmented address.



## Porting Your Romhack Codebase to F3DEX3

With a couple minor exceptions, F3DEX3 is generally backwards compatible with
F3DEX2 at the C GBI level. So, for an OoT or MM codebase, just use the new
`gbi.h` and the new microcode and clean/rebuild your project; only a couple very
small changes in the OoT codebase are needed from there. However, more changes
are recommended to increase performance and enable new features.

### Required Changes

- A few small modifications to `ucode_disas.c` and `lookathil.c` in OoT are
  needed to not use removed things from the GBI (see GBI Changes section below).
  Use the compiler errors to guide you for what to remove; removing them does
  not affect normal game functionality.

### Recommended Changes

- Whenever your code sends camera properties to the RSP (VP matrix, viewport,
  etc.), also set the camera world position with `SPCameraWorld`. This is
  required for the cull flags system and for Fresnel.
- Clean up any code using the deprecated, hacky `SPLookAtX` and `SPLookAtY` to
  use `SPLookAt` instead (only a few lines change).
- Change your game engine lighting code to support between 0 and 9 directional /
  point lights, instead of between 1 and 7 (F3DEX2 required at least one,
  though the GBI would create one light with black color if you set zero).
- Change your game engine lighting code to load all lights in one DMA transfer
  with `SPSetLights`, instead of one-at-a-time with repeated `SPLight` commands.
  Also, anywhere you are using `SPLight`, use this only for directional / point
  lights and use `SPAmbient` for ambient lights. Directional / point lights are
  16 bytes and ambient are 8, and the memory reserved for lights in the
  microcode is 16*9+8 bytes, so if you have 9 directional / point lights and
  then use `SPLight` to write the ambient light, it will overflow the buffer by
  8 bytes and corrupt memory.
- Consider setting lights once before rendering a scene and all actors, rather
  than setting lights before rendering each actor. OoT does the latter to
  emulate point lights in a scene with a directional light recomputed per actor.
  You can now just send those to the RSP as real point lights.
- Re-export as many display lists (scenes, objects, skeletons, etc.) as possible
  with fast64 set to F3DEX3 mode, to take advantage of the substantially larger
  vertex buffer and triangle packing commands. For any display lists which are
  not feasible to re-export (e.g. vanilla assets), manually add
  `G_LIGHTING_POSITIONAL` to `SP*GeometryMode` commands to ensure they can
  receive point lighting.


### C GBI Backwards Compatibility with F3DEX2

F3DEX3 is backwards compatible with F3DEX2 at the C GBI level for all commands
except:

- `G_LINE3D` (and `Gfx.line`) has been removed. This command did not actually
  work in F3DEX2 (it behaved as a no-op).
- `G_MW_CLIP` has been removed, and `g*SPClipRatio` has been converted into a
  no-op. Clipping is handled differently in F3DEX3 and cannot be changed from 2.
- `G_MV_MATRIX` and `G_MW_FORCEMTX` have been removed, and `g*SPForceMatrix` has
  been converted into a no-op. This is because there is no MVP matrix in F3DEX3.
- `G_MVO_LOOKATX` and `G_MVO_LOOKATY` have been removed, and `g*SPLookAtX` and
  `g*SPLookAtY` are deprecated. `g*SPLookAtX` has been changed to set both
  directions and `g*SPLookAtY` has been converted to a no-op. To set the lookat
  directions, use `g*SPLookAt`. The lookat directions are now in one 8-byte DMA
  word, so they must always be set at the same time as each other. Most of the
  non-functional fields (e.g. color) of `LookAt` and its sub-types have been
  removed, so code which accesses these fields needs to change. Code which only
  accesses lookat directions should be compatible with no changes.
- TODO update: `g*SPLight` cannot be used to load an ambient light into light 7 (`LIGHT_8`).
  It can be used to load directional, point, or ambient lights into lights 0-6
  (`LIGHT_1` through `LIGHT_7`). To load an ambient light into light 7
  (`LIGHT_8`) (or to load an ambient light into any slot), use `g*SPAmbient`.
  Note that you can now load all your lights with one command, `g*SPSetLights`;
  there is no need to set them one-at-a-time with `g*SPLight` (though you can).
- `G_MV_POINT` has been removed. This was not used in any command; it would have
  likely been used for debugging to copy vertices from DMEM to examine them.
  This does not affect `g*SPModifyVertex`, which is still supported.

 need relatively minor fixes due to
using removed things. The rest of the OoT codebase does not need code changes.

### Binary Display List Backwards Compatibility with F3DEX2

F3DEX3 is generally binary backwards compatible with OoT-style display lists for
objects, scenes, etc. It is not compatible at the binary level with SM64-style
display lists which encode object colors as light colors, as all the command
encodings related to lighting have changed. Of course, if you recompile these
display lists with the new `gbi.h`, it can run them.

The deprecated commands mentioned above in the C GBI section have had their
encodings changed (the original encodings will do bad things / crash). In
addition, the following other commands have had their encodings changed, making
them binary incompatible:
- All lighting-related commands, e.g. `gdSPDefLights*`, `g*SPNumLights`,
  `g*SPLight`, `g*SPLightColor`, `g*SPSetLights*`, `g*SPLookAt`. The basic
  lighting data structures `Light_t`, `PosLight_t`, and `Ambient_t` have not
  changed, but `LookAt_t` and all the larger data structures such as `Lightsn`,
  `Lights*`, and `PosLights*` have changed.
- `g*SPPerspNormalize` binary encoding has changed.
