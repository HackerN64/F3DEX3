#ifndef GBI_RDP_DEFINES_H
#define GBI_RDP_DEFINES_H

/*
 * The following commands are the "generated" RDP commands; the user
 * never sees them, the RSP microcode generates them.
 *                                    edge, shade, texture, zbuff bits:  estz
 */
#define G_TRI_FILL              0xC8    /* fill triangle:            11001000 */
#define G_TRI_SHADE             0xCC    /* shade triangle:           11001100 */
#define G_TRI_TXTR              0xCA    /* texture triangle:         11001010 */
#define G_TRI_SHADE_TXTR        0xCE    /* shade, texture triangle:  11001110 */
#define G_TRI_FILL_ZBUFF        0xC9    /* fill, zbuff triangle:     11001001 */
#define G_TRI_SHADE_ZBUFF       0xCD    /* shade, zbuff triangle:    11001101 */
#define G_TRI_TXTR_ZBUFF        0xCB    /* texture, zbuff triangle:  11001011 */
#define G_TRI_SHADE_TXTR_ZBUFF  0xCF    /* shade, txtr, zbuff trngl: 11001111 */

/* masks to create the above: */
#define G_RDP_TRI_FILL_MASK     0x08
#define G_RDP_TRI_SHADE_MASK    0x04
#define G_RDP_TRI_TXTR_MASK     0x02
#define G_RDP_TRI_ZBUFF_MASK    0x01

/* RDP commands */
#define G_TEXRECT           0xE4
#define G_TEXRECTFLIP       0xE5
#define G_RDPLOADSYNC       0xE6
#define G_RDPPIPESYNC       0xE7
#define G_RDPTILESYNC       0xE8
#define G_RDPFULLSYNC       0xE9
#define G_SETKEYGB          0xEA
#define G_SETKEYR           0xEB
#define G_SETCONVERT        0xEC
#define G_SETSCISSOR        0xED
#define G_SETPRIMDEPTH      0xEE
#define G_RDPSETOTHERMODE   0xEF
#define G_LOADTLUT          0xF0
#define G_RDPHALF_2         0xF1
#define G_SETTILESIZE       0xF2
#define G_LOADBLOCK         0xF3
#define G_LOADTILE          0xF4
#define G_SETTILE           0xF5
#define G_FILLRECT          0xF6
#define G_SETFILLCOLOR      0xF7
#define G_SETFOGCOLOR       0xF8
#define G_SETBLENDCOLOR     0xF9
#define G_SETPRIMCOLOR      0xFA
#define G_SETENVCOLOR       0xFB
#define G_SETCOMBINE        0xFC
#define G_SETTIMG           0xFD
#define G_SETZIMG           0xFE
#define G_SETCIMG           0xFF
#define G_NOOP              0x00


/*
 * RDP command argument defines
 */

/*
 * Coordinate shift values, number of bits of fraction
 */
#define G_TEXTURE_IMAGE_FRAC    2
#define G_TEXTURE_SCALE_FRAC    16
#define G_SCALE_FRAC            8
#define G_ROTATE_FRAC           16

/*
 * Maximum z-buffer value, used to initialize the z-buffer.
 * Note : this number is NOT the viewport z-scale constant.
 * See the comment next to G_MAXZ for more info.
 */
#define G_MAXFBZ    0x3FFF  /* 3b exp, 11b mantissa */

#define GPACK_RGBA5551(r, g, b, a) \
        ((((r) << 8) & 0xF800) |   \
         (((g) << 3) & 0x07C0) |   \
         (((b) >> 2) & 0x003E) |   \
          ((a) & 1))

#define GPACK_IA16(i, a)    (((i) << 8) | (a))

#define GPACK_ZDZ(z, dz)    (((z) << 2) | (dz))

/*
 * G_SETIMG fmt: set image formats
 */
#define G_IM_FMT_RGBA   0
#define G_IM_FMT_YUV    1
#define G_IM_FMT_CI     2
#define G_IM_FMT_IA     3
#define G_IM_FMT_I      4

/*
 * G_SETIMG siz: set image pixel size
 */
#define G_IM_SIZ_4b     0
#define G_IM_SIZ_8b     1
#define G_IM_SIZ_16b    2
#define G_IM_SIZ_32b    3
#define G_IM_SIZ_DD     5

#define G_IM_SIZ_4b_BYTES       0
#define G_IM_SIZ_4b_TILE_BYTES  G_IM_SIZ_4b_BYTES
#define G_IM_SIZ_4b_LINE_BYTES  G_IM_SIZ_4b_BYTES

#define G_IM_SIZ_8b_BYTES       1
#define G_IM_SIZ_8b_TILE_BYTES  G_IM_SIZ_8b_BYTES
#define G_IM_SIZ_8b_LINE_BYTES  G_IM_SIZ_8b_BYTES

#define G_IM_SIZ_16b_BYTES      2
#define G_IM_SIZ_16b_TILE_BYTES G_IM_SIZ_16b_BYTES
#define G_IM_SIZ_16b_LINE_BYTES G_IM_SIZ_16b_BYTES

#define G_IM_SIZ_32b_BYTES      4
#define G_IM_SIZ_32b_TILE_BYTES 2
#define G_IM_SIZ_32b_LINE_BYTES 2

#define G_IM_SIZ_4b_LOAD_BLOCK  G_IM_SIZ_16b
#define G_IM_SIZ_8b_LOAD_BLOCK  G_IM_SIZ_16b
#define G_IM_SIZ_16b_LOAD_BLOCK G_IM_SIZ_16b
#define G_IM_SIZ_32b_LOAD_BLOCK G_IM_SIZ_32b

#define G_IM_SIZ_4b_SHIFT  2
#define G_IM_SIZ_8b_SHIFT  1
#define G_IM_SIZ_16b_SHIFT 0
#define G_IM_SIZ_32b_SHIFT 0

#define G_IM_SIZ_4b_INCR  3
#define G_IM_SIZ_8b_INCR  1
#define G_IM_SIZ_16b_INCR 0
#define G_IM_SIZ_32b_INCR 0

/*
 * G_SETCOMBINE: color combine modes
 */
/* Color combiner constants: */
#define G_CCMUX_COMBINED        0
#define G_CCMUX_TEXEL0          1
#define G_CCMUX_TEXEL1          2
#define G_CCMUX_PRIMITIVE       3
#define G_CCMUX_SHADE           4
#define G_CCMUX_ENVIRONMENT     5
#define G_CCMUX_CENTER          6
#define G_CCMUX_SCALE           6
#define G_CCMUX_COMBINED_ALPHA  7
#define G_CCMUX_TEXEL0_ALPHA    8
#define G_CCMUX_TEXEL1_ALPHA    9
#define G_CCMUX_PRIMITIVE_ALPHA 10
#define G_CCMUX_SHADE_ALPHA     11
#define G_CCMUX_ENV_ALPHA       12
#define G_CCMUX_LOD_FRACTION    13
#define G_CCMUX_PRIM_LOD_FRAC   14
#define G_CCMUX_NOISE           7
#define G_CCMUX_K4              7
#define G_CCMUX_K5              15
#define G_CCMUX_1               6
#define G_CCMUX_0               31

/* Alpha combiner constants: */
#define G_ACMUX_COMBINED        0
#define G_ACMUX_TEXEL0          1
#define G_ACMUX_TEXEL1          2
#define G_ACMUX_PRIMITIVE       3
#define G_ACMUX_SHADE           4
#define G_ACMUX_ENVIRONMENT     5
#define G_ACMUX_LOD_FRACTION    0
#define G_ACMUX_PRIM_LOD_FRAC   6
#define G_ACMUX_1               6
#define G_ACMUX_0               7

/* typical CC cycle 1 modes */

/* typical CC cycle 1 modes */
#define	G_CC_PRIMITIVE              0, 0, 0, PRIMITIVE, 0, 0, 0, PRIMITIVE
#define	G_CC_SHADE                  0, 0, 0, SHADE, 0, 0, 0, SHADE

#define	G_CC_MODULATEI              TEXEL0, 0, SHADE, 0, 0, 0, 0, SHADE
#define	G_CC_MODULATEIDECALA        TEXEL0, 0, SHADE, 0, 0, 0, 0, TEXEL0
#define	G_CC_MODULATEIFADE          TEXEL0, 0, SHADE, 0, 0, 0, 0, ENVIRONMENT

#define	G_CC_MODULATERGB            G_CC_MODULATEI
#define	G_CC_MODULATERGBDECALA      G_CC_MODULATEIDECALA
#define	G_CC_MODULATERGBFADE        G_CC_MODULATEIFADE

#define	G_CC_MODULATEIA             TEXEL0, 0, SHADE, 0, TEXEL0, 0, SHADE, 0
#define	G_CC_MODULATEIFADEA         TEXEL0, 0, SHADE, 0, TEXEL0, 0, ENVIRONMENT, 0

#define	G_CC_MODULATEFADE           TEXEL0, 0, SHADE, 0, ENVIRONMENT, 0, TEXEL0, 0

#define	G_CC_MODULATERGBA           G_CC_MODULATEIA
#define	G_CC_MODULATERGBFADEA       G_CC_MODULATEIFADEA

#define	G_CC_MODULATEI_PRIM         TEXEL0, 0, PRIMITIVE, 0, 0, 0, 0, PRIMITIVE
#define	G_CC_MODULATEIA_PRIM        TEXEL0, 0, PRIMITIVE, 0, TEXEL0, 0, PRIMITIVE, 0
#define	G_CC_MODULATEIDECALA_PRIM   TEXEL0, 0, PRIMITIVE, 0, 0, 0, 0, TEXEL0

#define	G_CC_MODULATERGB_PRIM       G_CC_MODULATEI_PRIM
#define	G_CC_MODULATERGBA_PRIM      G_CC_MODULATEIA_PRIM
#define	G_CC_MODULATERGBDECALA_PRIM G_CC_MODULATEIDECALA_PRIM

#define	G_CC_FADE                   SHADE, 0, ENVIRONMENT, 0, SHADE, 0, ENVIRONMENT, 0
#define	G_CC_FADEA                  TEXEL0, 0, ENVIRONMENT, 0, TEXEL0, 0, ENVIRONMENT, 0

#define	G_CC_DECALRGB               0, 0, 0, TEXEL0, 0, 0, 0, SHADE
#define	G_CC_DECALRGBA              0, 0, 0, TEXEL0, 0, 0, 0, TEXEL0
#define	G_CC_DECALFADE              0, 0, 0, TEXEL0, 0, 0, 0, ENVIRONMENT

#define	G_CC_DECALFADEA             0, 0, 0, TEXEL0, TEXEL0, 0, ENVIRONMENT, 0

#define	G_CC_BLENDI                 ENVIRONMENT, SHADE, TEXEL0, SHADE, 0, 0, 0, SHADE
#define	G_CC_BLENDIA                ENVIRONMENT, SHADE, TEXEL0, SHADE, TEXEL0, 0, SHADE, 0
#define	G_CC_BLENDIDECALA           ENVIRONMENT, SHADE, TEXEL0, SHADE, 0, 0, 0, TEXEL0

#define	G_CC_BLENDRGBA              TEXEL0, SHADE, TEXEL0_ALPHA, SHADE, 0, 0, 0, SHADE
#define	G_CC_BLENDRGBDECALA         TEXEL0, SHADE, TEXEL0_ALPHA, SHADE, 0, 0, 0, TEXEL0
#define	G_CC_BLENDRGBFADEA          TEXEL0, SHADE, TEXEL0_ALPHA, SHADE, 0, 0, 0, ENVIRONMENT

#define G_CC_ADDRGB                 TEXEL0, 0, TEXEL0, SHADE, 0, 0, 0, SHADE
#define G_CC_ADDRGBDECALA           TEXEL0, 0, TEXEL0, SHADE, 0, 0, 0, TEXEL0
#define G_CC_ADDRGBFADE             TEXEL0, 0, TEXEL0, SHADE, 0, 0, 0, ENVIRONMENT

#define G_CC_REFLECTRGB             ENVIRONMENT, 0, TEXEL0, SHADE, 0, 0, 0, SHADE
#define G_CC_REFLECTRGBDECALA       ENVIRONMENT, 0, TEXEL0, SHADE, 0, 0, 0, TEXEL0

#define G_CC_HILITERGB              PRIMITIVE, SHADE, TEXEL0, SHADE, 0, 0, 0, SHADE
#define G_CC_HILITERGBA             PRIMITIVE, SHADE, TEXEL0, SHADE, PRIMITIVE, SHADE, TEXEL0, SHADE
#define G_CC_HILITERGBDECALA        PRIMITIVE, SHADE, TEXEL0, SHADE, 0, 0, 0, TEXEL0

#define G_CC_SHADEDECALA            0, 0, 0, SHADE, 0, 0, 0, TEXEL0
#define G_CC_SHADEFADEA             0, 0, 0, SHADE, 0, 0, 0, ENVIRONMENT

#define	G_CC_BLENDPE                PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT, TEXEL0, 0, SHADE, 0
#define	G_CC_BLENDPEDECALA          PRIMITIVE, ENVIRONMENT, TEXEL0, ENVIRONMENT, 0, 0, 0, TEXEL0

/* oddball modes */
#define	_G_CC_BLENDPE               ENVIRONMENT, PRIMITIVE, TEXEL0, PRIMITIVE, TEXEL0, 0, SHADE, 0
#define	_G_CC_BLENDPEDECALA         ENVIRONMENT, PRIMITIVE, TEXEL0, PRIMITIVE, 0, 0, 0, TEXEL0
#define	_G_CC_TWOCOLORTEX           PRIMITIVE, SHADE, TEXEL0, SHADE, 0, 0, 0, SHADE
/* used for 1-cycle sparse mip-maps, primitive color has color of lowest LOD */
#define	_G_CC_SPARSEST              PRIMITIVE, TEXEL0, LOD_FRACTION, TEXEL0, PRIMITIVE, TEXEL0, LOD_FRACTION, TEXEL0
#define G_CC_TEMPLERP               TEXEL1, TEXEL0, PRIM_LOD_FRAC, TEXEL0, TEXEL1, TEXEL0, PRIM_LOD_FRAC, TEXEL0

/* typical CC cycle 1 modes, usually followed by other cycle 2 modes */
#define	G_CC_TRILERP                TEXEL1, TEXEL0, LOD_FRACTION, TEXEL0, TEXEL1, TEXEL0, LOD_FRACTION, TEXEL0
#define	G_CC_INTERFERENCE           TEXEL0, 0, TEXEL1, 0, TEXEL0, 0, TEXEL1, 0


/*
 *  One-cycle color convert operation
 */
#define G_CC_1CYUV2RGB              TEXEL0, K4, K5, TEXEL0, 0, 0, 0, SHADE

/*
 *  NOTE: YUV2RGB expects TF step1 color conversion to occur in 2nd clock.
 * Therefore, CC looks for step1 results in TEXEL1
 */
#define G_CC_YUV2RGB                TEXEL1, K4, K5, TEXEL1, 0, 0, 0, 0

/* typical CC cycle 2 modes */
#define G_CC_PASS2                  0, 0, 0, COMBINED, 0, 0, 0, COMBINED
#define G_CC_MODULATEI2             COMBINED, 0, SHADE, 0, 0, 0, 0, SHADE
#define G_CC_MODULATEIA2            COMBINED, 0, SHADE, 0, COMBINED, 0, SHADE, 0
#define G_CC_MODULATERGB2           G_CC_MODULATEI2
#define G_CC_MODULATERGBA2          G_CC_MODULATEIA2
#define G_CC_MODULATEI_PRIM2        COMBINED, 0, PRIMITIVE, 0, 0, 0, 0, PRIMITIVE
#define G_CC_MODULATEIA_PRIM2       COMBINED, 0, PRIMITIVE, 0, COMBINED, 0, PRIMITIVE, 0
#define G_CC_MODULATERGB_PRIM2      G_CC_MODULATEI_PRIM2
#define G_CC_MODULATERGBA_PRIM2     G_CC_MODULATEIA_PRIM2
#define G_CC_DECALRGB2              0, 0, 0, COMBINED, 0, 0, 0, SHADE
/*
 * ?
#define G_CC_DECALRGBA2             COMBINED, SHADE, COMBINED_ALPHA, SHADE, 0, 0, 0, SHADE
*/
#define G_CC_BLENDI2                ENVIRONMENT, SHADE, COMBINED, SHADE, 0, 0, 0, SHADE
#define G_CC_BLENDIA2               ENVIRONMENT, SHADE, COMBINED, SHADE, COMBINED, 0, SHADE, 0
#define G_CC_CHROMA_KEY2            TEXEL0, CENTER, SCALE, 0, 0, 0, 0, 0
#define G_CC_HILITERGB2             ENVIRONMENT, COMBINED, TEXEL0, COMBINED, 0, 0, 0, SHADE
#define G_CC_HILITERGBA2            ENVIRONMENT, COMBINED, TEXEL0, COMBINED, ENVIRONMENT, COMBINED, TEXEL0, COMBINED
#define G_CC_HILITERGBDECALA2       ENVIRONMENT, COMBINED, TEXEL0, COMBINED, 0, 0, 0, TEXEL0
#define G_CC_HILITERGBPASSA2        ENVIRONMENT, COMBINED, TEXEL0, COMBINED, 0, 0, 0, COMBINED

/*
 * G_SETOTHERMODE_L sft: shift count
 */
#define G_MDSFT_ALPHACOMPARE    0
#define G_MDSFT_ZSRCSEL         2
#define G_MDSFT_RENDERMODE      3
#define G_MDSFT_BLENDER         16

/*
 * G_SETOTHERMODE_H sft: shift count
 */
#define G_MDSFT_ALPHADITHER     4
#define G_MDSFT_RGBDITHER       6
#define G_MDSFT_COMBKEY         8
#define G_MDSFT_TEXTCONV        9
#define G_MDSFT_TEXTFILT        12
#define G_MDSFT_TEXTLUT         14
#define G_MDSFT_TEXTLOD         16
#define G_MDSFT_TEXTDETAIL      17
#define G_MDSFT_TEXTPERSP       19
#define G_MDSFT_CYCLETYPE       20
#define G_MDSFT_COLORDITHER     22  /* Needed for OoT ucode_disas even though HW 1.0 only */
#define G_MDSFT_PIPELINE        23

/* G_SETOTHERMODE_H gPipelineMode */
#define G_PM_NPRIMITIVE     (0 << G_MDSFT_PIPELINE)
#ifdef KAZE_GBI_HACKS
#define G_PM_1PRIMITIVE     G_PM_NPRIMITIVE
#else
#define G_PM_1PRIMITIVE     (1 << G_MDSFT_PIPELINE)
#endif

/* G_SETOTHERMODE_H gSetCycleType */
#define G_CYC_1CYCLE        (0 << G_MDSFT_CYCLETYPE)
#define G_CYC_2CYCLE        (1 << G_MDSFT_CYCLETYPE)
#define G_CYC_COPY          (2 << G_MDSFT_CYCLETYPE)
#define G_CYC_FILL          (3 << G_MDSFT_CYCLETYPE)

/* G_SETOTHERMODE_H gSetTexturePersp */
#define G_TP_NONE           (0 << G_MDSFT_TEXTPERSP)
#define G_TP_PERSP          (1 << G_MDSFT_TEXTPERSP)

/* G_SETOTHERMODE_H gSetTextureDetail */
#define G_TD_CLAMP          (0 << G_MDSFT_TEXTDETAIL)
#define G_TD_SHARPEN        (1 << G_MDSFT_TEXTDETAIL)
#define G_TD_DETAIL         (2 << G_MDSFT_TEXTDETAIL)

/* G_SETOTHERMODE_H gSetTextureLOD */
#define G_TL_TILE           (0 << G_MDSFT_TEXTLOD)
#define G_TL_LOD            (1 << G_MDSFT_TEXTLOD)

/* G_SETOTHERMODE_H gSetTextureLUT */
#define G_TT_NONE           (0 << G_MDSFT_TEXTLUT)
#define G_TT_RGBA16         (2 << G_MDSFT_TEXTLUT)
#define G_TT_IA16           (3 << G_MDSFT_TEXTLUT)

/* G_SETOTHERMODE_H gSetTextureFilter */
#define G_TF_POINT          (0 << G_MDSFT_TEXTFILT)
#define G_TF_AVERAGE        (3 << G_MDSFT_TEXTFILT)
#define G_TF_BILERP         (2 << G_MDSFT_TEXTFILT)

/* G_SETOTHERMODE_H gSetTextureConvert */
#define G_TC_CONV           (0 << G_MDSFT_TEXTCONV)
#define G_TC_FILTCONV       (5 << G_MDSFT_TEXTCONV)
#define G_TC_FILT           (6 << G_MDSFT_TEXTCONV)

/* G_SETOTHERMODE_H gSetCombineKey */
#define G_CK_NONE           (0 << G_MDSFT_COMBKEY)
#define G_CK_KEY            (1 << G_MDSFT_COMBKEY)

/* G_SETOTHERMODE_H gSetColorDither */
#define G_CD_MAGICSQ        (0 << G_MDSFT_RGBDITHER)
#define G_CD_BAYER          (1 << G_MDSFT_RGBDITHER)
#define G_CD_NOISE          (2 << G_MDSFT_RGBDITHER)
#define G_CD_DISABLE        (3 << G_MDSFT_RGBDITHER)

/* G_SETOTHERMODE_H gSetAlphaDither */
#define G_AD_PATTERN        (0 << G_MDSFT_ALPHADITHER)
#define G_AD_NOTPATTERN     (1 << G_MDSFT_ALPHADITHER)
#define G_AD_NOISE          (2 << G_MDSFT_ALPHADITHER)
#define G_AD_DISABLE        (3 << G_MDSFT_ALPHADITHER)

/* G_SETOTHERMODE_L gSetAlphaCompare */
#define G_AC_NONE           (0 << G_MDSFT_ALPHACOMPARE)
#define G_AC_THRESHOLD      (1 << G_MDSFT_ALPHACOMPARE)
#define G_AC_DITHER         (3 << G_MDSFT_ALPHACOMPARE)

/* G_SETOTHERMODE_L gSetDepthSource */
#define G_ZS_PIXEL          (0 << G_MDSFT_ZSRCSEL)
#define G_ZS_PRIM           (1 << G_MDSFT_ZSRCSEL)

#ifdef DISABLE_AA
/* Disables antialiasing in all preset rendermodes, saving RDP time. Note that
this does NOT disable antialiasing in manually written rendermodes, e.g.
exported from fast64 with advanced options enabled. We can't redefine the real
IM_RD because IM_RD is needed for transparency also, and we can't distinguish
between a manually written rendermode using IM_RD for transparency and one using
it for antialiasing. */
#define AA_DEF 0
#define RD_DEF 0
#else
#define AA_DEF AA_EN
#define RD_DEF IM_RD
#endif

/* G_SETOTHERMODE_L gSetRenderMode */
#define AA_EN           0x0008
#define Z_CMP           0x0010
#define Z_UPD           0x0020
#define IM_RD           0x0040
#define CLR_ON_CVG      0x0080
#define CVG_DST_CLAMP   0x0000
#define CVG_DST_WRAP    0x0100
#define CVG_DST_FULL    0x0200
#define CVG_DST_SAVE    0x0300
#define ZMODE_OPA       0x0000
#define ZMODE_INTER     0x0400
#define ZMODE_XLU       0x0800
#define ZMODE_DEC       0x0C00
#define CVG_X_ALPHA     0x1000
#define ALPHA_CVG_SEL   0x2000
#define FORCE_BL        0x4000
#define TEX_EDGE        0x0000  /* not in HW V2; is 0x8000 in older HW */

#define G_BL_CLR_IN     0
#define G_BL_CLR_MEM    1
#define G_BL_CLR_BL     2
#define G_BL_CLR_FOG    3
#define G_BL_1MA        0
#define G_BL_A_MEM      1
#define G_BL_A_IN       0
#define G_BL_A_FOG      1
#define G_BL_A_SHADE    2
#define G_BL_1          2
#define G_BL_0          3

#define GBL_c1(m1a, m1b, m2a, m2b)  \
    (m1a) << 30 | (m1b) << 26 | (m2a) << 22 | (m2b) << 18
#define GBL_c2(m1a, m1b, m2a, m2b)  \
    (m1a) << 28 | (m1b) << 24 | (m2a) << 20 | (m2b) << 16

#define RM_AA_ZB_OPA_SURF(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |           \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_RA_ZB_OPA_SURF(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | CVG_DST_CLAMP |                    \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_XLU_SURF(clk)                                  \
    AA_DEF | Z_CMP | IM_RD | CVG_DST_WRAP | CLR_ON_CVG |        \
    FORCE_BL | ZMODE_XLU |                                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_OPA_DECAL(clk)                                 \
    AA_DEF | Z_CMP | RD_DEF | CVG_DST_WRAP | ALPHA_CVG_SEL |    \
    ZMODE_DEC |                                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_RA_ZB_OPA_DECAL(clk)                                 \
    AA_DEF | Z_CMP | CVG_DST_WRAP | ALPHA_CVG_SEL |             \
    ZMODE_DEC |                                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_XLU_DECAL(clk)                                 \
    AA_DEF | Z_CMP | IM_RD | CVG_DST_WRAP | CLR_ON_CVG |        \
    FORCE_BL | ZMODE_DEC |                                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_OPA_INTER(clk)                                 \
    AA_DEF | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |           \
    ALPHA_CVG_SEL | ZMODE_INTER |                               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_RA_ZB_OPA_INTER(clk)                                 \
    AA_DEF | Z_CMP | Z_UPD | CVG_DST_CLAMP |                    \
    ALPHA_CVG_SEL | ZMODE_INTER |                               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_XLU_INTER(clk)                                 \
    AA_DEF | Z_CMP | IM_RD | CVG_DST_WRAP | CLR_ON_CVG |        \
    FORCE_BL | ZMODE_INTER |                                    \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_XLU_LINE(clk)                                  \
    AA_DEF | Z_CMP | IM_RD | CVG_DST_CLAMP | CVG_X_ALPHA |      \
    ALPHA_CVG_SEL | FORCE_BL | ZMODE_XLU |                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_DEC_LINE(clk)                                  \
    AA_DEF | Z_CMP | IM_RD | CVG_DST_SAVE | CVG_X_ALPHA |       \
    ALPHA_CVG_SEL | FORCE_BL | ZMODE_DEC |                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

/* Note that this uses AA_EN not AA_DEF */
#define RM_AA_ZB_TEX_EDGE(clk)                                  \
    AA_EN | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |            \
    CVG_X_ALPHA | ALPHA_CVG_SEL | ZMODE_OPA | TEX_EDGE |        \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_TEX_INTER(clk)                                 \
    AA_DEF | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |           \
    CVG_X_ALPHA | ALPHA_CVG_SEL | ZMODE_INTER | TEX_EDGE |      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_SUB_SURF(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | IM_RD | CVG_DST_FULL |             \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_ZB_PCL_SURF(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | IM_RD | CVG_DST_CLAMP |            \
    ZMODE_OPA | G_AC_DITHER |                                   \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_OPA_TERR(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |           \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_TEX_TERR(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | RD_DEF | CVG_DST_CLAMP |           \
    CVG_X_ALPHA | ALPHA_CVG_SEL | ZMODE_OPA | TEX_EDGE |        \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_ZB_SUB_TERR(clk)                                  \
    AA_DEF | Z_CMP | Z_UPD | IM_RD | CVG_DST_FULL |             \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)


#define RM_AA_OPA_SURF(clk)                                     \
    AA_DEF | RD_DEF | CVG_DST_CLAMP |                           \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_RA_OPA_SURF(clk)                                     \
    AA_DEF | CVG_DST_CLAMP |                                    \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_XLU_SURF(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_WRAP | CLR_ON_CVG | FORCE_BL |     \
    ZMODE_OPA |                                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_XLU_LINE(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_CLAMP | CVG_X_ALPHA |              \
    ALPHA_CVG_SEL | FORCE_BL | ZMODE_OPA |                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_DEC_LINE(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_FULL | CVG_X_ALPHA |               \
    ALPHA_CVG_SEL | FORCE_BL | ZMODE_OPA |                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

/* Note that this uses AA_EN not AA_DEF */
#define RM_AA_TEX_EDGE(clk)                                     \
    AA_EN | RD_DEF | CVG_DST_CLAMP |                            \
    CVG_X_ALPHA | ALPHA_CVG_SEL | ZMODE_OPA | TEX_EDGE |        \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_SUB_SURF(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_FULL |                             \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_AA_PCL_SURF(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_CLAMP |                            \
    ZMODE_OPA | G_AC_DITHER |                                   \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_OPA_TERR(clk)                                     \
    AA_DEF | RD_DEF | CVG_DST_CLAMP |                           \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_TEX_TERR(clk)                                     \
    AA_DEF | RD_DEF | CVG_DST_CLAMP |                           \
    CVG_X_ALPHA | ALPHA_CVG_SEL | ZMODE_OPA | TEX_EDGE |        \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_AA_SUB_TERR(clk)                                     \
    AA_DEF | IM_RD | CVG_DST_FULL |                             \
    ZMODE_OPA | ALPHA_CVG_SEL |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)


#define RM_ZB_OPA_SURF(clk)                                     \
    Z_CMP | Z_UPD | CVG_DST_FULL | ALPHA_CVG_SEL |              \
    ZMODE_OPA |                                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_ZB_XLU_SURF(clk)                                     \
    Z_CMP | IM_RD | CVG_DST_FULL | FORCE_BL | ZMODE_XLU |       \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_ZB_OPA_DECAL(clk)                                    \
    Z_CMP | CVG_DST_FULL | ALPHA_CVG_SEL | ZMODE_DEC |          \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_A_MEM)

#define RM_ZB_XLU_DECAL(clk)                                    \
    Z_CMP | IM_RD | CVG_DST_FULL | FORCE_BL | ZMODE_DEC |       \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_ZB_CLD_SURF(clk)                                     \
    Z_CMP | IM_RD | CVG_DST_SAVE | FORCE_BL | ZMODE_XLU |       \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_ZB_OVL_SURF(clk)                                     \
    Z_CMP | IM_RD | CVG_DST_SAVE | FORCE_BL | ZMODE_DEC |       \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_ZB_PCL_SURF(clk)                                     \
    Z_CMP | Z_UPD | CVG_DST_FULL | ZMODE_OPA |                  \
    G_AC_DITHER |                                               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)


#define RM_OPA_SURF(clk)                                        \
    CVG_DST_CLAMP | FORCE_BL | ZMODE_OPA |                      \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)

#define RM_XLU_SURF(clk)                                        \
    IM_RD | CVG_DST_FULL | FORCE_BL | ZMODE_OPA |               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_TEX_EDGE(clk)                                        \
    CVG_DST_CLAMP | CVG_X_ALPHA | ALPHA_CVG_SEL | FORCE_BL |    \
    ZMODE_OPA | TEX_EDGE | AA_EN |                              \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)

#define RM_CLD_SURF(clk)                                        \
    IM_RD | CVG_DST_SAVE | FORCE_BL | ZMODE_OPA |               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_IN, G_BL_CLR_MEM, G_BL_1MA)

#define RM_PCL_SURF(clk)                                        \
    CVG_DST_FULL | FORCE_BL | ZMODE_OPA |                       \
    G_AC_DITHER |                                               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)

#define RM_ADD(clk)                                             \
    IM_RD | CVG_DST_SAVE | FORCE_BL | ZMODE_OPA |               \
    GBL_c##clk(G_BL_CLR_IN, G_BL_A_FOG, G_BL_CLR_MEM, G_BL_1)

#define RM_NOOP(clk)    \
    GBL_c##clk(0, 0, 0, 0)

#define RM_VISCVG(clk)                                          \
    IM_RD | FORCE_BL |                                          \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_BL, G_BL_A_MEM)

/* for rendering to an 8-bit framebuffer */
#define RM_OPA_CI(clk)                                          \
    CVG_DST_CLAMP | ZMODE_OPA |                                 \
    GBL_c##clk(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)

/* Custom version of RM_AA_ZB_XLU_SURF with Z_UPD */
#define RM_CUSTOM_AA_ZB_XLU_SURF(clk)				\
	RM_AA_ZB_XLU_SURF(clk) | Z_UPD

#define G_RM_CUSTOM_AA_ZB_XLU_SURF	RM_CUSTOM_AA_ZB_XLU_SURF(1)
#define G_RM_CUSTOM_AA_ZB_XLU_SURF2	RM_CUSTOM_AA_ZB_XLU_SURF(2)

#define G_RM_AA_ZB_OPA_SURF     RM_AA_ZB_OPA_SURF(1)
#define G_RM_AA_ZB_OPA_SURF2    RM_AA_ZB_OPA_SURF(2)
#define G_RM_AA_ZB_XLU_SURF     RM_AA_ZB_XLU_SURF(1)
#define G_RM_AA_ZB_XLU_SURF2    RM_AA_ZB_XLU_SURF(2)
#define G_RM_AA_ZB_OPA_DECAL    RM_AA_ZB_OPA_DECAL(1)
#define G_RM_AA_ZB_OPA_DECAL2   RM_AA_ZB_OPA_DECAL(2)
#define G_RM_AA_ZB_XLU_DECAL    RM_AA_ZB_XLU_DECAL(1)
#define G_RM_AA_ZB_XLU_DECAL2   RM_AA_ZB_XLU_DECAL(2)
#define G_RM_AA_ZB_OPA_INTER    RM_AA_ZB_OPA_INTER(1)
#define G_RM_AA_ZB_OPA_INTER2   RM_AA_ZB_OPA_INTER(2)
#define G_RM_AA_ZB_XLU_INTER    RM_AA_ZB_XLU_INTER(1)
#define G_RM_AA_ZB_XLU_INTER2   RM_AA_ZB_XLU_INTER(2)
#define G_RM_AA_ZB_XLU_LINE     RM_AA_ZB_XLU_LINE(1)
#define G_RM_AA_ZB_XLU_LINE2    RM_AA_ZB_XLU_LINE(2)
#define G_RM_AA_ZB_DEC_LINE     RM_AA_ZB_DEC_LINE(1)
#define G_RM_AA_ZB_DEC_LINE2    RM_AA_ZB_DEC_LINE(2)
#define G_RM_AA_ZB_TEX_EDGE     RM_AA_ZB_TEX_EDGE(1)
#define G_RM_AA_ZB_TEX_EDGE2    RM_AA_ZB_TEX_EDGE(2)
#define G_RM_AA_ZB_TEX_INTER    RM_AA_ZB_TEX_INTER(1)
#define G_RM_AA_ZB_TEX_INTER2   RM_AA_ZB_TEX_INTER(2)
#define G_RM_AA_ZB_SUB_SURF     RM_AA_ZB_SUB_SURF(1)
#define G_RM_AA_ZB_SUB_SURF2    RM_AA_ZB_SUB_SURF(2)
#define G_RM_AA_ZB_PCL_SURF     RM_AA_ZB_PCL_SURF(1)
#define G_RM_AA_ZB_PCL_SURF2    RM_AA_ZB_PCL_SURF(2)
#define G_RM_AA_ZB_OPA_TERR     RM_AA_ZB_OPA_TERR(1)
#define G_RM_AA_ZB_OPA_TERR2    RM_AA_ZB_OPA_TERR(2)
#define G_RM_AA_ZB_TEX_TERR     RM_AA_ZB_TEX_TERR(1)
#define G_RM_AA_ZB_TEX_TERR2    RM_AA_ZB_TEX_TERR(2)
#define G_RM_AA_ZB_SUB_TERR     RM_AA_ZB_SUB_TERR(1)
#define G_RM_AA_ZB_SUB_TERR2    RM_AA_ZB_SUB_TERR(2)

#define G_RM_RA_ZB_OPA_SURF     RM_RA_ZB_OPA_SURF(1)
#define G_RM_RA_ZB_OPA_SURF2    RM_RA_ZB_OPA_SURF(2)
#define G_RM_RA_ZB_OPA_DECAL    RM_RA_ZB_OPA_DECAL(1)
#define G_RM_RA_ZB_OPA_DECAL2   RM_RA_ZB_OPA_DECAL(2)
#define G_RM_RA_ZB_OPA_INTER    RM_RA_ZB_OPA_INTER(1)
#define G_RM_RA_ZB_OPA_INTER2   RM_RA_ZB_OPA_INTER(2)

#define G_RM_AA_OPA_SURF    RM_AA_OPA_SURF(1)
#define G_RM_AA_OPA_SURF2   RM_AA_OPA_SURF(2)
#define G_RM_AA_XLU_SURF    RM_AA_XLU_SURF(1)
#define G_RM_AA_XLU_SURF2   RM_AA_XLU_SURF(2)
#define G_RM_AA_XLU_LINE    RM_AA_XLU_LINE(1)
#define G_RM_AA_XLU_LINE2   RM_AA_XLU_LINE(2)
#define G_RM_AA_DEC_LINE    RM_AA_DEC_LINE(1)
#define G_RM_AA_DEC_LINE2   RM_AA_DEC_LINE(2)
#define G_RM_AA_TEX_EDGE    RM_AA_TEX_EDGE(1)
#define G_RM_AA_TEX_EDGE2   RM_AA_TEX_EDGE(2)
#define G_RM_AA_SUB_SURF    RM_AA_SUB_SURF(1)
#define G_RM_AA_SUB_SURF2   RM_AA_SUB_SURF(2)
#define G_RM_AA_PCL_SURF    RM_AA_PCL_SURF(1)
#define G_RM_AA_PCL_SURF2   RM_AA_PCL_SURF(2)
#define G_RM_AA_OPA_TERR    RM_AA_OPA_TERR(1)
#define G_RM_AA_OPA_TERR2   RM_AA_OPA_TERR(2)
#define G_RM_AA_TEX_TERR    RM_AA_TEX_TERR(1)
#define G_RM_AA_TEX_TERR2   RM_AA_TEX_TERR(2)
#define G_RM_AA_SUB_TERR    RM_AA_SUB_TERR(1)
#define G_RM_AA_SUB_TERR2   RM_AA_SUB_TERR(2)

#define G_RM_RA_OPA_SURF    RM_RA_OPA_SURF(1)
#define G_RM_RA_OPA_SURF2   RM_RA_OPA_SURF(2)

#define G_RM_ZB_OPA_SURF    RM_ZB_OPA_SURF(1)
#define G_RM_ZB_OPA_SURF2   RM_ZB_OPA_SURF(2)
#define G_RM_ZB_XLU_SURF    RM_ZB_XLU_SURF(1)
#define G_RM_ZB_XLU_SURF2   RM_ZB_XLU_SURF(2)
#define G_RM_ZB_OPA_DECAL   RM_ZB_OPA_DECAL(1)
#define G_RM_ZB_OPA_DECAL2  RM_ZB_OPA_DECAL(2)
#define G_RM_ZB_XLU_DECAL   RM_ZB_XLU_DECAL(1)
#define G_RM_ZB_XLU_DECAL2  RM_ZB_XLU_DECAL(2)
#define G_RM_ZB_CLD_SURF    RM_ZB_CLD_SURF(1)
#define G_RM_ZB_CLD_SURF2   RM_ZB_CLD_SURF(2)
#define G_RM_ZB_OVL_SURF    RM_ZB_OVL_SURF(1)
#define G_RM_ZB_OVL_SURF2   RM_ZB_OVL_SURF(2)
#define G_RM_ZB_PCL_SURF    RM_ZB_PCL_SURF(1)
#define G_RM_ZB_PCL_SURF2   RM_ZB_PCL_SURF(2)

#define G_RM_OPA_SURF       RM_OPA_SURF(1)
#define G_RM_OPA_SURF2      RM_OPA_SURF(2)
#define G_RM_XLU_SURF       RM_XLU_SURF(1)
#define G_RM_XLU_SURF2      RM_XLU_SURF(2)
#define G_RM_CLD_SURF       RM_CLD_SURF(1)
#define G_RM_CLD_SURF2      RM_CLD_SURF(2)
#define G_RM_TEX_EDGE       RM_TEX_EDGE(1)
#define G_RM_TEX_EDGE2      RM_TEX_EDGE(2)
#define G_RM_PCL_SURF       RM_PCL_SURF(1)
#define G_RM_PCL_SURF2      RM_PCL_SURF(2)
#define G_RM_ADD            RM_ADD(1)
#define G_RM_ADD2           RM_ADD(2)
#define G_RM_NOOP           RM_NOOP(1)
#define G_RM_NOOP2          RM_NOOP(2)
#define G_RM_VISCVG         RM_VISCVG(1)
#define G_RM_VISCVG2        RM_VISCVG(2)
#define G_RM_OPA_CI         RM_OPA_CI(1)
#define G_RM_OPA_CI2        RM_OPA_CI(2)


#define G_RM_FOG_SHADE_A    GBL_c1(G_BL_CLR_FOG, G_BL_A_SHADE, G_BL_CLR_IN, G_BL_1MA)
#define G_RM_FOG_PRIM_A     GBL_c1(G_BL_CLR_FOG, G_BL_A_FOG, G_BL_CLR_IN, G_BL_1MA)
#define G_RM_PASS           GBL_c1(G_BL_CLR_IN, G_BL_0, G_BL_CLR_IN, G_BL_1)

/*
 * G_SETCONVERT: K0-5
 */
#define G_CV_K0     175
#define G_CV_K1     -43
#define G_CV_K2     -89
#define G_CV_K3     222
#define G_CV_K4     114
#define G_CV_K5     42

/*
 * G_SETSCISSOR: interlace mode
 */
#define G_SC_NON_INTERLACE  0
#define G_SC_ODD_INTERLACE  3
#define G_SC_EVEN_INTERLACE 2


#endif // GBI_RDP_DEFINES_H
