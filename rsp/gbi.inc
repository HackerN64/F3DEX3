// GBI: Graphics Binary Interface

// Geometry mode flags
// First byte gets OR'd with G_TRI_FILL (0xC8) to form triangle opcode. Enabling
// textures is done through SPTexture; G_TEXTURE_ENABLE is defined in the
// GBI to 0. Binary display lists with this set will likely crash.
G_ZBUFFER               equ 0x00000001
//G_TEXTURE_ENABLE      equ 0x00000002
G_SHADE                 equ 0x00000004
// Bits 1 and 2 (0x06) index into a table for front/backface culling. Other bits
// are added.
G_CULL_FRONT            equ 0x00000200
G_CULL_BACK             equ 0x00000400
G_CULL_BOTH             equ 0x00000600
G_ATTROFFSET_ST_ENABLE  equ 0x00000100
G_ATTROFFSET_Z_ENABLE   equ 0x00000800
G_PACKED_NORMALS        equ 0x00001000
G_LIGHTTOALPHA          equ 0x00002000
G_AMBOCCLUSION          equ 0x00004000
G_FRESNEL               equ 0x00008000
G_FOG                   equ 0x00010000
G_LIGHTING              equ 0x00020000
G_TEXTURE_GEN           equ 0x00040000
G_TEXTURE_GEN_LINEAR    equ 0x00080000
//G_LOD                 equ 0x00100000 // Ignored by all F3DEX* variants
G_SHADING_SMOOTH        equ 0x00200000
//G_LIGHTING_POSITIONAL equ 0x00400000 // Ignored by F3DEX3, assumed always on
//G_CLIPPING            equ 0x00800000 // Ignored by all F3DEX* variants
// The top byte holds the geometry mode opcode.

G_TRI_FILL        equ 0xc8 // not a GBI command

G_DMA_IO          equ 0xd6
G_TEXTURE         equ 0xd7
G_POPMTX          equ 0xd8
G_GEOMETRYMODE    equ 0xd9
G_MTX             equ 0xda
G_MOVEWORD        equ 0xdb
G_MOVEMEM         equ 0xdc
G_LOAD_UCODE      equ 0xdd
G_DL              equ 0xde
G_ENDDL           equ 0xdf
G_SPNOOP          equ 0xe0
G_RDPHALF_1       equ 0xe1
G_SETOTHERMODE_L  equ 0xe2
G_SETOTHERMODE_H  equ 0xe3
G_TEXRECT         equ 0xe4
G_TEXRECTFLIP     equ 0xe5
// G_RDP_handler group start v
G_RDPLOADSYNC     equ 0xe6
G_RDPPIPESYNC     equ 0xe7
G_RDPTILESYNC     equ 0xe8
G_RDPFULLSYNC     equ 0xe9
G_SETKEYGB        equ 0xea
G_SETKEYR         equ 0xeb
G_SETCONVERT      equ 0xec
G_SETSCISSOR      equ 0xed // separate handler
G_SETPRIMDEPTH    equ 0xee
G_RDPSETOTHERMODE equ 0xef // separate handler
G_LOADTLUT        equ 0xf0
G_RDPHALF_2       equ 0xf1 // separate handler
G_SETTILESIZE     equ 0xf2
G_LOADBLOCK       equ 0xf3 // separate handler
G_LOADTILE        equ 0xf4
G_SETTILE         equ 0xf5
G_FILLRECT        equ 0xf6
G_SETFILLCOLOR    equ 0xf7
G_SETFOGCOLOR     equ 0xf8
G_SETBLENDCOLOR   equ 0xf9
G_SETPRIMCOLOR    equ 0xfa
G_SETENVCOLOR     equ 0xfb
G_SETCOMBINE      equ 0xfc
G_SETTIMG         equ 0xfd
G_SETZIMG         equ 0xfe
G_SETCIMG         equ 0xff
G_NOOP            equ 0x00
// G_RDP_handler group end ^
G_VTX             equ 0x01
G_MODIFYVTX       equ 0x02
G_CULLDL          equ 0x03
G_BRANCH_WZ       equ 0x04
G_TRI1            equ 0x05
G_TRI2            equ 0x06
G_QUAD            equ 0x07
G_TRISTRIP        equ 0x08
G_TRIFAN          equ 0x09
G_LIGHTTORDP      equ 0x0A
G_CULLVERTS       equ 0x0B
G_CULLRETURN      equ 0x0C
G_CULLBRANCH      equ 0x0D


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

// Clipping flags. Bits 0-3, 8-11, etc. contain garbage (values from another
// vertex or zeros) and are not used. Also, the bits for comparisons to W in
// clip ratio scaled clipping are actually for Z, but only X and Y are used in
// clip ratio scaled clipping.
CLIP_SHIFT_NX equ 4
CLIP_SHIFT_NY equ 5
CLIP_SHIFT_NZ equ 6
CLIP_SHIFT_NW equ 7
CLIP_SHIFT_PX equ 12
CLIP_SHIFT_PY equ 13
CLIP_SHIFT_PZ equ 14
CLIP_SHIFT_PW equ 15 // never used
CLIP_NX equ (1 << CLIP_SHIFT_NX)
CLIP_NY equ (1 << CLIP_SHIFT_NY)
CLIP_NZ equ (1 << CLIP_SHIFT_NZ)
CLIP_NW equ (1 << CLIP_SHIFT_NW)
CLIP_PX equ (1 << CLIP_SHIFT_PX)
CLIP_PY equ (1 << CLIP_SHIFT_PY)
CLIP_PZ equ (1 << CLIP_SHIFT_PZ)
CLIP_PW equ (1 << CLIP_SHIFT_PW) // never used
// These values apply to either screen space clipping or clip ratio scaled
// clipping, with appropriate shifts when used as one whole word.
CLIP_SHIFT_SCAL equ 16
CLIP_SHIFT_SCRN equ 0
// Values used for far and near clipping.
CLIP_FAR equ CLIP_PZ
CLIP_NEAR equ CLIP_NW // No Nearclipping uses -w instead of -z

// Could add CLIP_NZ and CLIP_PZ to SCRN if desired, even though not clipping there.
CLIP_MOD_MASK_SCRN_ALL equ ((CLIP_NX | CLIP_NY | CLIP_PX | CLIP_PY | CLIP_NEAR) >> 4)
CLIP_MOD_MASK_SCAL_ALL equ  (CLIP_NX | CLIP_NY | CLIP_PX | CLIP_PY)
CLIP_MOD_VTX_USED equ CLIP_PZ // won't ever be used for other things
