/**
 * @file gbi.f3dex3.h
 * @brief Modded GBI for use with F3DEX3 custom microcode
 */

#ifndef F3DEX3_H
#define F3DEX3_H

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
#include "gbi/gfx_legacy.h" /* Recommend gfx_modern.h instead */
#include "gbi/light_defs.h"
#include "gbi/macro_base.h"
#include "gbi/macro_rdp.h"
#include "gbi/rsp_common.h"

/* Don't remove this line which defines F3DEX3 as F3DEX2. Other headers in your
romhack codebase will likely assume that if the microcode is not F3DEX2, it is
F3DEX1 or older, thus breaking F3DEX3 compatibility even more. */
#define F3DEX_GBI_2  1
#define F3DEX_GBI_PL 1
#define F3DEX_GBI_3  1

/* This is only included to check correctness of OS_YIELD_DATA_SIZE. If you are
sure this is correct in your project, you can remove this include. */
#include "ultra64/sptask.h"
#if OS_YIELD_DATA_SIZE != 0xC00
#error "F3DEX3 requires OS_YIELD_DATA_SIZE == 0xC00"
#endif

/*
 * GBI commands in order
 */
/*#define G_SPECIAL_3       0xD3  no-op in F3DEX2 */
/*#define G_SPECIAL_2       0xD4  no-op in F3DEX2 */
#define G_FLUSH             0xD4
/*#define G_SPECIAL_1       0xD5  triggered MVP recalculation in F3DEX2 for debug */
#define G_MEMSET            0xD5
#define G_DMA_IO            0xD6
#define G_TEXTURE           0xD7
#define G_POPMTX            0xD8
#define G_GEOMETRYMODE      0xD9
#define G_MTX               0xDA
#define G_MOVEWORD          0xDB
#define G_MOVEMEM           0xDC
#define G_LOAD_UCODE        0xDD
#define G_DL                0xDE
#define G_ENDDL             0xDF
#define G_SPNOOP            0xE0
#define G_RDPHALF_1         0xE1
#define G_SETOTHERMODE_L    0xE2
#define G_SETOTHERMODE_H    0xE3
/* RDP commands go here */
#define G_VTX               0x01
#define G_MODIFYVTX         0x02
#define G_CULLDL            0x03
#define G_BRANCH_WZ         0x04
#define G_TRI1              0x05
#define G_TRI2              0x06
#define G_QUAD              0x07
/*#define G_LINE3D          0x08  no-op in F3DEX2 */
#define G_TRISNAKE          0x08  /* used to be G_TRISTRIP */
/* no command for           0x09     used to be G_TRIFAN */
#define G_LIGHTTORDP        0x0A
#define G_RELSEGMENT        0x0B

/* names differ between F3DEX2 and F3DZEX */
#define G_BRANCH_Z G_BRANCH_WZ
#define G_BRANCH_W G_BRANCH_WZ

/*
 * RSP command argument and misc defines
 */

/* Maximum number of transformed vertices kept in buffer in RSP DMEM */
#define G_MAX_VERTS 56

/* Maximum number of directional / point lights, not counting ambient */
#define G_MAX_LIGHTS 9

/* Maximum number of display list commands loaded at once into RSP DMEM */
#define G_INPUT_BUFFER_CMDS 21

/*
 * flags for G_SETGEOMETRYMODE
 *
 * Note that flat shading, i.e. not G_SHADING_SMOOTH, sets shade RGB for all
 * three verts to the value of the first vertex in the triangle. Shade alpha is
 * still separate for each vertex, which is desired behavior for fog but not for
 * any other F3DEX3 effects which use shade alpha.
 */
#define G_ZBUFFER               0x00000001
#define G_TEXTURE_ENABLE        0x00000000  /* actually 2, but controlled by SPTexture */
#define G_SHADE                 0x00000004
#define G_ATTROFFSET_ST_ENABLE  0x00000080
#define G_AMBOCCLUSION          0x00000100
#define G_CULL_NEITHER          0x00000000
#define G_CULL_FRONT            0x00000200
#define G_CULL_BACK             0x00000400
#define G_CULL_BOTH             0x00000600  /* useless but supported */
#define G_PACKED_NORMALS        0x00000800
#define G_LIGHTTOALPHA          0x00001000
#define G_LIGHTING_SPECULAR     0x00002000
#define G_FRESNEL_COLOR         0x00004000
#define G_FRESNEL_ALPHA         0x00008000
#define G_FOG                   0x00010000
#define G_LIGHTING              0x00020000
#define G_TEXTURE_GEN           0x00040000
#define G_TEXTURE_GEN_LINEAR    0x00080000
#define G_LOD                   0x00100000  /* Ignored by all F3DEX* variants */
#define G_SHADING_SMOOTH        0x00200000
#define G_LIGHTING_POSITIONAL   0x00400000  /* In F3DEX3, replaced by ENABLE_POINT_LIGHTS */
#define G_CLIPPING              0x00800000  /* Ignored by all F3DEX* variants */

/* See SPMatrix */
/**
 * @brief Specifies whether the matrix operation will be performed on the
 * model or the view*projection matrix.
 */
#define G_MTX_MODEL           0x00
/**
 * @brief Equivalent to G_MTX_MODEL, for backwards compatibility. The view
 * matrix used to be put in the same stack as the model matrix, whereas now it
 * should be multiplied with the projection matrix. In SM64, this is called
 * "mat stack fix"; in OoT, the vanilla game already does this.
 */
#define G_MTX_MODELVIEW       G_MTX_MODEL
/**
 * @brief @copybrief G_MTX_MODEL
 */
#define G_MTX_VIEWPROJECTION  0x04
/**
 * @brief Equivalent to G_MTX_VIEWPROJECTION, @see G_MTX_MODELVIEW.
 */
#define G_MTX_PROJECTION      G_MTX_VIEWPROJECTION
/**
 * @brief Multiplies the incoming matrix into the top of the matrix stack.
 * @note The binary encoding of this bit is flipped in SPMatrix to save a RSP
 * instruction. This is new in F3DEX3.
 */
#define G_MTX_MUL             0x00
/**
 * @brief Replaces the top of the matrix stack with the incoming matrix.
 * @note The binary encoding of this bit is flipped in SPMatrix to save a RSP
 * instruction. This is new in F3DEX3.
 */
#define G_MTX_LOAD            0x02
/**
 * @brief Do not push the top of the matrix stack to DRAM prior to matrix
 * operations.
 * @note The binary encoding of this bit is flipped in SPMatrix to save a RSP
 * instruction. This is true in both F3DEX2 and F3DEX3.
 */
#define G_MTX_NOPUSH          0x00
/**
 * @brief Push the top of the matrix stack to DRAM prior to matrix operations.
 * This is not supported for G_MTX_VIEWPROJECTION, only G_MTX_MODEL.
 * @note The binary encoding of this bit is flipped in SPMatrix to save a RSP
 * instruction. This is true in both F3DEX2 and F3DEX3.
 */
#define G_MTX_PUSH            0x01

/*
 * MOVEMEM indices
 * Each of these indexes an entry in a dmem table which points to an arbitrarily
 * sized block of dmem in which to store the result of a DMA.
 */
#define G_MV_MMTX      0
#define G_MV_TEMPMTX0  2  /* for internal use by G_MTX multiply mode */
#define G_MV_VPMTX     4
#define G_MV_TEMPMTX1  6  /* for internal use by G_MTX multiply mode */
#define G_MV_VIEWPORT  8
#define G_MV_LIGHT     10
/* G_MV_POINT is no longer supported because the internal vertex format is no
longer a multiple of 8 (DMA word). This was not used in any command anyway. */
/* G_MV_MATRIX is no longer supported. */
#define G_MV_PMTX G_MV_VPMTX /* backwards compatibility */

/*
 * MOVEWORD indices
 * Each of these indexes an entry in a dmem table which points to a word in dmem
 * where an immediate word will be stored.
 */
#define G_MW_FX             0x00 /* replaces G_MW_MATRIX which is no longer supported */
#define G_MW_NUMLIGHT       0x02
/* nothing for 0x04; G_MW_CLIP is no longer supported */
#define G_MW_SEGMENT        0x06
#define G_MW_FOG            0x08
#define G_MW_LIGHTCOL       0x0A
/* G_MW_FORCEMTX is no longer supported. */
/* G_MW_PERSPNORM is removed; perspective norm is now set via G_MW_FX. */


/*
 * These are offsets from the address in the dmem table
 */
#define G_MWO_NUMLIGHT           0x00
#define G_MWO_FOG                0x00


/* These are deprecated and no longer needed. */
#define G_MWO_aLIGHT_1           0x00
#define G_MWO_bLIGHT_1           0x04
#define G_MWO_aLIGHT_2           0x10
#define G_MWO_bLIGHT_2           0x14
#define G_MWO_aLIGHT_3           0x20
#define G_MWO_bLIGHT_3           0x24
#define G_MWO_aLIGHT_4           0x30
#define G_MWO_bLIGHT_4           0x34
#define G_MWO_aLIGHT_5           0x40
#define G_MWO_bLIGHT_5           0x44
#define G_MWO_aLIGHT_6           0x50
#define G_MWO_bLIGHT_6           0x54
#define G_MWO_aLIGHT_7           0x60
#define G_MWO_bLIGHT_7           0x64
#define G_MWO_aLIGHT_8           0x70
#define G_MWO_bLIGHT_8           0x74
#define G_MWO_aLIGHT_9           0x80
#define G_MWO_bLIGHT_9           0x84
#define G_MWO_aLIGHT_10          0x90
#define G_MWO_bLIGHT_10          0x94

/**
 * @brief changes the color of the vertex. The val parameter is interpreted as 4 bytes: red (high byte), green, blue, and alpha (low byte).
 * 
 */
#define G_MWO_POINT_RGBA         0x10
/**
 * @brief changes the S and T values (texture coordinates of the vertex). The high 16 bits of val specify the S coordinate, and the low 16 bits specify the T coordinate. Each coordinate is an S10.5 number.
 * 
 */
#define G_MWO_POINT_ST           0x14
/**
 * @brief change the screen coordinates of the vertex. The high 16 bits of val specify the X coordinate and the low 16 bits specify the Y coordinate. Both coordinates are S13.2 numbers with 0,0 being the upper-left of the screen, positive X going right, and positive Y going down.
 * 
 * @deprecated to use, won't work if the tri gets clipped.
 */
#define G_MWO_POINT_XYSCREEN     0x18
/**
 * @brief changes the screen Z coordinate of the vertex. The entire 32-bit val is taken as the new screen Z value. It is a 16.16 number in the range 0x00000000 to 0x03ff0000.
 * 
 * @deprecated to use, won't work if the tri gets clipped.
 */
#define G_MWO_POINT_ZSCREEN      0x1C

#define G_MWO_AO_AMBIENT         0x00
#define G_MWO_AO_DIRECTIONAL     0x02
#define G_MWO_AO_POINT           0x04
#define G_MWO_PERSPNORM          0x06
#define G_MWO_FRESNEL_SCALE      0x0C
#define G_MWO_FRESNEL_OFFSET     0x0E
#define G_MWO_ATTR_OFFSET_S      0x10
#define G_MWO_ATTR_OFFSET_T      0x12
#define G_MWO_ALPHA_COMPARE_CULL 0x14
#define G_MWO_LAST_MAT_DL_ADDR   0x16

/*
 * Macros
 */

/**
 * @brief macro which inserts a matrix operation at the end display list.
 * 
 * It inserts a matrix operation in the display list. The parameters allow you
 * to select which matrix stack to use (projection or model view), whether to
 * load or multiply, and whether or not to push the matrix stack. The following
 * parameters are bitwise OR'ed together:
 * - @ref G_MTX_MODEL - @copybrief G_MTX_MODEL
 * - @ref G_MTX_VIEWPROJECTION - @copybrief G_MTX_VIEWPROJECTION
 * - @ref G_MTX_MUL - @copybrief G_MTX_MUL
 * - @ref G_MTX_LOAD - @copybrief G_MTX_LOAD
 * - @ref G_MTX_NOPUSH - @copybrief G_MTX_NOPUSH
 * - @ref G_MTX_PUSH - @copybrief G_MTX_PUSH
 * 
 * The legacy parameters @ref G_MTX_MODELVIEW and @ref G_MTX_PROJECTION are also
 * supported, but in F3DEX3 you should always multiply the view matrix with the
 * projection matrix as G_MTX_VIEWPROJECTION, and only put model matrices in the
 * G_MTX_MODEL stack.
 * 
 * # Matrix Format
 * 
 * The format of the fixed-point matrices may seem a little awkward to the
 * application programmer because it is optimized for the RSP geometry engine.
 * This unusual format is hidden in the graphics utility libraries and not
 * usually exposed to the application programmer, but in some cases (static
 * matrix declarations or direct element manipulation) it is necessary to
 * understand the format.
 * 
 * The integer and fractional components of the matrix elements are separated.
 * The first 8 words (16 shorts) hold the 16-bit integer elements, the second
 * 8 words (16 shorts) hold the 16-bit fractional elements. The fact that the
 * Mtx type is declared as a long [4][4] array is slightly misleading. For
 * example, to declare a static identity matrix, use code similar to this:
 * ```#include "gbi.h"
 * static Mtx ident =
 * {
 * // integer portion:
 * 0x00010000, 0x00000000,
 * 0x00000001, 0x00000000,
 * 0x00000000, 0x00010000,
 * 0x00000000, 0x00000001,
 * 
 * // fractional portion:
 * 0x00000000, 0x00000000,
 * 0x00000000, 0x00000000,
 * 0x00000000, 0x00000000,
 * 0x00000000, 0x00000000,
 * };
 * ```
 * To force the translation elements of a matrix to be (10.5, 20.5, 30.5), use
 * code similar to this:
 * ```
 * #include "gbi.h"
 * 
 * mat.m[1][2] =
 *    (10 << 16) | (20);
 * mat.m[1][3] =
 *    (30 << 16) | (1);
 * 
 * mat.m[3][2] =
 *    (0x8000 << 16) | (0x8000);
 * mat.m[3][3] =
 *    (0x8000 << 16) | (0);
 * ```
 *
 * # Accuracy
 * 
 * Matrix multiplication in the RSP geometry engine is done using 32-bit integer
 * arithmetic, in s15.16 format (16 integer, 16 fractional bits, in other words
 * representing -32768.0 to 32767.999985 with a resolution of about 0.000015).
 * A 32 x 32 bit multiply results in a 64-bit number. Only the middle 32 bits of
 * this 64-bit result are kept for the new matrix, to preserve the s15.16
 * format.
 * 
 * A typical game object's transformation will have a scale around the range of
 * 1/100, a rotation which is always values -1.0 to 1.0, and a translation
 * around the range of 1000. When producing a final transformation matrix, you
 * will typically compose (multiply) one scale, multiple rotations (for limbs),
 * and finally one translation. Each matrix multiply on the RSP will lose
 * precision, especially if the scale has been applied before the rotations.
 * 
 * Therefore, your game should usually maintain a matrix stack on the CPU in
 * floating point, and once you have a final model matrix for each limb /
 * object, convert it to fixed point and load it to the RSP. Occasional uses of
 * G_MTX_MUL, such as multiplying view * projection or for HUD elements, are
 * okay. Both SM64 and OoT already operate this way.
 * 
 * # Performance
 * 
 * Your game generally should not use G_MTX_PUSH or SPPopMatrix*, even in a
 * scene graph style engine like SM64.
 * 
 * If you have taken the advice above to just compute and upload final model
 * matrices, there is no need to use push or pop--you'll always just do a single
 * load before rendering any model. If you need to return to a previous
 * transformation matrix, just upload that already-computed matrix again. Again,
 * both SM64 and OoT already do this.
 * 
 * In F3DEX3, the code for G_MTX_PUSH and SPPopMatrix* is moved to overlay 3,
 * meaning these operations will be slower on average than in F3DEX2.
 * 
 * @param m is the pointer to the 4x4 fixed-point matrix (see note above about
 * format)
 * @param p are the bit OR'd parameters to the matrix macro
 * (@ref G_MTX_MODEL, @ref G_MTX_VIEWPROJECTION, @ref G_MTX_MUL,
 * @ref G_MTX_LOAD, @ref G_MTX_NOPUSH, @ref G_MTX_PUSH)
 * 
 * @note The binary encoding for this command inverts both G_MTX_PUSH and
 * G_MTX_LOAD. F3DEX2 already inverted G_MTX_PUSH, but the inversion of
 * G_MTX_LOAD is new in F3DEX3. No C source level changes are needed due to
 * these inversions, it's just a binary encoding change.
 * 
 * @note G_MTX_PUSH | G_MTX_VIEWPROJECTION is not supported; the behavior will
 * be that G_MTX_PUSH is ignored in this case.
 * 
 * @note Unlike the display list stack, which is kept in DMEM and is 18 deep,
 * the matrix stack is kept in RDRAM and is of no specified size. It is of
 * whatever size the developer chooses to allocate; there is no bounds checking.
 */
#define gSPMatrix(pkt, m, p) \
        gDma2p((pkt),G_MTX, (m), sizeof(Mtx), (p) ^ G_MTX_PUSH ^ G_MTX_LOAD, 0)
/**
 * @brief macro which inserts a matrix operation in a static display list.
 * 
 * @copydetails gSPMatrix
 */
#define gsSPMatrix(m, p) \
        gsDma2p(     G_MTX, (m), sizeof(Mtx), (p) ^ G_MTX_PUSH ^ G_MTX_LOAD, 0)

/**
 * @brief macro which pops multiple matrices from a matrix stack.
 * 
 * It pops `num` matrices from the stack.
 * 
 * @note If the number of matrices to pop is greater than the number of matrices
 * currently on the stack, the stack ends up validly holding 0 matrices. This is
 * a rare case of "exception" handling in the microcode. Perhaps SGI's intention
 * was to allow for resetting the matrix stack by popping >= 10 matrices at
 * once.
 * 
 * @param mtx is the flag field that identifies which matrix stack to pop:
 * - @ref G_MTX_MODEL pops from the model matrix stack
 * - @ref G_MTX_VIEWPROJECTION pops from the view*projection matrix stack; this
 *   is not supposed to be supported but actually kind of is. The model matrix
 *   stack pointer is reduced by the number of matrices specified here, and then
 *   the resulting matrix is loaded into the view*projection matrix.
 * @param num is the number of matrices to pop
 */
#define gSPPopMatrixN(pkt, mtx, num) \
    gDma2p((pkt), G_POPMTX, (num) * 64, 64, (mtx) + G_MV_MMTX, 0)
/**
 * @brief macro which pops multiple matrices from a matrix stack.
 * 
 * @copydetails gSPPopMatrixN
 */
#define gsSPPopMatrixN(mtx, num) \
    gsDma2p(      G_POPMTX, (num) * 64, 64, (mtx) + G_MV_MMTX, 0)
/**
 * @brief macro which pops one matrix from a matrix stack in a static display list.
 * 
 * This is just SPPopMatrixN with num=1:
 * 
 * @copydetails gSPPopMatrixN
 */
#define gSPPopMatrix(pkt, mtx)       gSPPopMatrixN((pkt), (mtx), 1)
/**
 * @brief macro which pops one matrix from a matrix stack in a static display list.
 * 
 * @copydetails gSPPopMatrix
 */
#define gsSPPopMatrix(mtx)           gsSPPopMatrixN(      (mtx), 1)

/**
 * @brief macro which loads an internal vertex buffer in the RSP with points that are used by @ref gSP1Triangle macros to generate polygons at the end display list.
 * 
 * 
 * It loads an internal vertex buffer in the RSP with points that are used by @ref gSP1Triangle macros to generate polygons. This vertex cache can hold up to 56 vertices, and the vertex loading can begin at any entry (index) within the cache. The vertex coordinates (x,y,z) are encoded in signed 2's complement, 16-bit integers. The texture coordinates (s,t) are encoded in S10.5 format. A vertex either has a color or a normal (for shading). These values are 8-bit values. The colors and alphas are treated as 8-bit unsigned values (0-255), but the normals are treated as 8-bit signed values (-128 to 127). Therefore, the appropriate member of the union to use (.v. or .n.) depends on whether you are using colors or normals.
 * 
 * Normal coordinates range from -1.0 to 1.0. A value of -1.0 is represented as -128, and a value of 1.0 is represented as 128, but because the maximum positive value of a signed byte is 127, a value of 1.0 can't really be represented. Therefore, 0.992 is the maximum representable positive value, which is good enough for this purpose.
 * 
 * The flag value is used for the packed normals feature to store normals with octahedral encoding.
 * 
 * The coordinates (x,y,z) are transformed using the current 4x4 projection and model view matrices, and (s,t) are transformed using the scale defined by gSPTexture.
 * 
 * # Example
 * To load vertex cache entry 2,3,4, use this code:
 * ```c
 * gSPVertex(glistp++, v, 3, 2);
 * ```
 * 
 * @param v is the pointer to the vertex list (segment address)
 * @param n is the number of vertices
 * @param v0 is the load vertex by index vo(0~55) in vertex buffer
 */
#define gSPVertex(pkt, v, n, v0)                    \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_VTX,      24, 8) |    \
                    _SHIFTL((n),        12, 8) |    \
                    _SHIFTL((v0) + (n),  1, 7));    \
    _g->words.w1 = (unsigned int)(v);               \
})

/**
 * @brief macro which loads an internal vertex buffer in the RSP with points that are used by gSP1Triangle macros to generate polygons in a static display list.
 * 
 * @copydetails gSPVertex
 */
#define gsSPVertex(v, n, v0)        \
{                                   \
   (_SHIFTL(G_VTX,      24, 8) |    \
    _SHIFTL((n),        12, 8) |    \
    _SHIFTL((v0) + (n),  1, 7)),    \
    (unsigned int)(v)               \
}

/**
 * gSPLoadUcode   RSP loads specified ucode.
 *
 * uc_start  = ucode text section start
 * uc_dstart = ucode data section start
 */
#define gSPLoadUcodeEx(pkt, uc_start, uc_dstart, uc_dsize)  \
_DW({                                                       \
    Gfx *_g = (Gfx *)(pkt);                                 \
                                                            \
    _g->words.w0 = _SHIFTL(G_RDPHALF_1, 24, 8);             \
    _g->words.w1 = (unsigned int)(uc_dstart);               \
                                                            \
    _g = (Gfx *)(pkt);                                      \
                                                            \
    _g->words.w0 = (_SHIFTL(G_LOAD_UCODE,        24,  8) |  \
                    _SHIFTL((int)(uc_dsize) - 1,  0, 16));  \
    _g->words.w1 = (unsigned int)(uc_start);                \
})

/**
 * @copydetails gSPLoadUcodeEx
 */
#define gsSPLoadUcodeEx(uc_start, uc_dstart, uc_dsize)  \
{                                                       \
    _SHIFTL(G_RDPHALF_1, 24, 8),                        \
    (unsigned int)(uc_dstart),                          \
},                                                      \
{                                                       \
   (_SHIFTL(G_LOAD_UCODE,        24,  8) |              \
    _SHIFTL((int)(uc_dsize) - 1,  0, 16)),              \
    (unsigned int)(uc_start),                           \
}

#define gSPLoadUcode(pkt, uc_start, uc_dstart)  \
        gSPLoadUcodeEx((pkt), (uc_start), (uc_dstart), SP_UCODE_DATA_SIZE)
#define gsSPLoadUcode(uc_start, uc_dstart)      \
        gsSPLoadUcodeEx((uc_start), (uc_dstart), SP_UCODE_DATA_SIZE)

#define gSPLoadUcodeL(pkt, ucode)                                   \
        gSPLoadUcode((pkt), OS_K0_TO_PHYSICAL(& ucode##TextStart),  \
                            OS_K0_TO_PHYSICAL(& ucode##DataStart))
#define gsSPLoadUcodeL(ucode)                                       \
        gsSPLoadUcode(      OS_K0_TO_PHYSICAL(& ucode##TextStart),  \
                            OS_K0_TO_PHYSICAL(& ucode##DataStart))

/**
 * gSPDma_io  DMA to/from DMEM/IMEM for DEBUG.
 */
#define gSPDma_io(pkt, flag, dmem, dram, size)      \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_DMA_IO, 24, 8) |      \
                    _SHIFTL((flag), 23, 1) |        \
                    _SHIFTL((dmem) / 8, 13, 10) |   \
                    _SHIFTL((size) - 1, 0, 12));    \
    _g->words.w1 = (unsigned int)(dram);            \
})

/**
 * @copydetails gSPDma_io
 */
#define gsSPDma_io(flag, dmem, dram, size)  \
{                                           \
   (_SHIFTL(G_DMA_IO,   24,  8) |           \
    _SHIFTL((flag),     23,  1) |           \
    _SHIFTL((dmem) / 8, 13, 10) |           \
    _SHIFTL((size) - 1,  0, 12)),           \
    (unsigned int)(dram)                    \
}

#define gSPDmaRead(pkt,dmem,dram,size)  gSPDma_io((pkt),0,(dmem),(dram),(size))
#define gsSPDmaRead(dmem,dram,size)     gsSPDma_io(     0,(dmem),(dram),(size))
#define gSPDmaWrite(pkt,dmem,dram,size) gSPDma_io((pkt),1,(dmem),(dram),(size))
#define gsSPDmaWrite(dmem,dram,size)    gsSPDma_io(     1,(dmem),(dram),(size))

/**
 * Use RSP DMAs to set a region of memory to a repeated 16-bit value. This can
 * clear the color framebuffer or Z-buffer faster than the RDP can in fill mode.
 * SPMemset overwrites the DMEM vertex buffer, so vertices loaded before this
 * command cannot be used after it (though this would not normally be done).
 * 
 * dram: Segmented or physical start address. Must be aligned to 16 bytes.
 * value: 16-bit value to fill the memory with. e.g. 0 for color, 0xFFFC for Z.
 * size: Size in bytes to fill, must be nonzero and a multiple of 16 bytes.
 */
#define gSPMemset(pkt, dram, value, size)               \
_DW({                                                   \
    gImmp1(pkt, G_RDPHALF_1, ((value) & 0xFFFF));       \
    gDma0p(pkt, G_MEMSET, (dram), ((size) & 0xFFFFF0)); \
})

/**
 * @copydetails gSPMemset
 */
#define gsSPMemset(dram, value, size)    \
    gsImmp1(G_RDPHALF_1, ((value) & 0xFFFF)), \
    gsDma0p(G_MEMSET, (dram), ((size) & 0xFFFFF0))

/*
 * Triangle commands
 */

#define __gsSP1Triangle_w1(v0, v1, v2)    \
   (_SHIFTL((v0) * 2, 16, 8) |              \
    _SHIFTL((v1) * 2,  8, 8) |              \
    _SHIFTL((v2) * 2,  0, 8))

#define __gsSP1Triangle_w1f(v0, v1, v2, flag)         \
   (((flag) == 0) ? __gsSP1Triangle_w1(v0, v1, v2) :    \
    ((flag) == 1) ? __gsSP1Triangle_w1(v1, v2, v0) :    \
                    __gsSP1Triangle_w1(v2, v0, v1))

#define __gsSP1Quadrangle_w1f(v0, v1, v2, v3, flag)   \
   (((flag) == 0) ? __gsSP1Triangle_w1(v0, v1, v2) :    \
    ((flag) == 1) ? __gsSP1Triangle_w1(v1, v2, v3) :    \
    ((flag) == 2) ? __gsSP1Triangle_w1(v2, v3, v0) :    \
                    __gsSP1Triangle_w1(v3, v0, v1))

#define __gsSP1Quadrangle_w2f(v0, v1, v2, v3, flag)   \
   (((flag) == 0) ? __gsSP1Triangle_w1(v0, v2, v3) :    \
    ((flag) == 1) ? __gsSP1Triangle_w1(v1, v3, v0) :    \
    ((flag) == 2) ? __gsSP1Triangle_w1(v2, v0, v1) :    \
                    __gsSP1Triangle_w1(v3, v1, v2))


/**
 * 1 Triangle
 */
#define gSP1Triangle(pkt, v0, v1, v2, flag) \
    g1Word(pkt, G_TRI1, __gsSP1Triangle_w1f(v0, v1, v2, flag))
/**
 * @copydetails gSP1Triangle
 */
#define gsSP1Triangle(v0, v1, v2, flag)     \
    gs1Word(G_TRI1, __gsSP1Triangle_w1f(v0, v1, v2, flag))

/**
 * 1 Quadrangle
 */
#define gSP1Quadrangle(pkt, v0, v1, v2, v3, flag)                   \
_DW({                                                               \
    Gfx *_g = (Gfx *)(pkt);                                         \
    _g->words.w0 = (_SHIFTL(G_QUAD, 24, 8) |                        \
                    __gsSP1Quadrangle_w1f(v0, v1, v2, v3, flag));   \
    _g->words.w1 = (__gsSP1Quadrangle_w2f(v0, v1, v2, v3, flag));   \
})

/**
 * @copydetails gSP1Quadrangle
 */
#define gsSP1Quadrangle(v0, v1, v2, v3, flag)       \
{                                                   \
   (_SHIFTL(G_QUAD, 24, 8) |                        \
    __gsSP1Quadrangle_w1f(v0, v1, v2, v3, flag)),   \
    __gsSP1Quadrangle_w2f(v0, v1, v2, v3, flag)     \
}

/**
 * 2 Triangles
 */
#define gSP2Triangles(pkt, v00, v01, v02, flag0, v10, v11, v12, flag1)  \
_DW({                                                                   \
    Gfx *_g = (Gfx *)(pkt);                                             \
    _g->words.w0 = (_SHIFTL(G_TRI2, 24, 8) |                            \
                    __gsSP1Triangle_w1f(v00, v01, v02, flag0));         \
    _g->words.w1 =  __gsSP1Triangle_w1f(v10, v11, v12, flag1);          \
})

/**
 * @copydetails gSP2Triangles
 */
#define gsSP2Triangles(v00, v01, v02, flag0, v10, v11, v12, flag1)  \
{                                                                   \
   (_SHIFTL(G_TRI2, 24, 8) |                                        \
    __gsSP1Triangle_w1f(v00, v01, v02, flag0)),                     \
    __gsSP1Triangle_w1f(v10, v11, v12, flag1)                       \
}

/**
 * Make the triangle snake turn right before drawing this triangle. In other
 * words, build the new triangle off the newest and middle-age vertices of the
 * last triangle.
 * @see gSPTriSnake
 */
#define G_SNAKE_RIGHT  0
/**
 * Make the triangle snake turn left before drawing this triangle. In other
 * words, build the new triangle off the newest and oldest vertices of the last
 * triangle.
 * @see gSPTriSnake
 */
#define G_SNAKE_LEFT 1
/**
 * Logical-OR this into a triangle index to mark it as the last triangle of the
 * snake. In other words, this gets OR'd into the last valid index, not the
 * first invalid index.
 * 
 * @note Due to tri indices being multiplied by 2 in the binary encoding, this
 * is actually 0x80--the byte's sign bit--in the binary encoding.
 * 
 * @see gSPTriSnake
 */
#define G_SNAKE_LAST  0x40

#define _gSPTriSnakeW0(i1, i2, i3)        \
    (_SHIFTL(G_TRISNAKE,         24, 8) | \
     _SHIFTL((i2)*2,             16, 8) | \
     _SHIFTL((i1)*2,              8, 8) | \
     _SHIFTL((i3)*2|G_SNAKE_LEFT, 0, 8))
#define _gSPTriSnakeW1(i4, i4d, i5, i5d, i6, i6d, i7, i7d) \
    (_SHIFTL((i4)*2|(i4d),       24, 8) |                  \
     _SHIFTL((i5)*2|(i5d),       16, 8) |                  \
     _SHIFTL((i6)*2|(i6d),        8, 8) |                  \
     _SHIFTL((i7)*2|(i7d),        0, 8))

/**
 * Triangle snake is F3DEX3's accelerated triangles command. It is a generalized
 * form of a triangle strip or fan, which can represent any sequential chain of
 * connected triangles by encoding which side of the current triangle the next
 * triangle attaches to. This allows the chain of triangles to "snake" around
 * and double back next to itself, unlike a triangle strip. For more information
 * on the design, see Triangle Snake in the documentation.
 * 
 * The drawing algorithm is:
 * - Initialize 3 bytes of stored triangle indices, A-B-C, to i3-i1-i2, and draw
 *   this triangle. (This initialization and draw is actually implemented by
 *   storing i2-i1-i3 and then running the algorithm below with G_SNAKE_LEFT,
 *   which ends up storing i2 to C and i3 to A, ultimately creating i3-i1-i2.)
 * - Loop:
 *     - If the index in A has G_SNAKE_LAST or'd into it, exit.
 *     - Increment the input pointer, and read the next index and its direction
 *       flag (currently i4 and i4d).
 *     - If the direction flag is G_SNAKE_RIGHT, copy A to B; else
 *       (G_SNAKE_LEFT), copy A to C.
 *     - Store the new index (currently i4) to A.
 *     - Draw the triangle A-B-C and repeat the loop.
 *
 * For example, after drawing the first triangle i3-i1-i2, if i4 is
 * G_SNAKE_RIGHT, the snake turns right and draws i4-i3-i2:
 *                     3 --<-- 4
 *                    /'\    '/            (winding order and
 *                   /   \   /            first vertex for flat
 *                  /     \ /              shading are marked)
 *                 1 -->-- 2
 * Conversely, after the first triangle i3-i1-i2, if i4 is G_SNAKE_LEFT, the
 * snake turns left and draws i4-i1-i3:
 *             4 --<-- 3
 *              \'    /'\
 *               \   /   \
 *                \ /     \
 *                 1 -->-- 2
 * If the snake turns in the same direction repeatedly, it will coil up, forming
 * a triangle fan. If it slithers left and right alternately, this will form a
 * triangle strip. Any combination of these is also possible. In particular, a
 * useful shape is a triangle strip for a few tris, then a tri fan for a couple
 * tris to "turn around", then another tri strip alongside the first, and so on.
 * This shape can cover almost all tris of a typical surface with a single
 * snake, except for tris which have two unconnected edges which can only be the
 * first or last tris of the snake.
 * 
 * Logical-OR G_SNAKE_LAST into the last valid index of the snake. This index
 * still needs a valid G_SNAKE_LEFT or G_SNAKE_RIGHT for its direction. However,
 * for all indices after this, you can fill the index and direction parameters
 * with 0s.
 * 
 * @see gSPContinueSnake to extend the snake to more than 5 triangles.
 */
#define gSPTriSnake(pkt, i1, i2, i3, i4, i4d, i5, i5d, i6, i6d, i7, i7d) \
_DW({                                                                    \
    Gfx *_g = (Gfx *)(pkt);                                              \
    _g->words.w0 = _gSPTriSnakeW0(i1, i2, i3);                           \
    _g->words.w1 = _gSPTriSnakeW1(i4, i4d, i5, i5d, i6, i6d, i7, i7d);   \
})
/**
 * @copydetails gSPTriSnake
 */
#define gsSPTriSnake(i1, i2, i3, i4, i4d, i5, i5d, i6, i6d, i7, i7d) \
{                                                                    \
    _gSPTriSnakeW0(i1, i2, i3),                                      \
    _gSPTriSnakeW1(i4, i4d, i5, i5d, i6, i6d, i7, i7d)               \
}

/**
 * Continue a triangle snake for up to 8 more triangles. This is actually not
 * a display list command--there's no command byte. The data is just the next
 * 8 bytes of the display list data, still being processed by the previous
 * gSPTriSnake. Note that the microcode implementation does correctly handle
 * the case when the snake continues past the end of the current data in the
 * input buffer (which is a copy in DMEM of a chunk of the display list); the
 * input buffer is reloaded like it would be for more commands. So the snake can
 * be an unlimited length by continuing to append gSPContinueSnake commands.
 */
#define gSPContinueSnake(pkt, i0, i0d, i1, i1d, i2, i2d, i3, i3d,      \
                              i4, i4d, i5, i5d, i6, i6d, i7, i7d)      \
_DW({                                                                  \
    Gfx *_g = (Gfx *)(pkt);                                            \
    _g->words.w0 = _gSPTriSnakeW1(i0, i0d, i1, i1d, i2, i2d, i3, i3d); \
    _g->words.w1 = _gSPTriSnakeW1(i4, i4d, i5, i5d, i6, i6d, i7, i7d); \
})
/**
 * @copydetails gSPContinueSnake
 */
#define gsSPContinueSnake(i0, i0d, i1, i1d, i2, i2d, i3, i3d, \
                          i4, i4d, i5, i5d, i6, i6d, i7, i7d) \
{                                                             \
    _gSPTriSnakeW1(i0, i0d, i1, i1d, i2, i2d, i3, i3d),       \
    _gSPTriSnakeW1(i4, i4d, i5, i5d, i6, i6d, i7, i7d)        \
}

/**
 * 5 Triangles in strip arrangement. Draws the following tris:
 * v3-v1-v2, v4-v3-v2, v5-v3-v4, v6-v5-v4, v7-v5-v6
 * To draw fewer than 5 tris, set indices to -1 from the right; for example to
 * draw 4 tris, set v7 to -1, or to draw 3 tris set v6 to -1.
 * 
 * @note The first index of each triangle drawn is different, so that in
 * !G_SHADING_SMOOTH (flat shading) mode, the single color or single normal of
 * each triangle can be set independently.
 * 
 * @deprecated This used to be directly implemented in the microcode, but is
 * now implemented as a special case of gSPTriSnake. The latter is more general
 * and should be used directly.
 * 
 * @note One of the two handednesses of a 4 tri strip cannot be drawn directly
 * with gSPTriStrip, unless v1 and v2 are set to the same vertex to create a
 * degenerate triangle, which costs a little performance. However, now this
 * shape can be drawn with gSPTriSnake (directions left-right-left).
 */
#define gSPTriStrip(pkt, v1, v2, v3, v4, v5, v6, v7)              \
    gSPTriSnake(pkt, v1, v2,                                      \
        (v3) | (((v4) & 0x80) ? G_SNAKE_LAST : 0),                \
        (v4) | (((v5) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_RIGHT, \
        (v5) | (((v6) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT,  \
        (v6) | (((v7) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_RIGHT, \
        (v7) | G_SNAKE_LAST, G_SNAKE_LEFT)
/**
 * @copydetails gSPTriStrip
 */
#define gsSPTriStrip(v1, v2, v3, v4, v5, v6, v7)                  \
    gsSPTriSnake(v1, v2,                                          \
        (v3) | (((v4) & 0x80) ? G_SNAKE_LAST : 0),                \
        (v4) | (((v5) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_RIGHT, \
        (v5) | (((v6) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT,  \
        (v6) | (((v7) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_RIGHT, \
        (v7) | G_SNAKE_LAST, G_SNAKE_LEFT)
/**
 * 5 Triangles in fan arrangement. Draws the following tris:
 * v3-v1-v2, v4-v1-v3, v5-v1-v4, v6-v1-v5, v7-v1-v6
 * Otherwise works the same as @see gSPTriStrip.
 * 
 * @deprecated Use gSPTriSnake directly.
 */
#define gSPTriFan(pkt, v1, v2, v3, v4, v5, v6, v7)               \
    gSPTriSnake(pkt, v1, v2,                                     \
        (v3) | (((v4) & 0x80) ? G_SNAKE_LAST : 0),               \
        (v4) | (((v5) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v5) | (((v6) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v6) | (((v7) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v7) | G_SNAKE_LAST, G_SNAKE_LEFT)
/**
 * @copydetails gSPTriFan
 */
#define gsSPTriFan(v1, v2, v3, v4, v5, v6, v7)                   \
    gsSPTriSnake(v1, v2,                                         \
        (v3) | (((v4) & 0x80) ? G_SNAKE_LAST : 0),               \
        (v4) | (((v5) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v5) | (((v6) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v6) | (((v7) & 0x80) ? G_SNAKE_LAST : 0), G_SNAKE_LEFT, \
        (v7) | G_SNAKE_LAST, G_SNAKE_LEFT)


/**
 * @brief Clipping Macros
 * @deprecated
 * encodes SP no-ops it is not possible to change the clip ratio from 2 in F3DEX3.
 */
#define gSPClipRatio(pkt, r) gSPNoOp(pkt)
/**
 * @brief @copybrief gSPClipRatio
 * @deprecated
 * @copydetails gSPClipRatio
 */
#define gsSPClipRatio(r) gsSPNoOp()

/**
 * @brief Load new MVP matrix directly.
 * 
 * This is no longer supported as it was not used in production games.
 * @deprecated
 */
#define gSPForceMatrix(pkt, mptr) gSPNoOp(pkt)
/**
 * @brief Load new MVP matrix directly.
 * 
 * @copydetails gSPForceMatrix
 */
#define gsSPForceMatrix(mptr)    gsSPNoOp()

/**
 * Ambient occlusion
 * Enabled with the G_AMBOCCLUSION bit in geometry mode.
 * Each of these factors sets how much ambient occlusion affects lights of
 * the given type (ambient, directional, point). They are u16s.
 * You can set each independently or two adjacent values with one moveword.
 * A two-command macro is also provided to set all three values.
 * 
 * When building the model, you must encode the amount of ambient occlusion at
 * each vertex--effectively the shadow map for the model--in vertex alpha, where
 * 00 means darkest and FF means lightest. Then, the factors set with the
 * SPAmbOcclusion command determine how much the vertex alpha values affect the
 * light intensity. For example, if the ambient factor is set to 0x8000, this
 * means that in the darkest parts of the model, the ambient light intensity
 * will be reduced by 50%, and in the lightest parts of the model, the ambient
 * light intensity won't be reduced at all.
 * 
 * The default is:
 * amb = 0xFFFF (ambient light fully affected by vertex alpha)
 * dir = 0xA000 (directional lights 62% affected by vertex alpha)
 * point = 0    (point lights not at all affected by vertex alpha)
 * 
 * Two reasons to use ambient occlusion rather than darkening the vertex colors:
 * - With ambient occlusion, the geometry can be fully lit up with point and/or
 *   directional lights, depending on your settings here.
 * - Ambient occlusion can be used with cel shading to create areas which are
 *   "darker" for the cel shading thresholds, but still have bright / white
 *   vertex colors.
 * 
 * Two reasons to use these factors to modify ambient occlusion rather than
 * just manually scaling and offsetting all the vertex alpha values:
 * - To allow the behavior to differ between ambient, directional, and point
 *   lights
 * - To allow the lighting to be adjusted at the scene level on-the-fly
 */
#define gSPAmbOcclusionAmb(pkt, amb)     gMoveHalfwd(pkt, G_MW_FX, G_MWO_AO_AMBIENT, amb)
/**
 * @copydetails gSPAmbOcclusionAmb
 */
#define gsSPAmbOcclusionAmb(amb)        gsMoveHalfwd(     G_MW_FX, G_MWO_AO_AMBIENT, amb)
/**
 * @copydetails gSPAmbOcclusionAmb
 */
#define gSPAmbOcclusionDir(pkt, dir)     gMoveHalfwd(pkt, G_MW_FX, G_MWO_AO_DIRECTIONAL, dir)
/**
 * @copydetails gSPAmbOcclusionAmb
 */
#define gsSPAmbOcclusionDir(dir)        gsMoveHalfwd(     G_MW_FX, G_MWO_AO_DIRECTIONAL, dir)
/**
 * @copydetails gSPAmbOcclusionAmb
 */
#define gSPAmbOcclusionPoint(pkt, point) gMoveHalfwd(pkt, G_MW_FX, G_MWO_AO_POINT, point)
/**
 * @copydetails gSPAmbOcclusionAmb
 */
#define gsSPAmbOcclusionPoint(point)    gsMoveHalfwd(     G_MW_FX, G_MWO_AO_POINT, point)

#define gSPAmbOcclusionAmbDir(pkt, amb, dir) \
    gMoveWd(pkt, G_MW_FX, G_MWO_AO_AMBIENT,  \
        (_SHIFTL((amb), 16, 16) | _SHIFTL((dir), 0, 16)))
#define gsSPAmbOcclusionAmbDir(amb, dir)     \
    gsMoveWd(G_MW_FX, G_MWO_AO_AMBIENT,      \
        (_SHIFTL((amb), 16, 16) | _SHIFTL((dir), 0, 16)))
#define gSPAmbOcclusionDirPoint(pkt, dir, point) \
    gMoveWd(pkt, G_MW_FX, G_MWO_AO_DIRECTIONAL,  \
        (_SHIFTL((dir), 16, 16) | _SHIFTL((point), 0, 16)))
#define gsSPAmbOcclusionDirPoint(dir, point)     \
    gsMoveWd(G_MW_FX, G_MWO_AO_DIRECTIONAL,      \
        (_SHIFTL((dir), 16, 16) | _SHIFTL((point), 0, 16)))

#define gSPAmbOcclusion(pkt, amb, dir, point) \
_DW({                                         \
    gSPAmbOcclusionAmbDir(pkt, amb, dir);     \
    gSPAmbOcclusionPoint(pkt, point);         \
})
#define gsSPAmbOcclusion(amb, dir, point)     \
    gsSPAmbOcclusionAmbDir(amb, dir),         \
    gsSPAmbOcclusionPoint(point)

/**
 * Fresnel - Feature suggested by thecozies
 * Enabled with the G_FRESNEL bit in geometry mode.
 * The dot product between a vertex normal and the vector from the vertex to the
 * camera is computed. The offset and scale here convert this to a shade alpha
 * value. This is useful for making surfaces fade between transparent when
 * viewed straight-on and opaque when viewed at a large angle, or for applying a
 * fake "outline" around the border of meshes.
 * 
 * If using Fresnel, you need to set the camera world position whenever you set
 * the VP matrix, viewport, etc. See SPCameraWorld.
 * 
 * The RSP does:
 * s16 dotProduct = dot(vertex normal, camera pos - vertex pos);
 * dotProduct = abs(dotProduct); // 0 = points to side, 7FFF = points at or away
 * s32 factor = ((scale * dotProduct) >> 15) + offset;
 * s16 result = clamp(factor << 8, 0, 7FFF);
 * color_or_alpha = result >> 7;
 * 
 * At dotMax, color_or_alpha = FF, result = 7F80, factor = 7F
 * At dotMin, color_or_alpha = 00, result = 0, factor = 0
 * 7F = ((scale * dotMax) >> 15) + offset
 * 00 = ((scale * dotMin) >> 15) + offset
 * Subtract: 7F = (scale * (dotMax - dotMin)) >> 15
 *           3F8000 = scale * (dotMax - dotMin)
 *           scale = 3F8000 / (dotMax - dotMin)                <--
 * offset = -(((3F8000 / (dotMax - dotMin)) * dotMin) >> 15)
 * offset = -((7F * dotMin) / (dotMax - dotMin))               <--
 * 
 * To convert in the opposite direction:
 * ((7F - offset) << 15) / scale = dotMax
 * ((00 - offset) << 15) / scale = dotMin
 */
#define gSPFresnelScale(pkt, scale) \
    gMoveHalfwd(pkt, G_MW_FX, G_MWO_FRESNEL_SCALE, scale)
/**
 * @copydetails gSPFresnelScale
 */
#define gsSPFresnelScale(scale) \
    gsMoveHalfwd(G_MW_FX, G_MWO_FRESNEL_SCALE, scale)
/**
 * @copydetails gSPFresnelScale
 */
#define gSPFresnelOffset(pkt, offset) \
    gMoveHalfwd(pkt, G_MW_FX, G_MWO_FRESNEL_OFFSET, offset)
/**
 * @copydetails gSPFresnelScale
 */
#define gsSPFresnelOffset(offset) \
    gsMoveHalfwd(G_MW_FX, G_MWO_FRESNEL_OFFSET, offset)
/**
 * @copydetails gSPFresnelScale
 */
#define gSPFresnel(pkt, scale, offset) \
    gMoveWd(pkt, G_MW_FX, G_MWO_FRESNEL_SCALE, \
        (_SHIFTL((scale), 16, 16) | _SHIFTL((offset), 0, 16)))
/**
 * @copydetails gSPFresnelScale
 */
#define gsSPFresnel(scale, offset) \
    gsMoveWd(G_MW_FX, G_MWO_FRESNEL_SCALE, \
        (_SHIFTL((scale), 16, 16) | _SHIFTL((offset), 0, 16)))

/**
 * Attribute offsets
 * These are added to ST values after vertices are loaded and transformed.
 * The values are s16s. The addition is after the multiplication for ST scale in
 * SPTexture. Whether it is enabled or disabled at a given time is determined
 * by the G_ATTROFFSET_ST_ENABLE bit in the geometry mode. Normally you would
 * use ST offsets for UV scrolling.
 */
#define gSPAttrOffsetST(pkt, s, t) \
    gMoveWd(pkt, G_MW_FX, G_MWO_ATTR_OFFSET_S, \
        (_SHIFTL((s), 16, 16) | _SHIFTL((t), 0, 16)))
/**
 * @copydetails gSPAttrOffsetST
 */
#define gsSPAttrOffsetST(s, t) \
    gsMoveWd(G_MW_FX, G_MWO_ATTR_OFFSET_S, \
        (_SHIFTL((s), 16, 16) | _SHIFTL((t), 0, 16)))

    
/**
 * F3DEX3 has a basic auto-batched rendering system. At a high level, if a
 * material display list being run is the same as the last material, the texture
 * loads are automatically skipped the second time as they should already be in
 * TMEM.
 * 
 * This design generally works, but can break if you call a display list twice
 * but in between change a segment mapping so that a referenced image inside is
 * actually different the two times. In these cases, run the below command
 * between the two calls (e.g. when you change the segment) and the microcode
 * will not skip the second texture loads.
 * 
 * Internally, a material is defined to start with any set image command, and
 * end on any of the following: call, branch, return, vertex, all tri commands,
 * tex/fill rectangles, and successes on cull or branch w/z (which are usually
 * preceded by vertex loads anyway). The physical address of the display list
 * --not the address of the image--is stored when a material is started. If a
 * material starts and its physical address is the same as the stored last start
 * address, i.e. we're executing the same material display list as the last
 * material, material cull mode is set. In this mode, load block, load tile, and
 * load TLUT all are skipped. This mode is cleared when the material ends.
 * 
 * This design has the benefit that it works correctly even with complex
 * materials, e.g. with two CI4 textures (four loads), whereas it would be
 * difficult to implement tracking all these loads separately. Furthermore, a
 * design based on tracking the image addresses could break if you loaded
 * different tile sections of the same image in consecutive materials.
 */
#define gSPDontSkipTexLoadsAcross(pkt) \
    gMoveWd(pkt, G_MW_FX, G_MWO_LAST_MAT_DL_ADDR, 0xFFFFFFFF)
/**
 * @copydetails gSPDontSkipTexLoadsAcross
 */
#define gsSPDontSkipTexLoadsAcross() \
    gsMoveWd(G_MW_FX, G_MWO_LAST_MAT_DL_ADDR, 0xFFFFFFFF)


/**
 * @brief You can use this macro to modify certain sections of a vertex after it has been sent to the RSP (by the gSPVertex macro).
 * 
 * This is an advanced macro. You need a good understanding of how vertices work in the RSP microcode before you use this macro (refer to gSPVertex).
 * 
 * You can use this macro to modify certain sections of a vertex after it has been sent to the RSP (by the gSPVertex macro). This is useful for vertices that are shared between two or more triangles that must have different properties when associated with one triangle versus the other triangle.
 * 
 * For example, you might have two adjacent triangles that both need smooth-shaded color, but one is smooth-shaded red-to-yellow and the other is smooth-shaded green-to-cyan. In this case, the vertex that is shared by both triangles is sent with red/yellow color by using the gSPVertex macro. The first triangle is drawn. Then, the gSPModifyVertex macro is used to change the color to green/cyan, and the second triangle is drawn.

 * The primary use of the gSPModifyVertex macro is to modify the texture coordinate of a vertex so that a vertex that is shared by two triangles with different textures and different texture coordinate spaces can contain the texture coordinate for the first texture and then be modified to contain the texture coordinate for the second texture.
 * 
 * It is faster to use the gSPModifyVertex macro than to send a new vertex macro with a different but similar vertex because no transformations or lighting are done to the vertex when you use the gSPModifyVertex macro.
 * 
 * The where argument specifies which part of the vertex is to be modified. It can hold one of the following values:
 * - @ref G_MWO_POINT_RGBA - @copybrief G_MWO_POINT_RGBA
 * - @ref G_MWO_POINT_ST - @copybrief G_MWO_POINT_ST
 * - @ref G_MWO_POINT_XYSCREEN - @copybrief G_MWO_POINT_XYSCREEN
 * - @ref G_MWO_POINT_ZSCREEN - @copybrief G_MWO_POINT_ZSCREEN
 * 
 * @note
 * Lighting is not performed after a gSPModifyVertex macro, so modifying the color of the vertex with @ref G_MWO_POINT_RGBA is just that - modifying the actual color that will be output. It is not a modification of normal values. This means it cannot be used to update vertex normals for lighting.
 * 
 * The S and T coordinates supplied in the gSPModifyVertex macro are never multiplied by the texture scale (from the gSPTexture macro), so you must pre-scale them before sending them. For example, if you want a texture scale of 1/2 (0x8000), make the S and T values sent with the gSPModifyVertex macro half the value of the equivalent values used with the gSPVertex macro.
 * 
 * # Example
 * To share a vertex between two triangles with different textures and texture coordinates, use this code:
 * ```c
 * // load vertex by gSPVertex
 * gSPVertex(...);
 * // load texture of triangle 1
 * gDPLoadTextureBlock(...);
 * 
 * // draw triangle 1 using vertex #3
 * gSP1Triangle(glistp++, 1,2,3,0);
 * 
 * // change a value of vertex 3 to S=3.0 and T=2.5
 * gSPModifyVertex(glistp++, 3, G_MWO_POINT_ST, 0x00600050);
 * 
 * // load texture of triangle 2
 * gDPLoadTextureBlock(...);
 * 
 * // draw triangle 2 using vertex #3
 * gSP1Triangle(glistp++, 1,2,3,0);
 * ```
 * 
 * @param vtx specifies which of the RSP's vertices (0-55) to modify
 * @param where specifies which part of the vertex to modify (@ref G_MWO_POINT_RGBA, @ref G_MWO_POINT_ST, @ref G_MWO_POINT_XYSCREEN or @ref G_MWO_POINT_ZSCREEN)
 * @param val is the new value for the part of the vertex to be modified (a 32 bit integer number)
 */
# define gSPModifyVertex(pkt, vtx, where, val)      \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = (_SHIFTL(G_MODIFYVTX, 24,  8) |  \
                    _SHIFTL((where),     16,  8) |  \
                    _SHIFTL((vtx) * 2,    0, 16));  \
    _g->words.w1 = (unsigned int)(val);             \
})
/**
 * @brief You can use this macro to modify certain sections of a vertex after it has been sent to the RSP (by the gSPVertex macro).
 * 
 * @copydetails gSPModifyVertex
 */
# define gsSPModifyVertex(vtx, where, val)  \
{                                           \
   (_SHIFTL(G_MODIFYVTX, 24,  8) |          \
    _SHIFTL((where),     16,  8) |          \
    _SHIFTL((vtx) * 2,    0, 16)),          \
    (unsigned int)(val)                     \
}

/*
 * Display list optimization / object culling
 */

/**
 * Cull the display list based on screen clip flags of range of loaded verts.
 * Executes SPEndDisplayList if the convex hull formed by the specified range of
 * already-loaded vertices is offscreen.
 */
#define gSPCullDisplayList(pkt,vstart,vend)             \
_DW({                                                   \
    Gfx *_g = (Gfx *)(pkt);                             \
                                                        \
    _g->words.w0 = (_SHIFTL(G_CULLDL,     24, 8) |      \
                    _SHIFTL((vstart) * 2,  0, 16));     \
    _g->words.w1 = _SHIFTL((vend) * 2, 0, 16);          \
})
/**
 * @copydetails gSPCullDisplayList
 */
#define gsSPCullDisplayList(vstart,vend)    \
{                                           \
   (_SHIFTL(G_CULLDL,     24, 8) |          \
    _SHIFTL((vstart) * 2,  0, 16)),         \
    _SHIFTL((vend) * 2, 0, 16)              \
}

/*
 * gSPBranchLessZ   Branch DL if (vtx.z) less than or equal (zval).
 * Note that this uses W in F3DZEX / CFG_G_BRANCH_W, in which case all the
 * Z calculations below are wrong and raw values must be used.
 *
 *  dl   = DL branch to
 *  vtx  = Vertex
 *  zval = Screen depth
 *  near = Near plane
 *  far  = Far  plane
 *  flag = G_BZ_PERSP or G_BZ_ORTHO
 */

/* From gu.h */
#ifndef FTOFIX32
# define FTOFIX32(x) (long)((x) * (float)0x00010000)
#endif

#define G_BZ_PERSP  0
#define G_BZ_ORTHO  1

#define G_DEPTOZSrg(zval, near, far, flag, zmin, zmax)          \
    (((unsigned int)FTOFIX32(((flag) == G_BZ_PERSP ?            \
                  (1.0f - (float)(near) / (float)(zval)) /      \
                  (1.0f - (float)(near) / (float)(far )) :      \
                  ((float)(zval) - (float)(near)) /             \
                  ((float)(far ) - (float)(near))))) *          \
     (((int)((zmax) - (zmin))) & ~1) + (int)FTOFIX32(zmin))

#define G_DEPTOZS(zval, near, far, flag) \
    G_DEPTOZSrg(zval, near, far, flag, 0, G_MAXZ)

#define gSPBranchLessZrg(pkt, dl, vtx, zval, near, far, flag, zmin, zmax)   \
_DW({                                                                       \
    Gfx *_g = (Gfx *)(pkt);                                                 \
                                                                            \
    _g->words.w0 = _SHIFTL(G_RDPHALF_1, 24, 8);                             \
    _g->words.w1 = (unsigned int)(dl);                                      \
                                                                            \
    _g = (Gfx *)(pkt);                                                      \
                                                                            \
    _g->words.w0 = (_SHIFTL(G_BRANCH_Z, 24,  8) |                           \
                    _SHIFTL((vtx) * 5,  12, 12) |                           \
                    _SHIFTL((vtx) * 2,   0, 12));                           \
    _g->words.w1 = G_DEPTOZSrg(zval, near, far, flag, zmin, zmax);          \
})

#define gsSPBranchLessZrg(dl, vtx, zval, near, far, flag, zmin, zmax)   \
{                                                                       \
    _SHIFTL(G_RDPHALF_1, 24, 8),                                        \
    (unsigned int)(dl),                                                 \
},                                                                      \
{                                                                       \
   (_SHIFTL(G_BRANCH_Z, 24, 8) |                                        \
    _SHIFTL((vtx) * 5, 12, 12) |                                        \
    _SHIFTL((vtx) * 2, 0, 12)),                                         \
    G_DEPTOZSrg(zval, near, far, flag, zmin, zmax),                     \
}

#define gSPBranchLessZ(pkt, dl, vtx, zval, near, far, flag)         \
    gSPBranchLessZrg(pkt, dl, vtx, zval, near, far, flag, 0, G_MAXZ)
#define gsSPBranchLessZ(dl, vtx, zval, near, far, flag)             \
    gsSPBranchLessZrg(dl, vtx, zval, near, far, flag, 0, G_MAXZ)

/**
 *  gSPBranchLessZraw   Branch DL if (vtx.z) less than or equal (raw zval).
 *
 *  dl   = DL branch to
 *  vtx  = Vertex
 *  zval = Raw value of screen depth
 */
#define gSPBranchLessZraw(pkt, dl, vtx, zval)       \
_DW({                                               \
    Gfx *_g = (Gfx *)(pkt);                         \
                                                    \
    _g->words.w0 = _SHIFTL(G_RDPHALF_1, 24, 8);     \
    _g->words.w1 = (unsigned int)(dl);              \
                                                    \
    _g = (Gfx *)(pkt);                              \
                                                    \
    _g->words.w0 = (_SHIFTL(G_BRANCH_Z, 24,  8) |   \
                    _SHIFTL((vtx) * 5,  12, 12) |   \
                    _SHIFTL((vtx) * 2,   0, 12));   \
    _g->words.w1 = (unsigned int)(zval);            \
})

/**
 * @copydetails gSPBranchLessZraw
 */
#define gsSPBranchLessZraw(dl, vtx, zval)   \
{                                           \
    _SHIFTL(G_RDPHALF_1, 24, 8),            \
    (unsigned int)(dl),                     \
},                                          \
{                                           \
   (_SHIFTL(G_BRANCH_Z, 24,  8) |           \
    _SHIFTL((vtx) * 5,  12, 12) |           \
    _SHIFTL((vtx) * 2,   0, 12)),           \
    (unsigned int)(zval),                   \
}


/*
 * Lighting Commands
 */

/**
 * OR this flag into n in SPNumLights or SPSetLights* to indicate that one or
 * more of the lights are point lights.
 * Example: gSPSetLights(POLY_OPA_DISP++, numLights | ENABLE_POINT_LIGHTS, *lights);
 */
#define ENABLE_POINT_LIGHTS (0x8000 >> 4)

#define NUML(n)    ((n) * 0x10)
/**
 * F3DEX3 properly supports zero lights, so there is no need to use these macros
 * anymore.
 */
#define NUMLIGHTS_0 0
#define NUMLIGHTS_1 1
#define NUMLIGHTS_2 2
#define NUMLIGHTS_3 3
#define NUMLIGHTS_4 4
#define NUMLIGHTS_5 5
#define NUMLIGHTS_6 6
#define NUMLIGHTS_7 7
#define NUMLIGHTS_8 8
#define NUMLIGHTS_9 9

/**
 * Number of directional / point lights, in the range 0-9. There is also always
 * one ambient light not counted in this number. See also ENABLE_POINT_LIGHTS.
 */
#define gSPNumLights(pkt, n)                            \
    gMoveWd(pkt, G_MW_NUMLIGHT, G_MWO_NUMLIGHT, NUML(n))
/**
 * @copydetails gSPNumLights
 */
#define gsSPNumLights(n)                                \
    gsMoveWd(    G_MW_NUMLIGHT, G_MWO_NUMLIGHT, NUML(n))

/** There is also no need to use these macros. */
#define LIGHT_1     1
#define LIGHT_2     2
#define LIGHT_3     3
#define LIGHT_4     4
#define LIGHT_5     5
#define LIGHT_6     6
#define LIGHT_7     7
#define LIGHT_8     8
#define LIGHT_9     9
#define LIGHT_10    10

#define _LIGHT_TO_OFFSET(n) (((n) - 1) * 0x10 + 0x10) /* The + 0x10 skips cam pos and lookat */

/**
 * l should point to a Light struct.
 * n should be an integer 1-9 to load lights 0-8.
 * Can also load Ambient lights to lights 0-8 with this. However, if you have
 * 9 directional / point lights, you must use SPAmbient to load light 9
 * (LIGHT_10) with an ambient light. (That is, the memory for light 9 (LIGHT_10)
 * is only sizeof(Ambient), so if you load this with SPLight, it will overwrite
 * other DMEM and corrupt unrelated things.)
 * New code should not generally use SPLight, and instead use SPSetLights to set
 * all lights in one memory transaction.
 */
#define gSPLight(pkt, l, n) \
    gDma2p((pkt), G_MOVEMEM, (l), sizeof(Light), G_MV_LIGHT, _LIGHT_TO_OFFSET(n))
/**
 * @copydetails gSPLight
 */
#define gsSPLight(l, n) \
    gsDma2p(      G_MOVEMEM, (l), sizeof(Light), G_MV_LIGHT, _LIGHT_TO_OFFSET(n))

/**
 * l should point to an Ambient struct.
 * n should be an integer 1-10 to load lights 0-9.
 */
#define gSPAmbient(pkt, l, n) \
    gDma2p((pkt), G_MOVEMEM, (l), sizeof(Ambient), G_MV_LIGHT, _LIGHT_TO_OFFSET(n))
/**
 * @copydetails gSPAmbient
 */
#define gsSPAmbient(l, n) \
    gsDma2p(      G_MOVEMEM, (l), sizeof(Ambient), G_MV_LIGHT, _LIGHT_TO_OFFSET(n))

/**
 * gSPLightColor changes the color of a directional light without an additional
 * DMA transfer.
 * col is a 32 bit word where (col >> 24) & 0xFF is red, (col >> 16) & 0xFF is
 * green, and (col >> 8) & 0xFF is blue. (col & 0xFF) is ignored and masked to
 * zero.
 * n should be an integer 1-10 to apply to light 0-9.
 */
#define gSPLightColor(pkt, n, col)                  \
_DW({                                               \
    gMoveWd(pkt, G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 0), ((col) & 0xFFFFFF00));   \
    gMoveWd(pkt, G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 4), ((col) & 0xFFFFFF00));   \
})
/**
 * @copydetails gSPLightColor
 */
#define gsSPLightColor(n, col)                      \
    gsMoveWd(G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 0), ((col) & 0xFFFFFF00)),       \
    gsMoveWd(G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 4), ((col) & 0xFFFFFF00))
/*
 * Version for point lights. (col1 & 0xFF) must be set to the point light constant
 * factor (must be nonzero), and (col2 & 0xFF) must be set to the point light
 * linear factor.
 * n should be an integer 1-10 to apply to light 0-9.
 */
#define _gSPLightColor2(pkt, n, col1, col2) \
_DW({\
  gMoveWd(pkt, G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 0), col1); \
  gMoveWd(pkt, G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 4), col2); \
})
#define _gsSPLightColor2(n, col1, col2) \
  gsMoveWd(G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 0), col1), \
  gsMoveWd(G_MW_LIGHTCOL, ((((n) - 1) * 0x10) + 4), col2)


/**
 * Set all your scene's lights (directional/point + ambient) with one memory
 * transaction.
 * n is the number of directional / point lights, from 0 to 9. There is also
 * always an ambient light. If there are point lights, set ENABLE_POINT_LIGHTS
 * in n via logical or (i.e. set n to (numLights | ENABLE_POINT_LIGHTS))
 * name should be the NAME of a Lights struct (NOT A POINTER)
 * filled in with all the lighting data. You can use the gdSPDef* macros to fill
 * in the struct or just do it manually. Example:
 * Lights2 myLights; // 2 dir/pos + 1 ambient
 * <code to fill in the fields of myLights>
 * gSPSetLights(POLY_OPA_DISP++, 2, myLights);
 * 
 * If you need to use a pointer, e.g. if the number of lights is variable at
 * runtime:
 * Light *lights = memory_allocate((numLights + 1) * sizeof(Light));
 * lights[0].p.pos = ...;
 * lights[1].l.dir = ...;
 * ...
 * lights[numLights].l.col = ambient_color();
 * gSPSetLights(POLY_OPA_DISP++, ENABLE_POINT_LIGHTS | numLights,
 *     *lights); // <- NOTE DEREFERENCE
 * 
 * If you're wondering why this macro takes a name / dereference instead of a
 * pointer, it's for backwards compatibility.
 */
#define gSPSetLights(pkt, n, name) \
_DW({ \
    gSPNumLights(pkt, n); \
    gDma2p((pkt),  G_MOVEMEM, &(name), (n) * 0x10 + 8, G_MV_LIGHT, 0x10); \
})
/**
 * @copydetails gSPSetLights
 */
#define gsSPSetLights(n, name) \
    gsSPNumLights(n), \
    gsDma2p(G_MOVEMEM, &(name), (n) * 0x10 + 8, G_MV_LIGHT, 0x10)

#define  gSPSetLights0(pkt, name)  gSPSetLights(pkt, 0, name)
#define gsSPSetLights0(name)      gsSPSetLights(     0, name)
#define  gSPSetLights1(pkt, name)  gSPSetLights(pkt, 1, name)
#ifdef KAZE_GBI_HACKS
#define gsSPSetLights1(name)      gsSPNoOp()
#else
#define gsSPSetLights1(name)      gsSPSetLights(     1, name)
#endif
#define  gSPSetLights2(pkt, name)  gSPSetLights(pkt, 2, name)
#define gsSPSetLights2(name)      gsSPSetLights(     2, name)
#define  gSPSetLights3(pkt, name)  gSPSetLights(pkt, 3, name)
#define gsSPSetLights3(name)      gsSPSetLights(     3, name)
#define  gSPSetLights4(pkt, name)  gSPSetLights(pkt, 4, name)
#define gsSPSetLights4(name)      gsSPSetLights(     4, name)
#define  gSPSetLights5(pkt, name)  gSPSetLights(pkt, 5, name)
#define gsSPSetLights5(name)      gsSPSetLights(     5, name)
#define  gSPSetLights6(pkt, name)  gSPSetLights(pkt, 6, name)
#define gsSPSetLights6(name)      gsSPSetLights(     6, name)
#define  gSPSetLights7(pkt, name)  gSPSetLights(pkt, 7, name)
#define gsSPSetLights7(name)      gsSPSetLights(     7, name)
#define  gSPSetLights8(pkt, name)  gSPSetLights(pkt, 8, name)
#define gsSPSetLights8(name)      gsSPSetLights(     8, name)
#define  gSPSetLights9(pkt, name)  gSPSetLights(pkt, 9, name)
#define gsSPSetLights9(name)      gsSPSetLights(     9, name)


/**
 * Camera world position for Fresnel and specular lighting. Set this whenever
 * you set the VP matrix, viewport, etc. cam is the address of a PlainVtx struct.
 */
#define gSPCameraWorld(pkt, cam) \
    gDma2p((pkt), G_MOVEMEM, (cam), sizeof(PlainVtx), G_MV_LIGHT, 0)
/**
 * @copydetails gSPCameraWorld
 */
#define gsSPCameraWorld(cam) \
    gsDma2p(      G_MOVEMEM, (cam), sizeof(PlainVtx), G_MV_LIGHT, 0)


/**
 * Reflection/Hiliting Macros.
 * la is the address of a LookAt struct.
 */
#define gSPLookAt(pkt, la) \
    gDma2p((pkt), G_MOVEMEM, (la), sizeof(LookAt), G_MV_LIGHT, 8)
/**
 * @copydetails gSPLookAt
 */
#define gsSPLookAt(la) \
    gsDma2p(      G_MOVEMEM, (la), sizeof(LookAt), G_MV_LIGHT, 8)
 
/**
 * These versions are deprecated, please use g*SPLookAt. The two directions
 * cannot be set independently anymore as they both fit within one memory word.
 * (They could be set with moveword, but then the values would have to be within
 * the command itself, not at a memory address.)
 * This deprecated version has the X command set both (assuming l is the name /
 * address of a LookAt struct) and has the Y command as a SP no-op.
 * @deprecated
 */
#define gSPLookAtX(pkt, l) gSPLookAt(pkt, l)
/**
 * @copydetails gSPLookAtX
 */
#define gsSPLookAtX(l)     gsSPLookAt(l)
/**
 * @copydetails gSPLookAtX
 */
#define gSPLookAtY(pkt, l) gSPNoOp(pkt)
/**
 * @copydetails gSPLookAtX
 */
#define gsSPLookAtY(l)     gsSPNoOp()


#define gDPSetHilite1Tile(pkt, tile, hilite, width, height) \
    gDPSetTileSize(pkt, tile,                               \
        (hilite)->h.x1 & 0xFFF,                             \
        (hilite)->h.y1 & 0xFFF,                             \
        ((((width)  - 1) * 4) + (hilite)->h.x1) & 0xFFF,    \
        ((((height) - 1) * 4) + (hilite)->h.y1) & 0xFFF)
#define gsDPSetHilite1Tile(tile, hilite, width, height)     \
    gsDPSetTileSize(tile,                                   \
        (hilite)->h.x1 & 0xFFF,                             \
        (hilite)->h.y1 & 0xFFF,                             \
        ((((width)  - 1) * 4) + (hilite)->h.x1) & 0xFFF,    \
        ((((height) - 1) * 4) + (hilite)->h.y1) & 0xFFF)

#define gDPSetHilite2Tile(pkt, tile, hilite, width, height) \
    gDPSetTileSize(pkt, tile,                               \
        (hilite)->h.x2 & 0xFFF,                             \
        (hilite)->h.y2 & 0xFFF,                             \
        ((((width)  - 1) * 4) + (hilite)->h.x2) & 0xFFF,    \
        ((((height) - 1) * 4) + (hilite)->h.y2) & 0xFFF)
#define gsDPSetHilite2Tile(tile, hilite, width, height)     \
    gsDPSetTileSize(tile,                                   \
        (hilite)->h.x2 & 0xFFF,                             \
        (hilite)->h.y2 & 0xFFF,                             \
        ((((width)  - 1) * 4) + (hilite)->h.x2) & 0xFFF,    \
        ((((height) - 1) * 4) + (hilite)->h.y2) & 0xFFF)


/**
 * Set the occlusion plane. This is a quadrilateral in 3D space where all
 * geometry behind it is culled. You should create occlusion plane candidates
 * just behind walls and other large objects, and have your game engine pick
 * the most optimal one every frame to send to the RSP.
 * 
 * Computing the coefficients for the occlusion plane is far too complicated to
 * explain here. The reference implementation `guOcclusionPlane` is provided
 * separately.
 * 
 * o is the address of an OcclusionPlane struct
 */
#define gSPOcclusionPlane(pkt, o) \
    gDma2p((pkt), G_MOVEMEM, (o), sizeof(OcclusionPlane), G_MV_LIGHT, \
        (G_MAX_LIGHTS * 0x10) + 0x18)
/**
 * @copydetails gSPOcclusionPlane
 */
#define gsSPOcclusionPlane(o) \
    gsDma2p(      G_MOVEMEM, (o), sizeof(OcclusionPlane), G_MV_LIGHT, \
        (G_MAX_LIGHTS * 0x10) + 0x18)


/**
 * FOG macros
 * fm = z multiplier
 * fo = z offset
 * FOG FORMULA:    alpha(fog) = (eyespace z) * fm  + fo  CLAMPED 0 to 255
 *   note: (eyespace z) ranges -1 to 1
 *
 * Alternate method of setting fog:
 * min, max: range 0 to 1000: 0=nearplane, 1000=farplane
 * min is where fog begins (usually less than max and often 0)
 * max is where fog is thickest (usually 1000)
 *
 */
#define gSPFogFactor(pkt, fm, fo)                   \
    gMoveWd(pkt, G_MW_FOG, G_MWO_FOG,               \
       (_SHIFTL(fm, 16, 16) | _SHIFTL(fo, 0, 16)))

/**
 * @copydetails gSPFogFactor
 */
#define gsSPFogFactor(fm, fo)                       \
    gsMoveWd(G_MW_FOG, G_MWO_FOG,                   \
       (_SHIFTL(fm, 16, 16) | _SHIFTL(fo, 0, 16)))

#define gSPFogPosition(pkt, min, max)                               \
    gMoveWd(pkt, G_MW_FOG, G_MWO_FOG,                               \
       (_SHIFTL((128000 / ((max) - (min))), 16, 16) |               \
        _SHIFTL(((500 - (min)) * 256 / ((max) - (min))), 0, 16)))

#define gsSPFogPosition(min, max)                                   \
    gsMoveWd(G_MW_FOG, G_MWO_FOG,                                   \
       (_SHIFTL((128000 / ((max) - (min))), 16, 16) |               \
        _SHIFTL(((500 - (min)) * 256 / ((max) - (min))), 0, 16)))


/**
 * Macros to turn texture on/off
 */
#define gSPTexture(pkt, s, t, level, tile, on)                 \
_DW({                                                           \
    Gfx *_g = (Gfx *)(pkt);                                     \
                                                                \
    _g->words.w0 = (_SHIFTL(G_TEXTURE,  24, 8) |                \
                    _SHIFTL((level),    11, 3) |                \
                    _SHIFTL((tile),      8, 3) |                \
                    _SHIFTL((on),        1, 7));                \
    _g->words.w1 = (_SHIFTL((s), 16, 16) |                      \
                    _SHIFTL((t),  0, 16));                      \
})
/**
 * @copydetails gSPTexture
 */
#define gsSPTexture(s, t, level, tile, on) \
{                                           \
   (_SHIFTL(G_TEXTURE,  24, 8) |            \
    _SHIFTL((level),    11, 3) |            \
    _SHIFTL((tile),      8, 3) |            \
    _SHIFTL((on),        1, 7)),            \
   (_SHIFTL((s), 16, 16) |                  \
    _SHIFTL((t),  0, 16))                   \
}

/**
 * The bowtie value is a workaround for a bug in HW V1, and is not supported
 * by F3DEX2, let alone F3DEX3.
 */
#define gSPTextureL(pkt, s, t, level, bowtie, tile, on) \
    gSPTexture(pkt, s, t, level, tile, on)
/**
 * @copydetails gSPTextureL
 */
#define gsSPTextureL(s, t, level, bowtie, tile, on) \
    gsSPTexture(s, t, level, tile, on)


/**
 * Send the color of the specified light to one of the RDP's color registers.
 * light is the index of a light in the RSP counting from the end, i.e. 0 is
 * the ambient light, 1 is the last directional / point light, etc. The RGB
 * color of the selected light is combined with the alpha specified in this
 * command as word 1 of a RDP command, and word 0 is specified in this command.
 * Specialized versions are provided below for prim color and fog color, 
 * because these are the two versions needed for cel shading, but any RDP color
 * command could be specified this way.
 */
#define gSPLightToRDP(pkt, light, alpha, word0)    \
_DW({                                              \
    Gfx *_g = (Gfx *)(pkt);                        \
    _g->words.w0 = (_SHIFTL(G_LIGHTTORDP, 24, 8) | \
                    _SHIFTL(light * 0x10,  8, 8) | \
                    _SHIFTL(alpha,         0, 8)); \
    _g->words.w1 = (word0);                        \
})
/**
 * @copydetails gSPLightToRDP
 */
#define gsSPLightToRDP(light, alpha, word0) \
{                                           \
   (_SHIFTL(G_LIGHTTORDP, 24, 8) |          \
    _SHIFTL(light * 0x10,  8, 8) |          \
    _SHIFTL(alpha,         0, 8)),          \
   (word0)                                  \
}
#define gSPLightToPrimColor(pkt, light, alpha, m, l) \
    gSPLightToRDP(pkt, light, alpha,                 \
        (_SHIFTL(G_SETPRIMCOLOR, 24, 8) | _SHIFTL(m, 8, 8) | _SHIFTL(l, 0, 8)))
#define gsSPLightToPrimColor(light, alpha, m, l) \
    gsSPLightToRDP(light, alpha,                 \
        (_SHIFTL(G_SETPRIMCOLOR, 24, 8) | _SHIFTL(m, 8, 8) | _SHIFTL(l, 0, 8)))
#define gSPLightToFogColor(pkt, light, alpha) \
    gSPLightToRDP(pkt, light, alpha, _SHIFTL(G_SETFOGCOLOR, 24, 8))
#define gsSPLightToFogColor(light, alpha) \
    gsSPLightToRDP(light, alpha, _SHIFTL(G_SETFOGCOLOR, 24, 8))


#endif /* F3DEX3_H */
