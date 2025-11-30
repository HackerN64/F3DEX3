.include "rsp/lighting/ltadv_regs.inc"

ltadv_spec_fres_setup: // Odd instruction
    // Get aDIR = normalize(camera - vertex), aDOT = (vpWNrm dot aDIR)
    ldv     aDPosI[0], (cameraWorldPos - altBase)(altBaseReg) // Camera world pos
    j       ltadv_normal_to_vertex
     ldv    aDPosI[8], (cameraWorldPos - altBase)(altBaseReg)
     // nop; nop
ltadv_after_camera:
    // vnop; vnop
    vmov    aOAFrs[0], aDOT[0]       // Save Fresnel dot product in aOAFrs[0h]
    vmov    aOAFrs[4], aDOT[4]       // elems 0, 4
    bgez    laSpecular, ltadv_loop   // Sign bit clear = not specular
     li     laSpecFres, 0            // Clear flag for specular or fresnel
// aProj <- aLenF
    vmulf   aProj, vpWNrm, aDOT[0h]  // Projection of camera vec onto normal
    vmudh   $v29, aDIR, $v31[1]      // -camera vec
    j       ltadv_normals_to_regs    // For specular, replace vpWNrm with reflected vector
     // vnop; vnop
     vmadh  vpWNrm, aProj, $v31[3]   // + 2 * projection
     // vnop; vnop
     // aDPosI <- aProj
    
ltadv_xfrm: // Even instruction
    vmudn   $v29, vMTX0F, vpMdl[0h]
    lbu     curLight, numLightsxSize // Scalar instructions here must be OK to do twice
    vmadh   $v29, vMTX0I, vpMdl[0h]
    luv     vpRGBA,  (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2:1 RGBA
    vmadn   $v29, vMTX1F, vpMdl[1h]
    vmadh   $v29, vMTX1I, vpMdl[1h]
    addi    curLight, curLight, altBase // Point to ambient light
    vmadn   aDPosF, vMTX2F, vpMdl[2h]
    jr      $ra
     vmadh  aDPosI, vMTX2I, vpMdl[2h]
    
ltadv_after_mtx: // Even instruction
    move    laPtr, inVtx
    vcopy   aPNScl, vOne
    move    laVtxLeft, vtxLeft
    vmudn   aDPosF, vMTX1F, $v31[7] // 0x7FFF; transform a normal (0, 7FFF, 0)
    // 0001 00[20 0800 XX]01 = (1<<0),(1<<5),(1<<11),XX, repeat
    llv     aPNScl[3],  (packedNormalsConstants - altBase)(altBaseReg)
    vmadh   aDPosI, vMTX1I, $v31[7]
    j       ltadv_normalize
     llv    aPNScl[11], (packedNormalsConstants - altBase)(altBaseReg)
ltadv_continue_setup:
    lqv     aParam, (fxParams - altBase)(altBaseReg)
    vcopy   aNrmSc, aRcpLn // aRcpLn[0:1] is int:frac scale (1 / length)
    lsv     aPNScl[6], (packedNormalsMaskConstant - altBase)(altBaseReg) // F800
    vge     $v29, $v31, $v31[3] // Set VCC to 00011111
    andi    $11, vGeomMid, G_AMBOCCLUSION >> 8
    bnez    $11, @@skip_zero_ao
     andi   laL2A, vGeomMid, G_LIGHTTOALPHA >> 8
    vmrg    aParam, aParam, $v31[2] // 0
@@skip_zero_ao:
    jal     while_wait_dma_busy
     andi   laTexgen, vGeomMid, G_TEXTURE_GEN >> 8
    ldv     vpMdl[0], (VTX_IN_OB + 1 * inputVtxSize)(laPtr) // Vtx 2 Model pos + PN
    ldv     vpMdl[8], (VTX_IN_OB + 0 * inputVtxSize)(laPtr) // Vtx 1 Model pos + PN
align_with_warning 8, "One instruction of padding before ltadv_vtx_loop"
ltadv_vtx_loop: // Even instruction
    vmudm   $v29, aPNScl, vpMdl[3h] // Packed normals from elem 3,7 of model pos
    lw      $11,     (VTX_IN_CN + 1 * inputVtxSize)(laPtr) // Vtx 2 RGBA
    vmadn   vpNrmlY, $v31, $v31[2] // 0; load lower (vpMdl unsigned but must be T operand)
    lw      laSTKept,(VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 1 ST
    vand    vpNrmlX, vpMdl, aPNScl[3] // 0xF800; X component masked in elem 3, 7
    jal     ltadv_xfrm
     sw     $11,     (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2 RGBA -> Vtx 1 ST
    vmadn   vpWrlF, vMTX3F, vOne // Finish vertex pos transform
    vmadh   vpWrlI, vMTX3I, vOne
    andi    laPacked, vGeomMid, G_PACKED_NORMALS >> 8
// aOAFrs <- vpST
    vsub    aOAFrs, vpRGBA, $v31[7]  // 0x7FFF; offset alpha elems 3, 7
    luv     vpLtTot, (ltBufOfs + 0)(curLight) // Total light level, init to ambient
    vne     $v29, $v31, $v31[0h] // Set VCC to 01110111
    beqz    laPacked, @@skip_packed_normals
     lpv    vpMdl,  (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2:1 regular normals
    vmrg    vpMdl, vpNrmlY, vpNrmlX[3h] // Masked X to 0, 4; multiplied Y, Z in 1, 2, 5, 6
@@skip_packed_normals:
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    jal     ltadv_xfrm
// aAOF2 <- aDOT
     vmadm  aAOF2, aOAFrs, aParam[0] // + (alpha - 1) * aoAmb factor; elems 3, 7
// aLTC <- vpMdl
    vmulf   vpLtTot, vpLtTot, aAOF2[3h] // light color *= ambient factor
// aDOT <- aAOF2
    vmudn   $v29, aDPosF, aNrmSc[0h] // Vec frac * int scaling, discard result
// aDIR <- aDPosF
    addi    laPtr, laPtr, 2 * inputVtxSize
    vmadm   $v29, aDPosI, aNrmSc[1h] // Vec int * frac scaling, discard result
    addi    laVtxLeft, laVtxLeft, -2 * inputVtxSize
// vpWNrm <- vpNrmlX
    vmadh   vpWNrm, aDPosI, aNrmSc[0h] // Vec int * int scaling
    sll     laSpecular, vGeomMid, (31 - 5) // G_LIGHTING_SPECULAR to sign bit
    vmudn   vpWrlF, vpWrlF, $v31[1] // -1; negate world pos so add light/cam pos to it
    andi    laSpecFres, vGeomMid, (G_LIGHTING_SPECULAR | G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vmadh   vpWrlI, vpWrlI, $v31[1] // -1

.if CFG_DEBUG_NORMALS
    vmudh   $v29, vOne, $v31[5] // 0x4000; middle gray
    li      laTexgen, 0
    vmacf   vpRGBA, vpWNrm, $v31[5] // 0x4000; + 0.5 * normal
ltadv_finish_light:
ltadv_loop:
ltadv_normals_to_regs:
ltadv_specular:
.else

ltadv_normals_to_regs:
    vmudh   vpNrmlY, vOne, vpWNrm[1h] // Move normals to separate registers
    bnez    laSpecFres, ltadv_spec_fres_setup
     vmudh  vpNrmlZ, vOne, vpWNrm[2h] // per component, in elems 0-3, 4-7
// vpNrmlX <- vpWNrm
// aAOF <- aDPosI
align_with_warning 8, "One instruction of padding before ltadv_loop"
ltadv_loop: // Even instruction
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    lbu     $11,     (ltBufOfs + 3 - lightSize)(curLight) // Light type / constant attenuation
    vmadm   aAOF, aOAFrs, aParam[1] // + (alpha - 1) * aoDir factor; elems 3, 7
    beq     curLight, altBaseReg, ltadv_post
     lpv    aDOT[0], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 0-2
    bnez    $11, ltadv_point
     luv    aLTC,    (ltBufOfs + 0 - lightSize)(curLight) // Light color
    // vnop
    vmulf   $v29, vpNrmlX, aDOT[0]
    vmacf   $v29, vpNrmlY, aDOT[1]
    bltzal  laSpecular, ltadv_specular
     vmacf  aDOT, vpNrmlZ, aDOT[2]
    // vnop; vnop
ltadv_finish_light:
    vmulf   aLTC, aLTC, aAOF[3h] // light color *= dir or point light factor
    vge     aDOT, aDOT, $v31[2] // 0; clamp dot product to >= 0
    addi    curLight, curLight, -lightSize
    vmudh   $v29, vOne, vpLtTot // Load accum mid with current light level
    j       ltadv_loop
     // vnop; vnop
     vmacf  vpLtTot, aLTC, aDOT[0h] // + light color * dot product

ltadv_specular: // aDOT in/out, uses vpLtTot[3] and $11 as temps
    lb      $11, (ltBufOfs + 0xF - lightSize)(curLight) // Light size factor
    // nop; nop
    mtc2    $11, vpLtTot[6]        // Light size factor in elem 3 as temp
    vxor    aDOT, aDOT, $v31[7]    // = 0x7FFF - dot product
    // vnop; vnop; vnop
    vmudh   aDOT, aDOT, vpLtTot[3] // * size factor
    jr      $ra
     // vnop; vnop; vnop
     vxor   aDOT, aDOT, $v31[7]    // = 0x7FFF - result
     // land then one vnop before vmulf; replaces two vnops if not specular

.align 8
ltadv_post:
// aClOut <- vpWrlF
// aAlOut <- vpWrlI
// vpMdl <- aLTC
    vge     aAOF, vpLtTot, vpLtTot[1h] // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    ldv     vpMdl[0], (VTX_IN_OB + 1 * inputVtxSize)(laPtr) // Vtx 2 Model pos + PN
    vmulf   aClOut, vpRGBA, vpLtTot    // RGB output is RGB * light
    beqz    laL2A, @@skip_cel
     vcopy  aAlOut, vpRGBA             // Alpha output = vertex alpha (only 3, 7 matter)
    // Cel: alpha = max of light components, RGB = vertex color
    vge     aAOF, aAOF, aAOF[2h]       // elem 0 = max(R0, G0, B0); equiv for elem 4
    vcopy   aClOut, vpRGBA             // RGB output is vertex color
    vmudh   aAlOut, vOne, aAOF[0h]     // move light level elem 0, 4 to 3, 7
@@skip_cel:
    vne     $v29, $v31, $v31[3h]       // Set VCC to 11101110
    bnez    laPacked, @@skip_novtxcolor
     andi   $11, vGeomMid, (G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vcopy   aClOut, vpLtTot            // If no packed normals, base output is just light
@@skip_novtxcolor:
    vmrg    vpRGBA, aClOut, aAlOut     // Merge base output and alpha output
    beqz    $11, ltadv_skip_fresnel
     ldv    vpMdl[8], (VTX_IN_OB + 0 * inputVtxSize)(laPtr) // Vtx 1 Model pos + PN
    lsv     aAOF[0], (vTRC_0100_addr - altBase)(altBaseReg) // Load constant 0x0100 to temp
    vabs    aOAFrs, aOAFrs, aOAFrs     // Fresnel dot in aOAFrs[0h]; absolute value for underwater
    andi    $11, vGeomMid, G_FRESNEL_COLOR >> 8
    vmudh   $v29, vOne, aParam[7]      // Fresnel offset
    // vnop; vnop
    vmacu   aOAFrs, aOAFrs, aParam[6]  // + factor * scale, clamp to >= 0.
    beqz    $11, @@skip                // vmacu bad oflow bhv @ 7FFF is OK b/c here max values should be about 0200.
     // vnop; vnop; vnop
     vmudh  aOAFrs, aOAFrs, aAOF[0]    // Result * 0x0100, clamped to 0x7FFF
    veq     $v29, $v31, $v31[3h]       // Set VCC to 00010001 if G_FRESNEL_COLOR
@@skip:
    // vnop; vnop
    vmrg    vpRGBA, vpRGBA, aOAFrs[0h] // Replace color or alpha with fresnel
    // vnop; vnop

.endif // CFG_DEBUG_NORMALS

ltadv_skip_fresnel:
    beqz    laTexgen, ltadv_after_texgen
     suv    vpRGBA,   (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Vtx 2:1 RGBA
// Texgen: aDOT still contains lookat 0 in elems 0-2, lookat 1 in elems 4-6
// vpST <- aOAFrs
    texgen_dots aDOT, aLkDt0, aLkDt1
    texgen_body aDOT, aLkDt0, aLkDt1, 0h, ltadv_texgen_end
    texgen_lastinstr aLkDt0, aLkDt1
ltadv_texgen_end:  // Vtx 2 ST in vpST elem 0, 1; vtx 1 ST in vpST elem 4, 5
    slv     vpST[8],  (tempVtx1ST)(rdpCmdBufEndP1) // Vtx 1 ST
    bltz    laVtxLeft, ltadv_after_texgen  // Only vtx 1 is valid, don't write vtx 2
     lw     laSTKept, (tempVtx1ST)(rdpCmdBufEndP1) // Overwrite stored Vtx 1 ST
    slv     vpST[0],  (VTX_IN_TC - 1 * inputVtxSize)(laPtr) // Vtx 2 ST
ltadv_after_texgen:
    lw      $11,      (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Vtx 2 RGBA from vtx 1 ST slot
    bltz    laVtxLeft, vtx_setup_no_lighting
     sw     laSTKept, (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Restore vtx 1 ST
ltadv_vtx_loop_end:
    bgtz    laVtxLeft, ltadv_vtx_loop
     sw     $11,      (VTX_IN_CN - 1 * inputVtxSize)(laPtr) // Real vtx 2 RGBA
    j       vtx_setup_no_lighting
     // Delay slot is OK
    
ltadv_point:
    /*
    Input vector 1 elem size 7FFF.0000 -> len^2 3FFF0001 -> 1/len 0001.0040 -> vec +801E.FFC0 -> clamped 7FFF
        len^2 * 1/len = 400E.FFC1 so about half actual length
    Input vector 1 elem size 0100.0000 -> len^2 00010000 -> 1/len 007F.FFC0 -> vec  7FFF.C000 -> clamped 7FFF
        len^2 * 1/len = 007F.FFC0 so about half actual length
    Input vector 1 elem size 0010.0000 -> len^2 00000100 -> 1/len 07FF.FC00 -> vec  7FFF.C000
    Input vector 1 elem size 0001.0000 -> len^2 00000001 -> 1/len 7FFF.C000 -> vec  7FFF.C000
    */
// aDPosI <- aAOF
    ldv     aDPosI[0], (ltBufOfs + 8 - lightSize)(curLight) // Light position int part 0-3
    ldv     aDPosI[8], (ltBufOfs + 8 - lightSize)(curLight) // 4-7
    lbu     $10,     (ltBufOfs + 7 - lightSize)(curLight) // PL: Linear factor
    // vnop; vnop
    lbu     $24,     (ltBufOfs + 0xE - lightSize)(curLight) // PL: Quadratic factor
ltadv_normal_to_vertex:
    vadd    aDPosI, aDPosI, vpWrlI     // Not using aDPosF; frac part is just vpWrlF
    // vnop; vnop; vnop
ltadv_normalize: // Normalize vector in aDPosI:vpWrlF i/f
    vmudm   $v29, aDPosI, vpWrlF       // Squared. Don't care about frac*frac term
    sll     $11, $11, 8                // Constant factor, 00000100 - 0000FF00
    vmadn   $v29, vpWrlF, aDPosI
    sll     $10, $10, 6                // Linear factor, 00000040 - 00003FC0
    vmadh   $v29, aDPosI, aDPosI
    mtc2    $11, aNrmSc[4]             // Constant frac part in elem 2
// aLen2F <- aLTC
    vreadacc aLen2F, ACC_MIDDLE
    mtc2    $10, aNrmSc[6]             // Linear frac part in elem 3
    vreadacc aLen2I, ACC_UPPER
    srl     $11, $24, 5                // Top 3 bits
    // vnop; vnop
    vmudm   $v29, vOne, aLen2F[2h]     // Sum of squared components
    andi    $10, $24, 0x1F             // Bottom 5 bits
    vmadh   $v29, vOne, aLen2I[2h]
    ori     $10, $10, 0x20             // Append leading 1 to mantissa
    vmadm   $v29, vOne, aLen2F[1h]
    sllv    $10, $10, $11              // Left shift to create floating point
    vmadh   $v29, vOne, aLen2I[1h]
    sll     $10, $10, 8 // Min range 00002000, 00002100... 00003F00, max 00100000...001F8000
    vmadn   aLen2F, aLen2F, vOne       // elem 0; swapped so we can do vmadn and get result
    bnez    $24, @@skip // If original value is zero, set to zero
     vmadh  aLen2I, aLen2I, vOne
    li      $10, 0
@@skip:
    // vnop; vnop
// aRcpLn <- $v29
    vrsqh   aRcpLn[2], aLen2I[0]       // High input, garbage output
    vrsql   aRcpLn[1], aLen2F[0]       // Low input, low output
    mtc2    $10, aNrmSc[12]            // Quadratic frac part in elem 6
    vrsqh   aRcpLn[0], aLen2I[4]       // High input, high output
    srl     $10, $10, 16
    vrsql   aRcpLn[5], aLen2F[4]       // Low input, low output
    beq     laPtr, inVtx, ltadv_continue_setup // Return aRcpLn; cond works only iter 0
     vrsqh  aRcpLn[4], $v31[2]         // 0 input, high output
    // vnop; vnop; vnop
    vmudn   aDIR, vpWrlF, aRcpLn[0h]   // Vec frac * int scaling, discard result
    mtc2    $10, aNrmSc[14]            // Quadratic int part in elem 7
    vmadm   aDIR, aDPosI, aRcpLn[1h]   // Vec int * frac scaling, discard result
    vmadh   aDIR, aDPosI, aRcpLn[0h]   // Vec int * int scaling
// aLenF <- aDPosI
    vmudm   aLenF, aLen2I, aRcpLn[1h]  // len^2 int * 1/len frac; ignoring frac*frac
    vmadn   aLenF, aLen2F, aRcpLn[0h]  // len^2 frac * 1/len int = len frac
// aLenI <- aRcpLn
    vmadh   aLenI, aLen2I, aRcpLn[0h]  // len^2 int * 1/len int = len int
    vmulf   aDOT, vpNrmlX, aDIR[0h]    // Normalized light dir * normalized normals
    vmacf   aDOT, vpNrmlY, aDIR[1h]
    bnez    laSpecFres, ltadv_after_camera  // Return if initial spec/fres; returns aDOT, aDIR
     vmacf  aDOT, vpNrmlZ, aDIR[2h]
// $v29 <- aLenI
    vmudm   $v29, aLenI,  aNrmSc[3]    //   len int * linear factor frac
    vmadl   $v29, aLenF,  aNrmSc[3]    // + len frac * linear factor frac
    vmadm   $v29, vOne,   aNrmSc[2]    // + 1 * constant factor frac
    vmadl   $v29, aLen2F, aNrmSc[6]    // + len^2 frac * quadratic factor frac
    vmadm   $v29, aLen2I, aNrmSc[6]    // + len^2 int * quadratic factor frac
// aPLFcF <- aLen2F
    vmadn   aPLFcF, aLen2F, aNrmSc[7]  // + len^2 frac * quadratic factor int = aPLFcF frac
    bltzal  laSpecular, ltadv_specular
// aPLFcI <- aLen2I
     vmadh  aPLFcI, aLen2I, aNrmSc[7]  // + len^2 int * quadratic factor int  = aLen2I int
// aAOF <- aLenF
    vmudh   aAOF, vOne, $v31[7]        // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   aAOF, aOAFrs, aParam[2]    // + (alpha - 1) * aoPoint factor; elems 3, 7
    // vnop
// aDotSc <- aDIR
    vrcph   aDotSc[1], aPLFcI[0]       // 1/(2*light factor), input of 0000.8000 -> no change normals
    vrcpl   aDotSc[2], aPLFcF[0]       // Light factor 0001.0000 -> normals /= 2
    vrcph   aDotSc[3], aPLFcI[4]       // Light factor 0000.1000 -> normals *= 8 (with clamping)
// aLen2I <- aPLFcI
    vrcpl   aDotSc[6], aPLFcF[4]       // Light factor 0010.0000 -> normals /= 32
    vrcph   aDotSc[7], $v31[2]         // 0
// aLTC <- aPLFcF
    luv     aLTC,    (ltBufOfs + 0 - lightSize)(curLight) // aLTC = light color
    // vnop; vnop; vnop
    // This is a scale on the dot product, not the light, because the scale can
    // increase a small dot product (close to perpendicular), while it can't
    // increase a light beyond white.
    vmudm   $v29, aDOT, aDotSc[2h]     // Dot product int * scale frac
    j       ltadv_finish_light         // Returns aLTC, aAOF, aDOT
     vmadh  aDOT, aDOT, aDotSc[3h]     // Dot product int * scale int, clamp to 0x7FFF
     // vnop
     // aDIR <- aDotSc

/*
    ltadv per vertex pair up to light loop: 36
    ltadv per vertex pair last loop iter: 4
    ltadv per vertex pair after to next vtx pair, no packed normals: 23
total ltadv per vertex pair: 63
light loop directional: 18
    light loop point through jump: 6
    point: 64
    light loop point after return: 7
total point: 77
*/

ovl4_end:
.align 8
ovl4_padded_end:
