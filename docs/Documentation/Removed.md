@page removed Removed Features

# Removed Features

These features were present in earlier F3DEX3 versions, but have been removed.

## Legacy Vertex Pipeline (LVP) Configuration

Early versions of F3DEX3 were developed exclusively in an OoT context, where
scenes are almost always RDP bottlenecked. Thus, these versions focused on
reducing RDP time and adding new visual features at the cost of RSP time.

Later, Kaze Emanuar became interested in using F3DEX3 in Return to Yoshi's
Island due to the RDP performance improvements. However, due to the intense
optimization work he had done, his game was relatively balanced in RDP / RSP
time. Thus, when he tried F3DEX3, the decrease in RDP time and increase in RSP
time made the game slower overall, which was not acceptable.

As a result, the LVP configuration of F3DEX3 was developed, to bring
F3DEX2-style vertex processing in exchange for dropping some of the advanced
lighting features (which Kaze was not going to use anyway due to HLE
compatibility). This was implemented, and after much optimization across the
entire microcode, `F3DEX3_LVP_NOC` became slightly faster than F3DEX2 on both
RDP and RSP. This caused Kaze to immediately adopt this configuration of F3DEX3
for Return to Yoshi's Island.

Unfortunately, this meant that if developers wanted to use the advanced lighting
features of F3DEX3 in any part of their project, they were stuck with the much
slower non-LVP configuration of F3DEX3. The desire to have the microcode
automatically swap versions for each material, plus the invention of ways to
include some of the advanced lighting features in the LVP vertex processing
without any performance penalty when not using them, led to the reunion of the
versions. Now you get LVP-style performance when not using some of the advanced
features, and only pay the performance penalty while rendering objects which
use them.

A similar approach was also considered for the NOC configuration--to have the
microcode only compute the occlusion plane when it is enabled. This is
unfortunately infeasible. Register allocation / naming, as well as some
pipelined instructions leading into and out of lighting, are significantly
different between the occlusion plane and NOC versions of vertex processing.
This means the microcode would have to swap between four versions of lighting
code instead of just two, creating much more complexity with the overlay system
and IMEM size issues. Furthermore, the occlusion plane is typically not
enabled/disabled per object, but used when rendering as much of the game
contents as possible to maximize occluded objects. So it is reasonable to choose
the occlusion plane or NOC configuration on a per-frame or even per-scene basis.

## Octahedral Encoding for Packed Normals

Previous F3DEX3 versions encoded packed normals into the unused 2 bytes of each
vertex using a variant of [octahedral encoding](https://knarkowicz.wordpress.com/2014/04/16/octahedron-normal-vector-encoding/).
Using this method, the normals were effectively as precise as with the vanilla
method of replacing vertex RGB with normal XYZ. However, the decoding of this
format was inefficient, partly due to the requirement to also support vanilla
normals at vanilla performance. Once HailToDodongo showed that the community was
willing to accept the moderate precision loss of the much simpler 5-6-5 bit
encoding in [Tiny3D](https://github.com/HailToDodongo/tiny3d), this was adopted
in F3DEX3.

## Clipping minimal scanlines algorithm

Earlier F3DEX3 versions included a modified algorithm for triangulating the
polygon which was formed as the result of clipping. This algorithm broke up the
polygon into triangles in such a way that the fewest scanlines were accessed
multiple times, leading to maximum performance on the RDP. For example, if the
polygon was a diamond shape, this algorithm would always cut it horizontally--
leading to few or no scanlines being touched by both the top and bottom tris--as
opposed to vertically, leading to all scanlines being touched by the left and
right tris.

In testing, this was able to save a few hundred microseconds at best in scenes
with many large clipped tris. However, this feature has been removed, because it
was found to cause undesirable visual artifacts. Other changes to clipping were
experimented with in the past, and ultimately not included. These are not due to
a bug or design issue with the microcode, but a fundamental limitation of the
RDP: vertex colors are interpolated in screen space without perspective
correction. In other words, the shade colors of ANY triangle not flat to the
camera are slightly wrong, regardless of which microcode is in use. The same
world space portion of the triangle will have a slightly different color
depending on how the camera is rotated around it. The issues with clipping are a
result of this.

To show why this is an unavoidable issue on the N64, here is an example:

![Color interpolation example](colorinterp.png)

A: The triangle has vertex colors 0, 128, 255 (same for all three color
components) as shown. It is clipped off the left side of the screen halfway
through its world-space coordinates, so the generated vertices have colors 64
and 192 respectively.

B: Due to perspective and the clipped vertex being near the camera plane, the
clipped polygon is distorted to this shape.

C: If this polygon is triangulated this way, the point in the middle of the
polygon has color 160 (halfway between 64 and 255).

D: If this polygon is instead triangulated this way, the point in the middle of
the polygon has color 96 (halfway between 192 and 0).

Note that BOTH of these are wrong: the correct value for that pixel is 128,
because all points on the horizontal midline of the original triangle are
color 128. The N64 can't draw the correct triangle here--its colors would have
to change nonlinearly along an edge.

The problem with the clipping minimal scanlines algorithm is that it would
switch between cases C and D here based on which diagonal had a larger Y
component. In other words, if the camera moved slightly, the choice of
triangulation might change, causing the middle of the polygon to visibly change
color. This was visible on large scene triangles with lighting: as you walked
around, the colors would have slight but abrupt changes, which look wrong/bad.

The best we can do, which is what all previous F3D family microcodes did and
F3DEX3 does now, is to triangulate in a consistent way, based on the winding
of the input triangles. The results are still wrong, but they're wrong the same
way every frame, so there are no abrupt changes visible.

## Z attribute offsets

Earlier F3DEX3 versions included attribute offsets for vertex Z as well as ST.
By setting this to -2 and drawing an opaque tri, the tri would appear like a
decal, but with no Z-fighting. This has been removed and replaced with the decal
fix, which is automatic and does not require any special setup in the display
list.
