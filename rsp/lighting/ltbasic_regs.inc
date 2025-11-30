// Lighting basic:
lbPostAo       equ $2    // Address to return to after AO
lbFakeAmb      equ $4    // Pointer to ambient light or to 8 bytes of zeros if AO enabled
lbTexgenOrRet  equ $6    // ltbasic_texgen as negative if texgen, else vtx_return_from_lighting
curLight       equ $9    // Current light pointer with offset
ambLight       equ $21   // Ambient (top) light pointer with offset
lbAfter        equ $25   // Address to return to after main lighting loop (vertex or extras)
