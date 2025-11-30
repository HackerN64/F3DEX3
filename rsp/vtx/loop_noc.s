align_with_warning 8, "One instruction of padding before vertex loop"

vtx_loop_no_lighting:
// lCOL <- sSCI
// lDTC <- sRTF
// lVCI <- sRTI
// vpLtTot <- s1WF
// vpNrmlX <- s1WI
    vmadh   $v29, vMTX1I, vpMdl[1h]
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
    sh      flagsV1,        (VTX_CLIP      )(outVtx1) // Store first vertex flags
// lDOT <- vpMdl
// sFOG <- lCOL
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    luv     vpRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// sCLZ <- sTCL
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
vtx_return_from_lighting:
vtx_return_from_texgen:
vtx_store_for_clip:
    vmudl   $v29, vpClpF, $v30[3]       // Persp norm
    sub     $11, outVtx2, fogFlag       // Points 8 before outVtx2 if fog, else 0
// s1WI <- vpNrmlX
    vmadm   s1WI, vpClpI, $v30[3]       // Persp norm
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
// s1WF <- vpLtTot
    vmadn   s1WF, $v31, $v31[2]         // 0
    sbv     sFOG[15], (VTX_COLOR_A + 8)($11) // In VTX_SCR_Y if fog disabled...
    vmov    vpScrF[1], sCLZ[2]
    sbv     sFOG[7],  (VTX_COLOR_A + 8 - vtxSize)($11) // ...which gets overwritten below
// sSCF <- lDOT
    vmudn   sSCF, vpClpF, $v31[3]        // W * clip ratio for scaled clipping
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
// sSCI <- sFOG
    vmadh   sSCI, vpClpI, $v31[3]        // W * clip ratio for scaled clipping
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vrcph   $v29[0], s1WI[3]
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
// sRTF <- lDTC
    vrcpl   sRTF[2], s1WF[3]
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
// sRTI <- lVCI
    vrcph   sRTI[3], s1WI[7]
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    vrcpl   sRTF[6], s1WF[7]
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
    vrcph   sRTI[7], $v31[2] // 0
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadm   $v29, s1WI, sRTF[2h]
    sdv     vpClpF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadn   s1WF, s1WF, sRTI[3h]
// sTCL <- sCLZ
    ldv     sTCL[0],   (VTX_IN_TC + 2 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vpClpF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    lsv     vpClpF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmudh   $v29, vOne, $v31[4]  // 4
    sdv     vpClpI[8],  (VTX_INT_VEC   )(outVtx2)
    vmadn   s1WF, s1WF, $v31[0]  // -4
    lsv     vpClpF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, $v31[0]  // -4
    sdv     vpClpI[0],  (VTX_INT_VEC   )(outVtx1)
    vmudm   $v29, vpST, sSTS       // Scale ST
    ldv     sTCL[8],   (VTX_IN_TC + 3 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
// sST2 <- vpScrI
    vmadh   sST2, vOne, $v30          // + 1 * ST offset; elems 0, 1, 4, 5
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vpClpI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmadn   s1WF, s1WF, sRTI[3h]
    lsv     vpClpI[6],  (VTX_Z_INT     )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcopy   vpST, sTCL
    cfc2    $11, $vcc                   // Scaled clip results
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
// vpMdl <- sSCF
    ldv     vpMdl[0], (VTX_IN_OB + 2 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmadn   vpClpF, vpClpF, s1WI[3h]
    ldv     vpMdl[8], (VTX_IN_OB + 3 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmov    sTCL[4], vpST[2] // First vtx RG to elem 4
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmov    sTCL[5], vpST[3] // First vtx BA to elem 5
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
    vmudl   $v29, vpClpF, $v30[3] // Persp norm
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmadm   vpClpI, vpClpI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    // vnop  // TODO maybe can rotate the loop so this is the jr land slot?
    slv     sST2[8],           (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudh   $v29, sVPO, vOne // offset * 1
    slv     sST2[0],           (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    vmadh   $v29, sFGM, $v31[6] // + (0,0,0,1,0,0,0,1) * 0x7F00
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpScrF, vpClpF, sVPS   // + pos frac * scale
    or      flagsV2, flagsV2, $11    // Combine results for second vertex
// vpScrI <- sST2
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI:vpScrF is now screen space pos
    sh      flagsV2,           (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
vtx_store_loop_entry:
    vmudn   $v29, vMTX3F, vOne
    blez    vtxLeft, vtx_epilogue
     vmadh  $v29, vMTX3I, vOne
    vmadn   $v29, vMTX0F, vpMdl[0h]
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmadh   $v29, vMTX0I, vpMdl[0h]
    jr      vLoopRet
     vmadn  $v29, vMTX1F, vpMdl[1h]
    
vtx_epilogue:
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    beqz    fogFlag, @@skip_fog
     slv    vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    sbv     sFOG[15], (VTX_COLOR_A    )(outVtx2)
    sbv     sFOG[7],  (VTX_COLOR_A    )(outVtx1)
@@skip_fog:
    vmov    vpScrF[1], sCLZ[2]
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    // Fallthrough (across the versions boundary)
