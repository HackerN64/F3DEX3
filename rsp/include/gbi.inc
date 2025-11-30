// GBI: Graphics Binary Interface

// Geometry mode flags
// First byte gets OR'd with G_TRI_FILL (0xC8) to form triangle opcode. Enabling
// textures is done through SPTexture; G_TEXTURE_ENABLE is defined in the
// GBI to 0. Binary display lists with this set will likely crash.
G_ZBUFFER               equ 0x00000001
//G_TEXTURE_ENABLE      equ 0x00000002
G_SHADE                 equ 0x00000004
G_ATTROFFSET_ST_ENABLE  equ 0x00000080
G_AMBOCCLUSION          equ 0x00000100
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
//G_LIGHTING_POSITIONAL equ 0x00400000 // In F3DEX3, replaced by ENABLE_POINT_LIGHTS, part of light count
//G_CLIPPING            equ 0x00800000 // Ignored by all F3DEX* variants
// The top byte holds the geometry mode opcode.

G_TRI_FILL          equ 0xc8 // not a GBI command

G_FLUSH             equ 0xd4
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
G_VTX               equ 0x01
G_MODIFYVTX         equ 0x02
G_LIGHTTORDP        equ 0x0a
G_RELSEGMENT        equ 0x0b


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
