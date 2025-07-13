@page configuration Microcode Configuration

# Microcode Configuration

There are a few selectable configuration settings when building F3DEX3, which
can be enabled in any combination. With a couple minor exceptions, none of these
settings affect the GBI--in fact, you can swap between the microcode versions on
a per-frame basis if you build multiple versions into your romhack.

## No Occlusion Plane (NOC)

If you are not using the occlusion plane feature in your romhack, you can
use this configuration, which removes the computation of the occlusion plane
in the vertex processing pipeline, saving some RSP time.

If you care about performance, please do consider using the occlusion plane!
RDP time savings of 3-4 ms are common in scenes with reasonable occlusion
planes, and even saving a third of the total RDP time can sometimes happen.
Furthermore, when even a small percentage of the total triangles drawn are
occluded, not only is RDP time saved (which is the point), but RSP time is also
saved from not having to process those tris. This can offset the extra RSP time
for computing the occlusion plane for all vertices.

You can also build both the NOC and base microcodes into your ROM and switch
between them on a per-frame basis. If there is no occlusion plane active or the
best occlusion plane candidate would be very small on screen, you can use the
NOC microcode and save RSP time. If there is a significant occlusion plane, you
can use the base microcode and reduce the RDP time. You could also determine
which version to use on the profiling results from the previous frame: if the
RSP is the bottleneck (e.g. the RDP `CLK - CMD` is high), use the NOC version,
and otherwise use the base version.

## Profiling

F3DEX3 includes many performance counters. There are far too many counters for a
single microcode to maintain, so multiple configurations of the microcode can be
built, each containing a different set of performance counters. These can be
swapped while the game is running so the full set of counters can be effectively
accessed over multiple frames.

There are a total of 21 performance counters, including:
- Counts of vertices, triangles, rectangles, matrices, DL commands, etc.
- Times the microcode was processing vertices, processing triangles, stalled
  because the RDP FIFO in DMEM was full, and stalled waiting for DMAs to finish
- A counter enabling a rough measurement of how long the RDP was stalled
  waiting for RDRAM for I/O to the framebuffer / Z buffer (spoiler: often
  half to two thirds of the total RDP time!)

The default configuration of F3DEX3 provides a few of the most basic counters.
The additional profiling configurations, called A, B, and C (for example
`F3DEX3_BrZ_PA`), provide additional counters, but have two default features
removed to make space for the extra profiling. These two features were selected
because their removal does not affect the RDP render time.
- The `SPLightToRDP` commands are removed (they become no-ops)
- Flat shading mode, i.e. `!G_SHADING_SMOOTH`, is removed (all tris are smooth)

## Branch Depth Instruction (`BrZ` / `BrW`)

Use `BrZ` if the microcode is replacing F3DEX2 or an earlier F3D version (i.e.
SM64), or `BrW` if the microcode is replacing F3DZEX (i.e. OoT or MM). This
controls whether `SPBranchLessZ*` uses the vertex's W coordinate or screen Z
coordinate. If you are creating a new project for any game without using vanilla
scenes, and you're considering using this instruction for LoD, you should use
`BrW`.

## Debug Normals (`dbgN`)

Debug Normals has been moved out of the Makefile as it is not a microcode
version intended to be shipped. It can still be enabled by changing
`CFG_DEBUG_NORMALS equ 0` to `1` in the microcode.

To help debug lighting issues when integrating F3DEX3 into your romhack, this
feature causes the vertex colors of any material with lighting enabled to be set
to the normals. When F3DEX3 is using the "basic" lighting codepath, these are
the model space normals, and when it is using the "advanced" lighting codepath
(point lights, specular, or Fresnel) these are transformed, normalized world
space normals. The X, Y, and Z components map to R, G, and B, with each
dimension's conceptual (-1.0 ... 1.0) range mapped to (0 ... 255). This also
breaks vertex alpha and texgen / lookat.

Some ways to use this for debugging are:
- If the normals have obvious problems (e.g. flickering, or not changing
  smoothly as the object rotates / animates), there is likely a problem with the
  model space normals or the M matrix. Conversely, if there is a problem with
  the standard lighting results (e.g. flickering) but the normals don't have
  this problem, the problem is likely in the lighting data.
- If using the "advanced" lighting codepath, check that the colors don't change
  based on the camera position, but DO change as the object rotates, so that the
  same side of an object in world space is always the same color.
- Make a simple object like an octahedron or sphere, view it in game, and check
  that the normals are correct. A normal pointing along +X would be
  (1.0, 0.0, 0.0), meaning (255, 128, 128) or pink. A normal pointing along -X
  would be (-1.0, 0.0, 0.0), meaning (0, 128, 128) or dark cyan. Bright, fully
  saturated colors like green (0, 255, 0), yellow (255, 255, 0), or black should
  never appear as these would correspond to impossibly long normals.
- Make the same object (octahedron is easiest in this case) with vertex colors
  which match what the normals should be, and compare them.
