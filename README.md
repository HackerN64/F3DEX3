# F3DEX3

Modern microcode for N64 romhacks. Will make you want to finally ditch HLE.

## Features

### Most important

- **56 verts** can fit into DMEM at once, up from 32 verts in F3DEX2, and only
  13% below the 64 verts of reject microcodes. This reduces DRAM traffic and
  RSP time as fewer verts have to be reloaded and re-transformed, and also makes
  display lists shorter.

### New visual features

- New geometry mode bit `G_PACKED_NORMALS` enables simultaneous vertex colors
  and normals/lighting on the same object. There is no loss of color precision,
  and only a fraction of a bit of loss of normals precision in each model space
  axis. (The competing implementation loses no normals precision, but loses 3
  bits of each color channel.)
- New geometry mode bit `G_AMBOCCLUSION` enables ambient/directional occlusion
  for opaque materials. Paint the ambient light level into the vertex alpha
  channel; separate factors (set with `SPAmbOcclusion`) control how much this
  affects the ambient light and how much it affects all directional lights.
  Point lights are never affected by ambient occlusion.
- New geometry mode bit `G_LIGHTTOALPHA` moves light intensity (maximum of
  R, G, and B of what would normally be the shade color after lighting) to shade
  alpha. Then, if `G_PACKED_NORMALS` is also enabled, the shade RGB is set to
  the vertex RGB. Together with alpha compare and some special display lists
  from fast64 which draw triangles two or more times with different CC settings,
  this enables cel shading. Besides cel shading, `G_LIGHTTOALPHA` can also be
  used for bump mapping or other unusual CC effects (e.g. vertex color
  multiplies texture, lighting applied after).
- New geometry mode bit `G_FRESNEL` enables Fresnel. The dot product between a
  vertex normal and the vector from the vertex to the camera is computed. A
  settable scale and offset from `SPFresnel` converts this to a shade alpha
  value. This is useful for making surfaces fade between transparent when viewed
  straight-on and opaque when viewed at a large angle, or for applying a fake
  "outline" around the border of meshes.
- New geometry mode bits `G_ATTROFFSET_ST_ENABLE` and `G_ATTROFFSET_Z_ENABLE`
  apply settable offsets to vertex ST (`SPAttrOffsetST`) and/or Z
  (`SPAttrOffsetZ`) values. These offsets are applied after their respective
  scales. For Z, this enables a method of drawing coplanar surfaces like decals
  but without the Z fighting which can happen with the RDP's native decal mode.
  For ST, this enables UV scrolling without CPU intervention.

### New commands for performance

- New `SPTriangleStrip` and `SPTriangleFan` commands pack up to 5 tris into one
  64-bit GBI command (up from 2 tris in F3DEX2). In any given object, most tris
  can be drawn with these commands, with only a few at the end drawn with
  `SP2Triangles` or `SP1Triangle`, so this cuts the triangle portion of display
  lists roughly in half.
- New system for culling objects which are offscreen or far away, which saves
  memory traffic, RSP time, and even RDP time compared to the old commands
  `SPCullDL` and `SPBranchLessZ*`. See "Bounding vertices system" below.
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

### Improved existing features

- Point lighting has been redesigned. The appearance when a light is close to an
  object has been improved. Fixed a bug in F3DEX2 point lighting where a Z
  component was accidentally doubled in the point lighting calculations. The
  quadratic point light attenuation factor is now an E3M5 floating-point number.
  The performance penalty for point lighting has been reduced.
- Maximum number of directional / point lights raised from 7 to 9. Minimum
  number of directional / point lights lowered from 1 to 0 (F3DEX2 required at
  least one). Also supports loading all lights in one DMA transfer
  (`SPSetLights`), rather than one per light.

### HLE-compatible cycle-shaving optimizations for Kaze Emanuar

- The 56 vertex buffer is compatible with Kaze's supported HLE because that HLE
  incorrectly supports 64 vertices for all microcodes.
- The new culling system is compatible with Kaze's supported HLE because it uses
  command encodings which were previously treated as no-ops, and DLs can be
  structured so that if all the new commands are ignored, the full objects are
  always drawn.
- "Hints" system encodes the expected size of the target display list into call,
  branch, and return DL commands. This allows only the needed number of DL
  commands in the next DL to be fetched, rather than always fetching full
  buffers, saving some DRAM traffic (maybe around 100 us per frame). The bits
  used for this are ignored by HLE.
- F3DEX3 discards certain texture loads if they are identical to the last
  texture load. This dramatically reduces the performance penalty of repeatedly
  loading the same texture for instances of the same object--assuming the
  objects have only one texture, that texture is not CI, and that texture is of
  appropriate size so that it is loaded with `DPLoadBlock` rather than
  `DPLoadTile`.
- Clipped triangles are drawn by minimal overlapping scanlines algorithm; this
  slightly improves RDP draw time for large tris (max of about 500 us per frame,
  usually much less or zero).


## Bounding vertices system

The features of this system are easiest to understand with an example. Suppose
you have five houses in a scene, and each house has a chimney. The following
display list draws the chimneys, but culls each one if it is offscreen or too
far away, and skips the texture and material load if they are ALL not drawn.

```
Gfx chimneys_dl[] = {
// Set the W value representing the threshold at which the chimneys will be
// culled if they are farther than this. If you don't want objects to disappear
// no matter how far away they are, use 0x7FFFFFFF here.
gsSPWFarThreshold(0x01000000),
// Load vertices representing a bounding shape around one chimney, and check if
// this is on screen and close enough. Initialize the bounding flags results.
gsSPBoundingVerts(house1ChimneyBoundingBox, 8, G_BOUNDINGVERTS_REPLACE),
// Load bounding boxes around the other chimneys. Push each result on the stack.
gsSPBoundingVerts(house2ChimneyBoundingBox, 8, G_BOUNDINGVERTS_PUSH),
gsSPBoundingVerts(house3ChimneyBoundingBox, 8, G_BOUNDINGVERTS_PUSH),
gsSPBoundingVerts(house4ChimneyBoundingBox, 8, G_BOUNDINGVERTS_PUSH),
gsSPBoundingVerts(house5ChimneyBoundingBox, 8, G_BOUNDINGVERTS_PUSH),
// Return from this DL--skip the texture load--if all chimneys are invisible.
gsSPReturnNoneVisibleHint(1), // About hints: see SPEndDisplayListHint
// Load the chimney material.
gsDPLoadTextureBlock(...),
...
// Pop the visibility flag for chimney 5. If it is clear, branch past drawing
// chimney 5.
gsSPPopBranchNotVisibleHint(chimneys_dl_4, 1),
// Draw chimney 5.
gsSPVertex(...),
gsSP2Triangles(...),
...
// no gsSPEndDisplayList(); continue directly into the next display list.
};
Gfx chimneys_dl_4[] = {
// Pop the visibility flag for chimney 4. If it is clear, branch past drawing
// chimney 4.
gsSPPopBranchNotVisibleHint(chimneys_dl_3, 1),
// Draw chimney 4.
gsSPVertex(...),
gsSP2Triangles(...),
...
};
Gfx chimneys_dl_3[] = {
// Repeat until chimney 1.
// Instead of popping the visibility flag for chimney 1, just return if
// invisible.
gsSPReturnNoneVisibleHint(1),
// Draw chimney 1.
gsSPVertex(...),
gsSP2Triangles(...),
...
gsSPEndDisplayList()
};

```

The advantages of this system over the old `SPCullDL` and `SPBranchLessZ*`
system are:
- The vertices which are being examined for their positions are 8 bytes each
  (X Y Z 0 shorts), not full vertices with ignored ST and RGBA, halving their
  space occupied in the object/scene and the memory traffic.
- These vertices are loaded into a temporary buffer and do not overwrite the
  vertex buffer, in case needed values were being kept there.
- Not only is lighting computation never performed on these vertices regardless
  of the lighting geometry mode flags (manually disabling lighting is not
  necessary), a large chunk of the per-vertex processing is also skipped.
- The per-vertex processing uses an early return, so once the object is
  determined to be visible, no further vertices are processed. (This only saves
  RSP time, not DRAM traffic, as all the vertices are loaded at the beginning.)
- Both on-screen and distance are evaluated as part of the same operation,
  unlike vanilla where these were evaluated separately (and practically,
  `SPBranchLessZ*` was used rarely and only for LoD, not for distance culling).
- W is used to represent depth like in F3DZEX. Using W instead of Z to represent
  distance makes its computation independent of obscure RDP Z-buffer parameters.
  Unlike comparing distance in world coordinates, W is correlated to the
  object's effective size on screen; in other words, if you zoom in the camera
  without moving it, objects which were previously too far away will reappear.
- Results from many sub-objects are pushed into the same bounding flags value.
  Not only does this allow materials to be skipped, but the flags can then be
  popped and the individual sub-objects culled without any further processing.
  Examining bounding shapes around multiple sub-objects can often determine that
  all the sub-objects are offscreen, while one giant bounding shape containing
  all the sub-objects may be onscreen.
- The bounding flags value can be written directly with `SPLoadBoundingFlags`,
  allowing parts of DLs to be easily enabled or disabled from CPU code.
- F3DEX3 also provides `SPPopCallVisible`; F3DEX2 did not directly have a method
  for calling display lists based on culling results, only branching. Note that
  it is generally recommended to use the pattern in the code example above
  rather than calling sub-DLs with `SPPopCallVisible`, due to DL command buffer
  considerations and HLE compatibility.

`SPCullDL` and `SPBranchLessZ*` are still supported for backwards compatibility.
`SPCullDL` is just like in F3DEX2 but the new system will be faster than it.
`SPBranchLessZ*` is moved to overlay 4 (see below) so it will be slower than it
was in F3DEX2.

Also note that bounding shapes do not have to be axis-aligned bounding boxes;
they did not have to be in previous F3D* versions either. Any convex shape
containing your object is allowed; for more info see `SPBoundingVerts`.


## Porting Your Romhack Codebase to F3DEX3

For an OoT codebase, only a few minor changes are required to use F3DEX3.
However, more changes are recommended to increase performance and enable new
features.

There is only one build-time option for F3DEX3: enable `CFG_G_BRANCH_W` if the
microcode is replacing F3DZEX (i.e. OoT or MM), otherwise do not enable this
option if the microcode is replacing F3DEX2 or an earlier F3D version (i.e.
SM64). Enabling this option makes `SPBranchLessZ*` use the vertex's W
coordinate, otherwise it uses the screen Z coordinate. New display lists should
use the bounding vertices system instead of `SPBranchLessZ*`, so this only
matters for vanilla display lists used in your romhack.

How to modify the microcode in your HackerOoT based romhack (steps may be
similar for other games):
- Replace `include/ultra64/gbi.h` in your romhack with `gbi.h` from this repo.
- Make the "Required Changes" listed below.
- Build this repo (`make F3DEX3`).
- Copy the microcode binaries (`build/F3DEX3/F3DEX3.code` and
  `build/F3DEX3/F3DEX3.data`) to somewhere in your romhack repo, e.g. `data`.
- In `data/rsp.rodata.s`, change the line between `fifoTextStart` and
  `fifoTextEnd` to `.incbin "data/F3DEX3.code"` (or wherever you put the
  binary), and similarly change the line between `fifoDataStart` and
  `fifoDataEnd` to `.incbin "data/F3DEX3.data"`. After both the `fifoTextEnd`
  and `fifoDataEnd` labels, add a line `.balign 16`.
- If you are planning to ever update the microcode binaries in the future,
  add the following to the Makefile of your romhack, after the section starting
  with `build/data/%.o` (i.e. two lines after that, with a blank line before
  and after): `build/data/rsp.rodata.o: data/F3DEX3.code data/F3DEX3.data`. It
  is not a mistake that this new line you are adding won't have a second
  indented line after it; it is like the `message_data_static` lines below that.
  This will tell `make` to rebuild `rsp.rodata.o`, which includes the microcode
  binaries, whenever they are changed.
- Clean and build your romhack (`make clean`, `make`).
- Test your romhack and confirm that everything works as intended.
- Make as many of the "Recommended changes" listed below as possible.

### Required Changes

- Remove uses of obscure GBI features which have been removed in F3DEX3 (see
  "C GBI Compatibility" section below for full list). In OoT, the only changes
  needed are:
    - In `src/code/ucode_disas.c`, remove the switch statement cases for
      `G_LINE3D`, `G_MW_CLIP`, `G_MV_MATRIX`, `G_MVO_LOOKATX`, and
      `G_MVO_LOOKATY`.
    - In `src/libultra/gu/lookathil.c`, remove the lines which set the `col`,
      `colc`, and `pad` fields.
- Change your game engine lighting code to set the `type` (formerly `pad1`)
  field to 0 in the initialization of any directional light (`Light_t` and
  derived structs like `Light` or `Lightsn`). F3DEX3 ignores the state of the
  `G_LIGHTING_POSITIONAL` geometry mode bit in all display lists, meaning both
  directional and point lights are supported for all display lists (including
  vanilla). The light is identified as directional if `type` == 0 or point if
  `kc` > 0 (`kc` and `type` are the same byte). This change is required because
  otherwise garbage nonzero values may be put in the padding byte, leading
  directional lights to be misinterpreted as point lights.
    - The change needed in OoT is: in `src/code/z_lights.c`, in
      `Lights_BindPoint`, `Lights_BindDirectional`, and `Lights_NewAndDraw`, set
      `l.type` to 0 right before setting `l.col`.

### Recommended Changes (Non-Lighting)

- If you are using Fresnel at all, whenever your code sends camera properties to
  the RSP (VP matrix, viewport, etc.), also send the camera world position to
  the RSP with `SPCameraWorld`.
- Clean up any code using the deprecated, hacky `SPLookAtX` and `SPLookAtY` to
  use `SPLookAt` instead (this is only a few lines change). Also remove any
  code which writes `SPClipRatio` or `SPForceMatrix`--these are now no-ops, so
  you might as well not write them.
- Avoid using `G_MTX_MUL` in `SPMatrix`. That is, make sure your game engine
  computes a matrix stack on the CPU and sends the final matrix for each object
  / limb to the RSP, rather than multiplying matrices on the RSP. OoT already
  does the former for precision / accuracy reasons and only uses `G_MTX_MUL` in
  a couple obscure places; it is okay to leave those. This change is recommended
  because the `G_MTX_MUL` mode of `SPMatrix` has been moved to Overlay 4 in
  F3DEX3 (see below), making it substantially slower than it was in F3DEX2. It
  still functions the same though so you can use it if it's really needed.
- Re-export as many display lists (scenes, objects, skeletons, etc.) as possible
  with fast64 set to F3DEX3 mode, to take advantage of the substantially larger
  vertex buffer, triangle packing commands, "hints" system, etc.
- Once everything in your romhack is ported to F3DEX3 and everything is stable,
  `#define NO_SYNCS_IN_TEXTURE_LOADS` and fix any crashes or graphical issues
  that arise. Display lists exported from fast64 already do not contain these
  syncs, but vanilla display lists or custom ones using the texture loading
  multi-command macros do. Disabling the syncs saves a few percent of RDP cycles
  for each material setup; what percentage this is of the total RDP time depends
  on how many triangles are typically drawn between each material change. For
  more information, see the GBI documentation near this define.

### Recommended Changes (Lighting)

- Change your game engine lighting code to load all lights in one DMA transfer
  with `SPSetLights`, instead of one-at-a-time with repeated `SPLight` commands.
- Anywhere you are still using `SPLight` after this, use `SPLight` only for
  directional / point lights and use `SPAmbient` for ambient lights. Directional
  / point lights are 16 bytes and ambient are 8, and the first 8 bytes are the
  same for both types, so normally it's okay to use `SPLight` instead of
  `SPAmbient` to write ambient lights too. However, the memory space reserved
  for lights in the microcode is 16*9+8 bytes, so if you have 9 directional /
  point lights and then use `SPLight` to write the ambient light, it will
  overflow the buffer by 8 bytes and corrupt memory.
- Once you have made the above change for `SPAmbient`, increase the maximum
  number of lights in your engine from 7 to 9.
- Consider setting lights once before rendering a scene and all actors, rather
  than setting lights before rendering each actor. OoT does the latter to
  emulate point lights in a scene with a directional light recomputed per actor.
  You can now just send those to the RSP as real point lights, regardless of
  whether the display lists are vanilla or new.
- If you are porting a game which already had point lighting (e.g. Majora's
  Mask), note that the point light kc, kl, and kq factors have been changed, so
  you will need to redesign how game engine light parameters (e.g. "light
  radius") map to these parameters.


## Backwards Compatibility with F3DEX2

### C GBI Compatibility

F3DEX3 is backwards compatible with F3DEX2 at the C GBI level for all commands
except:

- The `G_SPECIAL_*` command IDs have been removed. `G_SPECIAL_2` and
  `G_SPECIAL_3` were no-ops in F3DEX2, and `G_SPECIAL_1` was a trigger to
  recalculate the MVP matrix. There is no MVP matrix in F3DEX3 so this is
  useless.
- `G_LINE3D` (and `Gfx.line`) has been removed. This command did not actually
  work in F3DEX2 (it behaved as a no-op).
- `G_MW_CLIP` has been removed, and `SPClipRatio` has been converted into a
  no-op. Clipping is handled differently in F3DEX3 and cannot be changed from 2.
- `G_MV_MATRIX`, `G_MW_MATRIX`, and `G_MW_FORCEMTX` have been removed, and
  `SPForceMatrix` has been converted into a no-op. This is because there is no
  MVP matrix in F3DEX3.
- `G_MVO_LOOKATX` and `G_MVO_LOOKATY` have been removed, and `SPLookAtX` and
  `SPLookAtY` are deprecated. `SPLookAtX` has been changed to set both
  directions and `SPLookAtY` has been converted to a no-op. To set the lookat
  directions, use `SPLookAt`. The lookat directions are now in one 8-byte DMA
  word, so they must always be set at the same time as each other. Most of the
  non-functional fields (e.g. color) of `LookAt` and its sub-types have been
  removed, so code which accesses these fields needs to change. Code which only
  accesses lookat directions should be compatible with no changes.
- As discussed above, the `pad1` field of `Light_t` is renamed to `type` and
  must be set to zero.
- If you do not raise the maximum number of lights from 7 to 9, the lighting GBI
  commands are backwards compatible. However, if you do raise the number of
  lights, you must use `SPAmbient` to write the ambient light, as discussed
  above. Note that you can now load all your lights with one command,
  `SPSetLights`.
- `G_MV_POINT` has been removed. This was not used in any command; it would have
  likely been used for debugging to copy vertices from DMEM to examine them.
  This does not affect `g*SPModifyVertex`, which is still supported, though this
  is moved to Overlay 4 (see below) so it will be slower than in F3DEX2.

### Binary Display List Compatibility

F3DEX3 is generally binary backwards compatible with OoT-style display lists for
objects, scenes, etc. It is not compatible at the binary level with SM64-style
display lists which encode object colors as light colors, as all the command
encodings related to lighting have changed. Of course, if you recompile these
display lists with the new `gbi.h`, it can run them.

The deprecated commands mentioned above in the C GBI section have had their
encodings changed (the original encodings will do bad things / crash). In
addition, the following other commands have had their encodings changed, making
them binary incompatible:
- All lighting-related commands, e.g. `gdSPDefLights*`, `SPNumLights`,
  `SPLight`, `SPLightColor`, `SPLookAt`. The basic lighting data structures
  `Light_t`, `PosLight_t`, and `Ambient_t` have not changed (except for the
  requirement to set `type` to zero in directional lights), but `LookAt_t` and
  all the larger data structures such as `Lightsn`, `Lights*`, and `PosLights*`
  have changed.
- `SPPerspNormalize` binary encoding has changed.


## What are the tradeoffs for all these new features?

### Overlay 4

F3DEX2 contains Overlay 2, which does lighting, and Overlay 3, which does
clipping (run on any large triangle which extends a large distance offscreen).
These overlays are more RSP assembly code which are loaded into the same space
in IMEM. If the wrong overlay is loaded when the other is needed, the proper
one is loaded and then code jumps to it. Display lists which do not use lighting
can stay on Overlay 3 at all times. Display lists for things that are typically
relatively small on screen, such as characters, can stay on Overlay 2 at all
times, because even when a triangle overlaps the edge of the screen, it
typically moves fully off the screen and is discarded before it reaches the
clipping bounds (2x the screen size).

In F3DEX2, the only case where the overlays are swapped frequently is for
scenes with lighting, because they have large triangles which often extend far
offscreen (Overlay 3) but also need lighting (Overlay 2). Worst case, the RSP
will load Overlay 2 once for every `SPVertex` command and then load Overlay 3
for every set of `SP*Triangle*` commands.

(If you're curious, Overlays 0 and 1 are not related to 2 and 3, and have to do
with starting and stopping RSP tasks. During normal display list execution,
Overlay 1 is always loaded.)

F3DEX3 introduces Overlay 4, which can occupy the same IMEM as Overlay 2 and 3.
This overlay contains handlers for:
- Computing the inverse transpose of the model matrix M (abbreviated as mIT),
  discussed below
- The codepath for `SPMatrix` with `G_MTX_MUL` set
- `SPBranchLessZ*`
- `SPModifyVertex`
- `SPDma_io`

Whenever any of these features is needed, the RSP has to swap to Overlay 4. The
next time lighting or clipping is needed, the RSP has to then swap back to
Overlay 2 or 3. The round-trip of these two overlay loads takes about 3.5
microseconds of DRAM time including overheads. Fortunately, all the above
features other than the mIT matrix are rarely or never used.

The mIT matrix is needed in F3DEX3 because normals are covectors--they stretch
in the opposite direction of an object's scaling. So while you multiply a vertex
by M to transform it from model space to world space, you have to multiply a
normal by M inverse transpose to go to world space. F3DEX2 solves this problem
by instead transforming light directions into model space with M transpose, and
computing the lighting in model space. However, this requires extra DMEM to
store the transformed lights, and adds an additional performance penalty for
point lighting which is absent in F3DEX3. Plus, having world space normals
enables the Fresnel feature.

If an object's transformation matrix stack only included translations,
rotations, and uniform scale (i.e. same scale in X, Y, and Z), then M inverse
transpose is just a rescaled version of M, and the normals can be transformed
with M directly. It is only when the matrix includes nonuniform scales or shear
that M inverse transpose differs from M. The difference gets larger as the scale
or shear gets more extreme.

F3DEX3 provides three options for handling this (see `SPNormalsMode`):
- `G_NORMALS_MODE_FAST`: Use M to transform normals. No performance penalty.
  Lighting will be slightly wrong for objects with nonuniform scale or shear.
- `G_NORMALS_MODE_AUTO`: The RSP will automatically compute M inverse transpose
  whenever M changes. Costs about 3.5 microseconds of DRAM time per matrix, i.e.
  per object or skeleton limb which has lighting enabled. Lighting is correct
  for nonuniform scale or shear.
- `G_NORMALS_MODE_MANUAL`: You compute M inverse transpose on the CPU and
  manually upload it to the RSP every time M changes.

It is recommended to use `G_NORMALS_MODE_FAST` (the default) for most things,
and use `G_NORMALS_MODE_AUTO` only for objects while they currently have a
nonuniform scale (e.g. Mario only while he is squashed).

### Optimizing for RSP code size

A number of over-zealous optimizations in F3DEX2 which saved a cycle or two but
took several more instructions have been removed. F3DEX3 will often be slightly
slower than F3DEX2 in RSP cycles (not DRAM traffic or RDP time), especially for
large quantities of very short commands. Note that for certain codepaths such as
point lighting, the RSP will now be faster than in F3DEX2, and the improved
performance from all the new microcode features should more than make up for
these slight reductions in efficiency.

### Far clipping removal

Far clipping is completely removed in F3DEX3. Far clipping is not intentionally
used for performance or aesthetic reasons in levels in vanilla SM64 or OoT,
though it can be seen in certain extreme cases. However, it is used on the SM64
title screen for the zoom-in on Mario's face, so this will look slightly
different.

The removal of far clipping saved a bunch of DMEM space, and enabled other
changes to the clipping implementation which saved even more DMEM space.

NoN (No Nearclipping) is also mandatory in F3DEX3, though this was already the
microcode option used in OoT.

### RDP temporary buffers shrinking

In FIFO versions of F3DEX2, there are two DMEM buffers to hold RDP commands
generated by the microcode, which are swapped and copied to the FIFO in DRAM.
These each had the capacity of two-and-a-fraction full-size triangle commands
(i.e. triangles with shade, texture, and Z-buffer). For short commands (e.g.
texture loads, color combiner, etc.) there is a minor performance gain from
having longer buffers in DMEM which are swapped to DRAM less frequently. And, if
a substantial portion of triangles were rendered without shade or texture such
that three tris could fit per buffer, being able to fit the three tris would
also slightly improve performance. However, in practice, the vast majority of
the FIFO is occupied by full-size tris, so the buffers are effectively only two
tris in size because a third tri can't fit. So, their size has been reduced to
two tris, saving a substantial amount of DMEM.
