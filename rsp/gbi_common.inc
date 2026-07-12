// GBI: Graphics Binary Interface

G_TRI_FILL          equ 0xc8 // not a GBI command

G_TEXRECT           equ 0xe4
G_TEXRECTFLIP       equ 0xe5
G_RDPLOADSYNC       equ 0xe6
G_RDPPIPESYNC       equ 0xe7
G_RDPTILESYNC       equ 0xe8
G_RDPFULLSYNC       equ 0xe9
G_SETKEYGB          equ 0xea
G_SETKEYR           equ 0xeb
G_SETCONVERT        equ 0xec
G_SETSCISSOR        equ 0xed
G_SETPRIMDEPTH      equ 0xee
G_RDPSETOTHERMODE   equ 0xef
G_LOADTLUT          equ 0xf0
G_RDPHALF_2         equ 0xf1
G_SETTILESIZE       equ 0xf2
G_LOADBLOCK         equ 0xf3
G_LOADTILE          equ 0xf4
G_SETTILE           equ 0xf5
G_FILLRECT          equ 0xf6
G_SETFILLCOLOR      equ 0xf7
G_SETFOGCOLOR       equ 0xf8
G_SETBLENDCOLOR     equ 0xf9
G_SETPRIMCOLOR      equ 0xfa
G_SETENVCOLOR       equ 0xfb
G_SETCOMBINE        equ 0xfc
G_SETTIMG           equ 0xfd
G_SETZIMG           equ 0xfe
G_SETCIMG           equ 0xff
G_NOOP              equ 0x00


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
