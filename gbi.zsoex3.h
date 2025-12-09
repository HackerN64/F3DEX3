/**
 * @file gbi.zsoex3.h
 * @brief Mostly custom GBI for use with ZSOEX3 custom microcode
 */

#ifndef ZSOEX3_H
#define ZSOEX3_H

/* List of options; the documentation for each is where it is used below. */
/* #define REQUIRE_SEMICOLONS_AFTER_GBI_COMMANDS */ /* recommended */
/* #define NO_SYNCS_IN_TEXTURE_LOADS */ /* see documentation */
/* #define F3DEX2_SEGMENTS */ /* see documentation */
/* #define DISABLE_AA */ /* developer taste */
/* #define RISKY_RDP_SYNCS */ /* see documentation */
/* #define KAZE_GBI_HACKS */ /* not recommended unless you are Kaze */

/* For definitions of u8, s16, etc., and _SHIFTL */
#include "ultra64/mbi.h"

/* Many of the components of the GBI have been split out into these individual
files, to reduce clutter and for reuse between microcodes. */
#include "gbi/rdp_defines.h"
#include "gbi/rsp_structs.h"
#include "gbi/gfx_modern.h"
#include "gbi/macro_base.h"
#include "gbi/macro_rdp.h"
#include "gbi/rsp_common.h"

/**
 * Extract these parameters from the start of the microcode data segment (in
 * RDRAM, not from the version in DMEM).
 * ```
 * UcodeBuildInfo build_info = *(const UcodeBuildInfo*)gspZSOEX3DataStart;
 * build_info.argsAddress; // Offset into DMEM to write args, @see UcodeArgs
 * build_info.cacheSize; // Size in bytes of the "cache", the DMEM region
 *                       // shareable between vertices, DL snippets, and matrices
 * ```
*/
typedef struct {
    u16 argsAddress;
    u16 cacheSize;
} UcodeBuildInfo;

/**
 * To launch the microcode:
 * - Copy the first 0x1000 bytes of the text segment to IMEM (starting at 0)
 * - Copy the data segment to DMEM (starting at 0)
 * - Write the ucode args directly to DMEM:
 * ```
 * volatile UcodeArgs* args = (volatile UcodeArgs*)(0xA4000000 + build_info.argsAddress);
 * args->ucodeTextStart = gspZSOEX3TextStart;
 * args->displayListStart = ...;
 * args->rdpFifoStart = ...;
 * args->rdpFifoEnd = ...;
 * ```
 * - Set the RSP PC to 0x1000 (start of IMEM) and unhalt it
*/
typedef struct {
    const void* ucodeTextStart;
    const void* displayListStart;
    void* rdpFifoStart;
    void* rdpFifoEnd;
} UcodeArgs;

/**
 * The microcode stores the performance counters in DMEM at argsAddress when it's done.
 * ```
 * volatile UcodePerfCounters* counters = (volatile UcodePerfCounters*)(0xA4000000 + build_info.argsAddress);
 * ... = counters->a;
 * ...
 * ```
*/
typedef struct {
    uint32_t a, b, c, d;
} UcodePerfCounters;

#define ZSOEX_GBI_1 1

/*
 * GBI commands in order
 */
#define G_FLUSH             0xDC
#define G_GEOMETRYMODE      0xDD
#define G_DL                0xDE
#define G_ENDDL             0xDF
#define G_SPNOOP            0xE0
#define G_MOVEWORD          0xE1
#define G_MOVEMEM           0xE2
#define G_RDPHALF_1         0xE3
/* RDP commands go here */
#define G_RELSEGMENT        0x01
#define G_VTX               0x02
#define G_TRI1              0x03
#define G_TRI2              0x04

/*
 * RSP command argument and misc defines
 */

/* Maximum number of display list commands loaded at once into RSP DMEM */
#define G_INPUT_BUFFER_CMDS 21


/*
 * flags for G_SETGEOMETRYMODE
 */
#define G_TEXTURE_ENABLE        0x00000002
#define G_SHADE                 0x00000004
#define G_AMBOCCLUSION          0x00000100  /* ignored, always on */
#define G_CULL_NEITHER          0x00000000
#define G_CULL_FRONT            0x00000200
#define G_CULL_BACK             0x00000400
#define G_CULL_BOTH             0x00000600  /* useless but supported */
#define G_LIGHTTOALPHA          0x00001000  /* ignored, always on */
#define G_LIGHTING              0x00020000  /* ignored, always on */
#define G_TEXTURE_GEN           0x00040000
#define G_TEXTURE_GEN_LINEAR    0x00080000
#define G_SHADING_SMOOTH        0x00200000  /* ignored, always on */

/*
 * MOVEMEM indices
 * Each of these indexes an entry in a dmem table which points to an arbitrarily
 * sized block of dmem in which to store the result of a DMA.
 */
#define G_MV_TRISTATE    0
#define G_MV_CACHEEND    2
#define G_MV_VIEWPORT    4
#define G_MV_LIGHTCOLORS 6

/*
 * MOVEWORD indices
 * Each of these indexes an entry in a dmem table which points to a word in dmem
 * where an immediate word will be stored.
 */
#define G_MW_FX        0
#define G_MW_SEGMENT   2

/* MOVEWORD offsets */
#define G_MWO_ALPHA_COMPARE_CULL 0x04
#define G_MWO_PERSPNORM          0x06

/**
 * Holds the MVP matrix and up to two light directions. Each light direction
 * must be in model space, i.e. world space dir transformed by M transpose.
*/
typedef struct {
    Mtx mtx;
    struct {
        signed char dir[3];
        char pad1;
        signed char dirc[3];
        char pad2;
    } lt[2];
} MtxAndLtDirs;

/**
 * Upload a MtxAndLtDirs struct to the specified matrix index. Matrices start
 * at the top of the cache and grow downwards. So for example, idx = 0 starts at
 * cacheEnd - 0x50, idx = 1 starts at cacheEnd - 0xA0, etc. You can trade off
 * how much cache space to spend on cached vertices, display lists, and
 * matrices.
*/
#define gSPMtxAndLtDirs(pkt, addr, idx) \
    gDma2p((pkt), G_MOVEMEM, (addr), sizeof(MtxAndLtDirs), G_MV_CACHEEND, \
        (-(sizeof(MtxAndLtDirs) * ((idx) + 1))))
#define gsSPMtxAndLtDirs(addr, idx) \
    gsDma2p(      G_MOVEMEM, (addr), sizeof(MtxAndLtDirs), G_MV_CACHEEND, \
        (-(sizeof(MtxAndLtDirs) * ((idx) + 1))))

/** For now this is the same as F3D family, will change later */
#define gSPVertex(pkt, v, n, v0)                    \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_VTX,      24, 8) |    \
                    _SHIFTL((n),        12, 8) |    \
                    _SHIFTL((v0) + (n),  1, 7));    \
    _g->words.w1 = (unsigned int)(v);               \
})
#define gsSPVertex(v, n, v0)        \
{                                   \
   (_SHIFTL(G_VTX,      24, 8) |    \
    _SHIFTL((n),        12, 8) |    \
    _SHIFTL((v0) + (n),  1, 7)),    \
    (unsigned int)(v)               \
}

/** For now this is the same as F3D family except without flag, will change later */
#define __gsSP1Triangle_w1(v0, v1, v2)    \
   (_SHIFTL((v0) * 2, 16, 8) |              \
    _SHIFTL((v1) * 2,  8, 8) |              \
    _SHIFTL((v2) * 2,  0, 8))


/**
 * 1 Triangle
 */
#define gSP1Triangle(pkt, v0, v1, v2) \
    g1Word(pkt, G_TRI1, __gsSP1Triangle_w1(v0, v1, v2))
/**
 * @copydetails gSP1Triangle
 */
#define gsSP1Triangle(v0, v1, v2)     \
    gs1Word(G_TRI1, __gsSP1Triangle_w1(v0, v1, v2))

/**
 * 2 Triangles
 */
#define gSP2Triangles(pkt, v00, v01, v02, v10, v11, v12)  \
_DW({                                                     \
    Gfx *_g = (Gfx *)(pkt);                               \
    _g->words.w0 = (_SHIFTL(G_TRI2, 24, 8) |              \
                    __gsSP1Triangle_w1(v00, v01, v02));   \
    _g->words.w1 =  __gsSP1Triangle_w1(v10, v11, v12);    \
})

/**
 * @copydetails gSP2Triangles
 */
#define gsSP2Triangles(v00, v01, v02, v10, v11, v12)  \
{                                                     \
   (_SHIFTL(G_TRI2, 24, 8) |                          \
    __gsSP1Triangle_w1(v00, v01, v02)),               \
    __gsSP1Triangle_w1(v10, v11, v12)                 \
}


#endif // ZSOEX3_H
