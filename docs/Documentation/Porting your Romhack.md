@page porting Porting Your Romhack Codebase to F3DEX3

# Porting Your Romhack Codebase to F3DEX3

For an OoT codebase, only a few minor changes are required to use F3DEX3.
However, more changes are recommended to increase performance and enable new
features.

How to modify the microcode in your HackerOoT based romhack (note that this is
already done in HackerOoT, so this is provided as a guide for other games):
- Replace `include/ultra64/gbi.h` in your romhack with `gbi.h` from this repo.
- Make the "Required Changes" listed below.
- Build this repo: install the latest version of `armips`, then `make
  F3DEX3_BrZ` or `make F3DEX3_BrW`.
- Copy the microcode binaries (`build/F3DEX3_X/F3DEX3_X.code` and
  `build/F3DEX3_X/F3DEX3_X.data`) to `data` in your romhack repo.
- In `data/rsp.rodata.s`, change the line between `fifoTextStart` and
  `fifoTextEnd` to `.incbin "data/F3DEX3_X.code"` (or wherever you put the
  binary), and similarly change the line between `fifoDataStart` and
  `fifoDataEnd` to `.incbin "data/F3DEX3_X.data"`. After both the `fifoTextEnd`
  and `fifoDataEnd` labels, add a line `.balign 16`.
- If you are planning to ever update the microcode binaries in the future,
  add the following to the Makefile of your romhack, after the section starting
  with `build/data/%.o` (i.e. two lines after that, with a blank line before
  and after): `build/data/rsp.rodata.o: data/F3DEX3_X.code data/F3DEX3_X.data`.
  It is not a mistake that this new line you are adding won't have a second
  indented line after it; it is like the `message_data_static` lines below that.
  This will tell `make` to rebuild `rsp.rodata.o`, which includes the microcode
  binaries, whenever they are changed.
- Clean and build your romhack (`make clean`, `make`).
- Test your romhack and confirm that everything works as intended.
- Make as many of the "Recommended changes" listed below as possible.
- If you start using new features in F3DEX3, make the "Changes required for new
  features" listed below.

## Required Changes

Both OoT and SM64:

- In any place where your game creates a viewport (whether statically or
  dynamically) (search for `Vp` case-sensitive, `SPViewport`, and `G_MAXZ`),
  change the maximum Z value from `G_MAXZ` to `G_NEW_MAXZ` and negate the
  Y scale. For more information, see the comment next to `G_MAXZ` in the GBI.
  Note that your romhack codebase may have the constant hardcoded (usually as
  `511` which is supposed to be `(G_MAXZ/2)`), instead of actually writing an
  expression containing `G_MAXZ`; you need to change these too, there are
  several of these in SM64. Fortunately, it is easy to notice if you have failed
  to update a Y scale, as anything drawn using that viewport will be upside
  down.
- Remove uses of internal GBI features which have been removed in F3DEX3 (see
  @ref compatibility for full list). In OoT, the only changes needed are:
    - In `src/code/ucode_disas.c`, remove the switch statement cases for
      `G_LINE3D`, `G_MW_CLIP`, `G_MV_MATRIX`, `G_MVO_LOOKATX`, `G_MVO_LOOKATY`,
      and `G_MW_PERSPNORM`.
    - In `src/libultra/gu/lookathil.c`, remove the lines which set the `col`,
      `colc`, and `pad` fields.
    - As mentioned above, in each place `G_MAXZ` is used, a compiler error will
      be generated; negate the Y scale in each related viewport and change the
      Z scale and offset to use `G_NEW_MAXZ`.
- Change your game engine lighting code to set the `type` (formerly `pad1`)
  field to 0 in the initialization of any directional light (`Light_t` and
  derived structs like `Light` or `Lightsn`). This change is required because
  otherwise garbage nonzero values may be put in this byte, which was a padding
  byte for a non-point-light microcode but is used to identify the light as
  point or directional in a point light microcode.
    - The change needed in OoT is: in `src/code/z_lights.c`, in
      `Lights_BindPoint`, `Lights_BindDirectional`, and `Lights_NewAndDraw`, set
      `l.type` to 0 right before setting `l.col`.
- If your game already had point lighting, use `ENABLE_POINT_LIGHTS` instead
  of `G_LIGHTING_POSITIONAL` to indicate that point lights are currently active.
  (Static uses of `G_LIGHTING_POSITIONAL` in display lists need not be removed
  as this bit is ignored.)

SM64 only:

- If you are using the vanilla lighting system where light directions are always
  fixed, the vanilla permanent light direction of `{0x28, 0x28, 0x28}` must be
  changed to `{0x49, 0x49, 0x49}`, or everything will be too dark. The former
  vector is not properly normalized, but F3D through F3DEX2 normalize light
  directions in the microcode, so it doesn't matter with those microcodes. The
  two lighting codepaths in F3DEX3 treat light directions and vertex normals
  differently: the fast one works like F3DEX2, but the slow one normalizes
  vertex normals after transforming them and does not modify light directions.
  Thus in this case, the light directions must already be normalized.
- Matrix stack fix (world space lighting / view matrix in VP instead of in M) is
  basically required. If you *really* want camera space lighting, use matrix
  stack fix, transform the fixed camera space light direction by V inverse each
  frame, and send that to the RSP.

## Recommended Changes (Non-Lighting)

- Clean up any code using the deprecated, hacky `SPLookAtX` and `SPLookAtY` to
  use `SPLookAt` instead (this is only a few lines change). Also remove any
  code which writes `SPClipRatio` or `SPForceMatrix`--these are now no-ops, so
  you might as well not write them.
- Avoid using `G_MTX_MUL` and `G_MTX_PUSH` in `SPMatrix`, and `SPPopMatrix*`,
  for performance and accuracy reasons. See the GBI for more information. If
  these are only used in a couple non-critical places such as for GUIs, that's
  okay.
- Re-export as many display lists (scenes, objects, skeletons, etc.) as possible
  with fast64 set to F3DEX3 mode, to take advantage of the substantially larger
  vertex buffer (and eventually when supported by community tools, the triangle
  packing commands and "hints" system).
- `#define REQUIRE_SEMICOLONS_AFTER_GBI_COMMANDS` (at the top of, or before
  including, the GBI) for a more modern, OoT-style codebase where uses of GBI
  commands require semicolons after them. SM64 omits the semicolons sometimes,
  e.g. `gSPDisplayList(gfx++, foo) gSPEndDisplayList(gfx++);`. If you are using
  `-Wpedantic`, using this define is required.
- Once everything in your romhack is ported to F3DEX3 and everything is stable,
  `#define NO_SYNCS_IN_TEXTURE_LOADS` (at the top of, or before including, the
  GBI) and fix any crashes or graphical issues that arise. Display lists
  exported from fast64 already do not contain these syncs, but vanilla display
  lists or custom ones using the texture loading multi-command macros do.
  Disabling the syncs saves a few percent of RDP cycles for each material setup;
  what percentage this is of the total RDP time depends on how many triangles
  are typically drawn between each material change. For more information, see
  the GBI documentation near this define.

## Recommended Changes (Lighting)

- Change your game engine lighting code to load all lights in one DMA transfer
  with `SPSetLights`, instead of one-at-a-time with repeated `SPLight` commands.
  Note that if you are using a pointer (dynamically allocated) rather than a
  direct variable (statically allocated), you need to dereference it; see the
  docstring for this macro in the GBI.
- If you still need to use `SPLight` somewhere after this, use `SPLight` only
  for directional / point lights and use `SPAmbient` for ambient lights.
  Directional / point lights are 16 bytes and ambient are 8, and the first 8
  bytes are the same for both types, so normally it's okay to use `SPLight`
  instead of `SPAmbient` to write ambient lights too. However, the memory space
  reserved for lights in the microcode is 16*9+8 bytes, so if you have 9
  directional / point lights and then use `SPLight` to write the ambient light,
  it will overflow the buffer by 8 bytes and corrupt memory.
- Once you have made the above change for `SPAmbient`, increase the maximum
  number of lights in your engine from 7 to 9.
- Consider setting lights once before rendering a scene and all actors, rather
  than setting lights before rendering each actor. OoT does the latter to
  emulate point lights in a scene with a directional light recomputed per actor.
  You can now just send those to the RSP as real point lights, regardless of
  whether the display lists are vanilla or new.
- If your game already had point lighting, note that the point light kc, kl, and
  kq factors have been changed, so you will need to redesign how game engine
  light parameters (e.g. "light radius") map to these parameters.

## Changes Required for New Features

Each of these changes is required if you want to use the respective new feature,
but is not necessary if you are not using it.

- For Fresnel and specular lighting: Whenever your code sends camera properties
  to the RSP (VP matrix, viewport, etc.), also send the camera world position to
  the RSP with `SPCameraWorld`. For OoT, this is not trivial because the game
  rendering creates and sets the view matrix in the main DL, then renders the
  game contents, then updates the camera, and finally retroactively modifies the
  view matrix at the beginning of the main DL. See the code in @ref camera.
- For specular lighting: Set the `size` field of any `Light_t` and `PosLight_t`
  to an appropriate value based on the game engine parameters for that light.
- For the occlusion plane: Bring the code from `cpu/occlusionplane.c` into your
  game and follow the included instructions.
- For the performance counters: See @ref counters.
