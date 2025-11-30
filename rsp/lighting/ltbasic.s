    bnez    viLtFlag, ltbasic_setup_after_xfrm  // Skip if lights were valid
     addi   lbFakeAmb, ambLight, ltBufOfs  // Ptr to load amb light from; normally actual ambient light
xfrm_dir_lights:
lpWrld  equ $v11  // light pair world direction
lpMdl   equ $v12  // light pair model space direction (not yet normalized)
lpFinal equ $v13  // light pair normalized model space direction
lpSqrI  equ $v14  // Light pair direction squared int part
lpSqrF  equ $v15  // Light pair direction squared frac part
lpMdl2  equ $v19  // Copy of lpMdl for pipelining
lpSumI  equ $v20  // Light pair direction sum of squares int part
lpSumF  equ $v21  // Light pair direction sum of squares frac part
lpRsqI  equ $v22  // Light pair reciprocal square root int part
lpRsqF  equ $v23  // Light pair reciprocal square root frac part
    // Transform directional lights' direction by M transpose.
    // First, load M transpose. $v0-$v7 is the MVP matrix and $v24-$v31 is
    // permanent values, leaving $v8-$v15 and $v16-$v23 for the transposes.
    // This is mainly just an excuse to use the rare ltv and swv instructions.
    // The F3DEX2 implementation takes 18 instructions and 11 cycles.
    // This implementation is 23 instructions and 17 cycles, but this version
    // loads M transpose to both halves of each vector so we can process two
    // lights at a time, which matters because there's always at least 3 lights
    // (technically 2 for EX3)--the lookat directions. Plus, those 17 cycles
    // also include a few instructions starting the loop.
    // Memory at mMatrix contains, in shorts within qwords, for the elements we care about:
    // A B C - D E F - (X int, Y int)
    // G H I - - - - - (Z int, W int)
    // M N O - P Q R - (X frac, Y frac)
    // S T U - - - - - (Z frac, W frac)
    // First, load this pattern in $v8-$v15 (int) and $v16-$v23 (frac).
    // $v8  A - G - A - G -   $v16 M - S - M - S -
    // $v9  - B - H - B - H   $v17 - N - T - N - T
    // $v10 I - C - I - C -   $v18 U - O - U - O -
    // $v11 - - - - - - - -   $v19 - - - - - - - -
    // $v12 D - - - D - - -   $v20 P - - - P - - -
    // $v13 - E - - - E - -   $v21 - Q - - - Q - -
    // $v14 - - F - - - F -   $v22 - - R - - - R -
    // $v15 - - - - - - - -   $v23 - - - - - - - -
    ltv     $v8[0],   (mMatrix + 0x00)($zero) // A to $v8[0] etc.
    ltv     $v8[12],  (mMatrix + 0x10)($zero) // G to $v8[2] etc.
    ltv     $v8[8],   (mMatrix + 0x00)($zero) // A to $v8[4] etc.
    ltv     $v8[4],   (mMatrix + 0x10)($zero) // G to $v8[6] etc.
    ltv     $v16[0],  (mMatrix + 0x20)($zero)
    ltv     $v16[12], (mMatrix + 0x30)($zero)
    ltv     $v16[8],  (mMatrix + 0x20)($zero)
    ltv     $v16[4],  (mMatrix + 0x30)($zero)
    veq     $v29, $v31, $v31[0q] // Set VCC to 10101010
    vmudh   $v9, vOne, $v9[1q]                // B - H - B - H -
    lsv     $v18[6],  (mMatrix + 0x2C)($zero) // U - O(R)U - O -
    vmrg    $v8, $v8, $v12[0q]                // A D G - A D G -
    lsv     $v18[14], (mMatrix + 0x2C)($zero) // U - O R U - O(R)
    vmrg    $v10, $v10, $v14[0q]              // I - C F I - C F
    lpv     lpWrld[0], (lightBufferLookat - altBase)(altBaseReg) // Lookat 0 and 1
    vmudh   $v17, vOne, $v17[1q]              // N - T - N - T -
    li      curLight, altBase - 4 * lightSize // + ltBufOfs = light -4; write pointer
    vmrg    $v9, $v9, $v13                    // B E H - B E H -
    li      $11, 0x7F                         // Mark lights valid. Could use some other reg known to be zero, but need a nop here.
    vmrg    $v16, $v16, $v20[0q]              // M P S - M P S -
    swv     $v18[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores O R U - O R U -
    vmudh   $v29,  $v8,  lpWrld[0h]           // Start transforming lookat
    lqv     $v18,    (tempXfrmLt)(rdpCmdBufEndP1)
    // This is slightly wrong, vmrg writes accum lo. But only affects lookat and
    // we are only reading accum mid result. Basically rounding error.
    vmrg    $v17, $v17, $v21                  // N Q T - N Q T -
    swv     $v10[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores C F I - C F I -
    vmadh   $v29,  $v9,  lpWrld[1h]
    lqv     $v10,    (tempXfrmLt)(rdpCmdBufEndP1)
    vmadn   $v29,  $v16, lpWrld[0h]
    sb      $11, dirLightsXfrmValid
    // 18 cycles
xfrm_light_loop_1:
    vmadn   $v29,  $v18, lpWrld[2h]
xfrm_light_loop_2:
    vmadn   $v29,  $v17, lpWrld[1h]
    vmadh   lpMdl, $v10, lpWrld[2h]  // lpMdl[0:2] and [4:6] = two lights dir in model space
    vrsqh   $v29[0], lpSumI[0]
    vrsql   lpRsqF[0], lpSumF[0]
    vrsqh   lpRsqI[0], lpSumI[4]
    addi    curLight, curLight, 2 * lightSize // Iters: -2, 0, 2, ...
    vrsql   lpRsqF[4], lpSumF[4]
    lw      $20, (ltBufOfs + 8 + 2 * lightSize)(curLight) // First iter = light 0
    vrsqh   lpRsqI[4], $v31[2]       // 0
    lw      $24, (ltBufOfs + 8 + 3 * lightSize)(curLight) // First iter = light 1
    vmudh   $v29, lpMdl, lpMdl       // Squared
    sub     $10, curLight, altBaseReg // Is curLight (write ptr) <= 0?
    vreadacc lpSqrF, ACC_MIDDLE      // Read not-clamped value
    sub     $11, curLight, ambLight  // Is curLight (write ptr) <, =, or > ambient light?
    vreadacc lpSqrI, ACC_UPPER
    sw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Store light 0
    vmudm   $v29,    lpMdl2, lpRsqF[0h] // Vec int * frac scaling
    sw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Store light 1
    vmadh   lpFinal, lpMdl2, lpRsqI[0h] // Vec int * int scaling
    lpv     lpWrld[0], (tempXfrmLt)(rdpCmdBufEndP1) // Load dirs 0-2, 4-6
    vmudm   $v29, vOne, lpSqrF[2h]  // Sum of squared components
    vmadh   $v29, vOne, lpSqrI[2h]
    vmadm   $v29, vOne, lpSqrF[1h]
    vmadh   $v29, vOne, lpSqrI[1h]
    spv     lpFinal[0], (tempXfrmLt)(rdpCmdBufEndP1) // Store elem 0-2, 4-6 as bytes to temp memory
    vmadn   lpSumF, lpSqrF,  vOne     // elem 0, 4; swapped so we can do vmadn and get result
    lw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vmadh   lpSumI, lpSqrI,  vOne
    lw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vcopy   lpMdl2, lpMdl
    blez    $10, xfrm_light_store_lookat // curLight = -2 or 0
     vmudh  $v29, $v8,  lpWrld[0h]
     // 20 cycles from xfrm_light_loop_2 not counting land
    vmadh   $v29, $v9,  lpWrld[1h]
    bgtz    $11, ltbasic_setup_after_xfrm // curLight > ambient; only one light valid
     sw     $20, (ltBufOfs + 0xC - 2 * lightSize)(curLight) // Write light relative -2
    vmadn   $v29, $v16, lpWrld[0h]
    bltz    $11, xfrm_light_loop_1   // curLight < ambient; more lights to compute
     sw     $24, (ltBufOfs + 0xC - 1 * lightSize)(curLight) // Write light relative -1
ltbasic_setup_after_xfrm:
    // Constants registers:
    //       e0     e1     e2     e3     e4     e5     e6     e7
    // vLTC  0xF800 Lt1 Z  AOAmb  AODir  Lt1 X  Lt1 Y  AOAmb  AODir
    // $v30  SOffs  TOffs  0/AOa  Persp  SOffs  TOffs  0x0020 0x0800
    lpv     vLTC[0], (ltBufOfs + 8 - lightSize)(ambLight) // First lt xfrmed dir in elems 4-6
    li      vLoopRet, ltbasic_start_standard
    andi    $11, vGeomMid, (G_AMBOCCLUSION | G_PACKED_NORMALS | G_LIGHTTOALPHA | G_TEXTURE_GEN) >> 8
    vmov    $v30[2], $v31[2] // 0 as AO alpha offset
    vmov    vLTC[1], vLTC[6] // Move first lt Z to elem 1; watch stall on vLTC load
    beqz    $11, vtx_after_lt_setup  // None of the above features enabled
     li     lbAfter, vtx_return_from_lighting
    andi    $11, vGeomMid, G_TEXTURE_GEN >> 8
    beqz    $11, @@skip_texgen
     andi   $10, vGeomMid, G_PACKED_NORMALS >> 8
    li      lbAfter, -0x8000 | ltbasic_texgen // Negative is used as flag
@@skip_texgen:
    beqz    $10, @@skip_packed
     move   lbTexgenOrRet, lbAfter
    // Packed normals setup
    sbv     $v31[15], (3)(lbFakeAmb)  // 0xFF; Set ambient "alpha" to FF / 7F80
    vmov    $v30[6], $v31[2] // 0; clear element 6, will overwrite second byte of it below
    sbv     $v31[15], (7)(lbFakeAmb)  // 0xFF; so vpLtTot alpha ~= 7FFF, so * vtx alpha
    li      lbAfter, ltbasic_packed
    li      vLoopRet, ltbasic_start_packed
    lsv     vLTC[0], (packedNormalsMaskConstant - altBase)(altBaseReg) // 0xF800; cull mode already zeroed
    llv     $v30[13], (packedNormalsConstants - altBase)(altBaseReg) // 00[20 0800 OB]; out of bounds truncates
@@skip_packed:
    andi    $11, vGeomMid, G_LIGHTTOALPHA >> 8
    beqz    $11, @@skip_l2a
     andi   $10, vGeomMid, G_AMBOCCLUSION >> 8
    li      lbAfter, ltbasic_l2a
@@skip_l2a:
    beqz    $10, vtx_after_lt_setup
     // AO setup
     move   lbPostAo, lbAfter // Harmless to be done even if not AO
    addi    lbFakeAmb, rdpCmdBufEndP1, tempAmbient  // Temp mem as ambient light
    vmov    $v30[2], $v31[7] // 7FFF as AO alpha offset
    spv     vOne[0], (0)(lbFakeAmb) // Store all zeros here (upper bytes of vOne are 0)
    llv     vLTC[4], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 2, 3
    llv     vLTC[12], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 6, 7
    j       vtx_after_lt_setup
     li     lbAfter, ltbasic_ao
    
.align 8
xfrm_light_store_lookat:
    vmadh   $v29, $v9,  lpWrld[1h]
    spv     lpFinal[0], (xfrmLookatDirs)($zero) // Store lookat. 1st time garbage, 2nd real
    vmadn   $v29, $v16, lpWrld[0h]
    j       xfrm_light_loop_2
     vmadn  $v29, $v18, lpWrld[2h]

// Lighting within vertex loop

.if CFG_NO_OCCLUSION_PLANE

.macro instan_lt_vec_1
    vmadh   $v29, vMTX1I, vpMdl[1h]
.endmacro
.macro instan_lt_vec_2
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
.endmacro
.macro instan_lt_vec_3
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
.endmacro
// lDOT <- vpMdl
.macro instan_lt_scl_1
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
.endmacro
.macro instan_lt_scl_2
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
.endmacro
// sFOG <- lCOL
.macro instan_lt_vs_45
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    sh      flagsV1, (VTX_CLIP      )(outVtx1) // Store first vertex flags
.endmacro

.else

.macro instan_lt_vec_1
    veq     $v29, $v31, $v31[0q]  // Set VCC to 10101010
.endmacro
.macro instan_lt_vec_2
    vmrg    sOCS, sOCS, sOTM      // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
.endmacro
.macro instan_lt_vec_3
    vmrg    vpScrF, vpScrF, sCLZ[2h]  // Z int elem 2, 6 to elem 1, 5; Z frac in elem 2, 6
.endmacro
// lDOT <- sCLZ
// vpRGBA <- sOTM
.macro instan_lt_scl_1
    sub     $11, outVtx1, fogFlag      // Points 8 before outVtx1 if fog, else 0
.endmacro
.macro instan_lt_scl_2
    sbv     sFOG[7],  (VTX_COLOR_A + 8)($11)
.endmacro
// lCOL <- sFOG
.macro instan_lt_vs_45
    vmudm   $v29, vpST, sSTS   // Scale ST
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vmadh   vpST, vOne, $v30   // + 1 * ST offset; elems 0, 1, 4, 5
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
.endmacro

.endif

.align 8

// If lighting, vLoopRet = ltbasic_start_packed if packed, else ltbasic_start_standard

ltbasic_start_packed:
    instan_lt_vec_1
    instan_lt_vec_2
    instan_lt_vec_3
    vand    vpNrmlX, vpMdl, vLTC[0]  // 0xF800; mask X to only top 5 bits
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load RGBA
    vmudn   vpNrmlY, vpMdl, $v30[6]  // (1 << 5) = 0x0020; left shift normals Y
    j       ltbasic_after_start
     vmudn  vpNrmlZ, vpMdl, $v30[7]  // (1 << 11) = 0x0800; left shift normals Z

.align 8
ltbasic_start_standard:
    // Using elem 3, 7 for regular normals because packed normal results are there.
    instan_lt_vec_1
    lpv     vpNrmlX[3], (tempVpRGBA)(rdpCmdBufEndP1) // X to elem 3, 7
    instan_lt_vec_2
    lpv     vpNrmlY[2], (tempVpRGBA)(rdpCmdBufEndP1) // Y to elem 3, 7
    instan_lt_vec_3
    lpv     vpNrmlZ[1], (tempVpRGBA)(rdpCmdBufEndP1) // Z to elem 3, 7
    vnop
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load vertex color input
ltbasic_after_start:

.if CFG_DEBUG_NORMALS
.warning "Debug normals visualization is enabled"
    vmudh   vpNrmlX, vOne, vpNrmlX[3h] // Move X to all elements
    vne     $v29, $v31, $v31[1h] // Set VCC to 10111011
    vmrg    vpNrmlX, vpNrmlX, vpNrmlY[3h] // X in 0, 4; Y to 1, 5
    vne     $v29, $v31, $v31[2h] // Set VCC to 11011101
    vmrg    vpNrmlX, vpNrmlX, vpNrmlZ[3h] // Z to 2, 6
    vmudh   $v29, vOne, $v31[5] // 0x4000; middle gray
    j       vtx_return_from_lighting
     vmacf  vpRGBA, vpNrmlX, $v31[5] // 0x4000; + 0.5 * normal
.else // CFG_DEBUG_NORMALS

    vmulf   $v29,  vpNrmlX, vLTC[4] // Normals X elems 3, 7 * first light dir X
// lDIR <- (NOC: -, Occ: sOTM)
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(ambLight) // Xfrmed dir in elems 4-6; temp reg
    vmacf   $v29,  vpNrmlY, vLTC[5] // Normals Y elems 3, 7 * first light dir Y
    luv     vpLtTot,    (0)(lbFakeAmb)  // Total light level, init to ambient or zeros if AO
// lDOT <- (NOC: vpMdl, Occ: sCLZ)
    vmacf   lDOT, vpNrmlZ, vLTC[1] // Normals Z elems 3, 7 * first light dir Z
    instan_lt_scl_1  // $11 can be used as a temporary, except b/w instan_lt_scl_1...
    vsub    lVCI, lVCI, $v30[2] // Offset alpha for AO, or 0 normally
    instan_lt_scl_2 // ...and instan_lt_scl_2
// lCOL <- (Occ: sFOG here / NOC: sSCI earlier)
    // vnop
    beq     ambLight, altBaseReg, ltbasic_post
     move   curLight, ambLight                   // Point to ambient light
ltbasic_loop:
    vge     lDTC, lDOT, $v31[2] // 0; clamp dot product to >= 0
    vmulf   $v29,  vpNrmlX, lDIR[4] // Normals X elems 3, 7 * next light dir
    luv     lCOL,   (ltBufOfs + 0 - 1*lightSize)(curLight) // Light color
    vmacf   $v29,  vpNrmlY, lDIR[5] // Normals Y elems 3, 7 * next light dir
    addi    curLight, curLight, -lightSize
    vmacf   lDOT, vpNrmlZ, lDIR[6] // Normals Z elems 3, 7 * next light dir
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(curLight) // Xfrmed dir in elems 4-6; DOES dual-issue
    vmudh   $v29, vOne, vpLtTot // Load accum mid with current light level
    bne     curLight, altBaseReg, ltbasic_loop
     vmacf  vpLtTot, lCOL, lDTC[3h] // + light color * dot product
ltbasic_post:
// (NOC: sFOG here / Occ: vpClpI later) <- lCOL
    instan_lt_vs_45
    vne     $v29, $v31, $v31[3h]           // Set VCC to 11101110
    jr      lbAfter
// vpRGBA <- lDIR
     vmrg   vpRGBA, vpLtTot, lVCI  // RGB = light, A = vtx alpha

.endif // CFG_DEBUG_NORMALS

// lbAfter       = ltbasic_ao if AO else
// lbPostAo      = ltbasic_l2a if L2A else
//                 ltbasic_packed if packed else
// lbTexgenOrRet = ltbasic_texgen if texgen else
//                 vtx_return_from_lighting
     
ltbasic_ao:
    vmudn   $v29, vLTC, lVCI[3h]      // (aoAmb 2 6, aoDir 3 7) * (alpha - 1)
    luv     vpRGBA, (ltBufOfs + 0)(ambLight)  // Ambient light level
    vmadh   lDTC, vOne, $v31[7]       // + 0x7FFF (1 in s.15)
    vadd    lVCI, lVCI, $v31[7]       // 0x7FFF; undo offset alpha
    vmulf   $v29, vpLtTot, lDTC[3h]   // Sum of dir lights *= dir factor
    vmacf   vpLtTot, vpRGBA, lDTC[2h] // + ambient * amb factor
    jr      lbPostAo                  // Return, texgen, l2a, or packed
     vmacf  vpRGBA, $v31, $v31[2]     // 0; need it in vpRGBA if returning, else in vpLtTot
     
ltbasic_l2a:
    // Light-to-alpha (cel shading): alpha = max of light components, RGB = vertex color
    vge     vpLtTot, vpLtTot, vpLtTot[1h] // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    vge     vpLtTot, vpLtTot, vpLtTot[2h] // elem 0 = max(R0, G0, B0); equiv for elem 4
    vne     $v29, $v31, $v31[3h]          // Reset VCC to 11101110 (clobbered by vge)
    jr      lbTexgenOrRet
     vmrg   vpRGBA, lVCI, vpLtTot[0h]     // RGB is vcol (garbage if not packed); A is light
    
ltbasic_packed:
    bgez    lbTexgenOrRet, vtx_return_from_lighting // < 0 for texgen
     vmulf  vpRGBA, vpLtTot, lVCI      // (Light color, 7FFF alpha) * vertex RGBA.
ltbasic_texgen:
// Texgen: in vpNrmlX:Y:Z; temps vpLtTot, lDOT, lDTC; out vpST.
lLkDrs equ lDTC    // lighting Lookat Directions
lLkDt0 equ vpLtTot // lighting Lookat Dot product 0
lLkDt1 equ lDOT    // lighting Lookat Dot product 1
    lpv     lLkDrs[0], (xfrmLookatDirs + 0)($zero) // Lookat 0 in 0-2, 1 in 4-6
.macro texgen_dots, lookats, dot0, dot1
    vmulf   $v29, vpNrmlX, lookats[0]  // Normals X * lookat 0 X
    vmacf   $v29, vpNrmlY, lookats[1]  // Normals Y * lookat 0 Y
    vmacf   dot0, vpNrmlZ, lookats[2]  // Normals Z * lookat 0 Z
    vmulf   $v29, vpNrmlX, lookats[4]  // Normals X * lookat 1 X
    vmacf   $v29, vpNrmlY, lookats[5]  // Normals Y * lookat 1 Y
    vmacf   dot1, vpNrmlZ, lookats[6]  // Normals Z * lookat 1 Z
.endmacro
    texgen_dots lLkDrs, lLkDt0, lLkDt1
.if !CFG_NO_OCCLUSION_PLANE
    addi    outVtxBase, outVtxBase, -2*vtxSize // Undo doing this twice due to repeating ST scale
.endif
// In ltbasic, normals are in elems 3, 7; in ltadv, elems 0, 4
    vmudh   lLkDt0, vOne, lLkDt0[3h] // Move dot 0 from elems 3, 7 to 0, 4
.macro texgen_body, lookats, dot0, dot1, normalselem, branch_no_texgen_linear
// lookats now holds texgen linear coefficients elems 0, 1
    llv     lookats[0], (texgenLinearCoeffs - altBase)(altBaseReg)
    vne     $v29, $v31, $v31[1h]    // Set VCC to 10111011
    andi    $11, vGeomMid, G_TEXTURE_GEN_LINEAR >> 8
    vmrg    dot0, dot0, dot1[normalselem] // Dot products in elements 0, 1, 4, 5
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    beqz    $11, branch_no_texgen_linear
     vmacf  vpST, dot0, $v31[5]     // + dot products * 0x4000 ( / 2)
    // Texgen_Linear:
    vmulf   vpST, dot0, $v31[5]     // dot products * 0x4000 ( / 2)
// dot0 now holds lighting Lookat ST squared
    vmulf   dot0, vpST, vpST        // ST squared
    vmulf   $v29, vpST, $v31[7]     // Move ST to accumulator (0x7FFF = 1)
// dot1 now holds lighting Lookat Temp
    vmacf   dot1, vpST, lookats[1]  // + ST * 0x6CB3
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    vmacf   vpST, vpST, lookats[0]  // + ST * 0x44D3
.endmacro
    texgen_body lLkDrs, lLkDt0, lLkDt1, 3h, vtx_return_from_texgen
    j       vtx_return_from_texgen
.macro texgen_lastinstr, dot0, dot1
     vmacf  vpST, dot0, dot1        // + ST squared * (ST + ST * coeff)
.endmacro
     texgen_lastinstr lLkDt0, lLkDt1
