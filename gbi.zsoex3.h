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

/* Many of the components of the GBI have been split out into these individual
files, to reduce clutter and for reuse between microcodes. */
#include "gbi/rdp_defines.h"
#include "gbi/rsp_structs.h"
#include "gbi/gfx_legacy.h" /* Recommend gfx_modern.h instead */
#include "gbi/light_defs.h"
#include "gbi/macro_base.h"
#include "gbi/macro_rdp.h"
#include "gbi/rsp_common.h"

#define ZSOEX_GBI_1 1

/*
 * GBI commands in order
 */
#define G_RELSEGMENT        0xDB
#define G_FLUSH             0xDC
#define G_GEOMETRYMODE      0xDD
#define G_MOVEWORD          0xDE
#define G_MOVEMEM           0xDF
#define G_DL                0xE0
#define G_ENDDL             0xE1
#define G_SPNOOP            0xE2
#define G_RDPHALF_1         0xE3
/* RDP commands go here */
#define G_VTX               0x01
#define G_TRI1              0x02
#define G_TRI2              0x03

/*
 * RSP command argument and misc defines
 */

/* Maximum number of transformed vertices kept in buffer in RSP DMEM */
#define G_MAX_VERTS TODO

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
#define G_MV_CACHEEND  0
#define G_MV_VIEWPORT  2

/*
 * MOVEWORD indices
 * Each of these indexes an entry in a dmem table which points to a word in dmem
 * where an immediate word will be stored.
 */
#define G_MW_FX        0
#define G_MW_SEGMENT   2



#endif // ZSOEX3_H
