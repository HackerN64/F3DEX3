vtx_after_dma:
    mfc2    outVtxBase, $v8[6]                 // Address of output start
    andi    inVtx, dmemAddr, 0xFFF8            // Round down input start addr to DMA word
.if COUNTER_A_UPPER_VERTEX_COUNT
    sll     $11, vtxLeft, 12                   // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
.endif
vtx_constants_for_clip:
    // Sets up constants needed for vertex loop, including during clipping.
    // Results fill vPerm1:4. Uses misc temps.
.if CFG_NO_OCCLUSION_PLANE
    llv     sFOG[0], (fogFactor)($zero)           // Load fog multiplier 0 and offset 1
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
    veq     $v29, $v31, $v31[3h]                  // VCC = 00010001
    ldv     sVPO[8], (viewport + 8)($zero)
    llv     sSTS[0], (textureSettings2)($zero)    // Texture ST scale in 0, 1
    vmrg    sFGM, vOne, $v31[2]                   // sFGM is 0,0,0,1,0,0,0,1
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    ldv     sVPS[8], (viewport)($zero)
    lb      $11, geometryModeLabel + 3            // G_ATTROFFSET_ST_ENABLE in sign bit
    vmrg    sVPO, sVPO, sFOG[1]                   // Put fog offset in elements 3,7 of vtrans
    llv     $v30[0], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 0, 1
    vmov    sSTS[4], sSTS[0]
    llv     $v30[8], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 4, 5
    vmrg    sVPS, sVPS, sFOG[0]                   // Put fog multiplier in elements 3,7 of vscale
    bltz    $11, @@keepoffset
     lbu    $7, mvpValid
    vclr    $v30
@@keepoffset:
.else
    lb      flagsV1, geometryModeLabel + 3    // G_ATTROFFSET_ST_ENABLE in sign bit
    lw      $11, (fogFactor)($zero)           // Load fog multiplier MSBs and offset LSBs
    llv     sSTS[0], (textureSettings2)($zero) // Texture ST scale in 0, 1
    llv     $v30[0], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 0, 1
    llv     $v30[8], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 4, 5
    bltz    flagsV1, @@keepoffset
     srl    $10, $11, 16                      // Fog multiplier to lower bits
    vclr    $v30
@@keepoffset:
    sh      $11, (viewport + 0xE)($zero)      // Store fog offset over vtrans W
    vmov    sSTS[4], sSTS[0]
    sh      $10, (viewport + 0x6)($zero)      // Store fog multiplier over vscale W
    lbu     $7, mvpValid
    ldv     sO03[0], (occlusionPlaneEdgeCoeffs     - altBase)(altBaseReg) // Load coeffs 0-3
    ldv     sO03[8], (occlusionPlaneEdgeCoeffs     - altBase)(altBaseReg) // and for vtx 2
    ldv     sO47[0], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // Load coeffs 4-7
    ldv     sO47[8], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // and for vtx 2
    ldv     sOCM[0], (occlusionPlaneMidCoeffs      - altBase)(altBaseReg) // Load mid coeffs
    ldv     sOCM[8], (occlusionPlaneMidCoeffs      - altBase)(altBaseReg) // and for vtx 2
.endif
    vmov    sSTS[5], sSTS[1]
    bltz    inVtx, clip_after_constants             // inVtx < 0 means from clipping
     lsv    $v30[6], (perspNorm - altBase)(altBaseReg) // Perspective norm elem 3
vtx_after_setup_constants:
    bnez    $7, @@skip_recalc_mvp
     lb     viLtFlag, pointLightFlag
    li      $2, vpMatrix
    li      dmemAddr, mMatrix
    jal     mtx_multiply
     li     $3, mvpMatrix
    sb      $10, mvpValid  // $10 is nonzero from mtx_multiply, in fact 0x18. Must be >= 0 to distinguish from cmds
@@skip_recalc_mvp:
    andi    $11, vGeomMid, G_LIGHTING >> 8
    bnez    $11, vtx_select_lighting
     sb     $zero, materialCullMode  // Vtx ends material. Must be before lighting for clever packedNormalsMaskConstant reuse
vtx_setup_no_lighting:
    li      vLoopRet, vtx_loop_no_lighting
vtx_after_lt_setup:
    li      $11, mvpMatrix
vtx_load_mtx:
    lqv     vMTX0I,     (0x00)($11)  // Load MVP matrix
    lqv     vMTX2I,     (0x10)($11)
    lqv     vMTX0F,     (0x20)($11)
    lqv     vMTX2F,     (0x30)($11)
    // nop TODO
    vcopy   vMTX1I,  vMTX0I
    vcopy   vMTX3I,  vMTX2I
    ldv     vMTX1I[0],  (0x08)($11)
    vcopy   vMTX1F,  vMTX0F
    ldv     vMTX3I[0],  (0x18)($11)
    vcopy   vMTX3F,  vMTX2F
    ldv     vMTX1F[0],  (0x28)($11)
    ldv     vMTX3F[0],  (0x38)($11)
    ldv     vMTX0I[8],  (0x00)($11)
    ldv     vMTX2I[8],  (0x10)($11)
    ldv     vMTX0F[8],  (0x20)($11)
    beqz    $11, ltadv_after_mtx    // $11 = 0 = mMatrix if from ltadv
     ldv    vMTX2F[8],  (0x30)($11)
vtx_final_setup_for_clip:
.if !CFG_NO_OCCLUSION_PLANE
    vge     $v29, $v31, $v31[2h] // VCC = 00110011
.endif
    andi    fogFlag, vGeomMid, G_FOG >> 8  // Can't put before lt b/c fogFlag = mtx valid flag.
.if !CFG_NO_OCCLUSION_PLANE
    vmrg    sOPM, vOne, $v31[1] // Signs of sOPM are --++--++
.endif
    srl     fogFlag, fogFlag, 5            // 8 if G_FOG is set, 0 otherwise
    addi    outVtx1, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.if !CFG_NO_OCCLUSION_PLANE
    addi    outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.endif
    bltz    inVtx, clip_after_final_setup  // inVtx < 0 means from clipping
.if CFG_NO_OCCLUSION_PLANE
     addi   outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.else
     vmudh  sOPM, sOPM, $v31[5] // sOPM is 0xC000, 0xC000, 0x4000, 0x4000, repeat
.endif
    jal     while_wait_dma_busy  // Wait for vertex load to finish
     addi   outVtxBase, outVtxBase, -vtxSize   // Will inc by 2, but need point to 2nd
.if CFG_NO_OCCLUSION_PLANE  // With occlusion plane, vpMdl loaded at vtx_store_loop_entry
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // 1st vec pos
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // 2nd vec pos
.endif
    llv     sTCL[8],  (VTX_IN_CN + 0 * inputVtxSize)(inVtx) // RGBA in 4:5
    llv     sTCL[12], (VTX_IN_CN + 1 * inputVtxSize)(inVtx) // RGBA in 6:7
    llv     vpST[0],  (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1
    j       vtx_store_loop_entry
     llv    vpST[8],  (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5
     