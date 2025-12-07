G_TEXTURE_ENABLE      equ 0x00000002

G_FLUSH             equ 0xDC
G_GEOMETRYMODE      equ 0xDD
G_DL                equ 0xDE
G_ENDDL             equ 0xDF
G_SPNOOP            equ 0xE0
G_MOVEWORD          equ 0xE1
G_MOVEMEM           equ 0xE2
G_RDPHALF_1         equ 0xE3
//
G_RELSEGMENT        equ 0x01
G_VTX               equ 0x02
G_TRI1              equ 0x03
G_TRI2              equ 0x04

G_BRANCH_Z equ G_BRANCH_WZ
G_BRANCH_W equ G_BRANCH_WZ

// Note that load and push are inverted in the GBI encoding.
G_MTX_VP_M        equ 0x04  // Binary: set for VP, clear for M
G_MTX_MUL_LOAD    equ 0x02  // Binary: set for mul, clear for load
G_MTX_NOPUSH_PUSH equ 0x01  // Binary: set for nopush, clear for push

G_MV_MMTX     equ 0x00
G_MV_TEMPMTX0 equ 0x02
G_MV_VPMTX    equ 0x04
G_MV_TEMPMTX1 equ 0x06
G_MV_VIEWPORT equ 0x08
G_MV_LIGHT    equ 0x0A

ZMODE_DEC equ 0x0C00  // from othermode low; the value is the mask

G_MAX_LIGHTS equ 9 // 9 directional / point lights, plus ambient light (and lookat)
lightSize equ 0x10

G_MAX_VERTS equ 104

// RSP Vertex structure offsets
vtxSize equ 0x16

  VTX_COLOR_VEC equ 0x00
VTX_COLOR_R     equ 0x00
VTX_COLOR_G     equ 0x01
VTX_COLOR_B     equ 0x02
VTX_COLOR_A     equ 0x03
  VTX_TC_VEC    equ 0x04
VTX_TC_S        equ 0x04
VTX_TC_T        equ 0x06
  VTX_SCR_VEC   equ 0x08
VTX_SCR_X       equ 0x08
VTX_SCR_Y       equ 0x0A
VTX_SCR_Z       equ 0x0C
VTX_SCR_Z_FRAC  equ 0x0E
  VTX_INV_W_VEC equ 0x10
VTX_INV_W_INT   equ 0x10
VTX_INV_W_FRAC  equ 0x12
  VTX_CLIP      equ 0x14
