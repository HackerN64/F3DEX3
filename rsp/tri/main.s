align_with_warning 8, "One instruction of padding before tris"

.macro tri_v1_move
    vmov    $v6[1], $v7[5] // Move next to cur vertex 1 addr. Must be after main tri code cause $v6 not saved.
.endmacro

G_TRI2_handler: // If we jumped here, want $ra next to be G_TRI1_handler
G_QUAD_handler:
    li      $ra, (G_TRI1_handler - (tris_end - G_TRI1_handler))
G_TRI1_handler: // Whether we get here from cmd handler or prev tri, $ra == G_TRI1_handler
    // $v6: -- V1 -- -- -- -- -- -- This vertex address 1
    // $v7: -- -- V2 V3 -- N1 N2 N3 This and next vertex addresses
    mfc2    $2, $v7[4]
    mfc2    origV1Addr, $v6[2] // Can't move this up, $v6 is not ready yet when coming from return_and_end_mat
    vmudh   $v6, vOne, $v6[1] // elem 2 of v6 = vertex 1 addr
    addi    $ra, $ra, (tris_end - G_TRI1_handler) // So next go to tris_end
tri_from_snake:
    vmudh   $v4, vOne, $v7[2] // elem 2 of v4 = vertex 2 addr
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 0x4000  // Increment number of tris requested
.endif
    vmudh   $v8, vOne, $v7[3] // elem 2 of v8 = vertex 3 addr
    mfc2    $3, $v7[6]
    vmov    $v7[3], $v7[7]    // Move next to cur vertex 3 addr.
tri_from_clip:
    vnxor   tHAtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    llv     $v6[0], VTX_SCR_VEC(origV1Addr) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vnxor   tMAtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vnxor   tLAtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vmov    $v7[2], $v7[6]    // Move next to cur vertex 2 addr.
    lhu     $6, VTX_CLIP(origV1Addr)
    vmudh   $v2, vOne, $v6[1] // v2 all elems = y-coord of vertex 1
    lhu     $7, VTX_CLIP($2)
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    lhu     $8, VTX_CLIP($3)
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    andi    $11, $6, CLIP_SCRN_NPXY | CLIP_CAMPLANE // All three verts on wrong side of same plane
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    and     $11, $11, $7
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    and     $11, $11, $8
    vmrg    tHPos, $v6, $v4   // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    bnez    $11, return_and_end_mat // Then the whole tri is offscreen, cull
     // 16 cycles (for tri2 first tri; tri1/only subtract 1 from counts)
     vmudh  $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    vmadh   $v26, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    lhu     $24, activeClipPlanes
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    sll     $20, vGeomMid, 29 // Original bit 10 (now bit 2) in the sign bit, for facing cull
    vmrg    tLPos, $v6, $v4   // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    or      $10, $6, $7
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    or      $10, $10, $8      // $10 = all clip bits which are true for any verts
    vmrg    $v4, tHPos, $v8   // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    mfc2    $9, $v26[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    tHPos, $v8, tHPos // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    and     $10, $10, $24     // If clipping is enabled, check clip flags
    vlt     $v29, $v6, $v2    // VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    bnez    $10, ovl234_clipmisc_entrypoint // Facing info and occlusion may be garbage if need to clip
     // 24 cycles
     srl    $11, $9, 31       // = 0 if x prod positive (back facing), 1 if x prod negative (front facing)
    vmudh   $v3, vOne, $v31[5] // 0x4000; some rounding factor
    sllv    $11, $20, $11     // Sign bit = bit 10 of geom mode if back facing, bit 9 if front facing
    vmrg    tMPos, $v4, tLPos // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    bltz    $11, return_and_end_mat // Cull if bit is set (culled based on facing)
     // 27 cycles
     vmrg   tLPos, tLPos, $v4 // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
tSubPxHF equ $v4
    vmudn   tSubPxHF, tHPos, $v31[5] // 0x4000
    beqz    $9, return_and_end_mat  // If cross product is 0, tri is degenerate (zero area), cull.
     // 29 cycles
.if !CFG_NO_OCCLUSION_PLANE
     and    $6, $6, $7
.endif
     vsub   tPosMmH, tMPos, tHPos
.if !CFG_NO_OCCLUSION_PLANE
    and     $6, $6, $8
.endif
    vsub    tPosLmH, tLPos, tHPos
.if !CFG_NO_OCCLUSION_PLANE
    andi    $6, $6, CLIP_OCCLUDED
.endif
    vsub    tPosHmM, tHPos, tMPos
.if !CFG_NO_OCCLUSION_PLANE
    bnez    $6, tri_culled_by_occlusion_plane // Cull if all verts occluded
     // 33 cycles
.endif
     mfc2   $1, tHPos[4]     // tHPos = lowest Y value = highest on screen (x, y, addr)
    // 32 cycles if NOC (34 if occlusion plane)
tPosCatI equ $v15 // 0 X L-M; 1 Y L-M; 2 X M-H; 3 X L-H; 4-7 garbage
    vsub    tPosCatI, tLPos, tMPos
    mfc2    $2, tMPos[4]     // tMPos = mid vertex (x, y, addr)
    vmov    tPosCatI[2], tPosMmH[0]
.if !ENABLE_PROFILING
    andi    $11, vGeomMid, G_SHADING_SMOOTH >> 8
.endif
    vmudh   $v29, tPosMmH, tPosLmH[0]
    li      $20, -8       // 0xFFF8; constant for some mask below
t1WI equ $v13 // elems 0, 4, 6
    vmadh   $v29, tPosLmH, tPosHmM[0]
    mfc2    $3, tLPos[4]     // tLPos = highest Y value = lowest on screen (x, y, addr)
tXPF equ $v16 // Triangle cross product
tXPI equ $v17
    vreadacc tXPI, ACC_UPPER
    add     $19, origV1Addr, flatV1Offset
    vreadacc tXPF, ACC_MIDDLE
    lpv     tHAtI[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
    vrcp    $v20[0], tPosCatI[1]
    lpv     tMAtI[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vmov    tPosCatI[3], tPosLmH[0]
    lpv     tLAtI[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vrcph   $v22[0], tXPI[1]
.if !ENABLE_PROFILING
    lpv     $v25[0], VTX_COLOR_VEC($19) // Load RGB from orig vtx 1 for flat shading
.endif
tXPRcpF equ $v23 // Reciprocal of cross product (becomes that * 4)
tXPRcpI equ $v24
    vrcpl   tXPRcpF[1], tXPF[1]
.if !ENABLE_PROFILING
    beqz    $11, tri_flat_shading  // Branch if G_SHADING_SMOOTH is clear
.endif
     vrcph  tXPRcpI[1], $v31[2]            // 0
tri_return_from_flat_shading:
    // 43 cycles
    vrcp    $v20[2], tPosMmH[1]
    ssv     tPosMmH[2], 0x0030(rdpCmdBufPtr) // MmHY -> first short (temp mem)
    vrcph   $v22[2], tPosMmH[1]
    llv     t1WI[0], VTX_INV_W_VEC($1)
    vrcp    $v20[3], tPosLmH[1]
    llv     t1WI[8], VTX_INV_W_VEC($2)
    vrcph   $v22[3], tPosLmH[1]
    llv     t1WI[12], VTX_INV_W_VEC($3)
    vmudl   tHAtI, tHAtI, vTRC_0100 // vertex color 1 >>= 8
    lb      $11, (alphaCompareCullMode)($zero)
    vmudl   tMAtI, tMAtI, vTRC_0100 // vertex color 2 >>= 8
    lw      $6, VTX_INV_W_VEC($1) // $6, $7, $8 = 1/W for H, M, L
    vmudl   tLAtI, tLAtI, vTRC_0100 // vertex color 3 >>= 8
    lw      $7, VTX_INV_W_VEC($2)
    vmudl   $v29, $v20, vTRC_0020
    lw      $8, VTX_INV_W_VEC($3)
    vmadm   $v22, $v22, vTRC_0020
    bnez    $11, tri_alpha_compare_cull
     vmadn  $v20, $v31, $v31[2] // 0
// $v6 <- tPosMmH; $v6 clobbered in alpha compare cull
tri_return_from_alpha_compare_cull: // Uses $v25, $v26
    // 53 cycles
tPosCatF equ $v25
    vmudm   tPosCatF, tPosCatI, vTRC_1000
    mtc2    $20, tMPos[14] // 0xFFF8; only elem 0, 1, 2 of this reg used now
    vmadn   tPosCatI, $v31, $v31[2] // 0
    sub     $11, $6, $7  // Four instr: $6 = max($6, $7)
    vsubc   tSubPxHF, vZero, tSubPxHF
    sra     $10, $11, 31
tSubPxHI equ $v26
    vsub    tSubPxHI, vZero, vZero
    and     $11, $11, $10
    vmudm   $v29, tPosCatF, $v20
    sub     $6, $6, $11
    vmadl   $v29, tPosCatI, $v20
    sub     $11, $6, $8  // Four instr: $6 = max($6, $8)
    vmadn   $v20, tPosCatI, $v22
    sra     $10, $11, 31
    vmadh   tPosCatI, tPosCatF, $v22
    and     $11, $11, $10
    vmudl   $v29, tXPRcpF, tXPF
    sub     $6, $6, $11
    vmadm   $v29, tXPRcpI, tXPF
    mfc2    $7, tXPI[1]
    vmadn   tXPF, tXPRcpF, tXPI
    lbu     $14, geometryModeLabel + 3 // Load lowest byte for G_SHADE, G_ZBUFFER. Also has G_ATTROFFSET_ST_ENABLE, but G_TRI_FILL will get OR'd into it and force that set.
    vmadh   tXPI, tXPRcpI, tXPI
    lbu     $9, textureSettings1 + 3 // Texture enabled = 0x2
    vand    $v22, $v20, tMPos[7] // 0xFFF8
    lsv     tMAtI[14], VTX_SCR_Z($2)
    vcr     tPosCatI, tPosCatI, vTRC_0100
    lsv     tLAtI[14], VTX_SCR_Z($3)
    vmudh   $v29, vOne, $v31[4] // 4
    ori     $11, $14, G_TRI_FILL // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadn   tXPF, tXPF, $v31[0] // -4
    or      $11, $11, $9 // Incorporate whether textures are enabled into the triangle command id
    vmadh   tXPI, tXPI, $v31[0] // -4
    sw      $6, 0x0010(rdpCmdBufPtr) // Store max of three verts' 1/W (upper) to temp mem
tMx1W equ $v25 // <- tPosCatF
    vmudn   $v29, $v3, tHPos[0]
    llv     tMx1W[0], 0x0010(rdpCmdBufPtr) // Load max of three verts' 1/W
    vmadl   $v29, $v22, tSubPxHF[1]
    ssv     tMPos[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadm   $v29, tPosCatI, tSubPxHF[1]
    lsv     tMAtF[14], VTX_SCR_Z_FRAC($2)
// $v2 <- tMPos
    vmadn   $v2, $v22, tSubPxHI[1]
    ssv     tLPos[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
    vmadh   $v3, tPosCatI, tSubPxHI[1]
    lsv     tLAtF[14], VTX_SCR_Z_FRAC($3)
    vrcph   $v29[0], tMx1W[0] // Reciprocal of max 1/W = min W
    ssv     tHPos[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
tMnWF equ $v10 // <- tLPos
    vrcpl   tMnWF[0], tMx1W[1]
    lbu     $10, textureSettings1 + 2  // Level and tile
t1WF equ $v14 // <- tHPos
    vmudh   t1WF, vOne, t1WI[1q]
    sb      $11, 0x0000(rdpCmdBufPtr) // Store the triangle command id
tMnWI equ $v25 // <- tMx1W
    vrcph   tMnWI[0], $v31[2]     // 0
    lw      $19, otherMode1
tSTWHMI equ $v22 // H = elems 0-2, M = elems 4-6; init W = 7FFF
    vmudh   tSTWHMI, vOne, $v31[7]  // 0x7FFF
    sb      $zero, materialCullMode // Covers tri write (non early exit)
    vmudm   $v29, t1WI, tMnWF[0] // 1/W each vtx * min W = 1 for one of the verts, < 1 for others
    llv     tSTWHMI[0], VTX_TC_VEC($1)
    vmadl   $v29, t1WF, tMnWF[0]
    ssv     tPosLmH[0], 0x0032(rdpCmdBufPtr) // LmHX -> second short (temp mem)
    vmadn   t1WF, t1WF, tMnWI[0]
    llv     tSTWHMI[8], VTX_TC_VEC($2)
    vmadh   t1WI, t1WI, tMnWI[0]
    ssv     tPosHmM[0], 0x0034(rdpCmdBufPtr) // HmMX -> third short (temp mem)
tSTWLI equ $v10 // L = elems 4-6; init W = 7FFF
tSTWLF equ $v13
    vmudh   tSTWLI, vOne, $v31[7]  // 0x7FFF
    andi    $19, $19, ZMODE_DEC    // Mask to two Z mode bits
    set_vcc_11110001                // select RGBA___Z or ____STW_
    llv     tSTWLI[8], VTX_TC_VEC($3)
    vmudm   $v29, tSTWHMI, t1WF[0h] // (S, T, 7FFF) * (1 or <1) for H and M
    addi    $19, $19, -ZMODE_DEC  // Check if equal to decal mode
    vmadh   tSTWHMI, tSTWHMI, t1WI[0h]
    ldv     tPosLmH[8], 0x0030(rdpCmdBufPtr) // MmHY -> e4, LmHX -> e5, HmMX -> e6
tSTWHMF equ $v25 // <- tMnWI
    vmadn   tSTWHMF, $v31, $v31[2]  // 0
    andi    $7, $7, 0x0080 // Extract the left major flag from $7
    vmudm   $v29, tSTWLI, t1WF[6]  // (S, T, 7FFF) * (1 or <1) for L
    or      $7, $7, $10 // Combine the left major flag with the level and tile from the texture settings
    vmadh   tSTWLI, tSTWLI, t1WI[6]
    sb      $7, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vmadn   tSTWLF, $v31, $v31[2]  // 0
    sdv     tSTWHMI[0], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int to temp mem
    vmrg    tMAtI, tMAtI, tSTWHMI // Merge S, T, W Mid into elems 4-6
    sdv     tSTWHMF[0], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac to temp mem
    vmrg    tMAtF, tMAtF, tSTWHMF // Merge S, T, W Mid into elems 4-6
// $v25 <- tSTWHMF
    ldv     tHAtI[8], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int from temp mem
    vmrg    tLAtI, tLAtI, tSTWLI // Merge S, T, W Low into elems 4-6
    ldv     tHAtF[8], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac from temp mem
    vmrg    tLAtF, tLAtF, tSTWLF // Merge S, T, W Low into elems 4-6
.if !ENABLE_PROFILING
    addi    perfCounterA, perfCounterA, 1 // Increment number of tris sent to RDP
.endif
    // 96 cycles
    vmudl   $v29, tXPF, tXPRcpF
    lsv     tHAtF[14], VTX_SCR_Z_FRAC($1)
    vmadm   $v29, tXPI, tXPRcpF
    lsv     tHAtI[14], VTX_SCR_Z($1) // contains R, G, B, A, S, T, W, Z
    vmadn   tXPRcpF, tXPF, tXPRcpI
    lh      $1, VTX_SCR_VEC($2)
    vmadh   tXPRcpI, tXPI, tXPRcpI
    addi    $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
    vmudh   tPosLmH, tPosLmH, $v31[0h] // e1 LmHY * -4 = 4*HmLY; e456 MmHY,LmHX,HmMX *= 4
    andi    $3, $14, G_SHADE
tAtLmHF equ $v10
tAtLmHI equ $v9
tAtMmHF equ $v13
tAtMmHI equ $v27
    vsubc   tAtLmHF, tLAtF, tHAtF
    sll     $1, $1, 14
    vsub    tAtLmHI, tLAtI, tHAtI
    sb      $zero, materialCullMode // This covers tri write out
    vsubc   tAtMmHF, tMAtF, tHAtF
    sw      $1, 0x0008(rdpCmdBufPtr)         // Store XL edge coefficient
    vsub    tAtMmHI, tMAtI, tHAtI
    ssv     $v3[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
// DaDx = (v3 - v1) * factor + (v2 - v1) * factor
tDaDxF equ $v2
tDaDxI equ $v3
    vmudn   $v29, tAtLmHF, tPosLmH[4] // MmHY * 4
    ssv     $v2[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[4] // MmHY * 4
    ssv     $v3[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vmadn   $v29, tAtMmHF, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     $v2[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     tPosCatI[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vreadacc tDaDxF, ACC_MIDDLE
    ssv     $v20[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vreadacc tDaDxI, ACC_UPPER
    ssv     tPosCatI[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
// DaDy = (v2 - v1) * factor + (v3 - v1) * factor
tDaDyF equ $v6
// tDaDyI <- $v27
    vmudn   $v29, tAtMmHF, tPosLmH[5] // LmHX * 4
    ssv     $v20[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[5] // LmHX * 4
    ssv     tPosCatI[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vmadn   $v29, tAtLmHF, tPosLmH[6] // HmMX * 4
    ssv     $v20[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[6] // HmMX * 4
    sll     $11, $3, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vreadacc tDaDyF, ACC_MIDDLE
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vreadacc tDaDyI, ACC_UPPER
    sll     $11, $9, 5              // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
// DaDx, DaDy *= more factors
    vmudl   $v29, tDaDxF, tXPRcpF[1]
    add     rdpCmdBufPtr, $1, $11   // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, tDaDxI, tXPRcpF[1]
    andi    $14, $14, G_ZBUFFER     // Get the value of G_ZBUFFER from the current geometry mode
    vmadn   tDaDxF, tDaDxF, tXPRcpI[1]
    sll     $11, $14, 4             // Shift (geometry mode & G_ZBUFFER) by 4 to get 0x10 if G_ZBUFFER is set
    vmadh   tDaDxI, tDaDxI, tXPRcpI[1]
    move    $10, rdpCmdBufPtr       // Write Z here
    vmudl   $v29, tDaDyF, tXPRcpF[1]
    add     rdpCmdBufPtr, rdpCmdBufPtr, $11  // Increment the triangle pointer by 0x10 bytes (depth coefficients) if G_ZBUFFER is set
    vmadm   $v29, tDaDyI, tXPRcpF[1]
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Check if we need to write out to RDP
    vmadn   tDaDyF, tDaDyF, tXPRcpI[1]
    sdv     tDaDxF[0], 0x0018($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   tDaDyI, tDaDyI, tXPRcpI[1]
    sdv     tDaDxI[0], 0x0008($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
// DaDe = DaDx * factor
tDaDeF equ $v8
tDaDeI equ $v9
    // 125 cycles
    vmadl   $v29, tDaDxF, $v20[3]
    sdv     tDaDxF[8], 0x0018($1)   // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadm   $v29, tDaDxI, $v20[3]
    sdv     tDaDxI[8], 0x0008($1)   // Store DsDx, DtDx, DwDx texture coefficients (integer)
    vmadn   tDaDeF, tDaDxF, tPosCatI[3]
    sdv     tDaDyF[0], 0x0038($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   tDaDeI, tDaDxI, tPosCatI[3]
    sdv     tDaDyI[0], 0x0028($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
// Base value += DaDe * factor
    vmudn   $v29, tHAtF, vOne[0]
    sdv     tDaDyF[8], 0x0038($1)   // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadh   $v29, tHAtI, vOne[0]
    sdv     tDaDyI[8], 0x0028($1)   // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadl   $v29, tDaDeF, tSubPxHF[1]
    sdv     tDaDeF[0], 0x0030($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadm   $v29, tDaDeI, tSubPxHF[1]
    sdv     tDaDeI[0], 0x0020($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    vmadn   tHAtF, tDaDeF, tSubPxHI[1]
    sdv     tDaDeF[8], 0x0030($1)   // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    vmadh   tHAtI, tDaDeI, tSubPxHI[1]
    sdv     tDaDeI[8], 0x0020($1)   // Store DsDe, DtDe, DwDe texture coefficients (integer)
    // All values start in element 7. "a", attribute, is Z. Need
    // tHAtI, tHAtF, tDaDxI, tDaDxF, tDaDeI, tDaDeF, tDaDyI, tDaDyF
    // VCC is still 11110001
    // 135 cycles
    vmrg    tDaDyI, tDaDyF, tDaDyI[7] // Elems 6-7: DzDyI:F
    beqz    $19, tri_decal_fix_z
     vmrg   tDaDxI, tDaDxF, tDaDxI[7] // Elems 6-7: DzDxI:F
tri_return_from_decal_fix_z:
    vmrg    tDaDeI, tDaDeF, tDaDeI[7] // Elems 6-7: DzDeI:F
    sdv     tHAtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    vmrg    $v10, tHAtF, tHAtI[7]  // Elems 6-7: ZI:F
    sdv     tHAtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    tri_v1_move                    // From return_and_end_mat, we didn't go there
    sdv     tHAtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    sdv     tHAtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)
    slv     tDaDyI[12], 0x0C($10)  // DzDyI:F
    slv     tDaDxI[12], 0x04($10)  // DzDxI:F
    slv     tDaDeI[12], 0x08($10)  // DzDeI:F
    bltz    dmemAddr, return_and_end_mat     // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
     slv    $v10[12], 0x00($10)   // ZI:F
     // 146 cycles
.include "rsp/flush_rdp_buffer.s"
