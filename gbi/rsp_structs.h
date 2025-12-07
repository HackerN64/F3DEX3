#ifndef GBI_RSP_STRUCTS_H
#define GBI_RSP_STRUCTS_H

/*
 * Data Structures
 */

/**
 * Vertex (set up for use with colors)
 */
typedef struct {
    short          ob[3];   /** x, y, z */
    unsigned short flag;    /** Holds packed normals, or unused */
    short          tc[2];   /** texture coord */
    unsigned char  cn[4];   /** color & alpha */
} Vtx_t;

/**
 * @copydetails Vtx_t
 */
typedef struct {
    short          ob[3];   /** x, y, z */
    unsigned short flag;    /** Packed normals are not used when normals are in colors */
    short          tc[2];   /** texture coord */
    signed char    n[3];    /** normal */
    unsigned char  a;       /** alpha  */
} Vtx_tn;

/**
 * @copydetails Vtx_t
 */
typedef union {
    Vtx_t  v;   /** Use this one for colors  */
    Vtx_tn n;   /** Use this one for normals */
    long long int force_structure_alignment;
} Vtx;

typedef struct {
    short pos[3];
    short pad; /** value ignored, need not be 0 */
} PlainVtx_t;

typedef union {
    PlainVtx_t c;
    long long int force_structure_alignment;
} PlainVtx;

/**
 * Triangle face
 */
typedef struct {
    unsigned char flag;
    unsigned char v[3];
} Tri;

/**
 * 4x4 matrix, fixed point s15.16 format.
 * First 8 words are integer portion of the 4x4 matrix
 * Last 8 words are the fraction portion of the 4x4 matrix
 */
typedef long int Mtx_t[4][4];
typedef union {
    Mtx_t   m;
    struct {
        u16 intPart[4][4];
        u16 fracPart[4][4];
    };
    long long int force_structure_alignment;
} Mtx;

#define IPART(x) (((s32)((x) * 0x10000) >> 16) & 0xFFFF)
#define FPART(x)  ((s32)((x) * 0x10000) & 0xFFFF)

/*
 * Viewport
 */

/**
 * There have been two breaking changes made to the F3DEX3 viewport relative to
 * F3DEX2 and all previous F3D microcodes.
 * - Max Z value changed from 0x03FF to 0x7FFF
 * - Y scale is negated (offset is not negated)
 * 
 * The reason for these changes is as follows. Apparently, SGI initially
 * intended the actual range of Z values in RDP triangle commands to be 0x03FF
 * (integer, plus 16 fractional bits). So this was set up in the GBI and games
 * were initially made this way. The actual range is 0x7FFF (plus 16 frac), at
 * least for RCP HW V2 (retail). So, instead of updating the value in the GBI,
 * SGI just added a scale up by 0x20 at the very end of the triangle processing
 * when writing out the Z coefficients to the RDP. Because of the way this
 * writing was implemented, there did not appear to be any performance penalty
 * to this scaling, so it just worked.
 * 
 * F3DEX3 moves this scale up to the viewport affine transformation step at the
 * end of the vertex processing, which allows an extra 5 bits of Z precision to
 * be retained during some intermediate calculations for the attributes in the
 * triangle write. In EX2, precision is sometimes lost in these calculations,
 * leading to Z fighting. In addition, F3DEX3 optimizes the Z writing, saving a
 * few cycles per written tri.
 * 
 * As far as the Y scale being negated, F3DEX2 did this at the cost of 3
 * instructions, but doing this on the CPU when creating the viewport is
 * effectively free.
 * 
 * Both of these changes were made together--and this macro was changed to an
 * error instead of just being changed to the new value--in order to maximize
 * the chances the developer actually changes their viewport. Some game
 * codebases might have the value derived from G_MAXZ hardcoded, so they might
 * miss this change and start getting weird Z buffer issues. But they won't miss
 * their game being upside down.
 */
#define G_MAXZ Error_please_update_viewport_Z_and_Y_see_GBI

/**
 * New max Z value for viewport.
 */
#define G_NEW_MAXZ 0x7FFF

/**
 * The viewport structure elements have 2 bits of fraction, necessary
 * to accomodate the sub-pixel positioning scaling for the hardware.
 * This can also be exploited to handle odd-sized viewports.
 *
 * Accounting for these fractional bits, using the default projection
 * and viewing matrices, the viewport structure is initialized thusly:
 *
 *      (SCREEN_WD/2)*4, -(SCREEN_HT/2)*4, G_NEW_MAXZ/2, 0,
 *      (SCREEN_WD/2)*4,  (SCREEN_HT/2)*4, G_NEW_MAXZ/2, 0,
 */
typedef struct {
    short vscale[4];    /** scale, 2 bits fraction (X and Y only) */
    short vtrans[4];    /** translate, 2 bits fraction (X and Y only) */
    /* both the above arrays are padded to 64-bit boundary */
} Vp_t;

typedef union {
    Vp_t vp;
    long long int force_structure_alignment[2];
} Vp;

#endif // GBI_RSP_STRUCTS_H
