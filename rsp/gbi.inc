// GBI: Graphics Binary Interface

// XBUS doesn't use the full yield data buffer, but does reference the full size,
// so a definition for both sizes needs to exist.
OS_YIELD_DATA_SIZE_TOTAL equ 0xC00
.if UCODE_METHOD == METHOD_FIFO
OS_YIELD_DATA_SIZE equ 0xC00
.else // UCODE_METHOD == METHOD_XBUS
OS_YIELD_DATA_SIZE equ 0x920
.endif

// Geometry mode flags
// First byte gets OR'd with 0xC8 to form triangle opcode. So we can use 0x80,
// 0x40, and 0x08 for other purposes while remaining forward compatible. (Of
// course, if you only care about backward compatibility, you can AND 0x07
// before the OR 0xC8 and use all the extra bits.) Note that backward compatible
// means a new/modded microcode will run old/vanilla DLs correctly, and forward
// compatible means an old/vanilla microcode will run DLs made for a new/modded
// microcode without any problems besides the specific new features missing.
G_ZBUFFER               equ 0x00000001
G_TEXTURE_ENABLE        equ 0x00000002
G_SHADE                 equ 0x00000004
// In this byte, the whole byte is used as an index into a table, so using any
// other bits will break forwards compatibility. Again, if you only want
// backwards compatibility, AND 0x06 when this is loaded and then you can use
// all six other bits.
G_CULL_FRONT            equ 0x00000200
G_CULL_BACK             equ 0x00000400
G_CULL_BOTH             equ 0x00000600
G_FOG                   equ 0x00010000
G_LIGHTING              equ 0x00020000
G_TEXTURE_GEN           equ 0x00040000
G_TEXTURE_GEN_LINEAR    equ 0x00080000
G_LOD                   equ 0x00100000 // Not used in any ucodes in repo
G_SHADING_SMOOTH        equ 0x00200000
G_LIGHTING_POSITIONAL   equ 0x00400000
G_CLIPPING              equ 0x00800000 // Initially on, but never checked
// The top byte holds the geometry mode opcode in the clear mask, so all its
// bits will either get cleared every time geom mode is set, or can never be
// cleared. The info in gbi.h warning programmers not to use the high 8 bits
// because they form a "clip code mask" is kind of irrelevant given that these
// bits can't be properly set or cleared.

G_FOG_H                 equ G_FOG / 0x10000
G_LIGHTING_H            equ G_LIGHTING / 0x10000
G_TEXTURE_GEN_H         equ G_TEXTURE_GEN / 0x10000
G_TEXTURE_GEN_LINEAR_H  equ G_TEXTURE_GEN_LINEAR / 0x10000
G_LOD_H                 equ G_LOD / 0x10000
G_SHADING_SMOOTH_H      equ G_SHADING_SMOOTH / 0x10000
G_LIGHTING_POSITIONAL_H equ G_LIGHTING_POSITIONAL / 0x10000
G_CLIPPING_H            equ G_CLIPPING / 0x10000

// dma
G_NOOP            equ 0x00
G_RDPHALF_2       equ 0xf1
G_SETOTHERMODE_H  equ 0xe3
G_SETOTHERMODE_L  equ 0xe2
G_RDPHALF_1       equ 0xe1
G_SPNOOP          equ 0xe0
G_ENDDL           equ 0xdf
G_DL              equ 0xde
G_LOAD_UCODE      equ 0xdd
G_MOVEMEM         equ 0xdc
G_MOVEWORD        equ 0xdb
G_MTX             equ 0xda
G_GEOMETRYMODE    equ 0xd9
G_POPMTX          equ 0xd8
G_TEXTURE         equ 0xd7
G_DMA_IO          equ 0xd6
G_SPECIAL_1       equ 0xd5
G_SPECIAL_2       equ 0xd4
G_SPECIAL_3       equ 0xd3

// immediate
G_VTX             equ 0x01
G_MODIFYVTX       equ 0x02
G_CULLDL          equ 0x03
G_BRANCH_Z        equ 0x04
G_TRI1            equ 0x05
G_TRI2            equ 0x06
G_QUAD            equ 0x07
G_LINE3D          equ 0x08

// rdp
G_SETCIMG         equ 0xff
G_SETZIMG         equ 0xfe
G_SETTIMG         equ 0xfd
G_SETCOMBINE      equ 0xfc
G_SETENVCOLOR     equ 0xfb
G_SETPRIMCOLOR    equ 0xfa
G_SETBLENDCOLOR   equ 0xf9
G_SETFOGCOLOR     equ 0xf8
G_SETFILLCOLOR    equ 0xf7
G_FILLRECT        equ 0xf6
G_SETTILE         equ 0xf5
G_LOADTILE        equ 0xf4
G_LOADBLOCK       equ 0xf3
G_SETTILESIZE     equ 0xf2
G_LOADTLUT        equ 0xf0
G_RDPSETOTHERMODE equ 0xef
G_SETPRIMDEPTH    equ 0xee
G_SETSCISSOR      equ 0xed
G_SETCONVERT      equ 0xec
G_SETKEYR         equ 0xeb
G_SETKEYGB        equ 0xea
G_RDPFULLSYNC     equ 0xe9
G_RDPTILESYNC     equ 0xe8
G_RDPPIPESYNC     equ 0xe7
G_RDPLOADSYNC     equ 0xe6
G_TEXRECTFLIP     equ 0xe5
G_TEXRECT         equ 0xe4

G_TRI_FILL        equ 0xc8


G_MTX_P_MV        equ 0x04
G_MTX_MUL_LOAD    equ 0x02
G_MTX_NOPUSH_PUSH equ 0x01

G_MV_MMTX     equ 0x02
G_MV_PMTX     equ 0x06
G_MV_VIEWPORT equ 0x08
G_MV_LIGHT    equ 0x0A
G_MV_POINT    equ 0x0C
G_MV_MATRIX   equ 0x0E

lightSize equ 0x18

// Input Vertex structure offsets, should match Vtx structure in gbi.h
inputVtxSize equ 0x10

  VTX_IN_OB     equ 0x00
VTX_IN_X        equ 0x00
VTX_IN_Y        equ 0x02
VTX_IN_Z        equ 0x04
VTX_IN_FLAG     equ 0x06
  VTX_IN_TC     equ 0x08
VTX_IN_S        equ 0x08
VTX_IN_T        equ 0x0A
  VTX_IN_CN     equ 0x0C // color or normal

// RSP Vertex structure offsets
vtxSize equ 0x28

  VTX_INT_VEC   equ 0x00
VTX_X_INT       equ 0x00
VTX_Y_INT       equ 0x02
VTX_Z_INT       equ 0x04
VTX_W_INT       equ 0x06
  VTX_FRAC_VEC  equ 0x08
VTX_X_FRAC      equ 0x08
VTX_Y_FRAC      equ 0x0A
VTX_Z_FRAC      equ 0x0C
VTX_W_FRAC      equ 0x0E
  VTX_COLOR_VEC equ 0x10
VTX_COLOR_R     equ 0x10
VTX_COLOR_G     equ 0x11
VTX_COLOR_B     equ 0x12
VTX_COLOR_A     equ 0x13
  VTX_TC_VEC    equ 0x14
VTX_TC_S        equ 0x14
VTX_TC_T        equ 0x16
  VTX_SCR_VEC   equ 0x18
VTX_SCR_X       equ 0x18
VTX_SCR_Y       equ 0x1A
VTX_Z           equ 0x1C
VTX_DZ          equ 0x1E
  VTX_INV_W_VEC equ 0x20
VTX_INV_W_INT   equ 0x20
VTX_INV_W_FRAC  equ 0x22
  VTX_FLAGS     equ 0x24
VTX_FLAGS_LO    equ 0x24
VTX_FLAGS_HI    equ 0x26
