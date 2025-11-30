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

// Clipping flags. 
// Initially, the bits are (for either type of clipping):
// 0-3: negative XYZW first vertex
// 4-7: negative XYZW second vertex
// 8-11: positive XYZW first vertex
// 12-15: positive XYZW second vertex
// Then, for screen clipping, the second vertex's results are shifted right 4,
// and for scaled clipping, the first vertex's results are shifted left 4.
// The results are then that the bits represent:
CLIP_SCRN_NX_SHIFT   equ 0 
CLIP_SCRN_NY_SHIFT   equ 1
//CLIP_SCRN_NZ_SHIFT equ 2 // would be nearclipping; not supported in F3DEX3
CLIP_CAMPLANE_SHIFT  equ 3 // equiv to CLIP_SCRN_NW_SHIFT; camera plane is -w in NoN
CLIP_SCAL_NX_SHIFT   equ 4
CLIP_SCAL_NY_SHIFT   equ 5
//CLIP_SCAL_NZ_SHIFT equ 6 // meaningless 
//CLIP_SCAL_NW_SHIFT equ 7 // meaningless 
CLIP_SCRN_PX_SHIFT   equ 8
CLIP_SCRN_PY_SHIFT   equ 9
//CLIP_SCRN_PZ_SHIFT equ 10 // would be farclipping; not supported in F3DEX3
CLIP_OCCLUDED_SHIFT  equ 11 // replaces meaningless CLIP_SCRN_PW_SHIFT
CLIP_SCAL_PX_SHIFT   equ 12
CLIP_SCAL_PY_SHIFT   equ 13
//CLIP_SCAL_PZ_SHIFT equ 14 // meaningless
//CLIP_SCAL_PW_SHIFT equ 15 // meaningless
CLIP_SCRN_NX  equ (1 << CLIP_SCRN_NX_SHIFT )
CLIP_SCRN_NY  equ (1 << CLIP_SCRN_NY_SHIFT )
CLIP_CAMPLANE equ (1 << CLIP_CAMPLANE_SHIFT)
CLIP_SCAL_NX  equ (1 << CLIP_SCAL_NX_SHIFT )
CLIP_SCAL_NY  equ (1 << CLIP_SCAL_NY_SHIFT )
CLIP_SCRN_PX  equ (1 << CLIP_SCRN_PX_SHIFT )
CLIP_SCRN_PY  equ (1 << CLIP_SCRN_PY_SHIFT )
CLIP_OCCLUDED equ (1 << CLIP_OCCLUDED_SHIFT)
CLIP_SCAL_PX  equ (1 << CLIP_SCAL_PX_SHIFT )
CLIP_SCAL_PY  equ (1 << CLIP_SCAL_PY_SHIFT )
// Combinations for simpler code
CLIP_SCRN_NPXY equ (CLIP_SCRN_NX | CLIP_SCRN_NY | CLIP_SCRN_PX | CLIP_SCRN_PY)
CLIP_SCAL_NPXY equ (CLIP_SCAL_NX | CLIP_SCAL_NY | CLIP_SCAL_PX | CLIP_SCAL_PY)
