@page compatibility Backwards Compatibility with F3DEX2

# Backwards Compatibility with F3DEX2

F3DEX3 is backwards compatible with F3DEX2 at the C GBI level for almost all
features and commands. See @ref porting for the relatively small list of code
changes you have to make to your romhack codebase to move from F3DEX2 to F3DEX3.
Also, some relatively obscure internal GBI definitions have been removed. 

F3DEX3 is generally binary backwards compatible with OoT-style display lists for
objects, scenes, etc. **It is not binary compatible with vanilla SM64-style
display lists which encode object colors as light colors**, as all the command
encodings related to lighting have changed.

## GBI Changes Reference

This is a reference if you run into GBI-related problems when building your
romhack after porting it to F3DEX3, or for HLE emulator authors implementing
changes from F3DEX2 to F3DEX3. The "Bin" and "C" columns indicate whether there
have been changes from F3DEX2 to F3DEX3 in binary encoding and C GBI usage
respectively. The "Perf" column indicates whether the performance of this
command (or the overall game performace if this command is used properly) has
significantly increased or decreased relative to F3DEX2 in a way that the
programmer should be aware of. The `g`,`gs`, or `gd` prefixes are all omitted,
e.g. `SPMatrix` refers to `gSPMatrix` and `gsSPMatrix`. `*` means wildcard.

### RDP Commands

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `DPLoadTLUT*`        | =   | =   | Up   | Load is not sent to RDP if repeated in auto-batched rendering. See the GBI comment near `SPDontSkipTexLoadsAcross`. This is a performance optimization only and doesn't affect on-screen output unless the game is buggy / misusing the feature, so this behavior need not be emulated in HLE. |
| `DPLoadBlock*`       | =   | =   | Up   | Same as `DPLoadTLUT*` above. |
| `DPLoadTile*`        | =   | =   | Up   | Same as `DPLoadTLUT*` above. |
| `SPSetOtherMode`     | =   | =   |      |  |
| All other `DP*`      | =   | =   |      | Microcode generally can't change RDP command behavior. |

### Main Drawing

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `SPVertex`           | =   | =   | Up   | Vertex buffer size in F3DEX3 is 56, up from 32 in F3DEX2. Also, many of the new features in F3DEX3 (new lighting, occlusion plane, etc.) are during `SPVertex` processing. |
| `Vtx_t` / `Vtx`      | *   | *   |      | Generally the same, but packed normals go in the `flag` field if enabled. |
| `SPModifyVertex`     | =   | =   |      |  |
| `G_MWO_POINT_RGBA`   | =   | =   |      |  |
| `G_MWO_POINT_ST`     | =   | =   |      |  |
| `G_MWO_POINT_XYSCREEN` | = | =   |      |  |
| `G_MWO_POINT_ZSCREEN`  | = | =   |      |  |
| `G_MV_POINT`         | Rem | Rem |      | Removed because the internal vertex format is no longer a multiple of 8 (DMA word). |
| `SPTexture`          | =   | =   |      |  |
| `SPTextureL`         | =   | =   |      | HW V1 workaround; long since deprecated. |
| `SP1Triangle`        | =   | =   | Up   | Some of the new features in F3DEX3 (occlusion plane, alpha compare culling, decal fix) are during triangle processing. |
| `SP2Triangles`       | =   | =   | Up   | Same as `SP1Triangle` above. |
| `SP1Quadrangle`      | =   | =   | Up   | Same as `SP1Triangle` above. |
| `SPTriStrip`         | New | New | Up   | New command that draws 5 tris from 7 indexes, see GBI. |
| `SPTriFan`           | New | New | Up   | New command that draws 5 tris from 7 indexes, see GBI. |
| `SPMemset`           | New | New | Up   | New command that memsets a RDRAM region faster than the RDP can, for framebuffer or Z-buffer clear. |
| `G_LINE3D`           | Rem | Rem |      | Removed; was a no-op in F3DEX2. |

### Control Logic

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `SPNoOp`             | =   | =   |      |  |
| `SPDisplayList*`     | =   | =   |      | Hints are encoded into previously unused bits, but this is a performance optimization only and will never affect on-screen output, so the hints encoding can be ignored by HLE. |
| `G_DL_PUSH`          | =   | =   |      |  |
| `SPBranchList*`      | =   | =   |      | Same as `SPDisplayList*` above. |
| `G_DL_NOPUSH`        | =   | =   |      |  |
| `SPEndDisplayList*`  | =   | =   |      | Same as `SPDisplayList*` above. |
| `SPCullDisplayList`  | =   | =   |      |  |
| `SPBranchLess*`      | *   | *   |      | In `BrZ` configuration, Z threshold values which are hard-coded into display lists (not based on `G_MAXZ`) must be multiplied by 0x20. See `G_MAXZ` below. |
| `SPLoadUcode*`       | =   | =   |      | Note that F3DEX3_PC (CFG_PROFILING_C) may have compatibility problems with other microcodes. It is specially designed to work with S2DEX for OoT but other microcodes are not guaranteed to work. This is not a limitation in other F3DEX3 variants. |
| `SPDma*`             | =   | =   | Down | Moved to Overlay 3 (slower) as it is rarely used. HLE can't emulate this by definition so must treat it as a no-op; games therefore use it for HLE/LLE detection. |
| `SPSegment`          | *   | *   |      | F3DEX3 supports F3DEX2 binary encoding for SPSegment, but this does not have the relative segment resolution behavior. The new behavior is obtained with the new command encoding with `G_RELSEGMENT`. |
| `G_MW_SEGMENT`       | =   | =   |      |  |
| `G_MWO_SEGMENT_*`    | =   | =   |      | These were never needed. |
| `SPFlush`            | New | New | Up   | This is a performance optimization only and can't be HLE emulated, so it should be treated as a no-op. |
| `G*` (`Gfx` subtypes) | ?  | ?   |      | Deprecated. These did not fully reflect the bits usage in actual commands even in F3DEX2. Almost none of these have been updated for F3DEX3. |

### 3D Space

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `Mtx`                | =   | =   |      |  |
| `SPMatrix`           | Chg | =   | *    | Encoding changed due to multiple flags below changing. |
| `G_MTX_PUSH`         | =   | =   | Down | `SPMatrix` processing with `G_MTX_PUSH` set is moved to Overlay 3 (slower) as games generally should not use the RSP matrix stack for accuracy and performance reasons (see GBI). |
| `G_MTX_NOPUSH`       | =   | =   |      |  |
| `G_MTX_LOAD`         | Chg | =   |      | Encoding inverted (in SPMatrix, not in the definition of `G_MTX_LOAD`). |
| `G_MTX_MUL`          | Chg | =   |      | Encoding inverted (in SPMatrix, not in the definition of `G_MTX_MUL`). |
| `G_MTX_MODEL`        | =   | New |      | New name for `G_MTX_MODELVIEW` as the view matrix must be multiplied into the projection matrix stack in F3DEX3. |
| `G_MTX_VIEWPROJECTION` | = | New |      | New name for `G_MTX_PROJECTION` as the view matrix must be multiplied into the projection matrix stack in F3DEX3. |
| `G_MV_MMTX`          | Chg | New |      | Encoding changed. |
| `G_MV_TEMPMTX0`      | Chg | =   |      | Encoding changed. |
| `G_MV_VPMTX`         | Chg | New |      | New name for `G_MV_PMTX`, encoding changed. |
| `G_MV_TEMPMTX1`      | Chg | =   |      | Encoding changed. |
| `SPPopMatrix*`       | Chg | =   | Down | Moved to Overlay 3 (slower) as games generally should not use the RSP matrix stack for accuracy and performance reasons (see GBI). Encoding is changed due to `G_MV_MMTX` changing. |
| `SPForceMatrix`      | Chg | Chg |      | Converted into no-op. |
| `G_MV_MATRIX`        | Rem | Rem |      | Removed. |
| `G_MW_MATRIX`        | Rem | Rem |      | Removed. |
| `G_MW_FORCEMTX`      | Rem | Rem |      | Removed. |
| `SPViewport`         | *   | *   |      | Command itself is the same, but see `Vp` below. |
| `Vp_t` / `Vp`        | Chg | Chg |      | The Y scale is now negated, and the Z values are different due to the change from `G_MAXZ` to `G_NEW_MAXZ`. |
| `G_MAXZ`             | Rem | Rem |      | Replaced with `G_NEW_MAXZ`. The name change is to force you to update your code--especially viewport definitions with hardcoded constants which are NOT defined in terms of `G_MAXZ`. |
| `G_NEW_MAXZ`         | New | New |      | The equivalent of `G_MAXZ` constant used in viewport calculations. |
| `G_MV_VIEWPORT`      | =   | =   |      |  |
| `SPPerspNormalize`   | Chg | =   |      | Encoding changed. |
| `G_MW_PERSPNORM`     | Rem | Rem |      | Removed. The perspective normalization factor is set via `G_MW_FX` with the changed encoding of `SPPerspNormalize`. |
| `G_MWO_PERSPNORM`    | New | New |      |  |
| `SPClipRatio`        | Chg | Chg |      | Converted into no-op. It is not possible to change the clip ratio from 2 in F3DEX3. Changing the clip ratio was rarely used in production games. |
| `G_MW_CLIP`          | Rem | Rem |      | Removed. See `SPClipRatio` above. |

### Lighting

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `Light_t`, `Light`   | Chg | *   |      | `type` field must be set to 0 (`LIGHT_TYPE_DIR`) to indicate directional light. `size` field for specular added. Otherwise the same, though note that now there is not an extra 8 bytes of padding between lights (the offset between them is 16, not 24). |
| `LIGHT_TYPE_DIR`     | New | New |      | New macro, but the encoding is the same as in F3DEX2_PL. |
| `PointLight_t`       | Chg | *   |      | Same changes as `Light_t`. Also the `kq` field is now interpreted as an E3M5 floating-point number. |
| `LIGHT_TYPE_POINT`   | New | New |      | New macro, but the encoding is the same as in F3DEX2_PL. |
| `Ambient_t`, `Ambient` | = | =   |      | Note that you must use `Ambient`, not `Light`, for the ambient light if you have 9 directional/point lights. |
| `Lights1`, `Lights2`, ... | Chg | * |   | The ambient light is at the end, not the beginning. The data layout matches the RSP internal data layout to enable `SPSetLights`. |
| `Lightsn`            | Chg | *   |      | Same as `Lights1` etc. Also, now 9 directional/point lights. |
| `Lights0`            | Chg | Chg |      | Now only contains Ambient (no Light) because F3DEX3 properly supports zero directional/point lights. |
| `SPDefLights*`       | Chg | =   |      | Matches changes in `Lights*`. Also, there is no need for these in a game with a real lighting engine. |
| `SPDefPointLights*`  | Chg | =   |      | Matches changes in `Lights*`. Also, there is no need for these in a game with a real lighting engine. |
| `SPNumLights`        | Chg | Chg |      | Encoding changed. `ENABLE_POINT_LIGHTS` can now be included. Zero lights is properly supported unlike in F3DEX2. The maximum number of point/directional lights is 9, up from 7. |
| `G_MW_NUMLIGHT`      | =   | =   |      |  |
| `G_MWO_NUMLIGHT`     | =   | =   |      |  |
| `NUML`               | Chg | =   |      | Encoding changed. |
| `NUMLIGHTS_*`        | Chg | =   |      | Deprecated as these are just defined equal to their number, because F3DEX3 supports zero lights. |
| `LIGHT_*`            | =   | =   |      | Deprecated and were not useful in F3DEX2 either. |
| `SPLight`            | Chg | =   |      | Encoding changed. Note that you must use `SPAmbient`, not `SPLight`, for the ambient light if you have 9 directional/point lights. Also note that you should usually use `SPSetLights` unless you need to set individual lights without affecting the others. |
| `SPAmbient`          | New | New |      | New command to upload the ambient light. If you have 0-8 directional/point lights, you can also use `SPLight` for this (slightly slower), but if you have 9 directional/point lights you must use `SPAmbient`. |
| `SPLightColor*`      | Chg | =   |      | Encoding changed. |
| `G_MW_LIGHTCOL`      | =   | =   |      |  |
| `G_MV_LIGHT`         | =   | =   |      |  |
| `SPSetLights*`       | Chg | *   | Up   | Implementation completely different from F3DEX2, uses one DMA transaction regardless of the number of lights. In C, you can/should use dynamically allocated memory for the `Lights*` struct being uploaded, as opposed to `SPDefLights*`, but you need to dereference the pointer passed to `SPSetLights*`. |
| `G_MWO_aLIGHT_*`     | Chg | =   |      | Encodings changed. No longer needed. |
| `G_MWO_bLIGHT_*`     | Chg | =   |      | Encodings changed. No longer needed. |
| `G_MVO_L*`           | Rem | Rem |      | Removed. |
| `SPCameraWorld`      | New | New |      | New command to set the camera position for Fresnel. |
| `PlainVtx`           | New | New |      | For `SPCameraWorld`. |
| `SPLookAt`           | New | New |      | Replaces `SPLookAtX` and `SPLookAtY`. |
| `SPLookAtX`          | Chg | *   |      | Encoding changed; in an attempt at backwards compatibility, defined as `SPLookAt`, which works with basic usage. |
| `SPLookAtY`          | Chg | *   |      | Converted to no-op. |
| `G_MVO_LOOKAT*`      | Rem | Rem |      | Removed with `SPLookAt` changes. |
| `LookAt_t`, `LookAt` | Chg | *   |      | The size is different and most of the non-functional fields have been removed. Code which only accesses the functional fields does not need to change. |
| `Hilite_t`, `Hilite` | =   | =   |      |  |
| `SPFog*`             | =   | =   |      |  |
| `G_MW_FOG`           | =   | =   |      |  |
| `G_MWO_FOG`          | =   | =   |      |  |

### Geometry Mode and New Effect Parameters

| Command                  | Bin | C   | Perf | Notes |
|--------------------------|-----|-----|------|-------|
| `SP*GeometryMode*`       | *   | *   |      | Commands themselves are the same, but many new geometry mode flags, see below. |
| `G_ZBUFFER`              | =   | =   |      |  |
| `G_TEXTURE_ENABLE`       | =   | =   |      | Very old (F3D / HW v1) display lists with this bit set will crash on F3DEX2, but not on F3DEX3. |
| `G_SHADE`                | =   | =   |      |  |
| `G_ATTROFFSET_ST_ENABLE` | New | New |      | New geometry mode bit that enables ST attribute offsets, usually for smooth scrolling. |
| `SPAttrOffsetST`         | New | New |      | New command which writes ST attribute offsets using `G_MWO_ATTR_OFFSET_*`. |
| `G_MWO_ATTR_OFFSET_S`    | New | New |      |  |
| `G_MWO_ATTR_OFFSET_T`    | New | New |      |  |
| `G_AMBOCCLUSION`         | New | New |      |  |
| `SPAmbOcclusion*`        | New | New |      | New commands which write ambient occlusion parameters using `G_MWO_AO_*`. |
| `G_MWO_AO_AMBIENT`       | New | New |      |  |
| `G_MWO_AO_DIRECTIONAL`   | New | New |      |  |
| `G_MWO_AO_POINT`         | New | New |      |  |
| `G_CULL_NEITHER`         | =   | =   |      |  |
| `G_CULL_FRONT`           | =   | =   |      |  |
| `G_CULL_BACK`            | =   | =   |      |  |
| `G_CULL_BOTH`            | =   | =   |      |  |
| `G_PACKED_NORMALS`       | New | New |      | New geometry mode bit that enables packed normals (simultaneous lighting and vertex colors). |
| `G_LIGHTTOALPHA`         | New | New |      | New geometry mode bit that moves the maximum of the three light color channels to shade alpha, usually for cel shading. |
| `G_LIGHTING_SPECULAR`    | New | New |      | New geometry mode bit that changes lighting from diffuse to specular. |
| `G_FRESNEL_COLOR`        | New | New |      | New geometry mode bit that computes Fresnel and places it in all three shade color channels. |
| `G_FRESNEL_ALPHA`        | New | New |      | New geometry mode bit that computes Fresnel and places it in shade alpha. |
| `SPFresnel*`             | New | New |      | New commands which write Fresnel parameters using `G_MWO_FRESNEL_*`. |
| `G_MWO_FRESNEL_SCALE`    | New | New |      |  |
| `G_MWO_FRESNEL_OFFSET`   | New | New |      |  |
| `G_FOG`                  | =   | =   |      |  |
| `G_LIGHTING`             | =   | =   |      |  |
| `G_TEXTURE_GEN`          | =   | =   |      |  |
| `G_TEXTURE_GEN_LINEAR`   | =   | =   |      |  |
| `G_LOD`                  | =   | =   |      | Ignored by all F3DEX* variants. |
| `G_SHADING_SMOOTH`       | =   | =   |      |  |
| `G_LIGHTING_POSITIONAL`  | Chg | Chg |      | This bit is ignored by F3DEX3--both in order to allow point lighting on all vanilla geometry, and because the F3DEX2_PL design of having this as a property of an object/model rather than a property of the lights state is poor design. In F3DEX3, whether point lights are present or not is determined by the `ENABLE_POINT_LIGHTS` flag in `SPNumLights` and `SPSetLights*`. |
| `G_CLIPPING`             | =   | =   |      | Ignored by all F3DEX* variants. |

### Miscellaneous

| Command              | Bin | C   | Perf | Notes |
|----------------------|-----|-----|------|-------|
| `SPOcclusionPlane`   | New | New |      | New command that uploads the occlusion plane coefficients. |
| `OcclusionPlane*`    | New | New |      | Structs for occlusion plane. |
| `SPLightToRDP`       | New | New |      | New command that copies RSP light color to RDP color, see GBI. |
| `SPLightToPrimColor` | New | New |      | Same as `SPLightToRDP` above. |
| `SPLightToFogColor`  | New | New |      | Same as `SPLightToRDP` above. |
| `SPDontSkipTexLoadsAcross` | New | New | Up | New command which locally cancels auto-batched rendering by writing an invalid address to `G_MWO_LAST_MAT_DL_ADDR`. |
| `G_MWO_LAST_MAT_DL_ADDR`   | New | New |      |  |
| `SPAlphaCompareCull` | New | New | Up   | New command which enables culling of tris based on shade alpha values, for cel shading. Normal use of this command in cel shading is a performance optimization only and doesn't affect on-screen output, so it can be treated as a no-op by an initial HLE implementation. But it is easy to write a display list where it does affect on-screen output, so a good HLE implementation should emulate it. |
| `G_ALPHA_COMPARE_CULL_*`   | New | New |      | Settings for `SPAlphaCompareCull`. |
| `G_MWO_ALPHA_COMPARE_CULL` | New | New |      |  |
| `MoveWd`             | =   | =   |      | Regular/valid encodings are the same. |
| `MoveHalfwd`         | New | New |      | Like `MoveWd` but writes 2 bytes instead of 4. |
| `G_MW_FX`            | New | New |      | New moveword table index for base address for many parameters. |
| `G_SPECIAL_1`        | Rem | Rem |      | Removed; in F3DEX2, triggered MVP matrix recalculation. |
| `G_SPECIAL_2`        | Rem | Rem |      | Removed; was a no-op in F3DEX2. |
| `G_SPECIAL_3`        | Rem | Rem |      | Removed; was a no-op in F3DEX2. |
