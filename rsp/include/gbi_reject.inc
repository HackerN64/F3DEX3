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
