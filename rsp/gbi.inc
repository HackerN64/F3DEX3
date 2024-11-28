// GBI: Graphics Binary Interface

// Geometry mode flags
// First byte gets OR'd with G_TRI_FILL (0xC8) to form triangle opcode. Enabling
// textures is done through SPTexture; G_TEXTURE_ENABLE is defined in the
// GBI to 0. Binary display lists with this set will likely crash.
G_ZBUFFER               equ 0x00000001
//G_TEXTURE_ENABLE      equ 0x00000002
G_SHADE                 equ 0x00000004
G_AMBOCCLUSION          equ 0x00000040
G_ATTROFFSET_ST_ENABLE  equ 0x00000100
// Bits 9 and 10 (0x0600) determine front/backface culling.
G_CULL_NEITHER          equ 0x00000000
G_CULL_FRONT            equ 0x00000200
G_CULL_BACK             equ 0x00000400
G_CULL_BOTH             equ 0x00000600
G_PACKED_NORMALS        equ 0x00000800
G_LIGHTTOALPHA          equ 0x00001000
G_LIGHTING_SPECULAR     equ 0x00002000
G_FRESNEL_COLOR         equ 0x00004000
G_FRESNEL_ALPHA         equ 0x00008000
G_FOG                   equ 0x00010000
G_LIGHTING              equ 0x00020000
G_TEXTURE_GEN           equ 0x00040000
G_TEXTURE_GEN_LINEAR    equ 0x00080000
//G_LOD                 equ 0x00100000 // Ignored by all F3DEX* variants
G_SHADING_SMOOTH        equ 0x00200000
//G_LIGHTING_POSITIONAL equ 0x00400000 // Ignored by F3DEX3, assumed always on
//G_CLIPPING            equ 0x00800000 // Ignored by all F3DEX* variants
// The top byte holds the geometry mode opcode.

G_TRI_FILL          equ 0xc8 // not a GBI command

G_MEMSET            equ 0xd5
G_DMA_IO            equ 0xd6
G_TEXTURE           equ 0xd7
G_POPMTX            equ 0xd8
G_GEOMETRYMODE      equ 0xd9
G_MTX               equ 0xda
G_MOVEWORD          equ 0xdb
G_MOVEMEM           equ 0xdc
G_LOAD_UCODE        equ 0xdd
G_DL                equ 0xde
G_ENDDL             equ 0xdf
G_SPNOOP            equ 0xe0
G_RDPHALF_1         equ 0xe1
G_SETOTHERMODE_L    equ 0xe2
G_SETOTHERMODE_H    equ 0xe3
G_TEXRECT           equ 0xe4
G_TEXRECTFLIP       equ 0xe5
// G_RDP_handler group start v
G_RDPLOADSYNC       equ 0xe6
G_RDPPIPESYNC       equ 0xe7
G_RDPTILESYNC       equ 0xe8
G_RDPFULLSYNC       equ 0xe9
G_SETKEYGB          equ 0xea
G_SETKEYR           equ 0xeb
G_SETCONVERT        equ 0xec
G_SETSCISSOR        equ 0xed // scis/oth handler
G_SETPRIMDEPTH      equ 0xee
G_RDPSETOTHERMODE   equ 0xef // scis/oth handler
G_LOADTLUT          equ 0xf0 // load handler
G_RDPHALF_2         equ 0xf1 // own handler
G_SETTILESIZE       equ 0xf2
G_LOADBLOCK         equ 0xf3 // load handler
G_LOADTILE          equ 0xf4 // load handler
G_SETTILE           equ 0xf5
G_FILLRECT          equ 0xf6
G_SETFILLCOLOR      equ 0xf7
G_SETFOGCOLOR       equ 0xf8
G_SETBLENDCOLOR     equ 0xf9
G_SETPRIMCOLOR      equ 0xfa
G_SETENVCOLOR       equ 0xfb
G_SETCOMBINE        equ 0xfc
// G_RDP_handler group end ^
G_SETTIMG           equ 0xfd
G_SETZIMG           equ 0xfe
G_SETCIMG           equ 0xff
G_NOOP              equ 0x00
// Second table start v
G_VTX               equ 0x01
G_MODIFYVTX         equ 0x02
G_CULLDL            equ 0x03
G_BRANCH_WZ         equ 0x04
G_TRI1              equ 0x05
G_TRI2              equ 0x06
G_QUAD              equ 0x07
G_TRISTRIP          equ 0x08
G_TRIFAN            equ 0x09
G_LIGHTTORDP        equ 0x0a
G_RELSEGMENT        equ 0x0b


G_BRANCH_Z equ G_BRANCH_WZ
G_BRANCH_W equ G_BRANCH_WZ

G_MTX_P_MV        equ 0x04
G_MTX_MUL_LOAD    equ 0x02
G_MTX_NOPUSH_PUSH equ 0x01

G_MV_MMTX     equ 0x02
G_MV_PMTX     equ 0x06
G_MV_VIEWPORT equ 0x08
G_MV_LIGHT    equ 0x0A

G_NORMALSMODE_FAST equ 0x00
G_NORMALSMODE_AUTO equ 0x01
G_NORMALSMODE_MANUAL equ 0x02

ZMODE_DEC equ 0x0C00  // from othermode low; the value is the mask

G_MAX_LIGHTS equ 9 // 9 directional / point lights, plus ambient light (and lookat)
lightSize equ 0x10

G_MAX_VERTS equ 56

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
CLIP_VTX_USED_SHIFT  equ 6 // replaces meaningless CLIP_SCAL_NZ_SHIFT
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
CLIP_VTX_USED equ (1 << CLIP_VTX_USED_SHIFT)
CLIP_SCRN_PX  equ (1 << CLIP_SCRN_PX_SHIFT )
CLIP_SCRN_PY  equ (1 << CLIP_SCRN_PY_SHIFT )
CLIP_OCCLUDED equ (1 << CLIP_OCCLUDED_SHIFT)
CLIP_SCAL_PX  equ (1 << CLIP_SCAL_PX_SHIFT )
CLIP_SCAL_PY  equ (1 << CLIP_SCAL_PY_SHIFT )
// Combinations for simpler code
CLIP_SCRN_NPXY equ (CLIP_SCRN_NX | CLIP_SCRN_NY | CLIP_SCRN_PX | CLIP_SCRN_PY)
CLIP_SCAL_NPXY equ (CLIP_SCAL_NX | CLIP_SCAL_NY | CLIP_SCAL_PX | CLIP_SCAL_PY)
