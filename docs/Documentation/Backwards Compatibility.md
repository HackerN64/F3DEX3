@page compatibility Backwards Compatibility with F3DEX2

# Backwards Compatibility with F3DEX2

## C GBI Compatibility

F3DEX3 is backwards compatible with F3DEX2 at the C GBI level for all features
and commands except:

- The `G_SPECIAL_*` command IDs have been removed. `G_SPECIAL_2` and
  `G_SPECIAL_3` were no-ops in F3DEX2, and `G_SPECIAL_1` was a trigger to
  recalculate the MVP matrix. There is no MVP matrix in F3DEX3 so this is
  useless.
- `G_LINE3D` (and `Gfx.line`) has been removed. This command did not actually
  work in F3DEX2 (it behaved as a no-op).
- `G_MW_CLIP` has been removed, and `SPClipRatio` has been converted into a
  no-op. Clipping is handled differently in F3DEX3 and the clip ratio cannot be
  changed from 2.
- `G_MV_MATRIX`, `G_MW_MATRIX`, and `G_MW_FORCEMTX` have been removed, and
  `SPForceMatrix` has been converted into a no-op. This is because there is no
  MVP matrix in F3DEX3.
- `G_MV_POINT` has been removed. This was not used in any command; it would have
  likely been used for debugging to copy vertices from DMEM to examine them.
  This does not affect `SPModifyVertex`, which is still supported.
- `G_MW_PERSPNORM` has been removed; `SPPerspNormalize` is still supported but
  is encoded differently, no longer using this define.
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
  `SPSetLights`, so it is not usually necessary to use `SPLight` and `SPAmbient`
  at all.

## Binary Display List Compatibility

F3DEX3 is generally binary backwards compatible with OoT-style display lists for
objects, scenes, etc. **It is not compatible at the binary level with SM64-style
display lists which encode object colors as light colors**, as all the command
encodings related to lighting have changed. Of course, if you recompile these
display lists with the new `gbi.h`, it can run them.

The deprecated commands mentioned above in the C GBI section have had their
encodings changed (the original encodings will do bad things / crash). In
addition, all lighting-related commands--e.g. `gdSPDefLights*`, `SPNumLights`,
`SPLight`, `SPLightColor`, `SPLookAt`--have had their encodings changed, making
them binary incompatible. The lighting data structures, e.g. `Light_t`,
`PosLight_t`, `LookAt_t`, `Lightsn`, `Lights*`, `PosLights*`, etc., have also
changed--generally only slightly, so most code is compatible with no changes.

`SPSegment` has been given a different command id (`G_RELSEGMENT` vs.
`G_MOVEWORD`) to facilitate relative segmented address translation. The
original binary encoding is still valid, but does not support relative
translation like the new encoding. However, recompiling with the C GBI will
always use the new encoding.
