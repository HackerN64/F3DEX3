G_TEXTURE_ENABLE      equ 0x00000002

G_FLUSH             equ 0xDD
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

mtxSize equ 0x50

// RSP Vertex structure offsets
vtxSize equ 0x14

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
  VTX_CLIP      equ 0x0E
  VTX_INV_W_VEC equ 0x10
VTX_INV_W_INT   equ 0x10
VTX_INV_W_FRAC  equ 0x12
