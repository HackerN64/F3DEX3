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

#define ZSOEX_GBI_1 1

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
typedef __attribute__((aligned(8))) struct {
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
typedef __attribute__((aligned(8))) struct {
    uint32_t a, b, c, d;
} UcodePerfCounters;

/*
 * GBI commands in order
 */
#define G_FLUSH             0xDD
#define G_DL                0xDE
#define G_ENDDL             0xDF
#define G_SPNOOP            0xE0
#define G_MOVEWORD          0xE1
#define G_MOVEMEM           0xE2
#define G_RDPHALF_1         0xE3
/* RDP commands go here */
#define G_RELSEGMENT        0x01
#define G_VTX               0x02
#define G_ZSOSECTION        0x03

/*
 * RSP command argument and misc defines
 */

/* Maximum number of display list commands loaded at once into RSP DMEM */
#define G_INPUT_BUFFER_CMDS 21


/*
 * flags for SPLoadGeometryMode
 */
#define G_TEXTURE_ENABLE        0x0002
#define G_SHADE                 0x0004
#define G_TEXTURE_GEN           0x2000
#define G_TEXTURE_GEN_LINEAR    0x4000
#define G_FACING_INVERT         0x8000

/*
 * MOVEMEM indices
 * Each of these indexes an entry in a dmem table which points to an arbitrarily
 * sized block of dmem in which to store the result of a DMA.
 */
#define G_MV_ZSOSECTION  0
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
#define G_MWO_GEOM_MODE          0x00
#define G_MWO_ALPHA_COMPARE_CULL 0x02
#define G_MWO_PERSPNORM          0x04

#define gSPLoadGeometryMode(pkt, halfword) \
    gMoveHalfwd(pkt, G_MW_FX, G_MWO_GEOM_MODE, halfword)
#define gsSPLoadGeometryMode(halfword) \
    gsMoveHalfwd(G_MW_FX, G_MWO_GEOM_MODE, halfword)

/**
 * Holds the MVP matrix and up to two light directions. Each light direction
 * must be in model space, i.e. world space dir transformed by M transpose.
*/
typedef __attribute__((aligned(8))) struct {
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

/**
 * Upload and perform transform and lighting on vertices.
 * @p addr Segmented address of some Vtx's
 * @p n Number of vertices to upload
 * @p v0 Vertex index in the cache to start overwriting
 * @p mtx1 Matrix index used for vertex weights of 0
 * @p mtx2 Matrix index used for vertex weights of FFFF
*/
#define gSPVertex(pkt, addr, n, v0, mtx1, mtx2)     \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
    _g->words.w0 = (_SHIFTL(G_VTX,      24, 8) |    \
                    _SHIFTL((mtx1),     20, 4) |    \
                    _SHIFTL((mtx2),     16, 4) |    \
                    _SHIFTL((n),         8, 8) |    \
                    _SHIFTL((v0) + (n),  0, 8));    \
    _g->words.w1 = (unsigned int)(addr);            \
})
/** @copydetails gSPVertex */
#define gsSPVertex(addr, n, v0, mtx1, mtx2) \
{                                           \
   (_SHIFTL(G_VTX,      24, 8) |            \
    _SHIFTL((mtx1),     20, 4) |            \
    _SHIFTL((mtx2),     16, 4) |            \
    _SHIFTL((n),         8, 8) |            \
    _SHIFTL((v0) + (n),  0, 8)),            \
    (unsigned int)(addr)                    \
}

/**
 * Defines a Z-sorting "section". All geometry (scene, objects, etc.) is
 * comprised of sections; the sections are Z-sorted on the CPU. Then each
 * section is comprised of sub-sections, which are sorted on the RSP by ZSOEX3.
 * Finally, each subsection contains one or more triangles, which are drawn in
 * an arbitrary order.
 * 
 * Formally, each section must have a convex hull which is non-overlapping in
 * volume (they may share points, lines, or planes) with any other section's
 * convex hull. And, every subsection must have a convex hull which is non-
 * overlapping with any other subsection's convex hull from the same section.
 * Finally, the tris of each subsection must be all convex or all concave, or
 * close enough to one of these that drawing the tris in an arbitrary order
 * works regardless of the camera angle.
 * 
 * There is an additional constraint: subsections are sorted based on the Z
 * value of a single reference vertex from each. Practically, this means that
 * tris must be roughly the same size, or that large tris must be roughly at
 * least their size away from small tris.
 * 
 * Practically, sections are defined by material boundaries, vertex cache
 * capacity, and what the game guarantees no other objects will intersect. For
 * example, a character's upper arm and lower arm could be the same section
 * (if they use the same material), in an RPG where nothing will ever be drawn
 * in the space between the two when the arm is folded. But in a fighting game,
 * when limbs of another character could be there, it would have to be one
 * section per bone.
 * 
 * A ZSOSection is a u8 array of length 33-256 bytes. Make sure it is declared
 * as __attribute__((aligned(8))) in your object file, or 16 if it will be
 * modified by the CPU.
 * 
 * At byte 0, the reference vertex indices start. There are up to 32 of these,
 * one per subsection. These identify which vertex to load the Z value of, to
 * sort the subsections.
 * 
 * At byte 32, the offsets start. There are up to 32 of these, one per
 * subsection. This is the offset in bytes from the start of the ZSOSection
 * for this subsection's data.
 * 
 * At byte N, where N is the offset of a particular subsection, is 1 byte of
 * metadata about the subsection. Its lower 7 bits are the triangle count in
 * this subsection. Its upper bit is: 0 = 3 indices per triangle, 1 = 1 index
 * per triangle as a tri strip. In the latter case it draws indices 0-1-2, 1-2-3
 * flipped, 2-3-4, 3-4-5 flipped, etc.
 *
 * Starting at byte N+1 are the triangle indices for this subsection. There are
 * 3 * (metadata & 0x7F) indices if !(metadata & 0x80), else there are 2 +
 * (metadata & 0x7F) indices.
 * 
 * This is organized in this strange way rather than using a typical struct
 * layout in order to promote packing. If there are fewer subsections, triangle
 * data can be placed in the upper bytes of the reference indices. For example,
 * a ZSOSection containing just one subsection can be 33 bytes and contain
 * 28 triangles: byte 0 is the reference vertex index, byte 1 is the metadata
 * 0x9C (tri strip + 28 tris), bytes 2 through 31 are the indices, and byte 33
 * is the offset 1.
 */
typedef unsigned char ZSOSection;

#define G_ZSOSECTION_MAX_SIZE 256

#define _ZSOSECTION_DMA_LEN(sz) ((((sz) + 7) & 0xF8) - 1)

/**
 * Upload, Z-sort, and draw the triangles of a section.
 * @p addr Segmented address of a ZSOSection
 * @p nss Number of subsections
 * @p sz Size in bytes of the ZSOSection
*/
#define gSPZSOSection(pkt, addr, nss, sz)                    \
_DW({                                                        \
    Gfx *_g = (Gfx *)(pkt);                                  \
    _g->words.w0 = (_SHIFTL(G_ZSOSECTION,           24, 8) | \
                    _SHIFTL((nss),                  16, 8) | \
                    _SHIFTL(_ZSOSECTION_DMA_LEN(sz), 0, 8)); \
    _g->words.w1 = (unsigned int)(addr);                     \
})
/** @copydetails gSPZSOSection */
#define gsSPZSOSection(addr, nss, sz)        \
{                                            \
   (_SHIFTL(G_ZSOSECTION,           24, 8) | \
    _SHIFTL((nss),                  16, 8) | \
    _SHIFTL(_ZSOSECTION_DMA_LEN(sz), 0, 8)), \
    (unsigned int)(addr)                     \
}


#endif // ZSOEX3_H
