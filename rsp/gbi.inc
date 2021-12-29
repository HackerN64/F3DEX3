// GBI: Graphics Binary Interface

OS_YIELD_DATA_SIZE equ 0xC00

// Geometry mode flags
G_ZBUFFER               equ 0x00000001
G_TEXTURE_ENABLE        equ 0x00000002
G_SHADE                 equ 0x00000004
G_CULL_FRONT            equ 0x00000200
G_CULL_BACK             equ 0x00000400
G_CULL_BOTH             equ 0x00000600
G_FOG                   equ 0x00010000
G_LIGHTING              equ 0x00020000
G_TEXTURE_GEN           equ 0x00040000
G_TEXTURE_GEN_LINEAR    equ 0x00080000
G_LOD                   equ 0x00100000
G_SHADING_SMOOTH        equ 0x00200000
G_LIGHTING_POSITIONAL   equ 0x00400000
G_CLIPPING              equ 0x00800000

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

G_MTX_P_MV        equ 0x04
G_MTX_MUL_LOAD    equ 0x02
G_MTX_NOPUSH_PUSH equ 0x01

vtxSize equ 0x10
