@page minimal-scanlines What happened to the clipping minimal scanlines algorithm?

# What happened to the clipping minimal scanlines algorithm?

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
because all points on the horizontal midline of the original triangle are color
128. The N64 can't draw the correct triangle here--its colors would have to
change nonlinearly along an edge.

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
