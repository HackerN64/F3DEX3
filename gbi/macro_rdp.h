#ifndef GBI_MACRO_RDP_H
#define GBI_MACRO_RDP_H

#define gsSPGeometryModeSetFirst(c, s)	gsSPGeometryMode(c, s)

#define gSPSetOtherMode(pkt, cmd, sft, len, data)           \
_DW({                                                       \
    Gfx *_g = (Gfx *)(pkt);                                 \
                                                            \
    _g->words.w0 = (_SHIFTL(cmd,                24, 8) |    \
                    _SHIFTL(32 - (sft) - (len),  8, 8) |    \
                    _SHIFTL((len) - 1,           0, 8));    \
    _g->words.w1 = (unsigned int)(data);                    \
})

#define gsSPSetOtherMode(cmd, sft, len, data)   \
{                                               \
   (_SHIFTL(cmd,                24, 8) |        \
    _SHIFTL(32 - (sft) - (len),  8, 8) |        \
    _SHIFTL((len) - 1,           0, 8)),        \
    (unsigned int)(data)                        \
}

/**
 * RDP setothermode register commands - register shadowed in RSP
 */
#define gDPPipelineMode(pkt, mode)  \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_PIPELINE, 1, mode)
/**
 * @copydetails gDPPipelineMode
 */
#define gsDPPipelineMode(mode)      \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_PIPELINE, 1, mode)

#define gDPSetCycleType(pkt, type)  \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_CYCLETYPE, 2, type)
#define gsDPSetCycleType(type)      \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_CYCLETYPE, 2, type)

#define gDPSetTexturePersp(pkt, type)   \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTPERSP, 1, type)
#define gsDPSetTexturePersp(type)       \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTPERSP, 1, type)

#define gDPSetTextureDetail(pkt, type)  \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTDETAIL, 2, type)
#define gsDPSetTextureDetail(type)      \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTDETAIL, 2, type)

#define gDPSetTextureLOD(pkt, type) \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTLOD, 1, type)
#define gsDPSetTextureLOD(type)     \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTLOD, 1, type)

#define gDPSetTextureLUT(pkt, type) \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTLUT, 2, type)
#define gsDPSetTextureLUT(type)     \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTLUT, 2, type)

#define gDPSetTextureFilter(pkt, type)  \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTFILT, 2, type)
#define gsDPSetTextureFilter(type)      \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTFILT, 2, type)

#define gDPSetTextureConvert(pkt, type) \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_TEXTCONV, 3, type)
#define gsDPSetTextureConvert(type)     \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_TEXTCONV, 3, type)

#define gDPSetCombineKey(pkt, type) \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_COMBKEY, 1, type)
#define gsDPSetCombineKey(type)     \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_COMBKEY, 1, type)

#define gDPSetColorDither(pkt, mode)    \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_RGBDITHER, 2, mode)
#define gsDPSetColorDither(mode)        \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_RGBDITHER, 2, mode)

#define gDPSetAlphaDither(pkt, mode)    \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_H, G_MDSFT_ALPHADITHER, 2, mode)
#define gsDPSetAlphaDither(mode)        \
    gsSPSetOtherMode(    G_SETOTHERMODE_H, G_MDSFT_ALPHADITHER, 2, mode)

/**
 * 'blendmask' is not supported anymore.
 * The bits are reserved for future use.
 * Fri May 26 13:45:55 PDT 1995
 * @deprecated
 */
#define gDPSetBlendMask(pkt, mask)  gSPNoOp(pkt)
/**
 * @copydetails gDPSetBlendMask
 */
#define gsDPSetBlendMask(mask)      gsSPNoOp()

#define gDPSetAlphaCompare(pkt, type)   \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_L, G_MDSFT_ALPHACOMPARE, 2, type)
#define gsDPSetAlphaCompare(type)       \
    gsSPSetOtherMode(    G_SETOTHERMODE_L, G_MDSFT_ALPHACOMPARE, 2, type)

#define gDPSetDepthSource(pkt, src) \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_L, G_MDSFT_ZSRCSEL, 1, src)
#define gsDPSetDepthSource(src) \
    gsSPSetOtherMode(    G_SETOTHERMODE_L, G_MDSFT_ZSRCSEL, 1, src)

#define gDPSetRenderMode(pkt, c0, c1)   \
    gSPSetOtherMode(pkt, G_SETOTHERMODE_L, G_MDSFT_RENDERMODE, 29, (c0) | (c1))
#define gsDPSetRenderMode(c0, c1)   \
    gsSPSetOtherMode(    G_SETOTHERMODE_L, G_MDSFT_RENDERMODE, 29, (c0) | (c1))

#define gSetImage(pkt, cmd, fmt, siz, width, i)     \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(cmd,         24,  8) |  \
                    _SHIFTL(fmt,         21,  3) |  \
                    _SHIFTL(siz,         19,  2) |  \
                    _SHIFTL((width) - 1,  0, 12));  \
    _g->words.w1 = (unsigned int)(i);               \
})

#define gsSetImage(cmd, fmt, siz, width, i) \
{                                           \
   (_SHIFTL(cmd,         24,  8) |          \
    _SHIFTL(fmt,         21,  3) |          \
    _SHIFTL(siz,         19,  2) |          \
    _SHIFTL((width) - 1,  0, 12)),          \
    (unsigned int)(i)                       \
}

#define gDPSetColorImage(pkt, f, s, w, i)   gSetImage(pkt, G_SETCIMG, f, s, w, i)
#define gsDPSetColorImage(f, s, w, i)       gsSetImage(    G_SETCIMG, f, s, w, i)


/* use these for new code */
#define gDPSetDepthImage(pkt, i)    gSetImage(pkt, G_SETZIMG, 0, 0, 1, i)
#define gsDPSetDepthImage(i)        gsSetImage(    G_SETZIMG, 0, 0, 1, i)
/* kept for compatibility */
#define gDPSetMaskImage(pkt, i)     gDPSetDepthImage(pkt, i)
#define gsDPSetMaskImage(i)         gsDPSetDepthImage(    i)

#define gDPSetTextureImage(pkt, f, s, w, i) gSetImage(pkt, G_SETTIMG, f, s, w, i)
#define gsDPSetTextureImage(f, s, w, i)     gsSetImage(    G_SETTIMG, f, s, w, i)

/*
 * RDP macros
 */

#define gDPSetCombine(pkt, muxs0, muxs1)            \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_SETCOMBINE, 24,  8) | \
                    _SHIFTL(muxs0,         0, 24)); \
    _g->words.w1 = (unsigned int)(muxs1);           \
})

#define gsDPSetCombine(muxs0, muxs1)    \
{                                       \
   (_SHIFTL(G_SETCOMBINE, 24,  8) |     \
    _SHIFTL(muxs0,         0, 24)),     \
    (unsigned int)(muxs1)               \
}

#define GCCc0w0(saRGB0, mRGB0, saA0, mA0)   \
   (_SHIFTL((saRGB0), 20, 4) |              \
    _SHIFTL((mRGB0),  15, 5) |              \
    _SHIFTL((saA0),   12, 3) |              \
    _SHIFTL((mA0),     9, 3))

#define GCCc1w0(saRGB1, mRGB1)  \
   (_SHIFTL((saRGB1), 5, 4) |   \
    _SHIFTL((mRGB1),  0, 5))

#define GCCc0w1(sbRGB0, aRGB0, sbA0, aA0)   \
   (_SHIFTL((sbRGB0), 28, 4) |              \
    _SHIFTL((aRGB0),  15, 3) |              \
    _SHIFTL((sbA0),   12, 3) |              \
    _SHIFTL((aA0),     9, 3))

#define GCCc1w1(sbRGB1, saA1, mA1, aRGB1, sbA1, aA1)    \
   (_SHIFTL((sbRGB1), 24, 4) |                          \
    _SHIFTL((saA1),   21, 3) |                          \
    _SHIFTL((mA1),    18, 3) |                          \
    _SHIFTL((aRGB1),   6, 3) |                          \
    _SHIFTL((sbA1),    3, 3) |                          \
    _SHIFTL((aA1),     0, 3))

#define gDPSetCombineLERP(pkt, a0, b0, c0, d0, Aa0, Ab0, Ac0, Ad0,          \
                               a1, b1, c1, d1, Aa1, Ab1, Ac1, Ad1)          \
_DW({                                                                       \
    Gfx *_g = (Gfx *)(pkt);                                                 \
                                                                            \
    _g->words.w0 = (_SHIFTL(G_SETCOMBINE, 24, 8) |                          \
                    _SHIFTL(GCCc0w0(G_CCMUX_##a0,  G_CCMUX_##c0,            \
                                    G_ACMUX_##Aa0, G_ACMUX_##Ac0) |         \
                            GCCc1w0(G_CCMUX_##a1,  G_CCMUX_##c1),           \
                        0, 24));                                            \
    _g->words.w1 =  (unsigned int)(GCCc0w1(G_CCMUX_##b0,  G_CCMUX_##d0,     \
                                           G_ACMUX_##Ab0, G_ACMUX_##Ad0) |  \
                                   GCCc1w1(G_CCMUX_##b1,  G_ACMUX_##Aa1,    \
                                           G_ACMUX_##Ac1, G_CCMUX_##d1,     \
                                           G_ACMUX_##Ab1, G_ACMUX_##Ad1));  \
})

#define gsDPSetCombineLERP(a0, b0, c0, d0, Aa0, Ab0, Ac0, Ad0,  \
                           a1, b1, c1, d1, Aa1, Ab1, Ac1, Ad1)  \
{                                                               \
   (_SHIFTL(G_SETCOMBINE, 24, 8) |                              \
    _SHIFTL(GCCc0w0(G_CCMUX_##a0,  G_CCMUX_##c0,                \
                    G_ACMUX_##Aa0, G_ACMUX_##Ac0) |             \
            GCCc1w0(G_CCMUX_##a1,  G_CCMUX_##c1),               \
        0, 24)),                                                \
    (unsigned int)(GCCc0w1(G_CCMUX_##b0,  G_CCMUX_##d0,         \
                           G_ACMUX_##Ab0, G_ACMUX_##Ad0) |      \
                   GCCc1w1(G_CCMUX_##b1,  G_ACMUX_##Aa1,        \
                           G_ACMUX_##Ac1, G_CCMUX_##d1,         \
                           G_ACMUX_##Ab1, G_ACMUX_##Ad1))       \
}

/**
 * SetCombineMode macros are NOT redunant. It allow the C preprocessor
 * to substitute single parameter which includes commas in the token and
 * rescan for higher parameter count macro substitution.
 *
 * eg.  gsDPSetCombineMode(G_CC_MODULATE, G_CC_MODULATE) turns into
 *  gsDPSetCombineLERP(TEXEL0, 0, SHADE, 0, TEXEL0, 0, SHADE, 0,
 *      TEXEL0, 0, SHADE, 0, TEXEL0, 0, SHADE, 0)
 */
#define gDPSetCombineMode(pkt, a, b)    gDPSetCombineLERP(pkt, a, b)
/**
 * @copydetails gDPSetCombineMode
 */
#define gsDPSetCombineMode(a, b)        gsDPSetCombineLERP(    a, b)

#define gDPSetColor(pkt, c, d)          \
_DW({                                   \
    Gfx *_g = (Gfx *)(pkt);             \
                                        \
    _g->words.w0 = _SHIFTL(c, 24, 8);   \
    _g->words.w1 = (unsigned int)(d);   \
})

#define gsDPSetColor(c, d)  \
{                           \
    _SHIFTL(c, 24, 8),      \
    (unsigned int)(d)       \
}

#define DPRGBColor(pkt, cmd, r, g, b, a)    \
    gDPSetColor(pkt, cmd,                   \
           (_SHIFTL(r, 24, 8) |             \
            _SHIFTL(g, 16, 8) |             \
            _SHIFTL(b,  8, 8) |             \
            _SHIFTL(a,  0, 8)))

#define sDPRGBColor(cmd, r, g, b, a)    \
    gsDPSetColor(cmd,                   \
           (_SHIFTL(r, 24, 8) |         \
            _SHIFTL(g, 16, 8) |         \
            _SHIFTL(b,  8, 8) |         \
            _SHIFTL(a,  0, 8)))

#define gDPSetEnvColor(pkt, r, g, b, a) \
            DPRGBColor(pkt, G_SETENVCOLOR,   r, g, b, a)
            
#ifdef KAZE_GBI_HACKS
#define gsDPSetEnvColor(r, g, b, a) \
            gsSPNoOp()
#else
#define gsDPSetEnvColor(r, g, b, a) \
            sDPRGBColor(    G_SETENVCOLOR,   r, g, b, a)
#endif

#define gDPSetBlendColor(pkt, r, g, b, a) \
            DPRGBColor(pkt, G_SETBLENDCOLOR, r, g, b, a)

#define gsDPSetBlendColor(r, g, b, a) \
            sDPRGBColor(    G_SETBLENDCOLOR, r, g, b, a)

#define gDPSetFogColor(pkt, r, g, b, a) \
            DPRGBColor(pkt, G_SETFOGCOLOR,   r, g, b, a)

#define gsDPSetFogColor(r, g, b, a) \
            sDPRGBColor(    G_SETFOGCOLOR,   r, g, b, a)

#define gDPSetFillColor(pkt, d) \
            gDPSetColor(pkt, G_SETFILLCOLOR, (d))

#define gsDPSetFillColor(d) \
            gsDPSetColor(    G_SETFILLCOLOR, (d))

#define gDPSetPrimDepth(pkt, z, dz)                         \
        gDPSetColor(pkt, G_SETPRIMDEPTH,                    \
                    _SHIFTL(z, 16, 16) | _SHIFTL(dz, 0, 16))

#define gsDPSetPrimDepth(z, dz)                             \
        gsDPSetColor(G_SETPRIMDEPTH,                        \
                    _SHIFTL(z, 16, 16) | _SHIFTL(dz, 0, 16))

#define gDPSetPrimColor(pkt, m, l, r, g, b, a)          \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
                                                        \
    _g->words.w0 = (_SHIFTL(G_SETPRIMCOLOR, 24, 8) |    \
                    _SHIFTL(m,               8, 8) |    \
                    _SHIFTL(l,               0, 8));    \
    _g->words.w1 = (_SHIFTL(r, 24, 8) |                 \
                    _SHIFTL(g, 16, 8) |                 \
                    _SHIFTL(b,  8, 8) |                 \
                    _SHIFTL(a,  0, 8));                 \
})

#define gsDPSetPrimColor(m, l, r, g, b, a)  \
{                                           \
   (_SHIFTL(G_SETPRIMCOLOR, 24, 8) |        \
    _SHIFTL(m,               8, 8) |        \
    _SHIFTL(l,               0, 8)),        \
   (_SHIFTL(r, 24, 8) |                     \
    _SHIFTL(g, 16, 8) |                     \
    _SHIFTL(b,  8, 8) |                     \
    _SHIFTL(a,  0, 8))                      \
}

/**
 * gDPSetOtherMode (This is for expert user.)
 *
 * This command makes all othermode parameters set.
 * Do not use this command in the same DL with another g*SPSetOtherMode DLs.
 *
 * [Usage]
 *  gDPSetOtherMode(pkt, modeA, modeB)
 *
 *      'modeA' is described all parameters of GroupA GBI command.
 *      'modeB' is also described all parameters of GroupB GBI command.
 *
 *  GroupA:
 *    gDPPipelineMode, gDPSetCycleType, gSPSetTexturePersp,
 *    gDPSetTextureDetail, gDPSetTextureLOD, gDPSetTextureLUT,
 *    gDPSetTextureFilter, gDPSetTextureConvert, gDPSetCombineKey,
 *    gDPSetColorDither, gDPSetAlphaDither
 *
 *  GroupB:
 *    gDPSetAlphaCompare, gDPSetDepthSource, gDPSetRenderMode
 *
 *  Use 'OR' operation to get modeA and modeB.
 *
 *  modeA = G_PM_* | G_CYC_* | G_TP_* | G_TD_* | G_TL_* | G_TT_* | G_TF_*
 *      G_TC_* | G_CK_*  | G_CD_* | G_AD_*;
 *
 *  modeB = G_AC_* | G_ZS_*  | G_RM_* | G_RM_*2;
 */
#define gDPSetOtherMode(pkt, mode0, mode1)              \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
                                                        \
    _g->words.w0 = (_SHIFTL(G_RDPSETOTHERMODE, 24, 8) | \
                    _SHIFTL(mode0, 0, 24));             \
    _g->words.w1 = (unsigned int)(mode1);               \
})

/**
 * @copydetails gDPSetOtherMode
 */
#define gsDPSetOtherMode(mode0, mode1)      \
{                                           \
   (_SHIFTL(G_RDPSETOTHERMODE, 24,  8) |    \
    _SHIFTL(mode0,              0, 24)),    \
    (unsigned int)(mode1)                   \
}

/*
 * Texturing macros
 */

#define G_TX_LOADTILE   7
#define G_TX_RENDERTILE 0

/*
 * Define this to remove syncs from texture loading multi-command macros.
 * 
 * You should convert your romhack codebase to F3DEX3 without this defined
 * first, then once everything is stable, define it and fix any crashes or
 * graphical issues that arise.
 * 
 * How the syncs work: load, tile, and pipe sync all delay the RDP by fixed
 * numbers of cycles. It is the smallest number for load, a medium number for
 * tile, and the largest number for pipe. These syncs do NOT wait until
 * something is finished being used; they just stall for a fixed time.
 * (DPFullSync is different and DOES wait for writebacks to memory to be done;
 * that is not considered in this explanation.)
 * 
 * Syncs always happen after rendering something and before changing some
 * settings. In other words:
 * - gsSP2Triangles(), gsSPTextureRectangle(), etc.
 * - gsDPSomeSync(),
 * - gsDPSetSomething()
 * You never need the opposite, i.e. you never need a sync after changing
 * settings but before rendering.
 * 
 * Which sync you use depends on which settings you are changing. If you are
 * doing a texture load (DPLoadBlock or DPLoadTile), you need a load sync (or
 * either of the other syncs which wait for even longer). If you are changing
 * tile settings, you need a tile sync (or pipe sync which is longer). If you
 * are changing CC, othermode, env color, or other things like that, you need
 * a pipe sync.
 * 
 * Display lists overall should be structured like:
 * 
 * - ...
 * - previous draw tris
 * - pipe sync
 * - texture load, CC settings, othermode, etc. (no syncs within these)
 * - (no sync here)
 * - draw tris
 * - pipe sync
 * - next material setup
 * - ...
 * 
 * In SM64, the pipe sync is at the end of each object or sub-object; in OoT
 * it is at the start of each display list. This ends up being the same thing
 * when the display lists are effectively concatenated: you have a pipe sync
 * after each set of rendering things, and before each new set of changing
 * settings.
 * 
 * If you are doing multitexture and/or CI texture loads, use a different tile
 * for each load, and then you don't need any syncs in the loads. As an extreme
 * example with two CI textures:
 * - previous pipe sync, either at the start of this DL or the end of the last
 * - set tile 7 to load texture 0 CIs (no syncs)
 * - load block on tile 7 (no syncs)
 * - set tile 5 to load texture 0 palette (no syncs)
 * - load block on tile 5 (no syncs)
 * - set tile 6 to load texture 1 CIs (no syncs)
 * - load block on tile 6 (no syncs)
 * - set tile 4 to load texture 1 palette (no syncs)
 * - load block on tile 4 (no syncs)
 * - set tile 0 for render texture 0 (no syncs)
 * - set tile 1 for render texture 0 (no syncs)
 * - set othermode, CC, etc. (no syncs)
 * - draw tris (no syncs)
 * - next pipe sync, either at the end of this DL or the start of the next
 * Both fast64 and the multi-command macros in this GBI if
 * NO_SYNCS_IN_TEXTURE_LOADS is enabled do this, but if you wrote the DLs by
 * hand or they were vanilla DLs not using the multi-command macros, they may
 * need to be updated. (Then again, in that case the syncs are also written by
 * hand, so these syncs changes do not affect them.)
 * 
 * If you are writing GUI display lists with texture rectangle which look like
 * - load tex
 * - tex rect
 * - load tex
 * - tex rect
 * you need a load sync before each load tex, and you don't need any other
 * syncs.
 */
#ifdef NO_SYNCS_IN_TEXTURE_LOADS
#define gDPLoadSyncInTexLoad(pkt) (void)0
#define gDPTileSyncInTexLoad(pkt) (void)0
#define gDPPipeSyncInTexLoad(pkt) (void)0
#define gsDPLoadSyncInTexLoad
#define gsDPTileSyncInTexLoad
#define gsDPPipeSyncInTexLoad
#define gsDPPipeSyncEndOfTexLoad
#define _G_TEXLOADTILE(rtile) (G_TX_LOADTILE - (rtile))
#define _G_PALLOADTILE(rtile) (G_TX_LOADTILE - 2 - (rtile))
#else
#define gDPLoadSyncInTexLoad(pkt) gDPLoadSync(pkt)
#define gDPTileSyncInTexLoad(pkt) gDPTileSync(pkt)
#define gDPPipeSyncInTexLoad(pkt) gDPPipeSync(pkt)
#define gsDPLoadSyncInTexLoad gsDPLoadSync(),
#define gsDPTileSyncInTexLoad gsDPTileSync(),
#define gsDPPipeSyncInTexLoad gsDPPipeSync(),
#define gsDPPipeSyncEndOfTexLoad , gsDPPipeSync()
#define _G_TEXLOADTILE(rtile) G_TX_LOADTILE
#define _G_PALLOADTILE(rtile) G_TX_LOADTILE
#endif


#define G_TX_NOMIRROR   (0 << 0)
#define G_TX_WRAP       (0 << 1)
#define G_TX_MIRROR     (1 << 0)
#define G_TX_CLAMP      (1 << 1)
#define G_TX_NOMASK     0
#define G_TX_NOLOD      0

#ifndef MAX
#define MAX(a, b) ((a) > (b) ? (a) : (b))
#endif

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

/*
 *  Dxt is the inverse of the number of 64-bit words in a line of
 *  the texture being loaded using the load_block command.  If
 *  there are any 1's to the right of the 11th fractional bit,
 *  dxt should be rounded up.  The following macros accomplish
 *  this.  The 4b macros are a special case since 4-bit textures
 *  are loaded as 8-bit textures.  Dxt is fixed point 1.11. RJM
 */
#define G_TX_DXT_FRAC   11

/*
 *  For RCP 2.0, the maximum number of texels that can be loaded
 *  using a load_block command is 2048.  In order to load the total
 *  4kB of Tmem, change the texel size when loading to be G_IM_SIZ_16b,
 *  then change the tile to the proper texel size after the load.
 *  The g*DPLoadTextureBlock macros already do this, so this change
 *  will be transparent if you use these macros.  If you use
 *  the g*DPLoadBlock macros directly, you will need to handle this
 *  tile manipulation yourself.  RJM.
 */
#define G_TX_LDBLK_MAX_TXL  2047

#define TXL2WORDS(txls, b_txl)  \
    MAX(1, ((txls) * (b_txl) / 8))

#define CALC_DXT(width, b_txl)  \
    (((1 << G_TX_DXT_FRAC) + TXL2WORDS(width, b_txl) - 1) / TXL2WORDS(width, b_txl))

#define TXL2WORDS_4b(txls)  \
    MAX(1, ((txls) / 16))

#define CALC_DXT_4b(width)  \
    (((1 << G_TX_DXT_FRAC) + TXL2WORDS_4b(width) - 1) / TXL2WORDS_4b(width))

#define gDPLoadTileGeneric(pkt, c, tile, uls, ult, lrs, lrt)    \
_DW({                                                           \
    Gfx *_g = (Gfx *)(pkt);                                     \
                                                                \
    _g->words.w0 = (_SHIFTL(c,   24,  8) |                      \
                    _SHIFTL(uls, 12, 12) |                      \
                    _SHIFTL(ult,  0, 12));                      \
    _g->words.w1 = (_SHIFTL(tile, 24, 3) |                      \
                    _SHIFTL(lrs, 12, 12) |                      \
                    _SHIFTL(lrt, 0, 12));                       \
})

#define gsDPLoadTileGeneric(c, tile, uls, ult, lrs, lrt)    \
{                                                           \
   (_SHIFTL(c,   24,  8) |                                  \
    _SHIFTL(uls, 12, 12) |                                  \
    _SHIFTL(ult,  0, 12)),                                  \
   (_SHIFTL(tile, 24,  3) |                                 \
    _SHIFTL(lrs,  12, 12) |                                 \
    _SHIFTL(lrt,   0, 12))                                  \
}

#define gDPSetTileSize(pkt, t, uls, ult, lrs, lrt)                  \
        gDPLoadTileGeneric(pkt, G_SETTILESIZE, t, uls, ult, lrs, lrt)
#define gsDPSetTileSize(t, uls, ult, lrs, lrt)                      \
        gsDPLoadTileGeneric(    G_SETTILESIZE, t, uls, ult, lrs, lrt)
#define gDPLoadTile(pkt, t, uls, ult, lrs, lrt)                     \
        gDPLoadTileGeneric(pkt, G_LOADTILE, t, uls, ult, lrs, lrt)
#define gsDPLoadTile(t, uls, ult, lrs, lrt)                         \
        gsDPLoadTileGeneric(    G_LOADTILE, t, uls, ult, lrs, lrt)

#define gDPSetTile(pkt, fmt, siz, line, tmem, tile, palette, cmt,   \
                        maskt, shiftt, cms, masks, shifts)          \
_DW({                                                               \
    Gfx *_g = (Gfx *)(pkt);                                         \
                                                                    \
    _g->words.w0 = (_SHIFTL(G_SETTILE, 24, 8) |                     \
                    _SHIFTL(fmt,       21, 3) |                     \
                    _SHIFTL(siz,       19, 2) |                     \
                    _SHIFTL(line,       9, 9) |                     \
                    _SHIFTL(tmem,       0, 9));                     \
    _g->words.w1 = (_SHIFTL(tile,    24, 3) |                       \
                    _SHIFTL(palette, 20, 4) |                       \
                    _SHIFTL(cmt,     18, 2) |                       \
                    _SHIFTL(maskt,   14, 4) |                       \
                    _SHIFTL(shiftt,  10, 4) |                       \
                    _SHIFTL(cms,      8, 2) |                       \
                    _SHIFTL(masks,    4, 4) |                       \
                    _SHIFTL(shifts,   0, 4));                       \
})

#define gsDPSetTile(fmt, siz, line, tmem, tile, palette, cmt,   \
                    maskt, shiftt, cms, masks, shifts)          \
{                                                               \
   (_SHIFTL(G_SETTILE, 24, 8) |                                 \
    _SHIFTL(fmt,       21, 3) |                                 \
    _SHIFTL(siz,       19, 2) |                                 \
    _SHIFTL(line,       9, 9) |                                 \
    _SHIFTL(tmem,       0, 9)),                                 \
   (_SHIFTL(tile,    24, 3) |                                   \
    _SHIFTL(palette, 20, 4) |                                   \
    _SHIFTL(cmt,     18, 2) |                                   \
    _SHIFTL(maskt,   14, 4) |                                   \
    _SHIFTL(shiftt,  10, 4) |                                   \
    _SHIFTL(cms,      8, 2) |                                   \
    _SHIFTL(masks,    4, 4) |                                   \
    _SHIFTL(shifts,   0, 4))                                    \
}

#define gDPLoadBlock(pkt, tile, uls, ult, lrs, dxt)         \
_DW({                                                               \
    Gfx *_g = (Gfx *)(pkt);                                         \
    _g->words.w0 = (_SHIFTL(G_LOADBLOCK, 24,  8) |                  \
                    _SHIFTL(uls,         12, 12) |                  \
                    _SHIFTL(ult,          0, 12));                  \
    _g->words.w1 = (_SHIFTL(tile,                         24,  3) | \
                    _SHIFTL(MIN(lrs, G_TX_LDBLK_MAX_TXL), 12, 12) | \
                    _SHIFTL(dxt,                           0, 12)); \
})

#define gsDPLoadBlock(tile, uls, ult, lrs, dxt) \
{                                                       \
   (_SHIFTL(G_LOADBLOCK, 24,  8) |                      \
    _SHIFTL(uls,         12, 12) |                      \
    _SHIFTL(ult,          0, 12)),                      \
   (_SHIFTL(tile,                           24,  3) |   \
    _SHIFTL((MIN(lrs, G_TX_LDBLK_MAX_TXL)), 12, 12) |   \
    _SHIFTL(dxt,                             0, 12))    \
}

#define gDPLoadTLUTCmd(pkt, tile, count)        \
_DW({                                           \
    Gfx *_g = (Gfx *)pkt;                       \
                                                \
    _g->words.w0 = _SHIFTL(G_LOADTLUT, 24, 8);  \
    _g->words.w1 = (_SHIFTL((tile),  24,  3) |  \
                    _SHIFTL((count), 14, 10));  \
})

#define gsDPLoadTLUTCmd(tile, count)    \
{                                       \
    _SHIFTL(G_LOADTLUT, 24, 8),         \
   (_SHIFTL((tile),  24,  3) |          \
    _SHIFTL((count), 14, 10))           \
}

#define gDPLoadTextureBlock(pkt, timg, fmt, siz, width, height, pal,        \
                                 cms, cmt, masks, maskt, shifts, shiftt)    \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,             \
        0, cmt, maskt, shiftt, cms, masks, shifts);                         \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) -1,              \
        CALC_DXT(width, siz##_BYTES));                                      \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, 0,                         \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                            \
})

#define gDPLoadTextureBlockYuv(pkt, timg, fmt, siz, width, height, pal,     \
                                    cms, cmt, masks, maskt, shifts, shiftt) \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,             \
        0, cmt, maskt, shiftt, cms, masks, shifts);                         \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) -1,              \
        CALC_DXT(width, siz##_BYTES));                                      \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((width) * 1) + 7) >> 3, 0,                                        \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                            \
})

/* Load fix rww 27jun95 */
/* The S at the end means odd lines are already word Swapped */

#define gDPLoadTextureBlockS(pkt, timg, fmt, siz, width, height, pal,       \
                                  cms, cmt, masks, maskt, shifts, shiftt)   \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,             \
        0, cmt, maskt, shiftt, cms, masks, shifts);                         \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1, 0);         \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, 0,                         \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                            \
})

/**
 *  Allow tmem address and render tile to be specified.
 *  The S at the end means odd lines are already word Swapped
 */
#define gDPLoadMultiBlockS(pkt, timg, tmem, rtile, fmt, siz, width, height, pal,    \
                                cms, cmt, masks, maskt, shifts, shiftt)             \
_DW({                                                                               \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                        \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt, shiftt, cms, masks, shifts);                                 \
    gDPLoadSyncInTexLoad(pkt);                                                      \
    gDPLoadBlock(pkt, _G_TEXLOADTILE(rtile), 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,0);                  \
    gDPPipeSyncInTexLoad(pkt);                                                      \
    gDPSetTile(pkt, fmt, siz,                                                       \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, tmem,                              \
        rtile, pal, cmt, maskt, shiftt, cms, masks,                                 \
        shifts);                                                                    \
    gDPSetTileSize(pkt, rtile, 0, 0,                                                \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                     \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                    \
})


#define gDPLoadTextureBlockYuvS(pkt, timg, fmt, siz, width, height, pal,        \
                                     cms, cmt, masks, maskt, shifts, shiftt)    \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                    \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,                 \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                      \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,0);              \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, siz,                                                   \
        (((width) * 1) + 7) >> 3, 0,                                            \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);          \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                                  \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})

/*
 *  allows tmem address to be specified
 */
#define _gDPLoadTextureBlock(pkt, timg, tmem, fmt, siz, width, height, pal, \
                                  cms, cmt, masks, maskt, shifts, shiftt)   \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, tmem, G_TX_LOADTILE,          \
        0, cmt, maskt, shiftt, cms, masks, shifts);                         \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,             \
        CALC_DXT(width, siz##_BYTES));                                      \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, tmem,                      \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                            \
})

/*
 *  allows tmem address and render tile to be specified
 */
#define _gDPLoadTextureBlockTile(pkt, timg, tmem, rtile, fmt, siz, width, height, pal,  \
                                      cms, cmt, masks, maskt, shifts, shiftt)           \
_DW({                                                                                   \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                            \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),              \
        0, cmt, maskt, shiftt, cms, masks, shifts);                                     \
    gDPLoadSyncInTexLoad(pkt);                                                          \
    gDPLoadBlock(pkt, _G_TEXLOADTILE(rtile), 0, 0,                                      \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,                         \
        CALC_DXT(width, siz##_BYTES));                                                  \
    gDPPipeSyncInTexLoad(pkt);                                                          \
    gDPSetTile(pkt, fmt, siz,                                                           \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, tmem,                                  \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                            \
    gDPSetTileSize(pkt, rtile, 0, 0,                                                    \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                         \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                        \
})

/**
 *  allows tmem address and render tile to be specified
 */
#define gDPLoadMultiBlock(pkt, timg, tmem, rtile, fmt, siz, width, height, pal, \
                               cms, cmt, masks, maskt, shifts, shiftt)          \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, siz##_LOAD_BLOCK, 1, timg);                    \
    gDPSetTile(pkt, fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),      \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, _G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,                 \
        CALC_DXT(width, siz##_BYTES));                                          \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, siz,                                                   \
        (((width) * siz##_LINE_BYTES) + 7) >> 3, tmem,                          \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                    \
    gDPSetTileSize(pkt, rtile, 0, 0,                                            \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})

#define gsDPLoadTextureBlock(timg, fmt, siz, width, height, pal,        \
                             cms, cmt, masks, maskt, shifts, shiftt)    \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,             \
        0, cmt, maskt, shiftt, cms, masks, shifts),                     \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                  \
        (((width)*(height) + siz##_INCR) >> siz##_SHIFT) - 1,           \
        CALC_DXT(width, siz##_BYTES)),                                  \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, siz,                                               \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), 0,                   \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),  \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                         \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

/* Here is the static form of the pre-swapped texture block loading */
/* See gDPLoadTextureBlockS() for reference.  Basically, just don't
   calculate DxT, use 0 */

#define gsDPLoadTextureBlockS(timg, fmt, siz, width, height, pal,       \
                              cms, cmt, masks, maskt, shifts, shiftt)   \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, 0, G_TX_LOADTILE,             \
        0, cmt, maskt,shiftt, cms, masks, shifts),                      \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1, 0),     \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, siz,                                               \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), 0,                   \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks,           \
        shifts),                                                        \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                         \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

/*
 *  Allow tmem address to be specified
 */
#define _gsDPLoadTextureBlock(timg, tmem, fmt, siz, width, height, pal, \
                              cms, cmt, masks, maskt, shifts, shiftt)   \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, tmem, G_TX_LOADTILE,          \
        0, cmt, maskt, shiftt, cms, masks, shifts),                     \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,         \
        CALC_DXT(width, siz##_BYTES)),                                  \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, siz,                                               \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), tmem,                \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks,           \
        shifts),                                                        \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                         \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)


/*
 *  Allow tmem address and render_tile to be specified
 */
#define _gsDPLoadTextureBlockTile(timg, tmem, rtile, fmt, siz, width, height, pal,  \
                                  cms, cmt, masks, maskt, shifts, shiftt)           \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                            \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),              \
        0, cmt, maskt, shiftt, cms, masks, shifts),                                 \
    gsDPLoadSyncInTexLoad                                                           \
    gsDPLoadBlock(_G_TEXLOADTILE(rtile), 0, 0,                                      \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,                     \
        CALC_DXT(width, siz##_BYTES)),                                              \
    gsDPPipeSyncInTexLoad                                                           \
    gsDPSetTile(fmt, siz,                                                           \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), tmem,                            \
        rtile, pal, cmt, maskt, shiftt, cms, masks,                                 \
        shifts),                                                                    \
    gsDPSetTileSize(rtile, 0, 0,                                                    \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                     \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)


/**
 *  Allow tmem address and render_tile to be specified, useful when loading
 *  mutilple tiles at a time.
 */
#define gsDPLoadMultiBlock(timg, tmem, rtile, fmt, siz, width, height, pal, \
                           cms, cmt, masks, maskt, shifts, shiftt)          \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                    \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),      \
        0, cmt, maskt, shiftt, cms, masks, shifts),                         \
    gsDPLoadSyncInTexLoad                                                   \
    gsDPLoadBlock(_G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1,             \
        CALC_DXT(width, siz##_BYTES)),                                      \
    gsDPPipeSyncInTexLoad                                                   \
    gsDPSetTile(fmt, siz,                                                   \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), tmem,                    \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),                \
    gsDPSetTileSize(rtile, 0, 0,                                            \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

/**
 *  Allows tmem and render tile to be specified.  Useful when loading
 *  several tiles at a time.
 *
 *  Here is the static form of the pre-swapped texture block loading
 *  See gDPLoadTextureBlockS() for reference.  Basically, just don't
 *  calculate DxT, use 0
 */
#define gsDPLoadMultiBlockS(timg, tmem, rtile, fmt, siz, width, height, pal,    \
                            cms, cmt, masks, maskt, shifts, shiftt)             \
    gsDPSetTextureImage(fmt, siz##_LOAD_BLOCK, 1, timg),                        \
    gsDPSetTile(fmt, siz##_LOAD_BLOCK, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt,shiftt, cms, masks, shifts),                              \
    gsDPLoadSyncInTexLoad                                                       \
    gsDPLoadBlock(_G_TEXLOADTILE(rtile), 0, 0,                                  \
        (((width) * (height) + siz##_INCR) >> siz##_SHIFT) - 1, 0),             \
    gsDPPipeSyncInTexLoad                                                       \
    gsDPSetTile(fmt, siz,                                                       \
        ((((width) * siz##_LINE_BYTES) + 7) >> 3), tmem,                        \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),                    \
    gsDPSetTileSize(rtile, 0, 0,                                                \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)


#define gDPLoadTextureBlock_4b(pkt, timg, fmt, width, height, pal,          \
                                    cms, cmt, masks, maskt, shifts, shiftt) \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_16b, 1, timg);                    \
    gDPSetTile(pkt, fmt, G_IM_SIZ_16b, 0, 0, G_TX_LOADTILE,                 \
        0, cmt, maskt, shiftt, cms, masks, shifts);                         \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + 3) >> 2) - 1,                                \
        CALC_DXT_4b(width));                                                \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                       \
        ((((width) >> 1) + 7) >> 3), 0,                                     \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                            \
})

/* Load fix rww 27jun95 */
/* The S at the end means odd lines are already word Swapped */

#define gDPLoadTextureBlock_4bS(pkt, timg, fmt, width, height, pal,             \
                                     cms, cmt, masks, maskt, shifts, shiftt)    \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_16b, 1, timg);                        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_16b, 0, 0, G_TX_LOADTILE,                     \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                      \
        (((width) * (height) + 3) >> 2) - 1,                                    \
        0);                                                                     \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), 0,                                         \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);          \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                                  \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})

/**
 *  4-bit load block.  Useful when loading multiple tiles
 */
#define gDPLoadMultiBlock_4b(pkt, timg, tmem, rtile, fmt, width, height, pal,   \
                                  cms, cmt, masks, maskt, shifts, shiftt)       \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_16b, 1, timg);                        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_16b, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, _G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + 3) >> 2) - 1,                                    \
        CALC_DXT_4b(width));                                                    \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                      \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                    \
    gDPSetTileSize(pkt, rtile, 0, 0,                                            \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})

/**
 *  4-bit load block.  Allows tmem and render tile to be specified.  Useful when
 *  loading multiple tiles.  The S means odd lines are already word swapped.
 */
#define gDPLoadMultiBlock_4bS(pkt, timg, tmem, rtile, fmt, width, height, pal,  \
                                   cms, cmt, masks, maskt, shifts, shiftt)      \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_16b, 1, timg);                        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_16b, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, _G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + 3) >> 2) - 1,                                    \
        0);                                                                     \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                      \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                    \
    gDPSetTileSize(pkt, rtile, 0, 0,                                            \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})


#define _gDPLoadTextureBlock_4b(pkt, timg, tmem, fmt, width, height, pal,       \
                                     cms, cmt, masks, maskt, shifts, shiftt)    \
_DW({                                                                           \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_16b, 1, timg);                        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_16b, 0, tmem, G_TX_LOADTILE,                  \
        0, cmt, maskt, shiftt, cms, masks, shifts);                             \
    gDPLoadSyncInTexLoad(pkt);                                                  \
    gDPLoadBlock(pkt, G_TX_LOADTILE, 0, 0,                                      \
        (((width) * (height) + 3) >> 2) - 1,                                    \
        CALC_DXT_4b(width));                                                    \
    gDPPipeSyncInTexLoad(pkt);                                                  \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                      \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);          \
    gDPSetTileSize(pkt, G_TX_RENDERTILE, 0, 0,                                  \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                                 \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC);                                \
})

#define gsDPLoadTextureBlock_4b(timg, fmt, width, height, pal,          \
                                cms, cmt, masks, maskt, shifts, shiftt) \
    gsDPSetTextureImage(fmt, G_IM_SIZ_16b, 1, timg),                    \
    gsDPSetTile(fmt, G_IM_SIZ_16b, 0, 0, G_TX_LOADTILE,                 \
        0, cmt, maskt, shiftt, cms, masks, shifts),                     \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                  \
        (((width) * (height) + 3) >> 2) - 1,                            \
        CALC_DXT_4b(width)),                                            \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                       \
        ((((width) >> 1) + 7) >> 3), 0,                                 \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),  \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                              \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                         \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

#define gsDPLoadTextureBlock_4bS(timg, fmt, width, height, pal,             \
                                 cms, cmt, masks, maskt, shifts, shiftt)    \
    gsDPSetTextureImage(fmt, G_IM_SIZ_16b, 1, timg),                        \
    gsDPSetTile(fmt, G_IM_SIZ_16b, 0, 0, G_TX_LOADTILE,                     \
        0, cmt, maskt, shiftt, cms, masks, shifts),                         \
    gsDPLoadSyncInTexLoad                                                   \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                      \
        (((width) * (height) + 3) >> 2) - 1,                                \
        0),                                                                 \
    gsDPPipeSyncInTexLoad                                                   \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), 0,                                     \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),      \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                                  \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

/**
 *  4-bit load block.  Allows tmem address and render tile to be specified.
 *  Useful when loading multiple tiles.
 */
#define gsDPLoadMultiBlock_4b(timg, tmem, rtile, fmt, width, height, pal,   \
                              cms, cmt, masks, maskt, shifts, shiftt)       \
    gsDPSetTextureImage(fmt, G_IM_SIZ_16b, 1, timg),                        \
    gsDPSetTile(fmt, G_IM_SIZ_16b, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt, shiftt, cms, masks, shifts),                         \
    gsDPLoadSyncInTexLoad                                                   \
    gsDPLoadBlock(_G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + 3) >> 2) - 1,                                \
        CALC_DXT_4b(width)),                                                \
    gsDPPipeSyncInTexLoad                                                   \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                  \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),                \
    gsDPSetTileSize(rtile, 0, 0,                                            \
        ((width)-1) << G_TEXTURE_IMAGE_FRAC,                                \
        ((height)-1) << G_TEXTURE_IMAGE_FRAC)


/**
 *  4-bit load block.  Allows tmem address and render tile to be specified.
 *  Useful when loading multiple tiles.  S means odd lines are already swapped.
 */
#define gsDPLoadMultiBlock_4bS(timg, tmem, rtile, fmt, width, height, pal,  \
                               cms, cmt, masks, maskt, shifts, shiftt)      \
    gsDPSetTextureImage(fmt, G_IM_SIZ_16b, 1, timg),                        \
    gsDPSetTile(fmt, G_IM_SIZ_16b, 0, tmem, _G_TEXLOADTILE(rtile),          \
        0, cmt, maskt, shiftt, cms, masks, shifts),                         \
    gsDPLoadSyncInTexLoad                                                   \
    gsDPLoadBlock(_G_TEXLOADTILE(rtile), 0, 0,                              \
        (((width) * (height) + 3) >> 2) - 1,                                \
        0),                                                                 \
    gsDPPipeSyncInTexLoad                                                   \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                  \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),                \
    gsDPSetTileSize(rtile, 0, 0,                                            \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)


/*
 *  Allows tmem address to be specified
 */
#define _gsDPLoadTextureBlock_4b(timg, tmem, fmt, width, height, pal,       \
                                 cms, cmt, masks, maskt, shifts, shiftt)    \
    gsDPSetTextureImage(fmt, G_IM_SIZ_16b, 1, timg),                        \
    gsDPSetTile(fmt, G_IM_SIZ_16b, 0, tmem, G_TX_LOADTILE,                  \
        0, cmt, maskt, shiftt, cms, masks, shifts),                         \
    gsDPLoadSyncInTexLoad                                                   \
    gsDPLoadBlock(G_TX_LOADTILE, 0, 0,                                      \
        (((width) * (height) + 3) >> 2) - 1,                                \
        CALC_DXT_4b(width)),                                                \
    gsDPPipeSyncInTexLoad                                                   \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                           \
        ((((width) >> 1) + 7) >> 3), tmem,                                  \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),      \
    gsDPSetTileSize(G_TX_RENDERTILE, 0, 0,                                  \
        ((width)  - 1) << G_TEXTURE_IMAGE_FRAC,                             \
        ((height) - 1) << G_TEXTURE_IMAGE_FRAC)

#define gDPLoadTextureTile(pkt, timg, fmt, siz, width, height,          \
                                uls, ult, lrs, lrt, pal,                \
                                cms, cmt, masks, maskt, shifts, shiftt) \
_DW({                                                                   \
    gDPSetTextureImage(pkt, fmt, siz, width, timg);                     \
    gDPSetTile(pkt, fmt, siz,                                           \
        (((((lrs) - (uls) + 1) * siz##_TILE_BYTES) + 7) >> 3), 0,       \
        G_TX_LOADTILE, 0, cmt, maskt, shiftt, cms, masks,               \
        shifts);                                                        \
    gDPLoadSyncInTexLoad(pkt);                                          \
    gDPLoadTile(pkt, G_TX_LOADTILE,                                     \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                  \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                 \
    gDPPipeSyncInTexLoad(pkt);                                          \
    gDPSetTile(pkt, fmt, siz,                                           \
        (((((lrs) - (uls) + 1) * siz##_LINE_BYTES) + 7) >> 3), 0,       \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);  \
    gDPSetTileSize(pkt, G_TX_RENDERTILE,                                \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                  \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                 \
})

/**
 *  Load texture tile.  Allows tmem address and render tile to be specified.
 *  Useful for loading multiple tiles.
 */
#define gDPLoadMultiTile(pkt, timg, tmem, rtile, fmt, siz, width, height,   \
                              uls, ult, lrs, lrt, pal,                      \
                              cms, cmt, masks, maskt, shifts, shiftt)       \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, siz, width, timg);                         \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((((lrs) - (uls) + 1) * siz##_TILE_BYTES) + 7) >> 3), tmem,        \
        _G_TEXLOADTILE(rtile), 0, cmt, maskt, shiftt, cms, masks, shifts);  \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadTile(pkt, _G_TEXLOADTILE(rtile),                                 \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                      \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                     \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, siz,                                               \
        (((((lrs) - (uls) + 1) * siz##_LINE_BYTES) + 7) >> 3), tmem,        \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                \
    gDPSetTileSize(pkt, rtile,                                              \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                      \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                     \
})


#define gsDPLoadTextureTile(timg, fmt, siz, width, height,              \
                            uls, ult, lrs, lrt, pal,                    \
                            cms, cmt, masks, maskt, shifts, shiftt)     \
    gsDPSetTextureImage(fmt, siz, width, timg),                         \
    gsDPSetTile(fmt, siz,                                               \
        (((((lrs) - (uls) + 1) * siz##_TILE_BYTES) + 7) >> 3), 0,       \
        G_TX_LOADTILE, 0, cmt, maskt, shiftt, cms, masks, shifts),      \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadTile(G_TX_LOADTILE,                                         \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                  \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrt) << G_TEXTURE_IMAGE_FRAC),                                 \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, siz,                                               \
        (((((lrs) - (uls) + 1) * siz##_LINE_BYTES) + 7) >> 3), 0,       \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),  \
    gsDPSetTileSize(G_TX_RENDERTILE,                                    \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                  \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrt) << G_TEXTURE_IMAGE_FRAC)

/**
 *  Load texture tile.  Allows tmem address and render tile to be specified.
 *  Useful for loading multiple tiles.
 */
#define gsDPLoadMultiTile(timg, tmem, rtile, fmt, siz, width, height,      \
                          uls, ult, lrs, lrt, pal,                         \
                          cms, cmt, masks, maskt, shifts, shiftt)          \
    gsDPSetTextureImage(fmt, siz, width, timg),                            \
    gsDPSetTile(fmt, siz,                                                  \
        (((((lrs) - (uls) + 1) * siz##_TILE_BYTES) + 7) >> 3), tmem,       \
        _G_TEXLOADTILE(rtile), 0, cmt, maskt, shiftt, cms, masks, shifts), \
    gsDPLoadSyncInTexLoad                                                  \
    gsDPLoadTile(_G_TEXLOADTILE(rtile),                                    \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                     \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrt) << G_TEXTURE_IMAGE_FRAC),                                    \
    gsDPPipeSyncInTexLoad                                                  \
    gsDPSetTile(fmt, siz,                                                  \
        (((((lrs) - (uls) + 1) * siz##_LINE_BYTES) + 7) >> 3),             \
        tmem, rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),         \
    gsDPSetTileSize(rtile,                                                 \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                     \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrt) << G_TEXTURE_IMAGE_FRAC)

#define gDPLoadTextureTile_4b(pkt, timg, fmt, width, height,                \
                                   uls, ult, lrs, lrt, pal,                 \
                                   cms, cmt, masks, maskt, shifts, shiftt)  \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_8b, ((width) >> 1), timg);        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_8b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), 0,                         \
        G_TX_LOADTILE, 0, cmt, maskt, shiftt, cms, masks, shifts);          \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadTile(pkt, G_TX_LOADTILE,                                         \
        (uls) << (G_TEXTURE_IMAGE_FRAC - 1),                                \
        (ult) << (G_TEXTURE_IMAGE_FRAC),                                    \
        (lrs) << (G_TEXTURE_IMAGE_FRAC - 1),                                \
        (lrt) << (G_TEXTURE_IMAGE_FRAC));                                   \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), 0,                         \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts);      \
    gDPSetTileSize(pkt, G_TX_RENDERTILE,                                    \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                      \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                     \
})

/**
 *  Load texture tile.  Allows tmem address and render tile to be specified.
 *  Useful for loading multiple tiles.
 */
#define gDPLoadMultiTile_4b(pkt, timg, tmem, rtile, fmt, width, height,     \
                                 uls, ult, lrs, lrt, pal,                   \
                                 cms, cmt, masks, maskt, shifts, shiftt)    \
_DW({                                                                       \
    gDPSetTextureImage(pkt, fmt, G_IM_SIZ_8b, ((width) >> 1), timg);        \
    gDPSetTile(pkt, fmt, G_IM_SIZ_8b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), tmem,                      \
        _G_TEXLOADTILE(rtile), 0, cmt, maskt, shiftt, cms, masks, shifts);  \
    gDPLoadSyncInTexLoad(pkt);                                              \
    gDPLoadTile(pkt, _G_TEXLOADTILE(rtile),                                 \
        (uls) << (G_TEXTURE_IMAGE_FRAC - 1),                                \
        (ult) << (G_TEXTURE_IMAGE_FRAC),                                    \
        (lrs) << (G_TEXTURE_IMAGE_FRAC - 1),                                \
        (lrt) << (G_TEXTURE_IMAGE_FRAC));                                   \
    gDPPipeSyncInTexLoad(pkt);                                              \
    gDPSetTile(pkt, fmt, G_IM_SIZ_4b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), tmem,                      \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts);                \
    gDPSetTileSize(pkt, rtile,                                              \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                      \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                      \
        (lrt) << G_TEXTURE_IMAGE_FRAC);                                     \
})

#define gsDPLoadTextureTile_4b(timg, fmt, width, height,                \
                               uls, ult, lrs, lrt, pal,                 \
                               cms, cmt, masks, maskt, shifts, shiftt)  \
    gsDPSetTextureImage(fmt, G_IM_SIZ_8b, ((width) >> 1), timg),        \
    gsDPSetTile(fmt, G_IM_SIZ_8b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), 0,                     \
        G_TX_LOADTILE, 0, cmt, maskt, shiftt, cms, masks, shifts),      \
    gsDPLoadSyncInTexLoad                                               \
    gsDPLoadTile(G_TX_LOADTILE,                                         \
        (uls) << (G_TEXTURE_IMAGE_FRAC - 1),                            \
        (ult) << (G_TEXTURE_IMAGE_FRAC),                                \
        (lrs) << (G_TEXTURE_IMAGE_FRAC - 1),                            \
        (lrt) << (G_TEXTURE_IMAGE_FRAC)),                               \
    gsDPPipeSyncInTexLoad                                               \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                       \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), 0,                     \
        G_TX_RENDERTILE, pal, cmt, maskt, shiftt, cms, masks, shifts),  \
    gsDPSetTileSize(G_TX_RENDERTILE,                                    \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                  \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                  \
        (lrt) << G_TEXTURE_IMAGE_FRAC)

/**
 * @copydetails gDPLoadMultiTile_4b
 */
#define gsDPLoadMultiTile_4b(timg, tmem, rtile, fmt, width, height,        \
                             uls, ult, lrs, lrt, pal,                      \
                             cms, cmt, masks, maskt, shifts, shiftt)       \
                                                                           \
    gsDPSetTextureImage(fmt, G_IM_SIZ_8b, ((width) >> 1), timg),           \
    gsDPSetTile(fmt, G_IM_SIZ_8b,                                          \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), tmem,                     \
        _G_TEXLOADTILE(rtile), 0, cmt, maskt, shiftt, cms, masks, shifts), \
    gsDPLoadSyncInTexLoad                                                  \
    gsDPLoadTile(_G_TEXLOADTILE(rtile),                                    \
        (uls) << (G_TEXTURE_IMAGE_FRAC - 1),                               \
        (ult) << (G_TEXTURE_IMAGE_FRAC),                                   \
        (lrs) << (G_TEXTURE_IMAGE_FRAC - 1),                               \
        (lrt) << (G_TEXTURE_IMAGE_FRAC)),                                  \
    gsDPPipeSyncInTexLoad                                                  \
    gsDPSetTile(fmt, G_IM_SIZ_4b,                                          \
        (((((lrs) - (uls) + 1) >> 1) + 7) >> 3), tmem,                     \
        rtile, pal, cmt, maskt, shiftt, cms, masks, shifts),               \
    gsDPSetTileSize(rtile,                                                 \
        (uls) << G_TEXTURE_IMAGE_FRAC,                                     \
        (ult) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrs) << G_TEXTURE_IMAGE_FRAC,                                     \
        (lrt) << G_TEXTURE_IMAGE_FRAC)

/**
 *  Load a 16-entry palette (for 4-bit CI textures)
 *  Assumes a 16 entry tlut is being loaded, palette # is 0-15
 *  With NO_SYNCS_IN_TEXTURE_LOADS: assumes that palette 0 is for multitexture
 *  texture 0 and palette 1 is for texture 1 (uses load tiles 5 and 4)
 */
#define gDPLoadTLUT_pal16(pkt, pal, dram)                            \
_DW({                                                                \
    gDPSetTextureImage(pkt, G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram);   \
    gDPTileSyncInTexLoad(pkt);                                       \
    gDPSetTile(pkt, 0, 0, 0, (256 + (((pal) & 0xF) * 16)),           \
                    _G_PALLOADTILE((pal) & 1), 0, 0, 0, 0, 0, 0, 0); \
    gDPLoadSyncInTexLoad(pkt);                                       \
    gDPLoadTLUTCmd(pkt, _G_PALLOADTILE((pal) & 1), 15);              \
    gDPPipeSyncInTexLoad(pkt);                                       \
})
/**
 * @copydetails gDPLoadTLUT_pal16
 */
#define gsDPLoadTLUT_pal16(pal, dram)                            \
    gsDPSetTextureImage(G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram),   \
    gsDPTileSyncInTexLoad                                        \
    gsDPSetTile(0, 0, 0, (256 + (((pal) & 0xF) * 16)),           \
                _G_PALLOADTILE((pal) & 1), 0, 0, 0, 0, 0, 0, 0), \
    gsDPLoadSyncInTexLoad                                        \
    gsDPLoadTLUTCmd(_G_PALLOADTILE((pal) & 1), 15)               \
    gsDPPipeSyncEndOfTexLoad

/**
 *  Load a 256-entry palette (for 8-bit CI textures)
 *  Assumes a 256 entry tlut is being loaded, palette # is not used
 */
#define gDPLoadTLUT_pal256(pkt, dram)                                   \
_DW({                                                                   \
    gDPSetTextureImage(pkt, G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram);      \
    gDPTileSyncInTexLoad(pkt);                                          \
    gDPSetTile(pkt, 0, 0, 0, 256,                                       \
                    _G_PALLOADTILE(0), 0, 0, 0, 0, 0, 0, 0);            \
    gDPLoadSyncInTexLoad(pkt);                                          \
    gDPLoadTLUTCmd(pkt, _G_PALLOADTILE(0), 255);                        \
    gDPPipeSyncInTexLoad(pkt);                                          \
})

/**
 * @copydetails gDPLoadTLUT_pal256
 */
#define gsDPLoadTLUT_pal256(dram)                               \
    gsDPSetTextureImage(G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram),  \
    gsDPTileSyncInTexLoad                                       \
    gsDPSetTile(0, 0, 0, 256,                                   \
                _G_PALLOADTILE(0), 0, 0, 0, 0, 0, 0, 0),        \
    gsDPLoadSyncInTexLoad                                       \
    gsDPLoadTLUTCmd(_G_PALLOADTILE(0), 255)                     \
    gsDPPipeSyncEndOfTexLoad

/*
 * Assumes that the starting TMEM address is calculated like in DPLoadTLUT_pal16
 * (which is the only sane way to do it if you are loading two palettes for
 * multitexture)
 */
#define _G_PALTMEMTOTILE(tmemaddr) _G_PALLOADTILE(((tmemaddr) >> 4) & 1)

#define gDPLoadTLUT(pkt, count, tmemaddr, dram)                       \
_DW({                                                                 \
    gDPSetTextureImage(pkt, G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram);    \
    gDPTileSyncInTexLoad(pkt);                                        \
    gDPSetTile(pkt, 0, 0, 0, tmemaddr,                                \
                    _G_PALTMEMTOTILE(tmemaddr), 0, 0, 0, 0, 0, 0, 0); \
    gDPLoadSyncInTexLoad(pkt);                                        \
    gDPLoadTLUTCmd(pkt, _G_PALTMEMTOTILE(tmemaddr), ((count) - 1));   \
    gDPPipeSyncInTexLoad(pkt);                                        \
})

#define gsDPLoadTLUT(count, tmemaddr, dram)                       \
    gsDPSetTextureImage(G_IM_FMT_RGBA, G_IM_SIZ_16b, 1, dram),    \
    gsDPTileSyncInTexLoad                                         \
    gsDPSetTile(0, 0, 0, tmemaddr,                                \
                _G_PALTMEMTOTILE(tmemaddr), 0, 0, 0, 0, 0, 0, 0), \
    gsDPLoadSyncInTexLoad                                         \
    gsDPLoadTLUTCmd(_G_PALTMEMTOTILE(tmemaddr), ((count) - 1))    \
    gsDPPipeSyncEndOfTexLoad



#define gDPSetScissor(pkt, mode, ulx, uly, lrx, lry)                \
_DW({                                                               \
    Gfx *_g = (Gfx *)pkt;                                           \
                                                                    \
    _g->words.w0 = (_SHIFTL(G_SETSCISSOR,               24,  8) |   \
                    _SHIFTL((int)((float)(ulx) * 4.0f), 12, 12) |   \
                    _SHIFTL((int)((float)(uly) * 4.0f),  0, 12));   \
    _g->words.w1 = (_SHIFTL(mode,                       24,  2) |   \
                    _SHIFTL((int)((float)(lrx) * 4.0f), 12, 12) |   \
                    _SHIFTL((int)((float)(lry) * 4.0f),  0, 12));   \
})


#define gDPSetScissorFrac(pkt, mode, ulx, uly, lrx, lry)    \
_DW({                                                       \
    Gfx *_g = (Gfx *)pkt;                                   \
                                                            \
    _g->words.w0 = (_SHIFTL(G_SETSCISSOR, 24,  8) |         \
                    _SHIFTL((int)((ulx)), 12, 12) |         \
                    _SHIFTL((int)((uly)),  0, 12));         \
    _g->words.w1 = (_SHIFTL(mode,         24,  2) |         \
                    _SHIFTL((int)((lrx)), 12, 12) |         \
                    _SHIFTL((int)((lry)),  0, 12));         \
})

#define gsDPSetScissor(mode, ulx, uly, lrx, lry)    \
{                                                   \
   (_SHIFTL(G_SETSCISSOR,               24,  8) |   \
    _SHIFTL((int)((float)(ulx) * 4.0f), 12, 12) |   \
    _SHIFTL((int)((float)(uly) * 4.0f),  0, 12)),   \
   (_SHIFTL(mode,                       24,  2) |   \
    _SHIFTL((int)((float)(lrx) * 4.0f), 12, 12) |   \
    _SHIFTL((int)((float)(lry) * 4.0f),  0, 12))    \
}

#define gsDPSetScissorFrac(mode, ulx, uly, lrx, lry)    \
{                                                       \
   (_SHIFTL(G_SETSCISSOR, 24,  8) |                     \
    _SHIFTL((int)((ulx)), 12, 12) |                     \
    _SHIFTL((int)((uly)),  0, 12)),                     \
   (_SHIFTL(mode,       24,  2) |                       \
    _SHIFTL((int)(lrx), 12, 12) |                       \
    _SHIFTL((int)(lry),  0, 12))                        \
}

/* Fraction never used in fill */
#define gDPFillRectangle(pkt, ulx, uly, lrx, lry)   \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_FILLRECT, 24,  8) |   \
                    _SHIFTL((lrx),      14, 10) |   \
                    _SHIFTL((lry),       2, 10));   \
    _g->words.w1 = (_SHIFTL((ulx), 14, 10) |        \
                    _SHIFTL((uly), 2, 10));         \
})

#define gsDPFillRectangle(ulx, uly, lrx, lry)   \
{                                               \
   (_SHIFTL(G_FILLRECT, 24,  8) |               \
    _SHIFTL((lrx),      14, 10) |               \
    _SHIFTL((lry),       2, 10)),               \
   (_SHIFTL((ulx), 14, 10) |                    \
    _SHIFTL((uly),  2, 10))                     \
}

/* like gDPFillRectangle but accepts negative arguments */
#define gDPScisFillRectangle(pkt, ulx, uly, lrx, lry)   \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
                                                        \
    _g->words.w0 = (_SHIFTL(G_FILLRECT,    24,  8) |    \
                    _SHIFTL(MAX((lrx), 0), 14, 10) |    \
                    _SHIFTL(MAX((lry), 0),  2, 10));    \
    _g->words.w1 = (_SHIFTL(MAX((ulx), 0), 14, 10) |    \
                    _SHIFTL(MAX((uly), 0),  2, 10));    \
})

#define gDPSetConvert(pkt, k0, k1, k2, k3, k4, k5)  \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_SETCONVERT, 24, 8) |  \
                    _SHIFTL(k0,           13, 9) |  \
                    _SHIFTL(k1,            4, 9) |  \
                    _SHIFTR(k2,            5, 4));  \
    _g->words.w1 = (_SHIFTL(k2, 27, 5) |            \
                    _SHIFTL(k3, 18, 9) |            \
                    _SHIFTL(k4,  9, 9) |            \
                    _SHIFTL(k5,  0, 9));            \
})

#define gsDPSetConvert(k0, k1, k2, k3, k4, k5)  \
{                                               \
   (_SHIFTL(G_SETCONVERT, 24, 8) |              \
    _SHIFTL(k0,           13, 9) |              \
    _SHIFTL(k1,            4, 9) |              \
    _SHIFTL(k2,            5, 4)),              \
   (_SHIFTL(k2, 27, 5) |                        \
    _SHIFTL(k3, 18, 9) |                        \
    _SHIFTL(k4,  9, 9) |                        \
    _SHIFTL(k5,  0, 9))                         \
}

#define gDPSetKeyR(pkt, cR, sR, wR)             \
_DW({                                           \
    Gfx *_g = (Gfx *)(pkt);                     \
                                                \
    _g->words.w0 = _SHIFTL(G_SETKEYR, 24, 8);   \
    _g->words.w1 = (_SHIFTL(wR, 16, 12) |       \
                    _SHIFTL(cR,  8,  8) |       \
                    _SHIFTL(sR,  0,  8));       \
})

#define gsDPSetKeyR(cR, sR, wR) \
{                               \
    _SHIFTL(G_SETKEYR, 24, 8),  \
   (_SHIFTL(wR, 16, 12) |       \
    _SHIFTL(cR,  8,  8) |       \
    _SHIFTL(sR,  0,  8))        \
}

#define gDPSetKeyGB(pkt, cG, sG, wG, cB, sB, wB)    \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_SETKEYGB, 24,  8) |   \
                    _SHIFTL(wG,         12, 12) |   \
                    _SHIFTL(wB,          0, 12));   \
    _g->words.w1 = (_SHIFTL(cG, 24, 8) |            \
                    _SHIFTL(sG, 16, 8) |            \
                    _SHIFTL(cB,  8, 8) |            \
                    _SHIFTL(sB,  0, 8));            \
})

#define gsDPSetKeyGB(cG, sG, wG, cB, sB, wB)    \
{                                               \
   (_SHIFTL(G_SETKEYGB, 24,  8) |               \
    _SHIFTL(wG,         12, 12) |               \
    _SHIFTL(wB,          0, 12)),               \
   (_SHIFTL(cG, 24,  8) |                       \
    _SHIFTL(sG, 16,  8) |                       \
    _SHIFTL(cB,  8,  8) |                       \
    _SHIFTL(sB,  0,  8))                        \
}

/**
 * Notice that textured rectangles are 128-bit commands, therefore
 * gsDPTextureRectangle() should not be used in display lists
 * under normal circumstances (use gsSPTextureRectangle()).
 * That is also why there is no gDPTextureRectangle() macros.
 */
#define gsDPTextureRectangle(xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
{                                                                       \
   (_SHIFTL(G_TEXRECT, 24,  8) |                                        \
    _SHIFTL(xh,        12, 12) |                                        \
    _SHIFTL(yh,         0, 12)),                                        \
   (_SHIFTL(tile, 24,  3) |                                             \
    _SHIFTL(xl,   12, 12) |                                             \
    _SHIFTL(yl,    0, 12)),                                             \
},                                                                      \
{                                                                       \
   (_SHIFTL(s, 16, 16) |                                                \
    _SHIFTL(t,  0, 16)),                                                \
   (_SHIFTL(dsdx, 16, 16) |                                             \
    _SHIFTL(dtdy,  0, 16))                                              \
}

/**
 * @copydetails gsDPTextureRectangle
 */
#define gDPTextureRectangle(pkt, xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
_DW({                                                                       \
    Gfx *_g = (Gfx *)(pkt);                                                 \
    if (pkt);                                                               \
    _g->words.w0 = (_SHIFTL(G_TEXRECT, 24,  8) |                            \
                    _SHIFTL(xh,        12, 12) |                            \
                    _SHIFTL(yh,         0, 12));                            \
    _g->words.w1 = (_SHIFTL(tile, 24,  3) |                                 \
                    _SHIFTL(xl,   12, 12) |                                 \
                    _SHIFTL(yl,    0, 12));                                 \
    _g ++;                                                                  \
    _g->words.w0 = (_SHIFTL(s, 16, 16) |                                    \
                    _SHIFTL(t,  0, 16));                                    \
    _g->words.w1 = (_SHIFTL(dsdx, 16, 16) |                                 \
                    _SHIFTL(dtdy,  0, 16));                                 \
})

#define gsDPTextureRectangleFlip(xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
{                                                                           \
   (_SHIFTL(G_TEXRECTFLIP, 24,  8) |                                        \
    _SHIFTL(xh,            12, 12) |                                        \
    _SHIFTL(yh,             0, 12)),                                        \
   (_SHIFTL(tile, 24,  3) |                                                 \
    _SHIFTL(xl,   12, 12) |                                                 \
    _SHIFTL(yl,    0, 12)),                                                 \
},                                                                          \
{                                                                           \
   (_SHIFTL(s, 16, 16) |                                                    \
    _SHIFTL(t,  0, 16)),                                                    \
   (_SHIFTL(dsdx, 16, 16) |                                                 \
    _SHIFTL(dtdy,  0, 16))                                                  \
}

#define gDPTextureRectangleFlip(pkt, xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
_DW({                                                                           \
    Gfx *_g = (Gfx *)(pkt);                                                     \
    if (pkt);                                                                   \
    _g->words.w0 = (_SHIFTL(G_TEXRECTFLIP, 24,  8) |                            \
                    _SHIFTL(xh,            12, 12) |                            \
                    _SHIFTL(yh,             0, 12));                            \
    _g->words.w1 = (_SHIFTL(tile, 24,  3) |                                     \
                    _SHIFTL(xl,   12, 12) |                                     \
                    _SHIFTL(yl,    0, 12));                                     \
    _g ++;                                                                      \
    _g->words.w0 = (_SHIFTL(s, 16, 16) |                                        \
                    _SHIFTL(t,  0, 16));                                        \
    _g->words.w1 = (_SHIFTL(dsdx, 16, 16) |                                     \
                    _SHIFTL(dtdy,  0, 16));                                     \
})

#define gsSPTextureRectangle(xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
   (_SHIFTL(G_TEXRECT, 24,  8) |                                        \
    _SHIFTL(xh,        12, 12) |                                        \
    _SHIFTL(yh,         0, 12)),                                        \
   (_SHIFTL(tile, 24,  3) |                                             \
    _SHIFTL(xl,   12, 12) |                                             \
    _SHIFTL(yl,    0, 12)),                                             \
   gsImmp1(G_RDPHALF_1,                                                 \
       (_SHIFTL(s, 16, 16) |                                            \
        _SHIFTL(t,  0, 16))),                                           \
   gsImmp1(G_RDPHALF_2,                                                 \
       (_SHIFTL(dsdx, 16, 16) |                                         \
        _SHIFTL(dtdy,  0, 16)))

#define gSPTextureRectangle(pkt, xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
_DW({                                                                       \
    Gfx *_g = (Gfx *)(pkt);                                                 \
                                                                            \
    _g->words.w0 = (_SHIFTL(G_TEXRECT, 24,  8) |                            \
                    _SHIFTL(xh,        12, 12) |                            \
                    _SHIFTL(yh,         0, 12));                            \
    _g->words.w1 = (_SHIFTL(tile, 24,  3) |                                 \
                    _SHIFTL(xl,   12, 12) |                                 \
                    _SHIFTL(yl,    0, 12));                                 \
   gImmp1(pkt, G_RDPHALF_1,                                                 \
       (_SHIFTL(s, 16, 16) |                                                \
        _SHIFTL(t,  0, 16)));                                               \
   gImmp1(pkt, G_RDPHALF_2,                                                 \
       (_SHIFTL(dsdx, 16, 16) |                                             \
        _SHIFTL(dtdy,  0, 16)));                                            \
})

/* like gSPTextureRectangle but accepts negative position arguments */
#define gSPScisTextureRectangle(pkt, xl, yl, xh, yh, tile, s, t, dsdx, dtdy)        \
_DW({                                                                               \
    Gfx *_g = (Gfx *)(pkt);                                                         \
                                                                                    \
    _g->words.w0 = (_SHIFTL(G_TEXRECT,        24,  8) |                             \
                    _SHIFTL(MAX((s16)(xh),0), 12, 12) |                             \
                    _SHIFTL(MAX((s16)(yh),0),  0, 12));                             \
    _g->words.w1 = (_SHIFTL((tile),           24,  3) |                             \
                    _SHIFTL(MAX((s16)(xl),0), 12, 12) |                             \
                    _SHIFTL(MAX((s16)(yl),0),  0, 12));                             \
   gImmp1(pkt, G_RDPHALF_1,                                                         \
       (_SHIFTL(((s) -                                                              \
                   (((s16)(xl)   < 0) ?                                             \
                   (((s16)(dsdx) < 0) ?                                             \
                    (MAX((((s16)(xl) * (s16)(dsdx)) >> 7), 0))  :                   \
                    (MIN((((s16)(xl) * (s16)(dsdx)) >> 7), 0))) : 0)), 16, 16) |    \
        _SHIFTL(((t) -                                                              \
                   ((     (yl)   < 0) ?                                             \
                   (((s16)(dtdy) < 0) ?                                             \
                    (MAX((((s16)(yl) * (s16)(dtdy)) >> 7), 0))  :                   \
                    (MIN((((s16)(yl) * (s16)(dtdy)) >> 7), 0))) : 0)),  0, 16)));   \
   gImmp1(pkt, G_RDPHALF_2,                                                         \
       (_SHIFTL((dsdx), 16, 16) |                                                   \
        _SHIFTL((dtdy),  0, 16)));                                                  \
})

#define gsSPTextureRectangleFlip(xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
   (_SHIFTL(G_TEXRECTFLIP, 24,  8) |                                        \
    _SHIFTL(xh,            12, 12) |                                        \
    _SHIFTL(yh,             0, 12)),                                        \
   (_SHIFTL(tile, 24,  3) |                                                 \
    _SHIFTL(xl,   12, 12) |                                                 \
    _SHIFTL(yl,    0, 12)),                                                 \
   gsImmp1(G_RDPHALF_1,                                                     \
       (_SHIFTL(s, 16, 16) |                                                \
        _SHIFTL(t,  0, 16))),                                               \
   gsImmp1(G_RDPHALF_2,                                                     \
       (_SHIFTL(dsdx, 16, 16) |                                             \
        _SHIFTL(dtdy,  0, 16)))

#define gSPTextureRectangleFlip(pkt, xl, yl, xh, yh, tile, s, t, dsdx, dtdy)    \
_DW({                                                                           \
    Gfx *_g = (Gfx *)(pkt);                                                     \
                                                                                \
    _g->words.w0 = (_SHIFTL(G_TEXRECTFLIP, 24,  8) |                            \
                    _SHIFTL(xh,            12, 12) |                            \
                    _SHIFTL(yh,             0, 12));                            \
    _g->words.w1 = (_SHIFTL(tile, 24,  3) |                                     \
                    _SHIFTL(xl,   12, 12) |                                     \
                    _SHIFTL(yl,    0, 12));                                     \
   gImmp1(pkt, G_RDPHALF_1,                                                     \
       (_SHIFTL(s, 16, 16) |                                                    \
        _SHIFTL(t,  0, 16)));                                                   \
   gImmp1(pkt, G_RDPHALF_2,                                                     \
       (_SHIFTL(dsdx, 16, 16) |                                                 \
        _SHIFTL(dtdy,  0, 16)));                                                \
})

#define gsDPWord(wordhi, wordlo)                    \
    gsImmp1(G_RDPHALF_1, (unsigned int)(wordhi)),   \
    gsImmp1(G_RDPHALF_2, (unsigned int)(wordlo))

#define gDPWord(pkt, wordhi, wordlo)                    \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
    gImmp1(pkt, G_RDPHALF_1, (unsigned int)(wordhi));   \
    gImmp1(pkt, G_RDPHALF_2, (unsigned int)(wordlo));   \
})

#ifdef RISKY_RDP_SYNCS
/*
 * The community has found that in nearly all instances, a tile sync is
 * sufficient where a pipe sync is normally used--between rendering something
 * and changing critical RDP settings. However, we are not 100% sure this is
 * true for all obscure settings, so it is risky.
*/
#define G_USEASPIPESYNC G_RDPTILESYNC
#else
#define G_USEASPIPESYNC G_RDPPIPESYNC
#endif

#define gDPFullSync(pkt)        gDPNoParam(pkt, G_RDPFULLSYNC)
#define gsDPFullSync()          gsDPNoParam(    G_RDPFULLSYNC)
#define gDPTileSync(pkt)        gDPNoParam(pkt, G_RDPTILESYNC)
#define gsDPTileSync()          gsDPNoParam(    G_RDPTILESYNC)
#define gDPPipeSync(pkt)        gDPNoParam(pkt, G_USEASPIPESYNC)
#define gsDPPipeSync()          gsDPNoParam(    G_USEASPIPESYNC)
#define gDPLoadSync(pkt)        gDPNoParam(pkt, G_RDPLOADSYNC)
#define gsDPLoadSync()          gsDPNoParam(    G_RDPLOADSYNC)
#define gDPNoOp(pkt)            gDPNoParam(pkt, G_NOOP)
#define gsDPNoOp()              gsDPNoParam(    G_NOOP)
#define gDPNoOpTag(pkt, tag)    gDPParam(pkt,   G_NOOP, tag)
#define gsDPNoOpTag(tag)        gsDPParam(      G_NOOP, tag)

#define gDPNoOpHere(pkt, file, line)        gDma1p(pkt, G_NOOP, file, line, 1)
#define gDPNoOpString(pkt, data, n)         gDma1p(pkt, G_NOOP, data, n, 2)
#define gDPNoOpWord(pkt, data, n)           gDma1p(pkt, G_NOOP, data, n, 3)
#define gDPNoOpFloat(pkt, data, n)          gDma1p(pkt, G_NOOP, data, n, 4)
#define gDPNoOpQuiet(pkt)                   gDma1p(pkt, G_NOOP, 0, 0, 5)
#define gDPNoOpVerbose(pkt, n)              gDma1p(pkt, G_NOOP, 0, n, 5)
#define gDPNoOpCallBack(pkt, callback, arg) gDma1p(pkt, G_NOOP, callback, arg, 6)
#define gDPNoOpOpenDisp(pkt, file, line)    gDma1p(pkt, G_NOOP, file, line, 7)
#define gDPNoOpCloseDisp(pkt, file, line)   gDma1p(pkt, G_NOOP, file, line, 8)
#define gDPNoOpTag3(pkt, type, data, n)     gDma1p(pkt, G_NOOP, data, n, type)

#endif // GBI_MACRO_RDP_H
