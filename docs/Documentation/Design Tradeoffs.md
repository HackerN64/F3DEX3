@page design-tradeoffs Design Tradeoffs

# What are the tradeoffs for all these new features?

## Vertex Processing RSP Time

See the Microcode Configuration and Performance Results sections above.

## Overlay 4

(Note that in the LVP configuration, Overlay 4 is absent; there is no M inverse
transpose matrix discussed below, and the other commands mentioned below are
directly in the microcode without an overlay, due to there being enough IMEM
space.)

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
- The codepath for `SPMatrix` with `G_MTX_MUL` set (base version only; this is
  moved out of the overlay to normal microcode in the NOC configuration due to
  having extra IMEM space available)
- `SPBranchLessZ*`
- `SPDma_io`

Whenever any of these features is needed, the RSP has to swap to Overlay 4. The
next time lighting or clipping is needed, the RSP has to then swap back to
Overlay 2 or 3. The round-trip of these two overlay loads takes about 5
microseconds of DRAM time including overheads. Fortunately, all the above
features other than the mIT matrix are rarely or never used.

The mIT matrix is needed in F3DEX3 because normals are covectors--they stretch
in the opposite direction of an object's scaling. So while you multiply a vertex
by M to transform it from model space to world space, you have to multiply a
normal by M inverse transpose to go to world space. F3DEX2 solves this problem
by instead transforming light directions into model space with M transpose, and
computing the lighting in model space. However, this requires extra DMEM to
store the transformed lights, and adds an additional performance penalty for
point lighting which is absent in F3DEX3. Plus, having world space normals in
F3DEX3 enables Fresnel and specular lighting.

If an object's transformation matrix stack only includes translations,
rotations, and uniform scale (i.e. same scale in X, Y, and Z), then M inverse
transpose is just a rescaled version of M, and the normals can be transformed
with M directly. It is only when the matrix includes nonuniform scales or shear
that M inverse transpose differs from M. The difference gets larger as the scale
or shear gets more extreme.

F3DEX3 provides three options for handling this (see `SPNormalsMode`):
- `G_NORMALS_MODE_FAST`: Use M to transform normals. No performance penalty.
  Lighting will be somewhat distorted for objects with nonuniform scale or
  shear.
- `G_NORMALS_MODE_AUTO`: The RSP will automatically compute M inverse transpose
  whenever M changes. Costs about 3.5 microseconds of DRAM time per matrix, i.e.
  per object or skeleton limb which has lighting enabled. Lighting is correct
  for nonuniform scale or shear.
- `G_NORMALS_MODE_MANUAL`: You compute M inverse transpose on the CPU and
  manually upload it to the RSP every time M changes.

It is recommended to use `G_NORMALS_MODE_FAST` (the default) for most things,
and use `G_NORMALS_MODE_AUTO` only for objects while they currently have a
nonuniform scale (e.g. Mario only while he is squashed).

## Optimizing for RSP code size

A number of optimizations in F3DEX2 which saved a few cycles but took several
more instructions have been removed. Outside of vertex processing, these have a
very small impact on overall RSP time and no impact on RDP time.

## Far clipping removal

Far clipping is completely removed in F3DEX3. Far clipping is not intentionally
used for performance or aesthetic reasons in levels in vanilla SM64 or OoT,
though it can be seen in certain extreme cases. However, it is used on the SM64
title screen for the zoom-in on Mario's face, so this will look slightly
different.

The removal of far clipping saved a bunch of DMEM space, and enabled other
changes to the clipping implementation which saved even more DMEM space.

NoN (No Nearclipping) is also mandatory in F3DEX3, though this was already the
microcode option used in OoT. Note that tris are still clipped at the camera
plane; nearclipping means they are clipped at the nearplane, which is a short
distance in front of the camera plane.

## Removal of scaled vertex normals

A few clever romhackers figured out that you could shrink the normals on verts
in your mesh (so their length is less than "1") to make the lighting on those
verts dimmer and create a version of ambient occlusion. In the base vertex
pipeline, F3DEX3 normalizes vertex normals after transforming them, which is
required for most features of the lighting system including packed normals, so
this no longer works. However, F3DEX3 has support for ambient occlusion via
vertex alpha, which accomplishes the same goal with some extra benefits:
- Much easier to create: just paint the vertex alpha in Blender / fast64. The
  scaled normals approach was not supported in fast64 and had to be done with
  scripts or by hand.
- The amount of ambient occlusion in F3DEX3 can be set at runtime based on
  variable scene lighting, whereas the scaled normals approach is baked into the
  mesh.
- F3DEX3 can have the vertex alpha affect ambient, directional, and point lights
  by different amounts, which is not possible with scaled normals. In fact,
  scaled normals never affect the ambient light, contrary to the concept of
  ambient occlusion.

Furthermore, for partial HLE compatibility, the same mesh can have the ambient
occlusion information encoded in both scaled normals and vertex alpha at the
same time. HLE will ignore the vertex alpha AO but use the scaled normals;
F3DEX3 will fix the normals' scale but then apply the AO.

The only case where scaled normals work but F3DEX3 AO doesn't work is for meshes
with vertex alpha actually used for transparency (therefore also no fog).

Note that in LVP mode, scaled normals are supported and work the same way as in
F3DEX2, while ambient occlusion is not supported.

## RDP temporary buffers shrinking

In FIFO versions of F3DEX2, there are two DMEM buffers to hold RDP commands
generated by the microcode, which are swapped and copied to the FIFO in DRAM.
These each had the capacity of two-and-a-fraction full-size triangle commands
(i.e. triangles with shade, texture, and Z-buffer). For short commands (e.g.
texture loads, color combiner, etc.) there is a slight performance gain from
having longer buffers in DMEM which are swapped to DRAM less frequently. And, if
a substantial portion of triangles were rendered without shade or texture such
that three tris could fit per buffer, being able to fit the three tris would
also slightly improve performance. However, in practice, the vast majority of
the FIFO is occupied by full-size tris, so the buffers are effectively only two
tris in size because a third tri can't fit. So, their size has been reduced to
two tris, saving a substantial amount of DMEM.

## Segment 0

Segment 0 is now reserved: ensure segment 0 is never set to anything but
0x00000000. In F3DEX2 and prior this was only a good idea (and SM64 and OoT
always follow this); in F3DEX3 segmented addresses are now resolved relative to
other segments. That is, `gsSPSegment(0x08, 0x07001000)` sets segment 8 to the
base address of segment 7 with an additional offset of 0x1000. So for correct
behavior when supplying a direct-mapped or physical address such as 0x80101000,
segment 0 must always be 0x00000000 so that this address resolves to e.g.
0x101000 as expected in this example.

## Non-textured tris

In F3DEX2, the RSP time for drawing non-textured tris was significantly lower
than for textured tris, by skipping a chunk of computation for the texture
coefficients if they were disabled. In F3DEX3, little to no computation is
skipped when textures are disabled, which means that the performance gain from
disabling textures in F3DEX2 has been mostly eliminated. (RDP time savings from
avoiding loading a texture are unaffected of course.) However, almost all
materials use textures, and F3DEX3 is a little faster at drawing textured tris
than F3DEX2, so this is still a benefit overall.

## Obscure semantic differences from F3DEX2 that should never matter in practice

- `SPLoadUcode*` corrupts the current M inverse transpose matrix state. If using
  `G_NORMALS_MODE_FAST`, this doesn't matter. If using `G_NORMALS_MODE_AUTO`,
  you must send the M matrix to the RSP again after returning to F3DEX3 from the
  other microcode (which would normally be done anyway when starting to draw the
  next object). If using `G_NORMALS_MODE_MANUAL`, you must send the updated
  M inverse transpose matrix to the RSP after returning to F3DEX3 from the other
  microcode (which would normally be done anyway when starting to draw the next
  object).
- Changing fog settings--i.e. enabling or disabling `G_FOG` in the geometry mode
  or executing `SPFogFactor` or `SPFogPosition`--between loading verts and
  drawing tris with those verts will lead to incorrect fog values for those
  tris. In F3DEX2, the fog settings at vertex load time would always be used,
  even if they were changed before drawing tris.
