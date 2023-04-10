# F3DEX3

### C GBI Backwards Compatibility with F3DEX2

F3DEX3 is backwards compatible with F3DEX2 at the C GBI level for all commands
except:

- `G_LINE3D` (and `Gfx.line`) has been removed. This command did not actually
  work in F3DEX2 (it behaved as a no-op).
- `G_MW_CLIP` has been removed, and `g*SPClipRatio` has been converted into a
  no-op. Clipping is handled differently in F3DEX3 and it is not recommended to
  ever change the clip ratio from its default of 2. For microcode development,
  it can be changed with `g*SPClipModSettings`.
- `G_MV_MATRIX` and `G_MW_FORCEMTX` have been removed, and `g*SPForceMatrix` has
  been converted into a no-op. This is because there is no MVP matrix in F3DEX3.
- `G_MVO_LOOKATX` and `G_MVO_LOOKATY` have been removed, and `g*SPLookAtX` and
  `g*SPLookAtY` are deprecated. `g*SPLookAtX` has been changed to set both
  directions and `g*SPLookAtY` has been converted to a no-op. To set the lookat
  directions, use `g*SPLookAt`. The lookat directions are now in one 8-bit DMA
  word, so they must always be set at the same time as each other. Most of the
  non-functional fields (e.g. color) of `LookAt` and its sub-types have been
  removed, so code which accesses these fields needs to change. Code which only
  accesses lookat directions should be compatible with no changes.
- `g*SPLight` cannot be used to load an ambient light into light 7 (`LIGHT_8`).
  It can be used to load directional, point, or ambient lights into lights 0-6
  (`LIGHT_1` through `LIGHT_7`). To load an ambient light into light 7
  (`LIGHT_8`) (or to load an ambient light into any slot), use `g*SPAmbient`.
  Note that you can now load all your lights with one command, `g*SPSetLights`;
  there is no need to set them one-at-a-time with `g*SPLight` (though you can).

`ucode_disas.c` and `lookathil.c` in OoT need relatively minor fixes due to
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
