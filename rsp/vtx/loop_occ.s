align_with_warning 8, "One instruction of padding before vertex loop"

    // 70 cycles, 16 more than NOC
    // 6 vu cycles for plane, 8 vu cycles for edges, 0 more vnops than NOC,
    // 1 branch delay slot with SU instr, 1 land-after-branch.
vtx_loop_no_lighting:
// lDTC <- sVPS
// lVCI <- sRTI
// vpLtTot <- sTCL
// vpNrmlX <- s1WF
// lDIR <- sOTM
    veq     $v29, $v31, $v31[0q]  // Set VCC to 10101010
    sub     $11, outVtx1, fogFlag      // Points 8 before outVtx1 if fog, else 0
    vmrg    sOCS, sOCS, sOTM      // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
    sbv     sFOG[7],  (VTX_COLOR_A + 8)($11) // ...which gets overwritten below
    vmrg    vpScrF, vpScrF, sCLZ[2h]  // Z int elem 2, 6 to elem 1, 5; Z frac in elem 2, 6
// vpRGBA <- lDIR
    luv     vpRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// lDOT <- sCLZ
// lCOL <- sFOG
vtx_return_from_texgen:
    vmudm   $v29, vpST, sSTS   // Scale ST
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vmadh   vpST, vOne, $v30   // + 1 * ST offset; elems 0, 1, 4, 5
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
vtx_return_from_lighting:
    vge     $v29, sOCS, sO47      // Each compare to coeffs 4-7
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
    vmudn   $v29, vMTX3F, vOne
    cfc2    $11, $vcc
    vmadh   $v29, vMTX3I, vOne
    slv     vpScrF[10], (VTX_SCR_Z      )(outVtx2)
    vmadn   $v29, vMTX0F, vpMdl[0h]
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadh   $v29, vMTX0I, vpMdl[0h]
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    vmadn   $v29, vMTX1F, vpMdl[1h]
    or      $11, $11, $10    // Combine occlusion results. Any set in 0-3, 4-7 = not occluded
    vmadh   $v29, vMTX1I, vpMdl[1h]
    andi    $10, $11, 0x000F // Bits 0-3 for vtx 1
// vpClpF <- lDOT
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
    addi    $11, $11, -(0x0010) // If not occluded, atl 1 of 4-7 set, so $11 >= 0x10. Else $11 < 0x10.
// vpClpI <- lCOL
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
    bnez    $10, @@skipv1    // If nonzero, at least one equation false, don't set occluded flag
     andi   $11, $11, CLIP_OCCLUDED // This is bit 11, = sign bit b/c |$11| <= 0xFF
    ori     flagsV1, flagsV1, CLIP_OCCLUDED // All equations true, set vtx 1 occluded flag
@@skipv1:
    // 16 cycles
vtx_store_for_clip:
    vmudl   $v29, vpClpF, $v30[3]       // Persp norm
    or      flagsV2, flagsV2, $11 // occluded = $11 negative = sign bit set = $11 is flag, else 0
// s1WI <- vpMdl
    vmadm   s1WI, vpClpI, $v30[3]       // Persp norm
    sh      flagsV2,            (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
// s1WF <- vpNrmlX
    vmadn   s1WF, $v31, $v31[2]         // 0
    blez    vtxLeft, vtx_epilogue
     vmudn  $v29, vpClpF, sOCM          // X * kx, Y * ky, Z * kz
    vmadh   $v29, vpClpI, sOCM          // Int * int
    sh      flagsV1,            (VTX_CLIP      )(outVtx1) // Store first vertex flags
    vrcph   $v29[0], s1WI[3]
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
// sRTF <- lDTC
    vrcpl   sRTF[2], s1WF[3]
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
// sRTI <- lVCI
    vrcph   sRTI[3], s1WI[7]
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
    vrcpl   sRTF[6], s1WF[7]
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
    vrcph   sRTI[7], $v31[2] // 0
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vreadacc sOCS, ACC_UPPER                // Load int * int portion
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmudl   $v29, s1WF, sRTF[2h]
    sdv     vpClpI[8],  (VTX_INT_VEC   )(outVtx2)
    vmadm   $v29, s1WI, sRTF[2h]
    sdv     vpClpI[0],  (VTX_INT_VEC   )(outVtx1)
    vmadn   s1WF, s1WF, sRTI[3h]
    sdv     vpClpF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vpClpF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    sqv     vpClpI, (tempVpRGBA)(rdpCmdBufEndP1) // For Z to W manip. RGBA not currently stored here
    vmudh   $v29, vOne, $v31[4]  // 4
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadn   s1WF, s1WF, $v31[0]  // -4
    ssv     vpClpI[4],  (tempVpRGBA + 6)(rdpCmdBufEndP1)  // First Z to W
    vmadh   s1WI, s1WI, $v31[0]  // -4
// sTCL <- vpLtTot
    ldv     sTCL[0],   (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
// sSCF <- vpScrF
    vmudn   sSCF, vpClpF, $v31[3]       // W * clip ratio for scaled clipping
    ssv     vpClpI[12], (tempVpRGBA + 14)(rdpCmdBufEndP1) // Second Z to W
// sSCI <- vpScrI
    vmadh   sSCI, vpClpI, $v31[3]       // W * clip ratio for scaled clipping
    lsv     vpClpF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmudl   $v29, s1WF, sRTF[2h]
    lqv     vpClpI, (tempVpRGBA)(rdpCmdBufEndP1) // Load int part with Z in W
    vmadm   $v29, s1WI, sRTF[2h]
    lsv     vpClpF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, sRTI[3h]
    ldv     sTCL[8],   (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    slv     vpST[8], (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    cfc2    $11, $vcc                   // Scaled clip results
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
    slv     vpST[0], (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    vmadn   vpClpF, vpClpF, s1WI[3h]
// sVPO <- sSCF
    ldv     sVPO[0], (viewport + 8)($zero) // Load viewport offset incl. fog for first vertex
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
// sOTM <- vpRGBA
    vadd    sOTM, sOCS, sOCS[1h] // Add Y to X
    ldv     sVPO[8], (viewport + 8)($zero) // Load viewport offset incl. fog for second vertex
    vcopy   vpST, sTCL
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmudl   $v29, vpClpF, $v30[3] // Persp norm
// sVPS <- sSCI
    ldv     sVPS[0], (viewport)($zero) // Load viewport scale incl. fog for first vertex
    vmadm   vpClpI, vpClpI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    ldv     sVPS[8], (viewport)($zero) // Load viewport scale incl. fog for second vertex
    vadd    sOCS, sOTM, sOCS[2h] // Add Z to X
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    vmov    sTCL[4], vpST[2] // First vtx RG to elem 4
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmudh   $v29, sVPO, vOne // offset * 1
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
// vpScrF <- sVPO
    vmadn   vpScrF, vpClpF, sVPS   // + pos frac * scale
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
// vpScrI <- sVPS
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI:vpScrF is now screen space pos
    or      flagsV2, flagsV2, $11            // Combine results for second vertex
// sFOG <- vpClpI
    vmadh   sFOG, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vlt     $v29, sOCS, sOCM[3h] // Occlusion plane X+Y+Z<C in elems 0, 4
    or      flagsV1, flagsV1, $10         // Combine results for first vertex
    vmov    sTCL[5], vpST[3] // First vtx BA to elem 5
    cfc2    $10, $vcc // Load occlusion plane mid results to bits 3 and 7
    vmudh   sOTM, vpScrI, $v31[4]   // 4; scale up x and y
// vpMdl <- s1WI
vtx_store_loop_entry:
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vge     sFOG, sFOG, $v31[6]   // 0x7F00; clamp fog to >= 0 (want low byte only)   
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    // vnop
    andi    $10, $10, (1 << 0) | (1 << 4) // Only bits 0, 4 from occlusion
    vmulf   $v29, sOPM, vpScrI[1h]  // -0x4000*Y1, --, +0x4000*Y1, --, repeat vtx 2
    sub     $11, outVtx2, fogFlag      // Points 8 before outVtx2 if fog, else 0
    vmacf   sOCS, sO03, sOTM[0h]  //    4*X1*c0, --,    4*X1*c2, --, repeat vtx 2
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmulf   $v29, sOPM, vpScrI[0h]  // --, -0x4000*X1, --, +0x4000*X1, repeat vtx 2
    sbv     sFOG[15], (VTX_COLOR_A + 8)($11) // In VTX_SCR_Y if fog disabled...
    vmacf   sOTM, sO03, sOTM[1h]  // --,    4*Y1*c1, --,    4*Y1*c3, repeat vtx 2
    jr      vLoopRet
// sCLZ <- vpClpF
     vge    sCLZ, vpScrI, $v31[2]   // 0; clamp Z to >= 0
     // vnop in land slot
     
vtx_epilogue:
    // Fallthrough (across the versions boundary)
