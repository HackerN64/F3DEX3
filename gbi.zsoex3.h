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
 *                       // shareable between vertices, a ZSOSection, DL
 *                       // snippets, and matrices
 * ```
*/
typedef struct {
    u16 argsAddress;
    u16 cacheSize;
} UcodeBuildInfo;

/**
 * The size in bytes of each vertex after being loaded into the cache. Vertices
 * are numbered starting from the bottom of the cache. Use this together with
 * cacheSize to compute cache addresses for a ZSOSection or DL snippets.
*/
#define G_CACHE_VTX_SIZE 0x14

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
    void* debugBuffer;
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
    uint32_t a, b, c, d, e, endTime;
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
#define G_MV_CACHEEND    0
#define G_MV_VIEWPORT    2
#define G_MV_LIGHTCOLORS 4

/*
 * MOVEWORD indices
 * Each of these indexes an entry in a dmem table which points to a word in dmem
 * where an immediate word will be stored.
 */
#define G_MW_FX        0
#define G_MW_SEGMENT   2

/* MOVEWORD offsets */
#define G_MWO_ASO_SCALE          0x00
#define G_MWO_ASO_COLOR_OFFSET   0x02
#define G_MWO_ASO_ALPHA_OFFSET   0x03
#define G_MWO_PERSPNORM          0x04
#define G_MWO_GEOM_MODE          0x06

#define gSPLoadGeometryMode(pkt, halfword) \
    gMoveHalfwd(pkt, G_MW_FX, G_MWO_GEOM_MODE, halfword)
#define gsSPLoadGeometryMode(halfword) \
    gsMoveHalfwd(G_MW_FX, G_MWO_GEOM_MODE, halfword)

/**
 * Attribute Stepper Overflow cel shading.
 * 
 * Modifies shade color and shade alpha coefficients sent to the RDP so that the
 * attribute stepper--the hardware unit in the RDP which increments color,
 * texture, and Z values during rasterization--overflows within the triangle.
 * The shade color and shade alpha values are close to zero in the dark part
 * of the triangle, and close to 0xFF in the light portion. The line between
 * these, where the overflow occurs, forms the cel shading threshold.
 * 
 * Shade color (RGB all together) and shade alpha are set up to overflow at
 * different thresholds, thus creating three differently shaded regions. Use the
 * 1-cycle CC to apply the shade color threshold and the 1-cycle blender to
 * apply the shade alpha threshold.
 * 
 * Set color and alpha to the darker and lighter lighting thresholds to use
 * respectively, e.g. 0x40 and 0xD0.
*/
#define gSPASOCelEnable(pkt, color, alpha) \
    gMoveWd(pkt, G_MW_FX, G_MWO_ASO_SCALE, _SPASOCelEnable(color, alpha))
#define gsSPASOCelEnable(color, alpha) \
    gsMoveWd(G_MW_FX, G_MWO_ASO_SCALE, _SPASOCelEnable(color, alpha))
#define gSPASOCelDisable(pkt) \
    gMoveWd(pkt, G_MW_FX, G_MWO_ASO_SCALE, G_ASO_CEL_SCALE_DISABLE << 16)
#define gsSPASOCelDisable() \
    gsMoveWd(G_MW_FX, G_MWO_ASO_SCALE, G_ASO_CEL_SCALE_DISABLE << 16)

#define G_ASO_CEL_SCALE_DISABLE 0x0100
#define G_ASO_CEL_SCALE_ENABLE  0xFF80

#define _SPASOCelEnable(color, alpha) \
    _SHIFTL(G_ASO_CEL_SCALE_ENABLE,    16, 16) | \
    _SHIFTL(((0x100 - (color)) >> 1),  8,  8) | \
    _SHIFTL(((0x100 - (alpha)) >> 1),  0,  8)

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
 * A ZSOSection is a u8 array of 33 or more bytes. Make sure it is declared
 * as __attribute__((aligned(8))) in your object file, or 16 if it will be
 * modified by the CPU.
 * 
 * At byte 0, the offsets start. There are up to 32 of these, one per
 * subsection. This is the offset from the start of the ZSOSection for this
 * subsection's data. It is shifted left by offs_shift and then added to the
 * address of the beginning of the ZSOSection. In other words, if offs_shift is
 * 0, the offsets address up to 256 bytes; if it is 1, they address up to 512
 * bytes but sections have to start on an even byte; and so on.
 * 
 * At byte 32, the reference vertex indices start. There are up to 32 of these,
 * one per subsection. These identify which vertex to load the Z value of, to
 * sort the subsections.
 * 
 * At byte N, where N is the offset of a particular subsection as calculated
 * above, is 1 byte of metadata about the subsection. Its lower 7 bits are the
 * triangle count in this subsection. Its upper bit is: 0 = 3 indices per
 * triangle, 1 = 1 index per triangle as a tri strip. In the latter case it
 * draws indices 0-1-2 flipped, 1-2-3, 2-3-4 flipped, 3-4-5, etc.
 *
 * Starting at byte N+1 are the triangle indices for this subsection. There are
 * 3 * (metadata & 0x7F) indices if !(metadata & 0x80), else there are 2 +
 * (metadata & 0x7F) indices.
 * 
 * This is organized in this strange way rather than using a typical struct
 * layout in order to promote packing. If there are fewer subsections, triangle
 * data can be placed in the upper bytes of the offsets. For example, a
 * ZSOSection containing just one subsection can be 33 bytes and contain 28
 * triangles: byte 0 is the offset 1, byte 1 is the metadata 0x9C (tri strip +
 * 28 tris), bytes 2 through 31 are the indices, and byte 33 is the reference
 * vertex index.
 */
typedef unsigned char ZSOSection;

#define G_ZSOSECTION_MAX_SIZE 0x180

#define _ZSOSECTION_DMA_LEN(sz) ((((sz) + 7) & 0x1F8) - 1)

#define _SPZSOSectionW0(sz, cache, nss, offs_shift) ( \
    _SHIFTL(G_ZSOSECTION,          24,  8) |          \
    _SHIFTL(offs_shift,            22,  2) |          \
    _SHIFTL((nss) - 1,             17,  5) |          \
    _SHIFTL(0 /* DMA to DMEM */,   16,  1) |          \
    _SHIFTL((cache) >> 3,           7,  9) |          \
    _SHIFTL((((sz) + 7) >> 3) - 1,  0,  7) )

/**
 * Upload, Z-sort, and draw the triangles of a section. @see ZSOSection
 * @p addr Segmented (RDRAM) address of a ZSOSection. Must be a multiple of 8.
 * @p sz Size in bytes of the ZSOSection. Does not have to be a multiple of 8,
 *    but will be rounded up to the next multiple of 8.
 * @p cache Cache address to upload the ZSOSection to. In bytes relative to the
 *    start of the cache. Must be a multiple of 8.
 * @p nss Number of subsections
 * @p offs_shift Left shift offset values by this many bits before adding them
 *    to the base address. If the ZSOSection is <= 256 bytes, set this to 0, and
 *    the offsets will be byte offsets. If it is between 257 and 512 bytes, set
 *    this to 1 and sections can start every other byte. Etc.
*/
#define gSPZSOSection(pkt, addr, sz, cache, nss, offs_shift)    \
_DW({                                                           \
    Gfx *_g = (Gfx *)(pkt);                                     \
    _g->words.w0 = _SPZSOSectionW0(sz, cache, nss, offs_shift); \
    _g->words.w1 = (unsigned int)(addr);                      \
})
/** @copydetails gSPZSOSection */
#define gsSPZSOSection(addr, sz, cache, nss, offs_shift) \
{                                                        \
    _SPZSOSectionW0(sz, cache, nss, offs_shift),         \
    (unsigned int)(addr)                                 \
}

#endif // ZSOEX3_H
