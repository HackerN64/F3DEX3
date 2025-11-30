.include "rsp/clipping/clipping_regs.inc"

// Each clip condition (clipping plane bit being checked) has three phases that
// occur in this order: find an onscreen vertex, then find the transition from an
// onscreen to offscreen vertex, then find the transition from an offscreen to an
// onscreen vertex. The latter two are the edges which must be subdivided.
CLIP_PHASE_FIND_ON        equ  1  // These are these values so that we can use branch
CLIP_PHASE_FIND_ON_TO_OFF equ -1  // instructions to check them, and so that the sign
CLIP_PHASE_FIND_OFF_TO_ON equ  0  // bit represents which condition (on/off) to continue.
// The clipping walk finds the two edges to be subdivided and stores them in temp
// memory at these offsets. There are two of these sets of three pointers contiguously.
CLIP_PTR_ONSCR  equ 0  // Onscreen vertex at the end of the edge
CLIP_PTR_OFFSCR equ 2  // Offscreen vertex at the other end of the edge
CLIP_PTR_GEN    equ 4  // Generated vertex, where to write the results
CLIP_PTR_COUNT  equ 6

clip_after_constants:
.if CFG_PROFILING_B
    addi    perfCounterB, perfCounterB, 1  // Increment clipped (input) tris count
.endif
    sqv     vZero[0], (clipPolySgn)($zero) // Clear whole polygon
    sh      origV1Addr, clipPoly + 0xA  // Initial polygon is right-justified
    sh      $2, clipPoly + 0xC
    sh      $3, clipPoly + 0xE
    sb      $zero, materialCullMode  // In case only/all tri(s) clip then offscreen
    li      clipMaskIdx, 5           // Will sub 1; 4=screen, 3=+x, 2=-x, 1=+y, 0=-y
    li      clipAlloc, 0             // Init to no temp verts allocated
clip_condlooptop:
    addi    clipMaskIdx, clipMaskIdx, -1
    lbu     clipMaskShift, (clipCondShifts)(clipMaskIdx)
    addi    clipPtrs, rdpCmdBufEndP1, tempClipPtrs // Temp mem in output buffer for vtx ptrs
    li      clipWalkCount, 0x18 // Give up if loop traversed the polygon 3x
    li      clipWalkPhase, CLIP_PHASE_FIND_ON
    j       clip_walk_loop
     li     clipIdx, 0xA // Start pos doesn't matter, cause first actual op at on-to-off, and there should be only one of these.

clip_found_on:
    li      clipWalkPhase, CLIP_PHASE_FIND_ON_TO_OFF
clip_walk_loop_top:
    bnez    clipWalkPhase, clip_walk_loop_continue // find on, or find on to off
     // 0 = find off to on. This is an offscreen vertex, so remove it.
    addi    $10, clipIdx, -2
clip_remove_loop:
    lhu     $11, (clipPoly + 0)($10)
    sh      $11, (clipPoly + 2)($10)
    bgtz    $10, clip_remove_loop
     addi   $10, $10, -2
    sh      $zero, (clipPoly + 0)
    // Deallocate it. The first iteration is for if it's in the main vertex buffer,
    // in which case the deallocation is a no-op.
    li      $11, 0xFFFFFEFF // 0b...111011111111 (8 set to the right of the 0)
    addi    $10, clipCurVtx, -(clipTempVerts - vtxSize)
clip_deallocate_loop:
    addi    $10, $10, -vtxSize
    bgez    $10, clip_deallocate_loop // First iter: loops if in clipTempVerts
     sra    $11, $11, 1               // First iter: else, clears ...11101111111 (7)
    and     clipAlloc, clipAlloc, $11 // Clear vertex allocation bit
clip_walk_loop_continue:
    move    clipLastVtx, clipCurVtx
clip_walk_loop_skip_vtx:
    addi    clipWalkCount, clipWalkCount, -1
    bltz    clipWalkCount, clip_timeout
     addi   clipIdx, clipIdx, 2
    andi    clipIdx, clipIdx, 0xE  // Circular addressing
clip_walk_loop:
    lhu     clipCurVtx, (clipPoly)(clipIdx)
    beqz    clipCurVtx, clip_walk_loop_skip_vtx // Vertex addr = 0 -> skip
     lhu    $10, VTX_CLIP(clipCurVtx)
    sllv    $10, $10, clipMaskShift // Put clipping bit in sign bit
    xor     $10, $10, clipWalkPhase // Invert the sign bit for phase -1
    bltz    $10, clip_walk_loop_top // Nonzero clipping bit = offscreen. Phase 1 and 0, continue if offscreen.
     sh     clipLastVtx, (CLIP_PTR_ONSCR)(clipPtrs) // For on to off only
    bgtz    clipWalkPhase, clip_found_on // 1 = find on
     sh     clipCurVtx, (CLIP_PTR_OFFSCR)(clipPtrs) // For on to off only
    // Insert a space here. The zeros are always on the left.
    blez    clipIdx, clip_err_insert // Would crash if continued with clipIdx == 0
     li     $10, 2
clip_insert_loop:
    lhu     $11, (clipPoly - 0)($10) // Last iter, unecessarily copies clipIdx left one
    sh      $11, (clipPoly - 2)($10) // but this is harmless & handles case clipIdx == 2
    bne     $10, clipIdx, clip_insert_loop
     addi   $10, $10, 2
    addi    clipIdx, clipIdx, -2 // For temp vtx, then reprocess current vtx. Checked clipIdx > 0 above.
    // Allocate a temp vertex
    li      $11, 0x0080 // 7 zeros to the right
    li      clipTempVtx, clipTempVerts - vtxSize
clip_allocate_loop:
    srl     $11, $11, 1 // First iter: 6 zeros to the right, at first temp vtx
    and     $10, $11, clipAlloc
    bnez    $10, clip_allocate_loop // First iter: branch if first temp vtx already allocated
     addi   clipTempVtx, clipTempVtx, vtxSize // First iter: clipTempVtx = clipTempVerts
    beqz    $11, clip_err_alloc
     or     clipAlloc, clipAlloc, $11 // Mark the vertex allocated
    sh      clipTempVtx, (clipPoly)(clipIdx)
    sh      clipTempVtx, (CLIP_PTR_GEN)(clipPtrs)
    addi    clipPtrs, clipPtrs, CLIP_PTR_COUNT
    bltz    clipWalkPhase, clip_walk_loop_continue // -1 = on to off
     li     clipWalkPhase, CLIP_PHASE_FIND_OFF_TO_ON // (nop if done)
    sh      clipLastVtx, (CLIP_PTR_OFFSCR - CLIP_PTR_COUNT)(clipPtrs) // Swapped for off to on
    sh      clipCurVtx, (CLIP_PTR_ONSCR - CLIP_PTR_COUNT)(clipPtrs) // Swapped for off to on
clip_do_subdivision:
    lhu     clipVOnsc, (CLIP_PTR_ONSCR - 2 * CLIP_PTR_COUNT)(clipPtrs)
    lhu     clipVOffsc, (CLIP_PTR_OFFSCR - 2 * CLIP_PTR_COUNT)(clipPtrs)
    // Interpolate between clipVOffsc and clipVOns; create a new vertex which is on the
    // clipping boundary (e.g. at the screen edge)
    /*
    Five clip conditions (these are in a different order from vanilla):
           cBaseI/cBaseF[3]       cDiffI/cDiffF[3]
    4 W=0:           W1              W1  -         W2
    3 +X :    X1 - 2*W1      (X1 - 2*W1) - (X2 - 2*W2) <- the 2 is clip ratio
    2 -X :    X1 + 2*W1      (X1 + 2*W1) - (X2 + 2*W2)
    1 +Y :    Y1 - 2*W1      (Y1 - 2*W1) - (Y2 - 2*W2)
    0 -Y :    Y1 + 2*W1      (Y1 + 2*W1) - (Y2 + 2*W2)
    */
    xori    $11, clipMaskIdx, 1          // Invert sign of condition
    ldv     cPosOnOfF[0], VTX_FRAC_VEC(clipVOnsc)
    ctc2    $11, $vcc                    // Conditions 1 (+y) or 3 (+x) -> vcc[0] = 0
    ldv     cPosOnOfI[0], VTX_INT_VEC (clipVOnsc)
    vmrg    cTemp, vOne, $v31[1]         // elem 0 is 1 if W or neg cond, -1 if pos cond
    andi    $11, clipMaskIdx, 4          // W condition and screen clipping
    ldv     cPosOnOfF[8], VTX_FRAC_VEC(clipVOffsc) // Off screen to elems 4-7
    bnez    $11, clip_w                  // If so, use 1 or -1
     ldv    cPosOnOfI[8], VTX_INT_VEC (clipVOffsc)
    vmudh   cTemp, cTemp, $v31[3]        // elem 0 is (1 or -1) * 2 (clip ratio)
    andi    $11, clipMaskIdx, 2          // Conditions 2 (-x) or 3 (+x)
    vmudm   cBaseF, vOne, cPosOnOfF[0h]  // Set accumulator (care about 3, 7) to X
    bnez    $11, clip_skipy
     vmadh  cBaseI, vOne, cPosOnOfI[0h]
    vmudm   cBaseF, vOne, cPosOnOfF[1h]  // Discard that and set accumulator 3, 7 to Y
    vmadh   cBaseI, vOne, cPosOnOfI[1h]
clip_skipy:
    vmadn   cBaseF, cPosOnOfF, cTemp[0]  // + W * +/- 2
    vmadh   cBaseI, cPosOnOfI, cTemp[0]
clip_skipxy:
    vsubc   cDiffF, cBaseF, cBaseF[7]    // Vtx on screen - vtx off screen
    vsub    cDiffI, cBaseI, cBaseI[7]
    // This is computing cDiffI:F = cBaseI:F / cDiffI:F to high precision.
    // The first step is a range reduction, where cRRF becomes a scale factor
    // (roughly min(1.0f, abs(1.0f / cDiffI:F))) which scales down cDiffI:F (denominator)
    // Then the reciprocal of cDiffI:F is computed with a Newton-Raphson iteration
    // and multiplied by cBaseI:F. Finally scale down the result (numerator) by cRRF.
    vor     cTemp, cDiffI, vOne[0]  // Round up int sum to odd; this ensures the value is not 0, otherwise vabs result will be 0 instead of +/- 2
    vrcph   cRRI[3], cDiffI[3]
    vrcpl   cRRF[3], cDiffF[3]              // 1 / (x+y+z+w), vtx on screen - vtx off screen
    vrcph   cRRI[3], $v31[2]                // 0; get int result of reciprocal
    vabs    cTemp, cTemp, $v31[3]           // 2; cTemp = +/- 2 based on sum positive (incl. zero) or negative
    vmudn   cRRF, cRRF, cTemp[3]            // multiply reciprocal by +/- 2
    vmadh   cRRI, cRRI, cTemp[3]
    veq     cRRI, cRRI, $v31[2]             // 0; if RR int part is 0
    vmrg    cRRF, cRRF, $v31[1]             // keep RR frac, otherwise set frac to 0xFFFF (max)
    lhu     outVtxBase, (CLIP_PTR_GEN - 2 * CLIP_PTR_COUNT)(clipPtrs)
    vmudl   $v29, cDiffF, cRRF[3]           // Multiply clDiffI:F by RR frac*frac
    ldv     cPosOfF[0], VTX_FRAC_VEC (clipVOffsc) // Off screen loaded above, but need
    vmadm   cDiffI, cDiffI, cRRF[3]         // int*frac, int out
    ldv     cPosOfI[0], VTX_INT_VEC  (clipVOffsc) // it in elems 0-3 for interp
    vmadn   cDiffF, $v31, $v31[2]           // 0; get frac out
    luv     cRGBAOf[0], VTX_COLOR_VEC(clipVOffsc)
    vrcph   sRTI[3], cDiffI[3]              // Reciprocal of new scaled cDiff (discard)
    luv     cRGBAOn[0], VTX_COLOR_VEC(clipVOnsc)
    vrcpl   sRTF[3], cDiffF[3]              // frac part
    llv     cSTOf[0],   VTX_TC_VEC   (clipVOffsc)
    vrcph   sRTI[3], $v31[2]                // 0; int part
    llv     cSTOn[0],   VTX_TC_VEC   (clipVOnsc) // Must be before vtx_final_setup_for_clip
    vmudl   $v29, sRTF, cDiffF              // D*R (see Newton-Raphson explanation)
.if CFG_NO_OCCLUSION_PLANE
    li      vtxLeft, -1                     // vtxLeft < 0 triggers vtx_epilogue
.else
    li      vtxLeft, inputVtxSize           // but trigger this on the second loop in this version
.endif
    vmadm   $v29, sRTI, cDiffF
.if CFG_NO_OCCLUSION_PLANE
    addi    outVtxBase, outVtxBase, -vtxSize // Inc'd by 2, must point to second vtx
.else
    addi    outVtxBase, outVtxBase, vtxSize // Not inc'd, must point to second vtx
.endif
    vmadn   cDiffF, sRTF, cDiffI
    li      vLoopRet, vtx_loop_no_lighting
    vmadh   cDiffI, sRTI, cDiffI
    addi    clipPtrs, clipPtrs, CLIP_PTR_COUNT
    vmudh   $v29, vOne, $v31[4]             // 4; 4 - 4 * (D*R)
    vmadn   cDiffF, cDiffF, $v31[0]         // -4
    vmadh   cDiffI, cDiffI, $v31[0]         // -4
    vmudl   $v29, sRTF, cDiffF              // 1/cDiff result = R * that
    vmadm   $v29, sRTI, cDiffF
    vmadn   sRTF, sRTF, cDiffI
    vmadh   sRTI, sRTI, cDiffI
    vmudl   $v29, cBaseF, sRTF              // cDiff regs = cBase / cDiff
    vmadm   $v29, cBaseI, sRTF
    vmadn   cDiffF, cBaseF, sRTI
    vmadh   cDiffI, cBaseI, sRTI 
    vmudl   $v29, cDiffF, cRRF[3]           // Scale by range reduction
    vmadm   cDiffI, cDiffI, cRRF[3]
    vmadn   cDiffF, $v31, $v31[2]           // Done cDiffI:F = cBaseI:F / cDiffI:F
    // Clamp to 0x0001 to 0xFFFF range and create inverse on-screen factor
    vlt     cDiffI, cDiffI, vOne[0]         // If integer part of factor less than 1,
    vmrg    cDiffF, cDiffF, $v31[1]         // keep frac part of factor, else set to 0xFFFF (max val)
    vsubc   $v29, cDiffF, vOne[0]           // frac part - 1 for carry
    vge     cDiffI, cDiffI, $v31[2]         // 0; If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    j       vtx_final_setup_for_clip        // TODO can merge this with vtx_store_for_clip Clobbers vcc and accum in !NOC config.
     vmrg   cFadeOf, cDiffF, vOne[0]        // keep frac part of factor, else set to 1 (min val)
clip_after_final_setup: // This is here because otherwise 3 cycle stall here.
    vmudn   cFadeOn, cFadeOf, $v31[1]       // signed x * -1 = 0xFFFF - unsigned x! Fade factor for on screen vert
    // Fade between attributes for on screen and off screen vert
    vmudm   $v29,     cRGBAOf, cFadeOf[3]
    vmadm   vpRGBA,   cRGBAOn, cFadeOn[3]
    vmudm   $v29,       cSTOf, cFadeOf[3]
    vmadm   sSTS,       cSTOn, cFadeOn[3]
    vmudl   $v29,     cPosOfF, cFadeOf[3]
    vmadm   $v29,     cPosOfI, cFadeOf[3]
    vmadl   $v29,   cPosOnOfF, cFadeOn[3]
    vmadm   vpClpI, cPosOnOfI, cFadeOn[3]
    j       vtx_store_for_clip
     vmadn  vpClpF, $v31, $v31[2]           // 0; load resulting frac pos
clip_after_vtx_store:
    addi    $11, rdpCmdBufEndP1, tempClipPtrs + 3 * CLIP_PTR_COUNT
    beq     $11, clipPtrs, clip_do_subdivision // Do one more subdivision
     slv    sSTS[0], (VTX_TC_VEC   )(outVtx1) // Store not-twice-scaled ST
clip_next_cond:
    bgtz    clipMaskIdx, clip_condlooptop // Currently 0 = continue to draw
     sh     $zero, activeClipPlanes // Only matters if we need to draw
// clipDrawPtr <- clipMaskIdx; currently at 0
// Draws verts in pattern like 4-2-3, 4-1-2, 4-0-1
    lh      $11, (clipPolySgn + 0xE)($zero)
    li      $ra, clip_draw_tris_loop
    sub     flatV1Offset, origV1Addr, $11 // Offset = real orig addr - cur V1
    move    origV1Addr, $11
clip_draw_tris_loop:
    addi    clipDrawPtr, clipDrawPtr, -2
    lh      $2,         (clipPolySgn + 0xC)(clipDrawPtr)
    llv     $v4[4],     (clipPolySgn + 0xC)(clipDrawPtr) // +A ($2), +C ($3) to elem 2, 3
    beqz    $2, clip_done
     lh     $3,         (clipPolySgn + 0xE)(clipDrawPtr)
    vmov    $v8[2], $v4[3]                               // +C ($3) to elem 2
    j       tri_from_clip
     lsv    $v6[4],     (clipPolySgn + 0xE)($zero)       // +E (origV1Addr) to elem 2

clip_timeout:
    bltz    clipWalkPhase, clip_next_cond // Timed out in find on to off: all onscreen, nothing to do for this cond
    // bgtz    clipWalkPhase, clip_done // Timed out in find on: all offscreen, discard tri.
    // j       clip_done        // Timed out in find off to on: error, give up
clip_err_alloc:
clip_err_insert:
clip_done:    // Delay slot is harmless if branched
     li     $11, CLIP_SCAL_NPXY | CLIP_CAMPLANE
    sh      $11, activeClipPlanes
    snake_c_to_v30
    tri_v1_move
    add     origV1Addr, origV1Addr, flatV1Offset // Real orig addr = cur V1 + offset
    li      flatV1Offset, 0
    lh      $ra, tempTriRA
    jr      $ra                  // Delay slot is harmless
clip_w:
     vcopy  cBaseF, cPosOnOfF    // Result is just W
    j       clip_skipxy
     vcopy  cBaseI, cPosOnOfI
