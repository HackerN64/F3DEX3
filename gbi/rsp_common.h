#ifndef GBI_RSP_COMMON_H
#define GBI_RSP_COMMON_H

/* See SPDisplayList / SPBranchList */
#define G_DL_PUSH       0
#define G_DL_NOPUSH     1

/* See SPAlphaCompareCull */
#define G_ALPHA_COMPARE_CULL_DISABLE  0
#define G_ALPHA_COMPARE_CULL_BELOW    1
#define G_ALPHA_COMPARE_CULL_ABOVE   -1

#define G_MW_HALFWORD_FLAG 0x8000 /* indicates store 2 bytes instead of 4 */

/* These were never needed. */
#define G_MWO_SEGMENT_0          0x00
#define G_MWO_SEGMENT_1          0x01
#define G_MWO_SEGMENT_2          0x02
#define G_MWO_SEGMENT_3          0x03
#define G_MWO_SEGMENT_4          0x04
#define G_MWO_SEGMENT_5          0x05
#define G_MWO_SEGMENT_6          0x06
#define G_MWO_SEGMENT_7          0x07
#define G_MWO_SEGMENT_8          0x08
#define G_MWO_SEGMENT_9          0x09
#define G_MWO_SEGMENT_A          0x0A
#define G_MWO_SEGMENT_B          0x0B
#define G_MWO_SEGMENT_C          0x0C
#define G_MWO_SEGMENT_D          0x0D
#define G_MWO_SEGMENT_E          0x0E
#define G_MWO_SEGMENT_F          0x0F



#define gSPNoOp(pkt)    g1Word(pkt, G_SPNOOP, 0)
#define gsSPNoOp()      gs1Word(    G_SPNOOP, 0)

#define gSPViewport(pkt, v) \
        gDma2p((pkt), G_MOVEMEM, (v), sizeof(Vp), G_MV_VIEWPORT, 0)
#define gsSPViewport(v) \
        gsDma2p(      G_MOVEMEM, (v), sizeof(Vp), G_MV_VIEWPORT, 0)

/*
 * Display list control flow
 */

#define _gSPDisplayListRaw(pkt,dl,hint)  gDma1p(pkt, G_DL, dl, hint, G_DL_PUSH)
#define _gsSPDisplayListRaw(   dl,hint)  gsDma1p(    G_DL, dl, hint, G_DL_PUSH)

#define _gSPBranchListRaw(pkt,dl,hint)   gDma1p(pkt, G_DL, dl, hint, G_DL_NOPUSH)
#define _gsSPBranchListRaw(   dl,hint)   gsDma1p(    G_DL, dl, hint, G_DL_NOPUSH)

#define _gSPEndDisplayListRaw(pkt,hint)  g1Word(pkt, G_ENDDL, hint)
#define _gsSPEndDisplayListRaw(hint)     gs1Word(    G_ENDDL, hint)

/*
 * Converts a total expected count of DL commands to a number of bytes to
 * initially NOT load into the DL command buffer.
 */
#define _DLHINTVALUE(count) \
    (((count) > 0 && ((count) % G_INPUT_BUFFER_CMDS) > 0) ? \
    ((G_INPUT_BUFFER_CMDS - ((count) % G_INPUT_BUFFER_CMDS)) << 3) : 0)

/**
 * Optimization for reduced memory traffic. In count, put the estimated number
 * of DL commands in the target DL (the DL being called / jumped to, or the DL
 * being returned to, starting from the next command to be executed) up to and
 * including the next call / jump / return. Normally, for SPDisplayList, this is
 * just the total number of commands in the target DL. The actual on-screen
 * result will not change regardless of the value of count, but the performance
 * will be best if count is correct, and potentially worse than not specifying
 * count if it is wrong.
 * Feature suggested by Kaze Emanuar
 */
#define gSPDisplayListHint(pkt, dl, count) _gSPDisplayListRaw(pkt, dl, _DLHINTVALUE(count))
/**
 * @copydetails gSPDisplayListHint
 */
#define gsSPDisplayListHint(    dl, count) _gsSPDisplayListRaw(    dl, _DLHINTVALUE(count))

/**
 * @copydetails gSPDisplayListHint
 */
#define gSPBranchListHint(pkt, dl, count) _gSPBranchListRaw( pkt, dl, _DLHINTVALUE(count))

/**
 * @copydetails gSPDisplayListHint
 */
#define gsSPBranchListHint(    dl, count) _gsSPBranchListRaw(     dl, _DLHINTVALUE(count))

/**
 * @copydetails gSPDisplayListHint
 */
#define gSPEndDisplayListHint(pkt, count) _gSPEndDisplayListRaw( pkt, _DLHINTVALUE(count))

/**
 * @copydetails gSPDisplayListHint
 */
#define gsSPEndDisplayListHint(    count) _gsSPEndDisplayListRaw(     _DLHINTVALUE(count))

/**
 * Normal control flow commands; same as @ref gSPDisplayListHint but with hint of 0
 */
#define gSPDisplayList(pkt, dl) _gSPDisplayListRaw(pkt, dl, 0)
/**
 * Normal control flow commands; same as @ref gsSPDisplayListHint but with hint of 0
 */
#define gsSPDisplayList(    dl) _gsSPDisplayListRaw(    dl, 0)

/**
 * Normal control flow commands; same as @ref gSPBranchListHint but with hint of 0
 */
#define gSPBranchList(pkt, dl)  _gSPBranchListRaw( pkt, dl, 0)
/**
 * Normal control flow commands; same as @ref gsSPBranchListHint but with hint of 0
 */
#define gsSPBranchList(    dl)  _gsSPBranchListRaw(     dl, 0)

/**
 * Normal control flow commands; same as @ref gSPEndDisplayListHint but with hint of 0
 */
#define gSPEndDisplayList(pkt)  _gSPEndDisplayListRaw( pkt, 0)
/**
 * Normal control flow commands; same as @ref gsSPEndDisplayListHint but with hint of 0
 */
#define gsSPEndDisplayList(  )  _gsSPEndDisplayListRaw(     0)


/**
 * Flush the internal DMEM buffer of RDP commands to the RDP FIFO in DRAM,
 * causing the RDP to immediately begin executing any previous commands.
 * Without SPFlush, the RDP may not begin executing any given command until up
 * to 46 more RDP commands after that have been processed by the RSP (or the
 * final end of the display list for the frame).
 * 
 * The primary use case is if your frame's display list begins with clearing
 * the framebuffer and/or Z buffer, and then proceeds to things which take
 * significant time on the RSP before emitting many RDP commands, such as
 * matrix and lighting for drawing a character model. You should insert SPFlush
 * after the first large buffer clear to cause the RDP to begin executing those
 * long operations immediately while the RSP is continuing to work. If you are
 * clearing both the framebuffer and Z buffer, you would usually only need one
 * SPFlush after the first of these two DPFillRect commands.
 */
#define gSPFlush(pkt)   g1Word(pkt, G_FLUSH, 0)

/**
 * @copydetails gSPFlush
 */
#define gsSPFlush()    gs1Word(     G_FLUSH, 0)


#define gMoveWd(pkt, index, offset, data) \
    gDma1p((pkt), G_MOVEWORD, data, (offset & 0xFFF), index)
#define gsMoveWd(    index, offset, data) \
    gsDma1p(      G_MOVEWORD, data, (offset & 0xFFF), index)
    
#define gMoveHalfwd(pkt, index, offset, data) \
    gDma1p((pkt), G_MOVEWORD, data, (offset & 0xFFF) | G_MW_HALFWORD_FLAG, index)
#define gsMoveHalfwd(    index, offset, data) \
    gsDma1p(      G_MOVEWORD, data, (offset & 0xFFF) | G_MW_HALFWORD_FLAG, index)

/*
 * Moveword commands
 */
#ifdef F3DEX2_SEGMENTS
/* Use F3DEX2 style segment setup binary encoding. F3DEX3 supports both the
F3DEX2 encoding and the F3DEX3 encoding, but the former does not have the
relative segment resolution behavior. */
#define gSPSegment(pkt, segment, base)              \
    gMoveWd(pkt, G_MW_SEGMENT, (segment) * 4, (base))
#define gsSPSegment(segment, base)                  \
    gsMoveWd(    G_MW_SEGMENT, (segment) * 4, (base))
#else
/* F3DEX3 style segment setup, which resolves segment addresses relative to
other segments. */
#define gSPSegment(pkt, segment, base)              \
    gDma1p((pkt), G_RELSEGMENT, (base), ((segment) * 4) & 0xFFF, G_MW_SEGMENT)
#define gsSPSegment(segment, base)                  \
    gsDma1p(      G_RELSEGMENT, (base), ((segment) * 4) & 0xFFF, G_MW_SEGMENT)
#endif

#define gSPPerspNormalize(pkt, s)   gMoveHalfwd(pkt, G_MW_FX, G_MWO_PERSPNORM, (s))
#define gsSPPerspNormalize(s)       gsMoveHalfwd(    G_MW_FX, G_MWO_PERSPNORM, (s))

/**
 * Alpha compare culling. This was originally created as an optimization for cel
 * shading, but it can also be used for other scenarios. In particular, it can
 * be used with fog to cull tris which are entirely in the fog. This could also
 * be accomplished with far clipping, but far clipping is removed in F3DEX3.
 * ```
 * // Cull tris where all three vertex shade alpha are >= 0xFF
 * gSPAlphaCompareCull(..., G_ALPHA_COMPARE_CULL_ABOVE, 0xFF);
 * ```
 * 
 * If mode == G_ALPHA_COMPARE_CULL_DISABLE, tris are drawn normally.
 * 
 * Otherwise:
 * - "vertex alpha" means the post-transform alpha value at each vertex being
 *   sent to the RDP. This may be the original model vertex alpha, fog, light
 *   level (for cel shading), or Fresnel.
 * - Assuming a cel shading context: you have a threshold value thresh, you draw
 *   tris once and want to write all pixels where shade alpha >= thresh. Then
 *   you change color settings and draw tris again, and want to write all other
 *   pixels, i.e. where shade alpha < thresh.
 * 
 * For the light pass:
 * - Set blend color alpha to thresh
 * - Set CC alpha cycle 1 (or only cycle) to (shade alpha - 0) * tex alpha + 0
 * - The RDP will draw pixels whenever shade alpha >= thresh (with binary alpha
 *   from the texture)
 * - Set mode = G_ALPHA_COMPARE_CULL_BELOW in SPAlphaCompareCull, and thresh
 * - The RSP will cull any tris where all three vertex alpha values (i.e. light
 *   level) are < thresh
 * 
 * For the dark pass:
 * - Set blend color alpha to 0x100 - thresh (yes, not 0xFF - thresh).
 * - Set CC alpha cycle 1 (or only cycle) to (1 - shade alpha) * tex alpha + 0
 * - The RDP will draw pixels whenever shade alpha < thresh (with binary alpha
 *   from the texture)
 * - Set mode = G_ALPHA_COMPARE_CULL_ABOVE in SPAlphaCompareCull, and thresh
 * - The RSP will cull any tris where all three vertex alpha values (i.e. light
 *   level) are >= thresh
 * 
 * The idea is to cull tris early on the RSP which won't have any of their
 * fragments drawn on the RDP, to save RDP time and memory bandwidth.
 */
#define gSPAlphaCompareCull(pkt, mode, thresh) \
    gMoveHalfwd(pkt, G_MW_FX, G_MWO_ALPHA_COMPARE_CULL, \
        (_SHIFTL((mode), 8, 8) | _SHIFTL((thresh), 0, 8)))
/**
 * @copydetails gSPAlphaCompareCull
 */
#define gsSPAlphaCompareCull(mode, thresh) \
    gsMoveHalfwd(G_MW_FX, G_MWO_ALPHA_COMPARE_CULL, \
        (_SHIFTL((mode), 8, 8) | _SHIFTL((thresh), 0, 8)))

#endif // GBI_RSP_COMMON_H
