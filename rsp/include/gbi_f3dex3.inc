.include "rsp/gbi_f3d.inc"
.include "rsp/gbi_clipping.inc"

// GBI commands
G_TRISNAKE          equ 0x08
// nothing          equ 0x09

G_MAX_LIGHTS equ 9 // 9 directional / point lights, plus ambient light (and lookat)
lightSize equ 0x10

G_MAX_VERTS equ 56

OS_YIELD_DATA_SIZE equ 0xC00
