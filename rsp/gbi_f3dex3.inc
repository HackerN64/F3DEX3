
G_MODIFYVTX         equ 0x02
G_CULLDL            equ 0x03
G_BRANCH_WZ         equ 0x04
G_TRI1              equ 0x05
G_TRI2              equ 0x06
G_QUAD              equ 0x07
G_TRISNAKE          equ 0x08
// nothing          equ 0x09
G_LIGHTTORDP        equ 0x0a
G_RELSEGMENT        equ 0x0b

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

G_MAX_VERTS equ 56

// RSP Vertex structure offsets
vtxSize equ 0x26

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
VTX_SCR_Z       equ 0x1C
VTX_SCR_Z_FRAC  equ 0x1E
  VTX_INV_W_VEC equ 0x20
VTX_INV_W_INT   equ 0x20
VTX_INV_W_FRAC  equ 0x22
  VTX_CLIP      equ 0x24
