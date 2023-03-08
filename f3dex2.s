.rsp

.include "rsp/rsp_defs.inc"
.include "rsp/gbi.inc"

// This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

// Tweak the li and la macros so that the output matches
.macro li, reg, imm
    addi reg, $zero, imm
.endmacro

.macro la, reg, imm
    addiu reg, $zero, imm
.endmacro

.macro move, dst, src
    ori dst, src, 0
.endmacro

// Vector macros
.if MOD_GENERAL
// This version doesn't depend on $v0, which may not exist in mods, and also
// doesn't get corrupted if $vco is set / consume $vco which may be needed for
// a subsequent instruction.
.macro vcopy, dst, src
    vor dst, src, src
.endmacro
.else
.macro vcopy, dst, src
    vadd dst, src, $v0[0]
.endmacro
.endif

.macro vclr, dst
    vxor dst, dst, dst
.endmacro

ACC_UPPER equ 0
ACC_MIDDLE equ 1
ACC_LOWER equ 2
.macro vreadacc, dst, N
    vsar dst, dst, dst[N]
.endmacro

/*
There are two different memory spaces for the overlays: (a) IMEM and (b) the
microcode file (which, plus an offset, is also the location in DRAM).

A label marks both an IMEM addresses and a file address, but evaluating the
label in an integer context (e.g. in a branch) gives the IMEM address.
`orga(your_label)` gets the file address of the label, and `.orga` sets the
file address.
`.headersize`, as well as the value after `.create`, sets the difference
between IMEM addresses and file addresses, so you can set the IMEM address
with `.headersize desired_imem_addr - orga()`.

In IMEM, the whole microcode is organized as (each row is the same address):

0x80 space             |                |
for boot code       Overlay 0       Overlay 1
                      (End          (More cmd 
start                 task)         handlers)
(initialization)       |                |

Many command
handlers

Overlay 2           Overlay 3
(Lighting)          (Clipping)

Vertex and
tri handlers

DMA code

In the file, the microcode is organized as:
start (file addr 0x0 = IMEM 0x1080)
Many command handlers
Overlay 3
Vertex and tri handlers
DMA code (end of this = IMEM 0x2000 = file 0xF80)
Overlay 0
Overlay 1
Overlay 2
*/

// Overlay table data member offsets
overlay_load equ 0x0000
overlay_len  equ 0x0004
overlay_imem equ 0x0006
.macro OverlayEntry, loadStart, loadEnd, imemAddr
    .dw loadStart
    .dh (loadEnd - loadStart - 1) & 0xFFFF
    .dh (imemAddr) & 0xFFFF
.endmacro

.macro jumpTableEntry, addr
    .dh addr & 0xFFFF
.endmacro

// RSP DMEM
.create DATA_FILE, 0x0000

/*
Matrices are stored and used in a transposed format compared to how they are
normally written in mathematics. For the integer part:
00 02 04 06  typical  Xscl Rot  Rot  0
08 0A 0C 0E  use:     Rot  Yscl Rot  0
10 12 14 16           Rot  Rot  Zscl 0
18 1A 1C 1E           Xpos Ypos Zpos 1
The fractional part comes next and is in the same format.
Applying this transformation is done by multiplying a row vector times the
matrix, like:
X  Y  Z  1  *  Xscl Rot  Rot  0  =  NewX NewY NewZ 1
               Rot  Yscl Rot  0
               Rot  Rot  Zscl 0
               Xpos Ypos Zpos 1
In C, the matrix is accessed as matrix[row][col], and the vector is vector[row].
*/
// 0x0000-0x0040: modelview matrix
mvMatrix:
    .fill 64

// 0x0040-0x0080: projection matrix
pMatrix:
    .fill 64

// 0x0080-0x00C0: modelviewprojection matrix
mvpMatrix:
    .fill 64
    
// 0x00C0-0x00C8: scissor (four 12-bit values)
scissorUpLeft: // the command byte is included since the command word is copied verbatim
    .dw (G_SETSCISSOR << 24) | ((  0 * 4) << 12) | ((  0 * 4) << 0)
scissorBottomRight:
    .dw ((320 * 4) << 12) | ((240 * 4) << 0)

// 0x00C8-0x00D0: othermode
otherMode0: // command byte included, same as above
    .dw (G_RDPSETOTHERMODE << 24) | (0x080CFF)
otherMode1:
    .dw 0x00000000

// 0x00D0-0x00D8: Saved texrect state for combining the multiple input commands into one RDP texrect command
texrectWord1:
    .fill 4 // first word, has command byte, xh and yh
texrectWord2:
    .fill 4 // second word, has tile, xl, yl

// 0x00D8: First half of RDP value for split commands (shared by perspNorm moveword to be able to write a 32-bit value)
rdpHalf1Val:
    .fill 4

// 0x00DC: perspective norm
perspNorm:
    .dh 0xFFFF

// 0x00DE: displaylist stack length
displayListStackLength:
    .db 0x00 // starts at 0, increments by 4 for each "return address" pushed onto the stack

    .db 0x48 // this seems to be the max displaylist length

// 0x00E0-0x00F0: viewport
viewport:
    .fill 16

// 0x00F0-0x00F4: Current RDP fifo output position
rdpFifoPos:
    .fill 4

// 0x00F4-0x00F8:
matrixStackPtr:
    .dw 0x00000000

// 0x00F8-0x0138: segment table
segmentTable:
    .fill (4 * 16) // 16 DRAM pointers

// 0x0138-0x0180: displaylist stack
displayListStack:

// 0x0138-0x0180: ucode text (shared with DL stack)
.if CFG_EXTRA_0A_BEFORE_ID_STR // F3DEX2 2.04H puts an extra 0x0A before the name
    .db 0x0A
.endif
    .ascii ID_STR, 0x0A

.align 16
.if . - displayListStack != 0x48
    .warning "ID_STR incorrect length, affects displayListStack"
.endif

// Base address for RSP effects DMEM region (see discussion in lighting below).
// Could pick a better name, basically a global fixed DMEM pointer used with
// fixed offsets to things in this region. It seems potentially data below this
// could be shared by different running microcodes whereas data after this is
// only used by the current microcode. Also this is used for a base address in
// vtx write / lighting because vector load offsets can't reach all of DMEM.
spFxBase:

.if !MOD_CLIP_CHANGES
// 0x0180-0x1B0: clipping values
clipRatio: // This is an array of 6 doublewords
// G_MWO_CLIP_R** point to the second word of each of these, and end up setting
// the Z scale (always 0 for X and Y components) and the W scale (clip ratio)
    .dw 0x00010000, 0x00000002 // 1 * x,    G_MWO_CLIP_RNX * w = negative x clip
    .dw 0x00000001, 0x00000002 // 1 * y,    G_MWO_CLIP_RNY * w = negative y clip
    .dw 0x00010000, 0x0000FFFE // 1 * x, (-)G_MWO_CLIP_RPX * w = positive x clip
    .dw 0x00000001, 0x0000FFFE // 1 * x, (-)G_MWO_CLIP_RPY * w = positive y clip
    .dw 0x00000000, 0x0001FFFF // 1 * z,  -1 * w = far clip
.if CFG_NoN
    .dw 0x00000000, 0x00000001 // 0 * all, 1 * w = no nearclipping
.else
    .dw 0x00000000, 0x00010001 // 1 * z,   1 * w = nearclipping
.endif
.endif

// 0x1B0: constants for register $v31
.align 0x10 // loaded with lqv
// VCC patterns used:
// vlt xxx, $v31, $v31[3]  = 11101110 in load_spfx_global_values (uses vne in mods)
// vne xxx, $v31, $v31[3h] = 11101110 in lighting
// veq xxx, $v31, $v31[3h] = 00010001 in lighting
v31Value:
.if MOD_VL_REWRITE
// v31 must go from lowest to highest (signed) values. 
    .dh -4     // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh -1     // used in init, clipping
    .dh 1      // used to load accumulator in many places, replaces vOne
    .dh 0x0010 // used in tri write for Newton-Raphson reciprocal, and point lighting
    .dh 0x0100 // used in tri write, vertex color >>= 8 and vcr?; also in lighting and point lighting
    .dh 0x4000 // used in tri write, texgen
    .dh 0x7F00 // used in vtx write and pre-jump instrs to there, also normals unpacking
    .dh 0x7FFF // used in vtx write, tri write, lighting, point lighting
.else
    .dh -1     // used in init, clipping
    .dh 4      // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh 8      // old ucode only: used in tri write
    .dh 0x7F00 // used in vtx write and pre-jump instrs to there, also 4 put here during point lighting
    .dh -4     // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh 0x4000 // used in tri write, texgen
    .dh vertexBuffer // 0x420; used in tri write
    .dh 0x7FFF // used in vtx write, tri write, lighting, point lighting
.endif

// 0x1C0: constants for register $v30
.align 0x10 // loaded with lqv
// VCC patterns used:
// vge xxx, $v30, $v30[7] = 11110001 in tri write
v30Value:
.if MOD_VL_REWRITE
    .dh vertexBuffer // 0x420; used in tri write
.else
    .dh 0x7FFC // not used!
.endif
    .dh vtxSize << 7 // 0x1400; it's not 0x2800 because vertex indices are *2; used in tri write for vtx index to addr
.if CFG_OLD_TRI_WRITE // See discussion in tri write where v30 values used
    .dh 0x01CC // used in tri write, vcr?
    .dh 0x0200 // not used!
    .dh -16    // used in tri write for Newton-Raphson reciprocal 
    .dh 0x0010 // used in tri write for Newton-Raphson reciprocal
    .dh 0x0020 // used in tri write, both signed and unsigned multipliers
    .dh 0x0100 // used in tri write, vertex color >>= 8; also in lighting
.else
    .dh 0x1000 // used in tri write, some multiplier
    .dh 0x0100 // used in tri write, vertex color >>= 8 and vcr?; also in lighting and point lighting
    .dh -16    // used in tri write for Newton-Raphson reciprocal 
    .dh 0xFFF8 // used in tri write, mask away lower ST bits?
    .dh 0x0010 // used in tri write for Newton-Raphson reciprocal; value moved to elem 7 for point lighting
    .dh 0x0020 // used in tri write, both signed and unsigned multipliers; value moved from elem 6 from point lighting
.endif

/*
Quick note on Newton-Raphson:
https://en.wikipedia.org/wiki/Division_algorithm#Newton%E2%80%93Raphson_division
Given input D, we want to find the reciprocal R. The base formula for refining
the estimate of R is R_new = R*(2 - D*R). However, since the RSP reciprocal
instruction moves the radix point 1 to the left, the result has to be multiplied
by 2. So it's 2*R*(2 - D*2*R) = R*(4 - 4*D*R) = R*(1*4 + D*R*-4). This is where
the 4 and -4 come from. For tri write, the result needs to be multiplied by 4
for subpixels, so it's 16 and -16.
*/

.align 0x10 // loaded with lqv
linearGenerateCoefficients:
    .dh 0xC000
    .dh 0x44D3
    .dh 0x6CB3
    .dh 2

.if !MOD_GENERAL
// 0x01D8
    .db 0x00 // Padding to allow mvpValid to be written to as a 32-bit word
mvpValid:
    .db 0x01

// 0x01DA
    .dh 0x0000 // Shared padding so that:
               // -- mvpValid can be written on its own for G_MW_FORCEMTX
               // -- Writing numLightsx18 with G_MW_NUMLIGHT sets lightsValid to 0
               // -- do_popmtx and load_mtx can invalidate both with one zero word write

// 0x01DC
lightsValid:   // Gets overwritten with 0 when numLights is written with moveword.
    .db 1
numLightsx18:
    .db 0

    .db 11
    .db 7 * 0x18
.endif

.if (. & 3) != 0
.error "Wrong alignment before fogFactor"
.endif

// 0x01E0
fogFactor:
    .dw 0x00000000

// 0x01E4
textureSettings1:
    .dw 0x00000000 // first word, has command byte, bowtie val, level, tile, and on

// textureSettings2 and modClipRatio loaded together
.if (. & 7) != 0
.error "Wrong alignment before textureSettings2"
.endif

// 0x01E8
textureSettings2:
    .dw 0x00000000 // second word, has s and t scale
    
.if MOD_GENERAL
mwModsStart:
.if MOD_CLIP_CHANGES
modClipRatio:
    .dh 0x0002 // Clip ratio; strongly recommend keeping as 2
modClipLargeTriThresh:
    .dh 120 << 2 // Number of quarter-scanlines high a triangle is to be considered large
.else
    .dw 0 //TODO
.endif
.endif

.if MOD_ATTR_OFFSETS
.if (. & 7) != 0
.error "Wrong alignment before attrOffsetST"
.endif
attrOffsetST:
    .dh 0x0100
    .dh 0xFF00

attrOffsetZ:
    .dh 0x0002
    .dh 0x0000
.endif

.if MOD_GENERAL
aoAmbientFactor:
    .dh 0xFFFF
aoDirectionalFactor:
    .dh 0xA000
.endif

// 0x01EC
geometryModeLabel:
    .dw G_CLIPPING

.if (. & 7) != 0
.error "Wrong alignment before lighting"
.endif

// excluding ambient light
MAX_LIGHTS equ 7

// 0x01F0-0x02E0: Light data; a total of 10 * lightSize light slots.
// Each slot's data is either directional or point (each pair of letters is a byte):
//      Directional lights:
// 0x00 RR GG BB 00 RR GG BB -- NX NY NZ -- -- -- -- --
// 0x10 TX TY TZ -- TX TY TZ -- (Normals transformed to camera space)
//      Point lights: 
// 0x00 RR GG BB CC RR GG BB LL XXXX YYYY ZZZZ QQ --
// 0x10 -- -- -- -- -- -- -- -- (Invalid transformed normals get stored here)
// CC: constant attenuation factor (0 indicates directional light)
// LL: linear attenuation factor
// QQ: quadratic attenuation factor
//
// First there are two lights, whose directions define the X and Y directions
// for texgen, via g(s)SPLookAtX/Y. The colors are ignored. These lights get
// transformed normals. g(s)SPLight which point here start copying at n*24+24,
// where n starts from 1 for one light (or zero lights), which effectively
// points at lightBufferMain.
lightBufferLookat:
    .fill (2 * lightSize)
// Then there are the main 8 lights. This is between one and seven directional /
// point (if built with this enabled) lights, plus the ambient light at the end.
// Zero lights is not supported, and is encoded as one light with black color
// (does not affect the result). Directional and point lights can be mixed in
// any order; ambient is always at the end.
lightBufferMain:
    .fill (8 * lightSize)
// Code uses pointers relative to spFxBase, with immediate offsets, so that
// another register isn't needed to store the start or end address of the array.
// Pointers are kept relative to spFxBase; this offset gets them to point to
// lightBufferMain instead.
ltBufOfs equ (lightBufferMain - spFxBase)
// One more topic on lighting: The point lighting code uses MV transpose instead
// of MV inverse to transform from camera space to model space. If MV has a
// uniform scale (same scale in X, Y, and Z), MV transpose = MV inverse times a
// scale factor. The lighting code effectively gets rid of the scale factor, so
// this is okay. But, if the matrix has nonuniform scaling, and especially if it
// has shear (nonuniform scaling applied somewhere in the middle of the matrix
// stack, such as to a whole skeletal / skinned mesh), this will not be correct.

// 0x02E0-0x02F0: Overlay 0/1 Table
overlayInfo0:
    OverlayEntry orga(ovl0_start), orga(ovl0_end), ovl0_start
overlayInfo1:
    OverlayEntry orga(ovl1_start), orga(ovl1_end), ovl1_start

.if MOD_GENERAL
    .db 0x00 // Padding to allow mvpValid to be written to as a 32-bit word
mvpValid:
    .db 0x01
    .dh 0x0000 // Shared padding to allow mvpValid (probably lightsValid?) and
               // numLightsx18 to both be written to as 32-bit words for moveword
lightsValid:   // Gets overwritten with 0 when numLights is written with moveword.
    .db 1
numLightsx18:
    .db 0
    
modSaveRA:
    // Store original $ra here during clipping instead of globally occupying
    // $30 = savedRA.
    .skip 2
modSaveFlatR4:
    // Store value of $4 here during clipping subdivision, so it can be used as
    // a local. It's the first vertex of three in the original tri, for loading
    // vertex colors from for flat shading.
    .skip 2
.endif

// 0x02F0-0x02FE: Movemem table
movememTable:
    // Temporary matrix in clipTempVerts scratch space, aligned to 16 bytes
    .dh (clipTempVerts + 15) & ~0xF // G_MTX multiply temp matrix (model)
    .dh mvMatrix          // G_MV_MMTX
    .dh (clipTempVerts + 15) & ~0xF // G_MTX multiply temp matrix (projection)
    .dh pMatrix           // G_MV_PMTX
    .dh viewport          // G_MV_VIEWPORT
    .dh lightBufferLookat // G_MV_LIGHT
    .dh vertexBuffer      // G_MV_POINT
// Further entries in the movemem table come from the moveword table

// 0x02FE-0x030E: moveword table
movewordTable:
    .dh mvpMatrix        // G_MW_MATRIX
    .dh numLightsx18 - 3 // G_MW_NUMLIGHT
.if MOD_CLIP_CHANGES
    .dh clipTempVerts    // G_MW_CLIP; discard writes to here
.else
    .dh clipRatio        // G_MW_CLIP
.endif
    .dh segmentTable     // G_MW_SEGMENT
    .dh fogFactor        // G_MW_FOG
    .dh lightBufferMain  // G_MW_LIGHTCOL
    .dh mvpValid - 1     // G_MW_FORCEMTX
    .dh perspNorm - 2    // G_MW_PERSPNORM
.if MOD_ATTR_OFFSETS
    .dh mwModsStart      // G_MW_MODS: 0 = large tri thresh and clip ratio,
                         // 1 = attrOffsetST, 2 = attrOffsetZ, 3 = ambient occlusion
.endif

// 0x030E-0x0314: G_POPMTX, G_MTX, G_MOVEMEM Command Jump Table
movememHandlerTable:
jumpTableEntry G_POPMTX_end   // G_POPMTX
jumpTableEntry G_MTX_end      // G_MTX (multiply)
jumpTableEntry G_MOVEMEM_end  // G_MOVEMEM, G_MTX (load)

// 0x0314-0x0370: RDP/Immediate Command Jump Table
.if !MOD_GENERAL
// Not actually used or supported--get rid of the DMEM for them
jumpTableEntry G_SPECIAL_3_handler
jumpTableEntry G_SPECIAL_2_handler
jumpTableEntry G_SPECIAL_1_handler
.endif
jumpTableEntry G_DMA_IO_handler
jumpTableEntry G_TEXTURE_handler
jumpTableEntry G_POPMTX_handler
jumpTableEntry G_GEOMETRYMODE_handler
jumpTableEntry G_MTX_handler
jumpTableEntry G_MOVEWORD_handler
jumpTableEntry G_MOVEMEM_handler
jumpTableEntry G_LOAD_UCODE_handler
jumpTableEntry G_DL_handler
jumpTableEntry G_ENDDL_handler
jumpTableEntry G_SPNOOP_handler
jumpTableEntry G_RDPHALF_1_handler
jumpTableEntry G_SETOTHERMODE_L_handler
jumpTableEntry G_SETOTHERMODE_H_handler
jumpTableEntry G_TEXRECT_handler
jumpTableEntry G_TEXRECTFLIP_handler
.if !MOD_CMD_JUMP_TABLE
jumpTableEntry G_SYNC_handler    // G_RDPLOADSYNC
jumpTableEntry G_SYNC_handler    // G_RDPPIPESYNC
jumpTableEntry G_SYNC_handler    // G_RDPTILESYNC
jumpTableEntry G_SYNC_handler    // G_RDPFULLSYNC
jumpTableEntry G_RDP_handler     // G_SETKEYGB
jumpTableEntry G_RDP_handler     // G_SETKEYR
jumpTableEntry G_RDP_handler     // G_SETCONVERT
.else
cmdJumpTableForwardBack:
.endif
jumpTableEntry G_SETSCISSOR_handler
jumpTableEntry G_RDP_handler     // G_SETPRIMDEPTH
jumpTableEntry G_RDPSETOTHERMODE_handler
jumpTableEntry G_RDP_handler     // G_LOADTLUT
jumpTableEntry G_RDPHALF_2_handler
.if !MOD_CMD_JUMP_TABLE
jumpTableEntry G_RDP_handler     // G_SETTILESIZE
jumpTableEntry G_RDP_handler     // G_LOADBLOCK
jumpTableEntry G_RDP_handler     // G_LOADTILE
jumpTableEntry G_RDP_handler     // G_SETTILE
jumpTableEntry G_RDP_handler     // G_FILLRECT
jumpTableEntry G_RDP_handler     // G_SETFILLCOLOR
jumpTableEntry G_RDP_handler     // G_SETFOGCOLOR
jumpTableEntry G_RDP_handler     // G_SETBLENDCOLOR
jumpTableEntry G_RDP_handler     // G_SETPRIMCOLOR
jumpTableEntry G_RDP_handler     // G_SETENVCOLOR
jumpTableEntry G_RDP_handler     // G_SETCOMBINE
jumpTableEntry G_SETxIMG_handler // G_SETTIMG
jumpTableEntry G_SETxIMG_handler // G_SETZIMG
jumpTableEntry G_SETxIMG_handler // G_SETCIMG

commandJumpTable:
jumpTableEntry G_NOOP_handler
.else
cmdJumpTablePositive:
.endif

// 0x0370-0x0380: DMA Command Jump Table
jumpTableEntry G_VTX_handler
jumpTableEntry G_MODIFYVTX_handler
jumpTableEntry G_CULLDL_handler
jumpTableEntry G_BRANCH_WZ_handler // different for F3DZEX
jumpTableEntry G_TRI1_handler
jumpTableEntry G_TRI2_handler
jumpTableEntry G_QUAD_handler
.if !MOD_GENERAL
// Not actually used or supported--get rid of the DMEM
jumpTableEntry G_LINE3D_handler
.endif

// 0x0380-0x03C4: vertex pointers
vertexTable:

// The vertex table is a list of pointers to the location of each vertex in the buffer
// After the last vertex pointer, there is a pointer to the address after the last vertex
// This means there are really 33 entries in the table

.macro vertexTableEntry, i
    .dh vertexBuffer + (i * vtxSize)
.endmacro

.macro vertexTableEntries, i
    .if i > 0
        vertexTableEntries (i - 1)
    .endif
    vertexTableEntry i
.endmacro

    vertexTableEntries 32

// 0x03C2-0x0410: ??
gCullMagicNumbers:
// Values added to cross product (16-bit sign extended).
// Then if sign bit is clear, cull the triangle.
    .dh 0xFFFF // }-G_CULL_NEITHER -- makes any value negative.
    .dh 0x8000 // }/    }-G_CULL_FRONT -- inverts the sign.
    .dh 0x0000 //       }/    }-G_CULL_BACK -- no change.
    .dh 0x0000 //             }/    }-G_CULL_BOTH -- makes any value positive.
    .dh 0x8000 //                   }/
// G_CULL_BOTH is useless as the tri will always be culled, so might as well not
// bother drawing it at all. Guess they just wanted completeness, and it only
// costs two bytes of DMEM.

.if !MOD_CLIP_CHANGES
.align 4
activeClipPlanes:
CLIP_ALL_SCAL equ ((CLIP_NX | CLIP_NY | CLIP_PX | CLIP_PY) << CLIP_SHIFT_SCAL)
CLIP_ALL_SCRN equ ((CLIP_FAR | CLIP_NEAR) << CLIP_SHIFT_SCRN)
    .dw CLIP_ALL_SCAL | CLIP_ALL_SCRN
.endif

// 0x3D0: Clipping polygons, as lists of vertex addresses. When handling each
// clipping condition, the polygon is read off one list and the modified polygon
// is written to the next one.
// Max verts in each polygon:
clipPoly:
    .fill 10 * 2   // 3   5   7   9
clipPoly2:         //  \ / \ / \ /
    .fill 10 * 2   //   4   6   8
// but there needs to be room for the terminating 0, and clipMaskList below needs
// to be word-aligned. So this is why it's 10 each.

.if MOD_CLIP_CHANGES
.if !CFG_NoN
    .error "MOD_CLIP_CHANGES requires CFG_NoN"
.endif
clipCondShifts:
    .db CLIP_SHIFT_NY - 4
    .db CLIP_SHIFT_PY - 4
    .db CLIP_SHIFT_NX - 4
    .db CLIP_SHIFT_PX - 4
.else
.align 4
clipMaskList:
    .dw CLIP_NX   << CLIP_SHIFT_SCAL
    .dw CLIP_NY   << CLIP_SHIFT_SCAL
    .dw CLIP_PX   << CLIP_SHIFT_SCAL
    .dw CLIP_PY   << CLIP_SHIFT_SCAL
    .dw CLIP_FAR  << CLIP_SHIFT_SCRN
    .dw CLIP_NEAR << CLIP_SHIFT_SCRN
.endif

// 0x0410-0x0420: Overlay 2/3 table
overlayInfo2:
    OverlayEntry orga(ovl2_start), orga(ovl2_end), ovl2_start
overlayInfo3:
    OverlayEntry orga(ovl3_start), orga(ovl3_end), ovl3_start

.align 8

// 0x0420-0x0920: Vertex buffer in RSP internal format
vertexBuffer:
    .skip (vtxSize * 32) // 32 vertices

.if . > OS_YIELD_DATA_SIZE - 8
    // OS_YIELD_DATA_SIZE (0xC00) bytes of DMEM are saved; the last two words are
    // the ucode and the DL pointer. Make sure anything past there is temporary.
    // (Input buffer will be reloaded from next instruction in the source DL.)
    .error "Important things in DMEM will not be saved at yield!"
.endif

// 0x0920-0x09C8: Input buffer
inputBuffer:
inputBufferLength equ 0xA8
    .skip inputBufferLength
inputBufferEnd:

// 0x09C8-0x0BA8: Space for temporary verts for clipping code
clipTempVerts:
clipTempVertsCount equ 12 // Up to 2 temp verts can be created for each of the 6 clip conditions.
    .skip clipTempVertsCount * vtxSize

// 0x09D0-0x0A10: Temp matrix for G_MTX multiplication mode, overlaps with clipTempVerts

.if MOD_RDP_BUFS_2_TRIS
RDP_CMD_BUFSIZE equ 0xB0
.else
RDP_CMD_BUFSIZE equ 0x158
.endif
RDP_CMD_BUFSIZE_EXCESS equ 0xB0 // Maximum size of an RDP triangle command
RDP_CMD_BUFSIZE_TOTAL equ RDP_CMD_BUFSIZE + RDP_CMD_BUFSIZE_EXCESS
// 0x0BA8-0x0D00: First RDP Command Buffer
rdpCmdBuffer1:
    .skip RDP_CMD_BUFSIZE
rdpCmdBuffer1End:
    .skip RDP_CMD_BUFSIZE_EXCESS


// 0x0DB0-0x0FB8: Second RDP Command Buffer
rdpCmdBuffer2:
    .skip RDP_CMD_BUFSIZE
rdpCmdBuffer2End:
    .skip RDP_CMD_BUFSIZE_EXCESS

.if MOD_GENERAL
totalDmemUse:
.endif

.if . > 0x00000FC0
    .error "Not enough room in DMEM"
.endif

.org 0xFC0

// 0x0FC0-0x1000: OSTask
OSTask:
    .skip 0x40

.close // DATA_FILE

// RSP IMEM
.create CODE_FILE, 0x00001080

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Use Map ///////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// Registers marked as "global" are only used for one purpose in the vanilla
// microcode. However, this does not necessarily mean they can't be used for
// other things in mods--this depends on which group they're listed in below.

// Note that these lists do not cover registers which are just used locally in
// a particular region of code--you're still responsible for not breaking the
// code you modify. This is designed to help you avoid breaking one part of the
// code by modifying a different part.

// Local register definitions are included with their code, not here.

// These registers are used globally, and their values can't be rebuilt, so
// they should never be used for anything besides their original purpose.
//                 $zero // global
rdpCmdBufEnd   equ $22   // global
rdpCmdBufPtr   equ $23   // global
taskDataPtr    equ $26   // global
inputBufferPos equ $27   // global
//                 $ra   // global

// These registers are used throughout the codebase and expected to have
// certain values, but you're free to overwrite them as long as you
// reconstruct the normal values after you're done (in fact point lighting does
// this for $v30 and $v31).
vZero equ $v0  // global (not in MOD_VL_REWRITE)
vOne  equ $v1  // global (not in MOD_VL_REWRITE)
//        $v30 // global except in point lighting (not in MOD_VL_REWRITE)
//        $v31 // global except in point lighting (actually global in MOD_VL_REWRITE)

// Must keep values during the full clipping process: clipping overlay, vertex
// write, tri drawing.
clipPolySelect        equ $18 // global
clipPolyWrite         equ $21 // also input_mtx_0
savedActiveClipPlanes equ $29 // global (mods: got rid of, now available)
savedRA               equ $30 // global (mods: got rid of, now available)

// Must keep values during the first part of the clipping process only: polygon
// subdivision and vertex write.
// $2: vertex at end of edge
clipMaskIdx  equ $5
secondVtxPos equ $8
outputVtxPos equ $15 // global
clipFlags    equ $16 // global
clipPolyRead equ $17 // global

// Must keep values during tri drawing.
// They are also used throughout the codebase, but can be overwritten once their
// use has been fulfilled for the specific command.
cmd_w1_dram equ $24 // Command word 1, which is also DMA DRAM addr; almost global, occasionally used locally
cmd_w0      equ $25 // Command word 0; almost global, occasionally used locally

// Must keep values during the full vertex process: load, lighting, and vertex write
// $1: count of remaining vertices
topLightPtr  equ $6   // Used locally elsewhere
curLight     equ $9   // Used locally elsewhere
inputVtxPos  equ $14  // global
mxr0i        equ $v8  // "matrix row 0 int part"
mxr1i        equ $v9  // All of these used locally elsewhere
mxr2i        equ $v10
mxr3i        equ $v11
mxr0f        equ $v12
mxr1f        equ $v13
mxr2f        equ $v14
mxr3f        equ $v15
vPairST      equ $v22
vPairMVPPosF equ $v23
vPairMVPPosI equ $v24
// Mods:
vPairRGBA equ $v27

// v25: prev vertex screen pos
// v26: prev vertex screen Z
// For point lighting
mvTc0f equ $v3
mvTc0i equ $v4
mvTc1i equ $v21
mvTc1f equ $v28 // same as vPairAlpha37
mvTc2i equ $v30
mvTc2f equ $v31

// Values set up by load_spfx_global_values, which must be kept during the full
// vertex process, and which are reloaded for each vert during clipping. See
// that routine for the detailed contents of each of these registers.
// secondVtxPos
spFxBaseReg equ $13  // global
vVpFgScale  equ $v16 // All of these used locally elsewhere
vVpFgOffset equ $v17
vVpMisc     equ $v18
// These two not used in MOD_GENERAL
vFogMask    equ $v19 // Used in MOD_ATTR_OFFSETS
vVpNegScale equ $v21

// Arguments to mtx_multiply
output_mtx  equ $19 // also dmaLen, also used by itself (mods: also rClipRes)
input_mtx_1 equ $20 // also dmemAddr and xfrmLtPtr (mods: also rClipRes)
input_mtx_0 equ $21 // also clipPolyWrite

// Arguments to dma_read_write
dmaLen   equ $19 // also output_mtx, also used by itself
dmemAddr equ $20 // also input_mtx_1 and xfrmLtPtr
// cmd_w1_dram   // used for all dma_read_write DRAM addresses, not just second word of command

// Arguments to load_overlay_and_enter
ovlTableEntry equ $11 // Commonly used locally
postOvlRA     equ $12 // Commonly used locally

// ==== Summary of uses of all registers
// $zero: Hardwired zero scalar register
// $1: vertex 1 addr, count of remaining vertices, pointer to store texture coefficients, local
// $2: vertex 2 addr, vertex at end of edge in clipping, pointer to store shade coefficients, local
// $3: vertex 3 addr, vertex at start of edge in clipping, local
// $4: pre-shuffle vertex 1 addr for flat shading (mods: got rid of, available local), local
// $5: clipMaskIdx, geometry mode high short during vertex load / lighting, local
// $6: topLightPtr, geometry mode low byte during tri write, local
// $7: fog flag in vtx write, local
// $8: secondVtxPos, local
// $9: curLight, local
// $10: briefly used local in vtx write (mods: got rid of, not used!)
// $11: ovlTableEntry, very common local
// $12: postOvlRA, curMatrix, local
// $13: spFxBaseReg
// $14: inputVtxPos
// $15: outputVtxPos
// $16: clipFlags
// $17: clipPolyRead
// $18: clipPolySelect
// $19: dmaLen, output_mtx, briefly used local (mods: also rClipRes)
// $20: dmemAddr, input_mtx_1, xfrmLtPtr (mods: also rClipRes)
// $21: clipPolyWrite, input_mtx_0
// $22: rdpCmdBufEnd
// $23: rdpCmdBufPtr
// $24: cmd_w1_dram, local
// $25: cmd_w0
// $26: taskDataPtr
// $27: inputBufferPos
// $28: not used!
// $29: savedActiveClipPlanes (mods, got rid of, not used!)
// $30: savedRA (unused in MOD_GENERAL, used in MOD_CLIP_CHANGES)
// $ra: Return address for jal, b*al
// $v0: vZero (every element 0)
// $v1: vOne (every element 1)
// $v2: very common local
// $v3: mvTc0f, local
// $v4: mvTc0i, local
// $v5: vPairNZ, local
// $v6: vPairNY, local
// $v7: vPairNX, vPairRGBATemp, local
// $v8: mxr0i, local
// $v9: mxr1i, local
// $v10: mxr2i, local
// $v11: mxr3i, local
// $v12: mxr0f, local
// $v13: mxr1f, local
// $v14: mxr2f, local
// $v15: mxr3f, local
// $v16: vVpFgScale, local
// $v17: vVpFgOffset, local
// $v18: vVpMisc, local
// $v19: vFogMask, local
// $v20: local
// $v21: mvTc1i, vVpNegScale, local
// $v22: vPairST, local
// $v23: vPairMVPPosF, local
// $v24: vPairMVPPosI, local
// $v25: prev vertex data, local
// $v26: prev vertex data, local
// $v27: vPairRGBA, local
// $v28: mvTc1f, vPairAlpha37, local
// $v29: register to write to discard results, local
// $v30: mvTc2i, constant values for tri write
// $v31: mvTc2f, general constant values


// Initialization routines
// Everything up until displaylist_dma will get overwritten by ovl0 and/or ovl1
start: // This is at IMEM 0x1080, not the start of IMEM
.if BUG_WRONG_INIT_VZERO
    vor     vZero, $v16, $v16 // Sets vZero to $v16--maybe set to zero by the boot ucode?
.else
    vclr    vZero             // Clear vZero
.endif
    lqv     $v31[0], (v31Value)($zero)
    lqv     $v30[0], (v30Value)($zero)
    li      rdpCmdBufPtr, rdpCmdBuffer1
.if !BUG_FAIL_IF_CARRY_SET_AT_INIT
    vadd    vOne, vZero, vZero   // Consume VCO (carry) value possibly set by the previous ucode, before vsub below
.endif
    li      rdpCmdBufEnd, rdpCmdBuffer1End
.if MOD_VL_REWRITE
    vsub    vOne, vZero, $v31[1]   // -1
.else
    vsub    vOne, vZero, $v31[0]   // Vector of 1s
.endif
.if !CFG_XBUS // FIFO version
    lw      $11, rdpFifoPos
    lw      $12, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // task done and yielded signals
    beqz    $11, task_init
     mtc0   $1, SP_STATUS
    andi    $12, $12, OS_TASK_YIELDED
    beqz    $12, calculate_overlay_addrs    // skip overlay address calculations if resumed from yield?
     sw     $zero, OSTask + OSTask_flags
    j       load_overlay1_init              // Skip the initialization and go straight to loading overlay 1
     lw     taskDataPtr, OS_YIELD_DATA_SIZE - 8  // Was previously saved here at yield time
task_init:
    mfc0    $11, DPC_STATUS
    andi    $11, $11, DPC_STATUS_XBUS_DMA
    bnez    $11, wait_dpc_start_valid
     mfc0   $2, DPC_END
    lw      $3, OSTask + OSTask_output_buff
    sub     $11, $3, $2
    bgtz    $11, wait_dpc_start_valid
     mfc0   $1, DPC_CURRENT
    lw      $4, OSTask + OSTask_output_buff_size
    beqz    $1, wait_dpc_start_valid
     sub    $11, $1, $4
    bgez    $11, wait_dpc_start_valid
     nop
    bne     $1, $2, f3dzex_0000111C
wait_dpc_start_valid:
     mfc0   $11, DPC_STATUS
    andi    $11, $11, DPC_STATUS_START_VALID
    bnez    $11, wait_dpc_start_valid
     li     $11, DPC_STATUS_CLR_XBUS
    mtc0    $11, DPC_STATUS
    lw      $2, OSTask + OSTask_output_buff_size
    mtc0    $2, DPC_START
    mtc0    $2, DPC_END
f3dzex_0000111C:
    sw      $2, rdpFifoPos
.else // CFG_XBUS
wait_dpc_start_valid:
    mfc0 $11, DPC_STATUS
    andi $11, $11, DPC_STATUS_DMA_BUSY | DPC_STATUS_START_VALID 
    bne $11, $zero, wait_dpc_start_valid
     sw $zero, rdpFifoPos
    addi $11, $zero, DPC_STATUS_SET_XBUS
    mtc0 $11, DPC_STATUS
    addi rdpCmdBufPtr, $zero, rdpCmdBuffer1
    mtc0 rdpCmdBufPtr, DPC_START
    mtc0 rdpCmdBufPtr, DPC_END
    lw $12, OSTask + OSTask_flags
    addi $1, $zero, SP_CLR_SIG2 | SP_CLR_SIG1
    mtc0 $1, SP_STATUS
    andi $12, $12, OS_TASK_YIELDED
    beqz $12, f3dzex_xbus_0000111C
     sw $zero, OSTask + OSTask_flags
    j load_overlay1_init
     lw taskDataPtr, OS_YIELD_DATA_SIZE - 8 // Was previously saved here at yield time
.fill 16 * 4 // Bunch of nops here to make it the same size as the fifo code.
f3dzex_xbus_0000111C:
.endif
    lw      $11, matrixStackPtr
    bnez    $11, calculate_overlay_addrs
     lw     $11, OSTask + OSTask_dram_stack
    sw      $11, matrixStackPtr
calculate_overlay_addrs:
    lw      $1, OSTask + OSTask_ucode
    lw      $2, overlayInfo0 + overlay_load
    lw      $3, overlayInfo1 + overlay_load
    lw      $4, overlayInfo2 + overlay_load
    lw      $5, overlayInfo3 + overlay_load
    add     $2, $2, $1
    add     $3, $3, $1
    sw      $2, overlayInfo0 + overlay_load
    sw      $3, overlayInfo1 + overlay_load
    add     $4, $4, $1
    add     $5, $5, $1
    sw      $4, overlayInfo2 + overlay_load
    sw      $5, overlayInfo3 + overlay_load
    lw      taskDataPtr, OSTask + OSTask_data_ptr
load_overlay1_init:
    li      ovlTableEntry, overlayInfo1   // set up loading of overlay 1

// Make room for overlays 0 and 1. Normally, overlay 1 ends exactly at ovl01_end,
// and overlay 0 is much shorter, but if things are modded this constraint must be met.
// The 0x88 is because the file starts 0x80 into IMEM, and the overlays can extend 8
// bytes over the next two instructions as well.
.orga max(orga(), max(ovl0_end - ovl0_start, ovl1_end - ovl1_start) - 0x88)

// Also needs to be aligned so that ovl01_end is a DMA word, in case ovl0 and ovl1
// are shorter than the code above and the code above is an odd number of instructions.
.align 8

// Unnecessarily clever code. The jal sets $ra to the address of the next instruction,
// which is displaylist_dma. So the padding has to be before these two instructions,
// so that this is immediately before displaylist_dma; otherwise the return address
// will be in the last few instructions of overlay 1. However, this was unnecessary--
// it could have been a jump and then `la postOvlRA, displaylist_dma`,
// and the padding put after this.
    jal     load_overlay_and_enter  // load overlay 1 and enter
     move   postOvlRA, $ra          // set up the return address, since load_overlay_and_enter returns to postOvlRA

ovl01_end:
// Overlays 0 and 1 overwrite everything up to this point (2.08 versions overwrite up to the previous .align 8)

displaylist_dma: // loads inputBufferLength bytes worth of displaylist data via DMA into inputBuffer
    li      dmaLen, inputBufferLength - 1               // set the DMA length
    move    cmd_w1_dram, taskDataPtr                    // set up the DRAM address to read from
    jal     dma_read_write                              // initiate the DMA read
     la     dmemAddr, inputBuffer                       // set the address to DMA read to
    addiu   taskDataPtr, taskDataPtr, inputBufferLength // increment the DRAM address to read from next time
    li      inputBufferPos, -inputBufferLength          // reset the DL word index
wait_for_dma_and_run_next_command:
G_POPMTX_end:
G_MOVEMEM_end:
    jal     while_wait_dma_busy                         // wait for the DMA read to finish
.if !MOD_GENERAL
G_LINE3D_handler:
.endif
G_SPNOOP_handler:
.if !MOD_GENERAL
.if !CFG_G_SPECIAL_1_IS_RECALC_MVP                      // F3DEX2 2.04H has this as a real command
G_SPECIAL_1_handler:
.endif
G_SPECIAL_2_handler:
G_SPECIAL_3_handler:
.endif
run_next_DL_command:
     mfc0   $1, SP_STATUS                               // load the status word into register $1
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // load the command word into cmd_w0
    beqz    inputBufferPos, displaylist_dma             // load more DL commands if none are left
     andi   $1, $1, SP_STATUS_SIG0                      // check if the task should yield
    sra     $12, cmd_w0, 24                             // extract DL command byte from command word
.if !MOD_CMD_JUMP_TABLE
    sll     $11, $12, 1                                 // multiply command byte by 2 to get jump table offset
    lhu     $11, (commandJumpTable)($11)                // get command subroutine address from command jump table
.endif
    bnez    $1, load_overlay_0_and_enter                // load and execute overlay 0 if yielding; $1 > 0
     lw     cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // load the next DL word into cmd_w1_dram
.if !MOD_CMD_JUMP_TABLE
    jr      $11                                         // jump to the loaded command handler; $1 == 0
.endif
     addiu  inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
.if MOD_CMD_JUMP_TABLE
    // $12 must retain the command byte for load_mtx, and $11 must contain the handler called for G_SETOTHERMODE_H_handler
    addiu   $2, $12, -G_VTX                             // If >= G_VTX, use jump table
    bgez    $2, do_cmd_jump_table                       // $2 is the index
     addiu  $11, $2, (cmdJumpTablePositive - cmdJumpTableForwardBack) / 2 // Will be interpreted relative to other jump table
    addiu   $2, $2, G_VTX - (0xFF00 | G_SETTIMG)        // If >= G_SETTIMG, use handler; for G_NOOP, this puts
    bgez    $2, G_SETxIMG_handler                       // garbage in second word, but normal handler does anyway
     addiu  $3, $2, G_SETTIMG - G_SETTILESIZE           // If >= G_SETTILESIZE, use handler
    bgez    $3, G_RDP_handler
     addiu  $11, $3, G_SETTILESIZE - G_SETSCISSOR       // If >= G_SETSCISSOR, use jump table
    bgez    $11, do_cmd_jump_table
     nop
    addiu   $11, $11, G_SETSCISSOR - G_RDPLOADSYNC      // If >= G_RDPLOADSYNC, use handler; for the syncs, this
    bgez    $11, G_RDP_handler                          // stores the second command word, but that's fine
do_cmd_jump_table:                                      // If fell through, $1 has cmdJumpTableForwardBack and $12 is negative pointing into it
     sll    $11, $11, 1                                 // Multiply jump table index in $2 by 2 for addr offset
    lhu     $11, cmdJumpTableForwardBack($11)           // Load address of handler from jump table
    jr      $11                                         // Jump to handler
.endif

.if MOD_CMD_JUMP_TABLE
    // Move this up here, so that the branch delay slot of the jr above is harmless.
G_ENDDL_handler:
    lbu     $1, displayListStackLength          // Load the DL stack index
    beqz    $1, load_overlay_0_and_enter        // Load overlay 0 if there is no DL return address, to end the graphics task processing; $1 < 0
     addi   $1, $1, -4                          // Decrement the DL stack index
    j       f3dzex_ovl1_00001020                // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($1) // Load the address of the DL to return to into the taskDataPtr (the current DL address)
.endif

.if CFG_G_SPECIAL_1_IS_RECALC_MVP // Microcodes besides F3DEX2 2.04H have this as a noop
.if MOD_GENERAL
    .error "MOD_GENERAL is incompatible with CFG_G_SPECIAL_1_IS_RECALC_MVP"
.else
G_SPECIAL_1_handler:    // Seems to be a manual trigger for mvp recalculation
    li      $ra, run_next_DL_command
    li      input_mtx_0, pMatrix
    li      input_mtx_1, mvMatrix
    li      output_mtx, mvpMatrix
    j       mtx_multiply
     sb     cmd_w0, mvpValid
.endif
.endif

G_DMA_IO_handler:
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra     dmemAddr, dmemAddr, 2
    j       dma_read_write  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     li     $ra, wait_for_dma_and_run_next_command  // Setup the return address for running the next DL command

G_GEOMETRYMODE_handler:
    lw      $11, geometryModeLabel  // load the geometry mode value
    and     $11, $11, cmd_w0        // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      $11, $11, cmd_w1_dram   // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    j       run_next_DL_command     // run the next DL command
     sw     $11, geometryModeLabel  // update the geometry mode value

.if !MOD_CMD_JUMP_TABLE             // Moved up to above for branch reasons.
G_ENDDL_handler:
    lbu     $1, displayListStackLength          // Load the DL stack index
    beqz    $1, load_overlay_0_and_enter        // Load overlay 0 if there is no DL return address, to end the graphics task processing; $1 < 0
     addi   $1, $1, -4                          // Decrement the DL stack index
    j       f3dzex_ovl1_00001020                // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($1) // Load the address of the DL to return to into the taskDataPtr (the current DL address)
.endif

G_RDPHALF_2_handler:
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val                 // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
    sdv     $v29[0], -8(rdpCmdBufPtr)
G_RDP_handler:
    sw      cmd_w1_dram, 4(rdpCmdBufPtr)        // Add the second word of the command to the RDP command buffer
G_SYNC_handler:
G_NOOP_handler:
    sw      cmd_w0, 0(rdpCmdBufPtr)         // Add the command word to the RDP command buffer
    j       check_rdp_buffer_full_and_run_next_cmd
     addi   rdpCmdBufPtr, rdpCmdBufPtr, 8   // Increment the next RDP command pointer by 2 words

G_SETxIMG_handler:
    li      $ra, G_RDP_handler          // Load the RDP command handler into the return address, then fall through to convert the address to virtual
// Converts the segmented address in cmd_w1_dram to the corresponding physical address
segmented_to_physical:
    srl     $11, cmd_w1_dram, 22          // Copy (segment index << 2) into $11
    andi    $11, $11, 0x3C                // Clear the bottom 2 bits that remained during the shift
    lw      $11, (segmentTable)($11)      // Get the current address of the segment
    sll     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address to the left so that the top 8 bits are shifted out
    srl     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr      $ra
     add    cmd_w1_dram, cmd_w1_dram, $11 // Add the segment's address to the masked input address, resulting in the virtual address

G_RDPSETOTHERMODE_handler:
    sw      cmd_w0, otherMode0       // Record the local otherMode0 copy
    j       G_RDP_handler            // Send the command to the RDP
     sw     cmd_w1_dram, otherMode1  // Record the local otherMode1 copy

G_SETSCISSOR_handler:
    sw      cmd_w0, scissorUpLeft            // Record the local scissorUpleft copy
    j       G_RDP_handler                    // Send the command to the RDP
     sw     cmd_w1_dram, scissorBottomRight  // Record the local scissorBottomRight copy

check_rdp_buffer_full_and_run_next_cmd:
    li      $ra, run_next_DL_command    // Set up running the next DL command as the return address

.if !CFG_XBUS // FIFO version
check_rdp_buffer_full:
     sub    $11, rdpCmdBufPtr, rdpCmdBufEnd
    blez    $11, return_routine         // Return if rdpCmdBufEnd >= rdpCmdBufPtr
flush_rdp_buffer:
     mfc0   $12, SP_DMA_BUSY
    lw      cmd_w1_dram, rdpFifoPos
    addiu   dmaLen, $11, RDP_CMD_BUFSIZE
    bnez    $12, flush_rdp_buffer
     lw     $12, OSTask + OSTask_output_buff_size
    mtc0    cmd_w1_dram, DPC_END
    add     $11, cmd_w1_dram, dmaLen
    sub     $12, $12, $11
    bgez    $12, f3dzex_000012A8
@@await_start_valid:
     mfc0   $11, DPC_STATUS
    andi    $11, $11, DPC_STATUS_START_VALID
    bnez    $11, @@await_start_valid
     lw     cmd_w1_dram, OSTask + OSTask_output_buff
f3dzex_00001298:
    mfc0    $11, DPC_CURRENT
    beq     $11, cmd_w1_dram, f3dzex_00001298
     nop
    mtc0    cmd_w1_dram, DPC_START
f3dzex_000012A8:
    mfc0    $11, DPC_CURRENT
    sub     $11, $11, cmd_w1_dram
    blez    $11, f3dzex_000012BC
     sub    $11, $11, dmaLen
    blez    $11, f3dzex_000012A8
f3dzex_000012BC:
     add    $11, cmd_w1_dram, dmaLen
    sw      $11, rdpFifoPos
    // Set up the DMA from DMEM to the RDP fifo in RDRAM
    addi    dmaLen, dmaLen, -1                                  // subtract 1 from the length
    addi    dmemAddr, rdpCmdBufEnd, -(0x2000 | RDP_CMD_BUFSIZE) // The 0x2000 is meaningless, negative means write
    xori    rdpCmdBufEnd, rdpCmdBufEnd, rdpCmdBuffer1End ^ rdpCmdBuffer2End // Swap between the two RDP command buffers
    j       dma_read_write
     addi   rdpCmdBufPtr, rdpCmdBufEnd, -RDP_CMD_BUFSIZE
.else // CFG_XBUS
check_rdp_buffer_full:
    addi $11, rdpCmdBufPtr, -(OSTask - RDP_CMD_BUFSIZE_EXCESS)
    blez $11, ovl0_04001284
     mtc0 rdpCmdBufPtr, DPC_END
ovl0_04001260:
    mfc0 $11, DPC_STATUS
    andi $11, $11, DPC_STATUS_END_VALID | DPC_STATUS_START_VALID
    bne $11, $zero, ovl0_04001260
ovl0_0400126C:
     mfc0 $11, DPC_CURRENT
    addi rdpCmdBufPtr, $zero, rdpCmdBuffer1
    beq $11, rdpCmdBufPtr, ovl0_0400126C
     nop
    mtc0 rdpCmdBufPtr, DPC_START
    mtc0 rdpCmdBufPtr, DPC_END
ovl0_04001284:
    mfc0 $11, DPC_CURRENT
    sub $11, $11, rdpCmdBufPtr
    blez $11, ovl0_0400129C
     addi $11, $11, -RDP_CMD_BUFSIZE_EXCESS
    blez $11, ovl0_04001284
     nop
ovl0_0400129C:
    jr $ra
     nop
.endif

.align 8
ovl23_start:

ovl3_start:

// Jump here to do lighting. If overlay 3 is loaded (this code), loads and jumps
// to overlay 2 (same address as right here).
ovl23_lighting_entrypoint_copy:  // same IMEM address as ovl23_lighting_entrypoint
    li      ovlTableEntry, overlayInfo2          // set up a load for overlay 2
    j       load_overlay_and_enter               // load overlay 2
     li     postOvlRA, ovl23_lighting_entrypoint // set the return address

// Jump here to do clipping. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl23_clipping_entrypoint:
.if MOD_GENERAL
    sh      $ra, modSaveRA
.else
    move    savedRA, $ra
.endif
ovl3_clipping_nosavera:
.if MOD_GENERAL
    sh      $4, modSaveFlatR4
.endif
.if MOD_CLIP_CHANGES
.if MOD_VL_REWRITE
    vxor    vZero, vZero, vZero
    jal     vl_mod_setup_constants
.else
    jal     load_spfx_global_values
.endif
     la     clipMaskIdx, 4
.else
    la      clipMaskIdx, 0x0014
.endif
.if MOD_VL_REWRITE
    vsub    vOne, vZero, $v31[1] // -1; 1 = 0 - -1
.endif
    la      clipPolySelect, 6  // Everything being indexed from 6 saves one instruction at the end of the loop
.if MOD_CLIP_CHANGES
    // Using $30 (formerly savedRA) for two things:
    // - Greater than zero if doing clipping, less than zero if normal tri draw outside clipping.
    //   For whether to check clip masks.
    // - Tracking how many vertices have been written. This is relative to clipTempVerts,
    //   but once that is exhausted and wraps, and eventually searches, this keeps going up.
    la      $30, clipTempVerts - vtxSize
.else
    la      outputVtxPos, clipTempVerts
.endif
    // Write the current three verts as the initial polygon
    sh      $1, (clipPoly - 6 + 0)(clipPolySelect)
    sh      $2, (clipPoly - 6 + 2)(clipPolySelect)
    sh      $3, (clipPoly - 6 + 4)(clipPolySelect)
    sh      $zero, (clipPoly)(clipPolySelect) // Zero to mark end of polygon
.if !MOD_CLIP_CHANGES
    lw      savedActiveClipPlanes, activeClipPlanes
.endif
.if MOD_CLIP_CHANGES
    la      $9, CLIP_NEAR >> 4                       // Initial clip mask for no nearclipping
.endif
// Available locals here: $11, $1, $7, $20, $24, $12
clipping_condlooptop: // Loop over six clipping conditions: near, far, +y, +x, -y, -x
.if MOD_CLIP_CHANGES
    lhu     clipFlags, VTX_CLIP($3)                  // Load flags for V3, which will be the final vertex of the last polygon
.else
    lw      $9, (clipMaskList)(clipMaskIdx)          // Load clip mask
    lw      clipFlags, VTX_CLIP($3)                  // Load flags for V3, which will be the final vertex of the last polygon
.endif
    and     clipFlags, clipFlags, $9                 // Mask V3's flags to current clip condition
    addi    clipPolyRead,   clipPolySelect, -6       // Start reading at the beginning of the old polygon
    xori    clipPolySelect, clipPolySelect, 6 ^ (clipPoly2 + 6 - clipPoly) // Swap to the other polygon memory
    addi    clipPolyWrite,  clipPolySelect, -6       // Start writing at the beginning of the new polygon
clipping_edgelooptop: // Loop over edges connecting verts, possibly subdivide the edge
    // Edge starts from V3, ends at V2
    lhu     $2, (clipPoly)(clipPolyRead)       // Read next vertex of input polygon as V2 (end of edge)
    addi    clipPolyRead, clipPolyRead, 0x0002 // Increment read pointer
    beqz    $2, clipping_nextcond              // If V2 is 0, done with input polygon
.if MOD_CLIP_CHANGES
     lhu    $11, VTX_CLIP($2)                  // Load flags for V2
.else
     lw     $11, VTX_CLIP($2)                  // Load flags for V2
.endif
    and     $11, $11, $9                       // Mask V2's flags to current clip condition
    beq     $11, clipFlags, clipping_nextedge  // Both set or both clear = both off screen or both on screen, no subdivision
     move   clipFlags, $11                     // clipFlags = masked V2's flags
    // Going to subdivide this edge
.if MOD_CLIP_CHANGES
    addiu   $30, $30, vtxSize                  // Next vertex
    move    outputVtxPos, $30
    // TODO more logic for wrap, search, etc.
clipping_mod_contsetupsubdivide:
.endif
    beqz    clipFlags, clipping_skipswap23     // V2 flag is clear / on screen, therefore V3 is set / off screen
     move   $19, $2                            // 
    move    $19, $3                            // Otherwise swap V2 and V3; note we are overwriting $3 but not $2
    move    $3, $2                             // 
clipping_skipswap23: // After possible swap, $19 = vtx not meeting clip cond / on screen, $3 = vtx meeting clip cond / off screen
.if MOD_CLIP_CHANGES
    // Determine if doing screen or scaled clipping
    andi    $11, clipMaskIdx, 4
    bnez    $11, clipping_interpolate          // If W, screen clipping
     la     $4, 0
    lhu     $11, VTX_CLIP($3)                  // Load flags for offscreen vertex
    srl     $11, $11, 4                        // Look at scaled rather than screen clipping
    and     $4, $11, $9                        // Mask to current clip condition; $4 is nonzero if outside scaled box
clipping_interpolate:
.endif
    // Interpolate between these two vertices; create a new vertex which is on the
    // clipping boundary (e.g. at the screen edge)
vClBaseF equ $v8
vClBaseI equ $v9
vClDiffF equ $v10
vClDiffI equ $v11
.if !MOD_CLIP_CHANGES
    sll     $11, clipMaskIdx, 1  // clipMaskIdx counts by 4, so this is now by 8
    ldv     $v2[0], (clipRatio)($11) // Load four shorts holding clip ratio for this clip condition
.endif
    ldv     $v4[0], VTX_FRAC_VEC($19) // Vtx on screen, frac pos
    ldv     $v5[0], VTX_INT_VEC ($19) // Vtx on screen, int pos
.if MOD_CLIP_CHANGES
    /*
    Five clip conditions (these are in a different order from vanilla):
           vClBaseI/vClBaseF[3]     vClDiffI/vClDiffF[3]
    4 W=0:             W1                 W1  -         W2
    3 +X :      X1 - 2*W1         (X1 - 2*W1) - (X2 - 2*W2) <- the 2 is clip ratio, can be changed
    2 -X :      X1 + 2*W1         (X1 + 2*W1) - (X2 + 2*W2)    it is 1 if we are doing screen clipping
    1 +Y :      Y1 - 2*W1         (Y1 - 2*W1) - (Y2 - 2*W2)
    0 -Y :      Y1 + 2*W1         (Y1 + 2*W1) - (Y2 + 2*W2)
    */
.if MOD_VL_REWRITE
    xori    $11, clipMaskIdx, 1              // Invert sign of condition
    ctc2    $11, $vcc                        // Conditions 1 (+y) or 3 (+x) -> vcc[0] = 0
    ldv     $v4[8], VTX_FRAC_VEC($3)         // Vtx off screen, frac pos
    vmrg    $v29, vOne, $v31[1]              // elem 0 is 1 if W or neg cond, -1 if pos cond
    beqz    $4, clipping_mod_skipnoclipratio // If $4 = 0 (screen clipping), branch and use 1 or -1
     ldv    $v5[8], VTX_INT_VEC ($3)         // Vtx off screen, int pos
    vmudh   $v29, $v29, vVpMisc[6]           // elem 0 is (1 or -1) * clipRatio
.else
    vmudh   $v29, $v31, vVpMisc[5]           // v29[0] = -clipRatio (v31[0] = -1)
    ldv     $v4[8], VTX_FRAC_VEC($3)         // Vtx off screen, frac pos
    ctc2    clipMaskIdx, $vcc                // Conditions 1 (+y) or 3 (+x) -> vcc[0] = 1
    ldv     $v5[8], VTX_INT_VEC ($3)         // Vtx off screen, int pos
    bnez    $4, clipping_mod_skipnoclipratio // If $4 = 0, don't branch and use -1 or 1
     vmrg   $v29, $v29, vVpMisc[5]           // vcc[0] = 1 -> v29[0] = -clipRatio, else clipRatio
    vmrg    $v29, $v31, vOne                 // vcc[0] = 1 -> v29[0] = -1, else 1
.endif
clipping_mod_skipnoclipratio:
    andi    $11, clipMaskIdx, 4              // W condition
    vor     vClBaseF, vZero, $v4             // Result is just W
    bnez    $11, clipping_mod_skipxy
     vor    vClBaseI, vZero, $v5
    andi    $11, clipMaskIdx, 2              // Conditions 2 (-x) or 3 (+x)
    vmudm   vClBaseF, vOne, $v4[0h]          // Set accumulator (care about 3, 7) to X
    bnez    $11, clipping_mod_skipy
     vmadh  vClBaseI, vOne, $v5[0h]
    vmudm   vClBaseF, vOne, $v4[1h]          // Discard that and set accumulator 3, 7 to Y
    vmadh   vClBaseI, vOne, $v5[1h]
clipping_mod_skipy:
    vmadn   vClBaseF, $v4, $v29[0]           // + W * +/- clipRatio
    vmadh   vClBaseI, $v5, $v29[0]
clipping_mod_skipxy:
    vsubc   vClDiffF, vClBaseF, vClBaseF[7]  // Vtx on screen - vtx off screen
    lqv     $v25[0], (linearGenerateCoefficients)($zero) // Used just to load the value 2
    vsub    vClDiffI, vClBaseI, vClBaseI[7]
.else
    ldv     $v6[0], VTX_FRAC_VEC($3)         // Vtx off screen, frac pos
    ldv     $v7[0], VTX_INT_VEC ($3)         // Vtx off screen, int pos
.if MOD_VL_REWRITE
    vmudh   $v3, $v2, $v31[1]                // -1; v3 = -clipRatio
.else
    vmudh   $v3, $v2, $v31[0]                // v3 = -clipRatio
.endif
    vmudn   vClBaseF, $v4, $v2               // frac:   vtx on screen * clip ratio
    vmadh   vClBaseI, $v5, $v2               // int:  + vtx on screen * clip ratio   9:8
    vmadn   vClDiffF, $v6, $v3               // frac: - vtx off screen * clip ratio
    vmadh   vClDiffI, $v7, $v3               // int:  - vtx off screen * clip ratio 11:10
    vaddc   vClBaseF, vClBaseF, vClBaseF[0q] // frac: y += x, w += z, vtx on screen only
    lqv     $v25[0], (linearGenerateCoefficients)($zero) // Used just to load the value 2
    vadd    vClBaseI, vClBaseI, vClBaseI[0q] // int:  y += x, w += z, vtx on screen only
    vaddc   vClDiffF, vClDiffF, vClDiffF[0q] // frac: y += x, w += z, vtx on screen - vtx off screen
    vadd    vClDiffI, vClDiffI, vClDiffI[0q] // int:  y += x, w += z, vtx on screen - vtx off screen
    vaddc   vClBaseF, vClBaseF, vClBaseF[1h] // frac: w += y (sum of all 4), vtx on screen only
    vadd    vClBaseI, vClBaseI, vClBaseI[1h] // int:  w += y (sum of all 4), vtx on screen only
    vaddc   vClDiffF, vClDiffF, vClDiffF[1h] // frac: w += y (sum of all 4), vtx on screen - vtx off screen
    vadd    vClDiffI, vClDiffI, vClDiffI[1h] // int:  w += y (sum of all 4), vtx on screen - vtx off screen
.endif
    // Not sure what the first reciprocal is for.
.if BUG_CLIPPING_FAIL_WHEN_SUM_ZERO       // Only in F3DEX2 2.04H
    vrcph   $v29[0], vClDiffI[3]          // int:  1 / (x+y+z+w), vtx on screen - vtx off screen
.else
    vor     $v29, vClDiffI, vOne[0]       // round up int sum to odd; this ensures the value is not 0, otherwise v29 will be 0 instead of +/- 2
    vrcph   $v3[3], vClDiffI[3]
.endif
    vrcpl   $v2[3], vClDiffF[3]           // frac: 1 / (x+y+z+w), vtx on screen - vtx off screen
    vrcph   $v3[3], vZero[0]              // get int result of reciprocal
.if BUG_CLIPPING_FAIL_WHEN_SUM_ZERO       // Only in F3DEX2 2.04H
    vabs    $v29, vClDiffI, $v25[3]       // 0x0002 // v29 = +/- 2 based on sum positive or negative (Bug: or 0 if sum is 0)
.else
    vabs    $v29, $v29, $v25[3]           // 0x0002 // v29 = +/- 2 based on sum positive (incl. zero) or negative
.endif
    vmudn   $v2, $v2, $v29[3]             // multiply reciprocal by +/- 2
    vmadh   $v3, $v3, $v29[3]
    veq     $v3, $v3, vZero[0]            // if reciprocal high is 0
.if MOD_VL_REWRITE
    vmrg    $v2, $v2, $v31[1]             // keep reciprocal low, otherwise set to -1
.else
    vmrg    $v2, $v2, $v31[0]             // keep reciprocal low, otherwise set to -1
.endif
    vmudl   $v29, vClDiffF, $v2[3]        // sum frac * reciprocal, discard
    vmadm   vClDiffI, vClDiffI, $v2[3]    // sum int * reciprocal, frac out
    vmadn   vClDiffF, vZero, vZero[0]     // get int out
    vrcph   $v13[3], vClDiffI[3]          // reciprocal again (discard result)
    vrcpl   $v12[3], vClDiffF[3]          // frac part
    vrcph   $v13[3], vZero[0]             // int part
    vmudl   $v29, $v12, vClDiffF          // self * own reciprocal? frac*frac discard
    vmadm   $v29, $v13, vClDiffF          // self * own reciprocal? int*frac discard
    vmadn   vClDiffF, $v12, vClDiffI      // self * own reciprocal? frac out
    vmadh   vClDiffI, $v13, vClDiffI      // self * own reciprocal? int out
.if MOD_VL_REWRITE
    vmudh   $v29, vOne, vVpMisc[3]        // 4 (int part), Newton-Raphson algorithm
    vmadn   vClDiffF, vClDiffF, $v31[0]   // - 4 * prev result frac part
    vmadh   vClDiffI, vClDiffI, $v31[0]   // - 4 * prev result frac part
.else
    vmudh   $v29, vOne, $v31[1]           // 4 (int part), Newton-Raphson algorithm
    vmadn   vClDiffF, vClDiffF, $v31[4]   // - 4 * prev result frac part
    vmadh   vClDiffI, vClDiffI, $v31[4]   // - 4 * prev result frac part
.endif
    vmudl   $v29, $v12, vClDiffF          // * own reciprocal again? frac*frac discard
    vmadm   $v29, $v13, vClDiffF          // * own reciprocal again? int*frac discard
    vmadn   $v12, $v12, vClDiffI          // * own reciprocal again? frac out
    vmadh   $v13, $v13, vClDiffI          // * own reciprocal again? int out
    vmudl   $v29, vClBaseF, $v12
.if MOD_CLIP_CHANGES
    // Have to load $v6 and $v7 because they were not loaded above.
    // Also, put color/TC in $v12 and $v13 instead of $v26 and $v25 as the former
    // will survive vertices_store.
    ldv     $v6[0], VTX_FRAC_VEC($3)      // Vtx off screen, frac pos
.else
    luv     $v26[0], VTX_COLOR_VEC($3)    // Vtx off screen, RGBA
.endif
    vmadm   $v29, vClBaseI, $v12
.if MOD_CLIP_CHANGES
    ldv     $v7[0], VTX_INT_VEC ($3)      // Vtx off screen, int pos
.else
    llv     $v26[8], VTX_TC_VEC   ($3)    // Vtx off screen, ST
.endif
    vmadn   vClDiffF, vClBaseF, $v13
.if MOD_CLIP_CHANGES
    luv     $v12[0], VTX_COLOR_VEC($3)    // Vtx off screen, RGBA
.else
    luv     $v25[0], VTX_COLOR_VEC($19)   // Vtx on screen, RGBA
.endif
    vmadh   vClDiffI, vClBaseI, $v13      // 11:10 = vtx on screen sum * prev calculated value
.if MOD_VL_REWRITE
    llv     $v14[0], VTX_TC_VEC   ($3)    // Vtx off screen, ST
.elseif MOD_CLIP_CHANGES
    llv     $v12[8], VTX_TC_VEC   ($3)    // Vtx off screen, ST
.else
    llv     $v25[8], VTX_TC_VEC   ($19)   // Vtx on screen, ST
.endif
    vmudl   $v29, vClDiffF, $v2[3]
.if MOD_CLIP_CHANGES
    luv     $v13[0], VTX_COLOR_VEC($19)   // Vtx on screen, RGBA
.endif
    vmadm   vClDiffI, vClDiffI, $v2[3]
.if MOD_VL_REWRITE
    llv     vPairST[0], VTX_TC_VEC   ($19)   // Vtx on screen, ST
.elseif MOD_CLIP_CHANGES
    llv     $v13[8], VTX_TC_VEC   ($19)   // Vtx on screen, ST
.endif
    vmadn   vClDiffF, vClDiffF, vZero[0]  // * one of the reciprocals above
    // Clamp fade factor
    vlt     vClDiffI, vClDiffI, vOne[0]   // If integer part of factor less than 1,
.if MOD_VL_REWRITE
    vmrg    vClDiffF, vClDiffF, $v31[1]   // keep frac part of factor, else set to 0xFFFF (max val)
.else
    vmrg    vClDiffF, vClDiffF, $v31[0]   // keep frac part of factor, else set to 0xFFFF (max val)
.endif
    vsubc   $v29, vClDiffF, vOne[0]       // frac part - 1 for carry
    vge     vClDiffI, vClDiffI, vZero[0]  // If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
vClFade1 equ $v10 // = vClDiffF
vClFade2 equ $v2
    vmrg    vClFade1, vClDiffF, vOne[0]   // keep frac part of factor, else set to 1 (min val)
.if MOD_VL_REWRITE
    vmudn   vClFade2, vClFade1, $v31[1]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for on screen vert
.else
    vmudn   vClFade2, vClFade1, $v31[0]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for on screen vert
.endif
    // Fade between attributes for on screen and off screen vert
.if MOD_CLIP_CHANGES
    // Save on-screen fade factor * on screen W in $v9:$v8.
    // Also, colors are now in $v12 and $v13.
    vmudl   $v29, $v4, vClFade2[3]        //   Fade factor for on  screen vert * on  screen vert pos frac
    vmadm   $v9, $v5, vClFade2[3]         // + Fade factor for on  screen vert * on  screen vert pos int
    vmadn   $v8, vZero, vZero             // Load resulting frac pos
    vmadl   $v29, $v6, vClFade1[3]        // + Fade factor for off screen vert * off screen vert pos frac
    vmadm   vPairMVPPosI, $v7, vClFade1[3] // + Fade factor for off screen vert * off screen vert pos int
    vmadn   vPairMVPPosF, vZero, vZero[0] // Load resulting frac pos
.if MOD_VL_REWRITE
    vmudm   $v29, $v14, vClFade1[3]       //   Fade factor for off screen vert * off screen vert TC
    vmadm   vPairST, vPairST, vClFade2[3] // + Fade factor for on  screen vert * on  screen vert TC
    vmudm   $v29, $v12, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color
    vmadm   vPairRGBA, $v13, vClFade2[3]  // + Fade factor for on  screen vert * on  screen vert color
.else
    vmudm   $v29, $v12, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color and TC
    vmadm   vPairST, $v13, vClFade2[3]    // + Fade factor for on  screen vert * on  screen vert color and TC
.endif
.else
    vmudl   $v29, $v6, vClFade1[3]        //   Fade factor for off screen vert * off screen vert pos frac
    vmadm   $v29, $v7, vClFade1[3]        // + Fade factor for off screen vert * off screen vert pos int
    vmadl   $v29, $v4, vClFade2[3]        // + Fade factor for on  screen vert * on  screen vert pos frac
    vmadm   vPairMVPPosI, $v5, vClFade2[3] //+ Fade factor for on  screen vert * on  screen vert pos int
    vmadn   vPairMVPPosF, vZero, vZero[0] // Load resulting frac pos
    vmudm   $v29, $v26, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color and TC
    vmadm   vPairST, $v25, vClFade2[3]    // + Fade factor for on  screen vert * on  screen vert color and TC
.endif
    li      $7, 0x0000                    // Set no fog
.if MOD_VL_REWRITE
    jal     vl_mod_vtx_store
     move   secondVtxPos, outputVtxPos
.else
    li      $1, 0x0002                    // Set vertex count to 1, so will only write one
.if MOD_CLIP_CHANGES
    addi    secondVtxPos, rdpCmdBufPtr, 2*vtxSize // Second vertex is unused memory in command buffer
    j       vertices_store
     li     $ra, -1                       // comes back here, via bltz $ra, clipping_after_vtxwrite
.else
    sh      outputVtxPos, (clipPoly)(clipPolyWrite) // Add the address of the new vert to the output polygon
    j       load_spfx_global_values // Goes to load_spfx_global_values, then to vertices_store, then
     li     $ra, vertices_store + 0x8000 // comes back here, via bltz $ra, clipping_after_vtxwrite
.endif
.endif

clipping_after_vtxwrite:
// outputVtxPos has been incremented by 2 * vtxSize
// Store last vertex attributes which were skipped by the early return
.if MOD_CLIP_CHANGES
.if MOD_VL_REWRITE
    vmudl   $v29, $v8, vVpMisc[2]         // interp * W * persp norm
    andi    $11, clipMaskIdx, 4           // Is W?
    vmadm   $v9, $v9, vVpMisc[2]
.else
    vmudl   $v29, $v8, vVpMisc[4]         // interp * W * persp norm
    andi    $11, clipMaskIdx, 4           // Is W?
    vmadm   $v9, $v9, vVpMisc[4]
.endif
    or      $11, $11, $4                  // Or scaled clipping?
    vmadn   $v8, vZero, vZero
    bnez    $11, clipping_mod_skipfixcolor // Don't do perspective-incorrect color interpolation
.if MOD_VL_REWRITE
     vmudl  $v29, $v8, $v28               // $v30:$v28 still contains computed 1/W
    vmadm   $v29, $v9, $v28
    vmadn   vClDiffF, $v8, $v30
    vmadh   vClDiffI, $v9, $v30
.else
     suv    vPairST[0], (VTX_COLOR_VEC  - 2 * vtxSize)(outputVtxPos) // Store linearly interpolated color
    vmudl   $v29, $v8, $v5                // $v4:$v5 still contains computed 1/W
    vmadm   $v29, $v9, $v5
    vmadn   vClDiffF, $v8, $v4
    vmadh   vClDiffI, $v9, $v4
.endif
    // Clamp fade factor (same code as above, except the input and therefore vClFade1 is for on screen vert)
    vlt     vClDiffI, vClDiffI, vOne[0]   // If integer part of factor less than 1,
.if MOD_VL_REWRITE
    vmrg    vClDiffF, vClDiffF, $v31[1]   // keep frac part of factor, else set to 0xFFFF (max val)
.else
    vmrg    vClDiffF, vClDiffF, $v31[0]   // keep frac part of factor, else set to 0xFFFF (max val)
.endif
    vsubc   $v29, vClDiffF, vOne[0]       // frac part - 1 for carry
    vge     vClDiffI, vClDiffI, vZero[0]  // If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    vmrg    vClFade1, vClDiffF, vOne[0]   // keep frac part of factor, else set to 1 (min val)
.if MOD_VL_REWRITE
    vmudn   vClFade2, vClFade1, $v31[1]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for off screen vert
.else
    vmudn   vClFade2, vClFade1, $v31[0]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for off screen vert
.endif
    // Interpolate colors
    vmudm   $v29, $v12, vClFade2[3]       //   Fade factor for off screen vert * off screen vert color and TC
    vmadm   $v8, $v13, vClFade1[3]        // + Fade factor for on  screen vert * on  screen vert color and TC
.if MOD_VL_REWRITE
    suv     $v8[0],     (VTX_COLOR_VEC )(outputVtxPos)
    slv     vPairST[0], (VTX_TC_VEC    )(outputVtxPos)
.else
    suv     $v8[0],     (VTX_COLOR_VEC  - 2 * vtxSize)(outputVtxPos)
.endif
clipping_mod_skipfixcolor:
.endif
.if !MOD_VL_REWRITE
.if BUG_NO_CLAMP_SCREEN_Z_POSITIVE
    sdv     $v25[0],    (VTX_SCR_VEC    - 2 * vtxSize)(outputVtxPos)
.else
    slv     $v25[0],    (VTX_SCR_VEC    - 2 * vtxSize)(outputVtxPos)
.endif
    ssv     $v26[4],    (VTX_SCR_Z_FRAC - 2 * vtxSize)(outputVtxPos)
.if !MOD_CLIP_CHANGES
    suv     vPairST[0], (VTX_COLOR_VEC  - 2 * vtxSize)(outputVtxPos)
.endif
    slv     vPairST[8], (VTX_TC_VEC     - 2 * vtxSize)(outputVtxPos)
.if !BUG_NO_CLAMP_SCREEN_Z_POSITIVE          // Not in F3DEX2 2.04H
    ssv     $v3[4],     (VTX_SCR_Z      - 2 * vtxSize)(outputVtxPos)
.endif
.endif
.if MOD_CLIP_CHANGES
    beqz    $4, clipping_mod_endedge         // Did screen clipping, done
.if !MOD_VL_REWRITE
     addi   outputVtxPos, outputVtxPos, -2*vtxSize // back by 2 vertices because this was incremented
.endif
    la      $4, 0                            // Change from scaled clipping to screen clipping
    j       clipping_interpolate
     move   $3, outputVtxPos                 // Off-screen vertex is now the one we just wrote
clipping_mod_endedge:
    sh      outputVtxPos, (clipPoly)(clipPolyWrite) // Write generated vertex to polygon
.else
    addi    outputVtxPos, outputVtxPos, -vtxSize // back by 1 vtx so we are actually 1 ahead of where started
.endif
    addi    clipPolyWrite, clipPolyWrite, 2  // Original outputVtxPos was already written here; increment write ptr
clipping_nextedge:
    bnez    clipFlags, clipping_edgelooptop  // Discard V2 if it was off screen (whether inserted vtx or not)
     move   $3, $2                           // Move what was the end of the edge to be the new start of the edge
    sh      $3, (clipPoly)(clipPolyWrite)    // Former V2 was on screen, so add it to the output polygon
    j       clipping_edgelooptop
     addi   clipPolyWrite, clipPolyWrite, 2

clipping_nextcond:
    sub     $11, clipPolyWrite, clipPolySelect // Are there less than 3 verts in the output polygon?
    bltz    $11, clipping_done                 // If so, degenerate result, quit
     sh     $zero, (clipPoly)(clipPolyWrite)   // Terminate the output polygon with a 0
    lhu     $3, (clipPoly - 2)(clipPolyWrite)  // Initialize the edge start (V3) to the last vert
.if MOD_CLIP_CHANGES
clipping_mod_nextcond_skip:
    beqz    clipMaskIdx, clipping_mod_draw_tris
     lbu    $11, (clipCondShifts - 1)(clipMaskIdx) // Load next clip condition shift amount
    la      $9, 1
    sllv    $9, $9, $11                        // $9 is clip mask
    addiu   clipMaskIdx, clipMaskIdx, -1
    // Compare all verts to clip mask. If any are outside scaled, run the clipping.
    // Also see if there are at least two outside the screen; if none, obviously don't
    // do clipping, and if one, clipping would produce another tri, so better to let
    // this part be scissored.
    // Available locals here: $11, $1, $7, $20, $24, $12
    sll     $7, $9, 4                          // Scaled version of current clip mask
    addi    clipPolyRead, clipPolySelect, -6   // Start reading from beginning of current poly
    move    $12, $9                            // Counts down how many outside screen, starts as 1*mask
clipping_mod_checkcond_loop:
    lhu     $2, (clipPoly)(clipPolyRead)       // Load vertex address
    lhu     $1, VTX_CLIP($2)                   // Load clip flags
    and     $11, $1, $7                        // Mask to outside scaled
    bnez    $11, clipping_condlooptop          // If any vert outside scaled, run the clipping
     and    $1, $1, $9                         // Mask to outside screen
    addiu   clipPolyRead, clipPolyRead, 2      // Going to read next vertex
    blt     clipPolyRead, clipPolyWrite, clipping_mod_checkcond_loop
     sub    $12, $12, $1                       // Subtract 1*mask for each outside screen
    // Loop done. If $12 is negative, there are at least two verts outside screen.
    bltz    $12, clipping_condlooptop
     nop    // Could optimize this to branch one instr later and put a copy of the first instr here.
    j       clipping_mod_nextcond_skip         // Otherwise go to next clip condition.
    // Next instruction is OK to clobber $4 here when jumping.
clipping_mod_draw_tris:
.else
    bnez    clipMaskIdx, clipping_condlooptop  // Done with clipping conditions?
     addi   clipMaskIdx, clipMaskIdx, -0x0004  // Point to next condition
.endif
.if !MOD_CLIP_CHANGES
    sw      $zero, activeClipPlanes            // Disable all clipping planes while drawing tris
.endif
.if MOD_GENERAL
    lhu     $4, modSaveFlatR4                  // Pointer to original first vertex for flat shading
.endif
.if MOD_VL_REWRITE
    lqv     $v30, v30Value($zero)
.endif
// Current polygon starts 6 (3 verts) below clipPolySelect, ends 2 (1 vert) below clipPolyWrite
.if MOD_CLIP_CHANGES
    addiu   clipPolySelect, clipPolySelect, -6 // = Pointer to first vertex
    addiu   clipPolyWrite, clipPolyWrite, -2   // = Pointer to last vertex
    // Available locals: most registers ($5, $6, $7, $8, $9, $11, $12, etc.)
    // Available regs which won't get clobbered by tri write: 
    // clipPolySelect, clipPolyWrite, $14 (inputVtxPos), $15 (outputVtxPos), (more)
    // Find vertex highest on screen (lowest screen Y)
    la      $5, 0x7FFF                // current best value
    move    $7, clipPolySelect        // initial vertex pointer
    lhu     $12, (clipPoly)($7)       // Load vertex address
clipping_mod_search_highest_loop:
    lh      $11, VTX_SCR_Y($12)       // Load screen Y
    bge     $11, $5, clipping_mod_search_skip_better
     addiu  $7, $7, 2                 // Next vertex
    addiu   $14, $7, -2               // Save pointer to best/current vertex
    move    $5, $11                   // Save best value
clipping_mod_search_skip_better:
    bge     clipPolyWrite, $7, clipping_mod_search_highest_loop
     lhu    $12, (clipPoly)($7)       // Next vertex address
    // Find next closest vertex, from the two on either side
    bne     $14, clipPolySelect, @@skip1
     addiu  $6, $14, -2               // $6 = previous vertex
    move    $6, clipPolyWrite
@@skip1:
    lhu     $7, (clipPoly)($6)
    bne     $14, clipPolyWrite, @@skip2
     addiu  $8, $14, 2                // $8 = next vertex
    move    $8, clipPolySelect
@@skip2:
    lhu     $9, (clipPoly)($8)
    lh      $7, VTX_SCR_Y($7)
    lh      $9, VTX_SCR_Y($9)
    bge     $7, $9, clipping_mod_draw_loop // If value from prev vtx >= value from next, use next
     move   $15, $8                   // $14 is first, $8 -> $15 is next
    move    $15, $14                  // $14 -> $15 is next
    move    $14, $6                   // $6 -> $14 is first
clipping_mod_draw_loop:
    // Current edge is $14 - $15 (pointers to clipPoly). We can either draw
    // (previous) - $14 - $15, or we can draw $14 - $15 - (next). We want the
    // one where the lower edge covers the fewest scanlines. This edge is
    // (previous) - $15 or $14 - (next).
    // $1, $2, $3, $5 are vertices at $11=prev, $14, $15, $12=next
    bne     $14, clipPolySelect, @@skip1
     addiu  $11, $14, -2
    move    $11, clipPolyWrite
@@skip1:
    beq     $11, $15, clipping_done // If previous is $15, we only have two verts left, done
     lhu    $1, (clipPoly)($11)     // From the group below, need something in the delay slot
    bne     $15, clipPolyWrite, @@skip2
     addiu  $12, $15, 2
    move    $12, clipPolySelect
@@skip2:
    lhu     $2, (clipPoly)($14)
    lhu     $3, (clipPoly)($15)
    lhu     $5, (clipPoly)($12)
    lsv     $v5[0], (VTX_SCR_Y)($1)
    lsv     $v5[4], (VTX_SCR_Y)($2)
    lsv     $v5[2], (VTX_SCR_Y)($3)
    lsv     $v5[6], (VTX_SCR_Y)($5)
    vsub    $v5, $v5, $v5[1q]  // Y(prev) - Y($15) in elem 0, Y($14) - Y(next) in elem 2
    move    $8, $14            // Temp copy of $14, will be overwritten
    vabs    $v5, $v5, $v5      // abs of each
    vlt     $v29, $v5, $v5[0h] // Elem 2: second difference less than first difference
    cfc2    $9, $vcc           // Get comparison results
    andi    $9, $9, 4          // Look at only vector element 2
    beqz    $9, clipping_mod_final_draw // Skip the change if second diff greater than or equal to first diff
     move   $14, $11           // If skipping, drawing prev-$14-$15, so update $14 to be prev
    move    $1, $2             // Drawing $14, $15, next
    move    $2, $3
    move    $3, $5
    move    $14, $8            // Restore overwritten $14
    move    $15, $12           // Update $15 to be next
clipping_mod_final_draw:
.if MOD_VL_REWRITE
    mtc2    $1, $v27[10]              // Addresses go in vector regs too
.else
    mtc2    $1, $v2[10]               // Addresses go in vector regs too
.endif
    vor     $v3, vZero, $v31[5]       // Not sure what this is, was in init code before tri_to_rdp_noinit
    mtc2    $2, $v4[12]
.if MOD_VL_REWRITE
    mtc2    $3, $v27[14]
.else
    mtc2    $3, $v2[14]
.endif
    j       tri_to_rdp_noinit         // Draw tri
     la     $ra, clipping_mod_draw_loop // When done, return to top of loop
    // armips requires everything to be defined on all .if-paths
    reg1 equ $zero  // garbage value
    val1 equ 0x1337 // garbage value
.else
clipping_draw_tris_loop:
.if CFG_CLIPPING_SUBDIVIDE_DESCENDING
    // Draws verts in pattern like 0-4-3, 0-3-2, 0-2-1. This also draws them with
    // the opposite winding as they were originally drawn with, possibly a bug?
    reg1 equ clipPolyWrite
    val1 equ -0x0002
.else
    // Draws verts in pattern like 0-1-4, 1-2-4, 2-3-4
    reg1 equ clipPolySelect
    val1 equ 0x0002
.endif
    // Load addresses of three verts to draw; each vert may be in normal vertex array or temp buffer
    lhu     $1, (clipPoly - 6)(clipPolySelect)
    lhu     $2, (clipPoly - 4)(reg1)
    lhu     $3, (clipPoly - 2)(clipPolyWrite)
    mtc2    $1, $v2[10]               // Addresses go in vector regs too
    vor     $v3, vZero, $v31[5]       // Not sure what this is, was in init code before tri_to_rdp_noinit
    mtc2    $2, $v4[12]
    jal     tri_to_rdp_noinit         // Draw tri
     mtc2   $3, $v2[14]
    bne     clipPolyWrite, clipPolySelect, clipping_draw_tris_loop
     addi   reg1, reg1, val1
.endif
clipping_done:
.if MOD_GENERAL
    lhu     $ra, modSaveRA
    jr      $ra
.else
    jr      savedRA  // This will be G_TRI1_handler if was first tri of pair, else run_next_DL_command
.endif
.if MOD_CLIP_CHANGES
     la     $30, -1  // Back to normal tri drawing mode (check clip masks)
.else
     sw     savedActiveClipPlanes, activeClipPlanes
.endif

.align 8

// Leave room for loading overlay 2 if it is larger than overlay 3 (true for f3dzex)
.orga max(ovl2_end - ovl2_start + orga(ovl3_start), orga())
ovl3_end:

ovl23_end:

.if MOD_VL_REWRITE

G_VTX_handler:
    jal     segmented_to_physical              // Convert address in cmd_w1_dram to physical
     lhu    $1, (inputBufferEnd - 0x07)(inputBufferPos) // Size in inputVtxSize units
    srl     $2, cmd_w0, 11                     // n << 1
    addiu   $11, inputBufferPos, inputBufferEnd - 0x08 // Out of reach of offset
    sub     $2, cmd_w0, $2                     // v0 << 1
    sb      $2, (inputBufferEnd - 0x06)(inputBufferPos) // Store v0 << 1 as byte 2
    lpv     $v27[0], (0)($11)                  // v0 << 1 is elem 2, (v0 + n) << 1 is elem 3
    j       vtx_indices_to_addr
     la     $11, vtx_return_from_addrs
vtx_return_from_addrs:
    mfc2    $3, $v27[6]                        // Address of end in vtxSize units
    sub     dmemAddr, $3, $1
    jal     dma_read_write
     addi   dmaLen, $1, -1                     // DMA length is always offset by -1
    mfc2    outputVtxPos, $v27[4]              // Address of start in vtxSize units
    move    inputVtxPos, dmemAddr
    jal     vl_mod_matrix_load
     lhu    $5, (geometryModeLabel + 1)($zero) // Middle 2 bytes
    addiu   outputVtxPos, outputVtxPos, -2*vtxSize // Going to increment this by 2 verts below
    jal     while_wait_dma_busy
     andi   $7, $5, G_FOG >> 8                 // Nonzero if fog enabled
vl_mod_vtx_load_loop:
    ldv     $v20[0],      (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos)
    vlt     $v29, $v31, $v31[4] // Set VCC to 11110000
    ldv     $v20[8],      (VTX_IN_OB + inputVtxSize * 1)(inputVtxPos)
    vmudn   $v29, $v7, $v31[2]  // 1
    // Element access wraps in lpv/luv, but not intuitively. Basically the named
    // element and above do get the values at the specified address, but the earlier
    // elements get the values before that, except masked to 0xF. So for example here,
    // elems 4-7 get bytes 0-3 of the vertex as it looks like they should, but elems
    // 0-3 get bytes C-F of the vertex (which is what we want).
    luv     vPairRGBA[4], (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Colors as unsigned, lower 4
    vmadh   $v29, $v3, $v31[2]
    luv     $v25[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, $v4, $v20[0h]
    lpv     $v28[4],      (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Normals as signed, lower 4
    vmadh   $v29, $v0, $v20[0h]
    lpv     $v26[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, $v5, $v20[1h]
    llv     vPairST[0],   (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // ST in 0:1
    vmadh   $v29, $v1, $v20[1h]
    llv     vPairST[8],   (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // ST in 4:5
    vmadn   $v21, $v6, $v20[2h]
    andi    $11, $5, G_LIGHTING >> 8
    vmadh   $v20, $v2, $v20[2h] // $v20:$v21 = vertices world coords
    // Elems 0-1 get bytes 6-7 of the following vertex (0)
    lpv     $v30[2],      (VTX_IN_TC - inputVtxSize * 1)(inputVtxPos) // Packed normals as signed, lower 2
    vmrg    vPairRGBA, vPairRGBA, $v25 // Merge colors
    //bnez    $11, vl_mod_lighting // TODO testing
     // Elems 4-5 get bytes 6-7 of the following vertex (1)
     lpv    $v25[6],      (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // Upper 2 in 4:5
 vl_mod_return_from_lighting:
    vmudn   $v29, $v15, $v31[2] // 1
    addiu   inputVtxPos, inputVtxPos, 2*inputVtxSize
    vmadh   $v29, $v11, $v31[2] // 1
    addiu   outputVtxPos, outputVtxPos, 2*vtxSize
    vmadl   $v29, $v12, $v21[0h]
    addiu   $1, $1, -2*inputVtxSize // Counter of remaining verts * inputVtxSize
    vmadm   $v29, $v8,  $v21[0h]
    addiu   secondVtxPos, outputVtxPos, vtxSize
    vmadn   $v29, $v12, $v20[0h]
    bgez    $1, @@skip1
     vmadh  $v29, $v8,  $v20[0h]
    move    secondVtxPos, outputVtxPos
@@skip1:
    vmadl   $v29, $v13, $v21[1h]
    la      $ra, vl_mod_vtx_load_loop
    vmadm   $v29, $v9,  $v21[1h]
    bgtz    $1, @@skip2
     vmadn  $v29, $v13, $v20[1h]
    la      $ra, run_next_DL_command
@@skip2:
    vmadh   $v29, $v9,  $v20[1h]
    vmadl   $v29, $v14, $v21[2h]
    vmadm   $v29, $v10, $v21[2h]
    vmadn   vPairMVPPosF, $v14, $v20[2h]
    vmadh   vPairMVPPosI, $v10, $v20[2h]
    vmudm   $v29, vPairST, vVpMisc     // Scale ST; must be after texgen
    vmadh   vPairST, vFogMask, $v31[2] // + 1 * ST offset
vl_mod_vtx_store:
    // Inputs: vPairMVPPosI, vPairMVPPosF, vPairST, vPairRGBA
    // Locals: $v20, $v21, $v25, $v26, $v28, $v30 ($v29 is temp)
    // Alive at end for clipping: $v30:$v28 = 1/W, vPairRGBA
    // Scalar regs: secondVtxPos, outputVtxPos; set to the same thing if only write 1 vtx
    // $7 != 0 if fog; temps $11, $12, $20, $24
    vmudl   $v29, vPairMVPPosF, vVpMisc[2] // Persp norm
    sdv     vPairMVPPosF[8],  (VTX_FRAC_VEC  )(secondVtxPos)
    vmadm   $v20, vPairMVPPosI, vVpMisc[2] // Persp norm
    sdv     vPairMVPPosF[0],  (VTX_FRAC_VEC  )(outputVtxPos)
    vmadn   $v21, vFogMask, vFogMask[3] // Zero
    sdv     vPairMVPPosI[8],  (VTX_INT_VEC   )(secondVtxPos)
    vch     $v29, vPairMVPPosI, vPairMVPPosI[3h] // Clip screen high
    sdv     vPairMVPPosI[0],  (VTX_INT_VEC   )(outputVtxPos)
    vcl     $v29, vPairMVPPosF, vPairMVPPosF[3h] // Clip screen low
    suv     vPairRGBA[4],     (VTX_COLOR_VEC )(secondVtxPos)
    vmudn   $v26, vPairMVPPosF, vVpMisc[6] // Clip ratio
    suv     vPairRGBA[0],     (VTX_COLOR_VEC )(outputVtxPos)
    vmadh   $v25, vPairMVPPosI, vVpMisc[6] // Clip ratio
    slv     vPairST[8],       (VTX_TC_VEC    )(secondVtxPos)
    vrcph   $v29[0], $v20[3]
    slv     vPairST[0],       (VTX_TC_VEC    )(outputVtxPos)
    vrcpl   $v28[3], $v21[3]
    cfc2    $20, $vcc
    vrcph   $v30[3], $v20[7]
    vrcpl   $v28[7], $v21[7]
    vrcph   $v30[7], vFogMask[3] // Zero
    srl     $24, $20, 4            // Shift second vertex screen clipping to first slots
    vch     $v29, vPairMVPPosI, $v25[3h] // Clip scaled high
    andi    $12, $20, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
    vcl     $v29, vPairMVPPosF, $v26[3h] // Clip scaled low
    andi    $24, $24, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
    vmudl   $v29, $v21, $v28
    cfc2    $20, $vcc
    vmadm   $v29, $v20, $v28
    lsv     vPairMVPPosF[14], (VTX_Z_FRAC    )(secondVtxPos) // load Z into W slot, will be for fog below
    vmadn   $v21, $v21, $v30
    lsv     vPairMVPPosF[6],  (VTX_Z_FRAC    )(outputVtxPos) // load Z into W slot, will be for fog below
    vmadh   $v20, $v20, $v30
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vge     $v29, vPairMVPPosI, vFogMask[3] // Zero; vcc set if w >= 0
    andi    $20, $20, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
    vmudh   $v29, vVpMisc, $v31[2] // 4 * 1 in elems 3, 7
    andi    $11, $11, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
    vmadn   $v21, $v21, $v31[0] // -4
    or      $24, $24, $20          // Combine final results for second vertex
    vmadh   $v20, $v20, $v31[0] // -4
    or      $12, $12, $11               // Combine final results for first vertex
    vmrg    $v25, vFogMask, $v31[7] // 0 or 0x7FFF in elems 3, 7, latter if w < 0
    lsv     vPairMVPPosI[14], (VTX_Z_INT     )(secondVtxPos) // load Z into W slot, will be for fog below
    vmudl   $v29, $v21, $v28
    lsv     vPairMVPPosI[6],  (VTX_Z_INT     )(outputVtxPos) // load Z into W slot, will be for fog below
    vmadm   $v29, $v20, $v28
    vmadn   $v28, $v21, $v30
    vmadh   $v30, $v20, $v30    // $v30:$v28 is 1/W
    vmadh   $v25, $v25, $v31[7] // 0x7FFF; $v25:$v28 is 1/W but large number if W negative
    vmudl   $v29, vPairMVPPosF, $v28[3h]
    sh      $24,              (VTX_CLIP      )(secondVtxPos) // Store second vertex results
    vmadm   $v29, vPairMVPPosI, $v28[3h]
    sh      $12,              (VTX_CLIP      )(outputVtxPos) // Store first vertex results
    vmadn   vPairMVPPosF, vPairMVPPosF, $v25[3h]
    ssv     $v28[14],         (VTX_INV_W_FRAC)(secondVtxPos)
    vmadh   vPairMVPPosI, vPairMVPPosI, $v25[3h] // pos * 1/W
    ssv     $v28[6],          (VTX_INV_W_FRAC)(outputVtxPos)
    vmudl   $v29, vPairMVPPosF, vVpMisc[2] // Persp norm
    ssv     $v30[14],         (VTX_INV_W_INT )(secondVtxPos)
    vmadm   vPairMVPPosI, vPairMVPPosI, vVpMisc[2] // Persp norm
    ssv     $v30[6],          (VTX_INV_W_INT )(outputVtxPos)
    vmadn   vPairMVPPosF, vFogMask, vFogMask[3] // Zero
    vmudh   $v29, vVpFgOffset, $v31[2] // offset * 1
    vmadn   vPairMVPPosF, vPairMVPPosF, vVpFgScale // + XYZ * scale
    vmadh   vPairMVPPosI, vPairMVPPosI, vVpFgScale
    vge     $v21, vPairMVPPosI, $v31[6] // 0x7F00; clamp fog to >= 0 (low byte only)
    slv     vPairMVPPosI[8],  (VTX_SCR_VEC   )(secondVtxPos)
    vge     $v20, vPairMVPPosI, vFogMask[3] // Zero; clamp Z to >= 0
    slv     vPairMVPPosI[0],  (VTX_SCR_VEC   )(outputVtxPos)
    ssv     vPairMVPPosF[12], (VTX_SCR_Z_FRAC)(secondVtxPos)
    beqz    $7, vl_mod_skip_fog
     ssv    vPairMVPPosF[4],  (VTX_SCR_Z_FRAC)(outputVtxPos)
    sbv     $v21[15],         (VTX_COLOR_A   )(secondVtxPos)
    sbv     $v21[7],          (VTX_COLOR_A   )(outputVtxPos)
vl_mod_skip_fog:
    ssv     $v20[12],         (VTX_SCR_Z     )(secondVtxPos)
    jr      $ra
     ssv    $v20[4],          (VTX_SCR_Z     )(outputVtxPos)

 vl_mod_matrix_load:
     // M matrix is $v0-$v7, VP matrix is $v8-$v15
     lqv     $v0,     (mvMatrix + 0x00)($zero)
     lqv     $v2,     (mvMatrix + 0x10)($zero)
     lqv     $v4,     (mvMatrix + 0x20)($zero)
     lqv     $v6,     (mvMatrix + 0x30)($zero)
     lqv     $v8,     (pMatrix  + 0x00)($zero)
     vor     $v1,  $v0,  $v0
     lqv     $v10,    (pMatrix  + 0x10)($zero)
     vor     $v3,  $v2,  $v2
     lqv     $v12,    (pMatrix  + 0x20)($zero)
     vor     $v5,  $v4,  $v4
     lqv     $v14,    (pMatrix  + 0x30)($zero)
     vor     $v7,  $v6,  $v6
     ldv     $v1[0],  (mvMatrix + 0x08)($zero)
     vor     $v9,  $v8,  $v8
     ldv     $v3[0],  (mvMatrix + 0x18)($zero)
     vor     $v11, $v10, $v10
     ldv     $v5[0],  (mvMatrix + 0x28)($zero)
     vor     $v13, $v12, $v12
     ldv     $v7[0],  (mvMatrix + 0x38)($zero)
     vor     $v15, $v14, $v14
     ldv     $v0[8],  (mvMatrix + 0x00)($zero)
     ldv     $v2[8],  (mvMatrix + 0x10)($zero)
     ldv     $v4[8],  (mvMatrix + 0x20)($zero)
     ldv     $v6[8],  (mvMatrix + 0x30)($zero)
     ldv     $v9[0],  (pMatrix  + 0x08)($zero)
     ldv     $v11[0], (pMatrix  + 0x18)($zero)
     ldv     $v13[0], (pMatrix  + 0x28)($zero)
     ldv     $v15[0], (pMatrix  + 0x38)($zero)
     ldv     $v8[8],  (pMatrix  + 0x00)($zero)
     ldv     $v10[8], (pMatrix  + 0x10)($zero)
     ldv     $v12[8], (pMatrix  + 0x20)($zero)
     ldv     $v14[8], (pMatrix  + 0x30)($zero)
 vl_mod_setup_constants:
 /*
 $v16 = vVpFgScale  = [vscale[0], -vscale[1], vscale[2], fogMult,   (repeat)]
 $v17 = vVpFgOffset = [vtrans[0],  vtrans[1], vtrans[2], fogOffset, (repeat)]
 $v18 = vVpMisc     = [TexSScl,   TexTScl,    perspNorm, 4,         TexSScl,   TexTScl, clipRatio, 4     ]
 $v19 = vFogMask    = [TexSOfs,   TexTOfs,    aoAmb,     0,         TexSOfs,   TexTOfs, aoDir,     0     ]
 $v31 =               [-4,        -1,         1,         0x0010,    0x0100,    0x4000,  0x7F00,    0x7FFF]
 aoAmb, aoDir set to 0 if ambient occlusion disabled
 */
    li      spFxBaseReg, spFxBase
    vne     $v29, $v31, $v31[2h]                  // VCC = 11011101
    ldv     vFogMask[0], (attrOffsetST - spFxBase)(spFxBaseReg) // elems 0, 1, 2 = S, T, Z offset
    vxor    $v21, $v21, $v21                      // Zero
    ldv     vVpFgOffset[0], (viewport + 8)($zero) // Load vtrans duplicated in 0-3 and 4-7
    ldv     vVpFgOffset[8], (viewport + 8)($zero)
    lhu     $12, (geometryModeLabel+2)($zero)
    lhu     $24, (perspNorm)($zero)               // Can't load this as a short because not enough reach
    vmrg    $v29, $v21, vFogMask[2]               // all zeros except elems 2, 6 are Z offset
    ldv     vFogMask[8], (attrOffsetST - spFxBase)(spFxBaseReg) // Duplicated in 4-6
    vsub    $v22, $v21, $v31[0]                   // Vector of 4s = 0 - -4
    andi    $11, $12, G_ATTROFFSET_Z_ENABLE
    beqz    $11, @@skipz                          // Skip if Z offset disabled
     llv    $v20[4], (aoAmbientFactor - spFxBase)(spFxBaseReg) // Load aoAmb 2 and aoDir 3
    vadd    vVpFgOffset, vVpFgOffset, $v29        // add Z offset if enabled
@@skipz:
    andi    $11, $12, G_ATTROFFSET_ST_ENABLE
    bnez    $11, @@skipst                         // Skip if ST offset enabled
     ldv    vVpMisc[0], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale in 0, 1, clipRatio in 2
    vxor    vFogMask, vFogMask, vFogMask          // If disabled, clear ST offset
@@skipst:
    andi    $11, $12, G_AMBOCCLUSION
    vmov    $v20[6], $v20[3]                      // move aoDir to 6
    bnez    $11, @@skipao                         // Skip if ambient occlusion enabled
     ldv    vVpMisc[8], (textureSettings2 - spFxBase)(spFxBaseReg) // Duplicated in 4-6
    vor     $v20, $v21, $v21                      // Set aoAmb and aoDir to 0
@@skipao:
    ldv     vVpFgScale[0], (viewport)($zero)      // Load vscale duplicated in 0-3 and 4-7
    ldv     vVpFgScale[8], (viewport)($zero)
    llv     $v23[0], (fogFactor - spFxBase)(spFxBaseReg) // Load fog multiplier 0 and offset 1
    mtc2    $24, vVpMisc[4]                       // perspNorm
    vmrg    vFogMask, vFogMask, $v20              // move aoAmb and aoDir into vFogMask
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    vsub    $v20, $v21, vVpFgScale                // -vscale
    vmrg    vVpFgScale, vVpFgScale, $v23[0]       // Put fog multiplier in elements 3,7 of vscale
    vadd    $v23, $v23, $v31[6]                   // Add 0x7F00 to fog offset
    vmrg    vVpMisc, vVpMisc, $v22                // Put 4s in elements 3,7
    vmrg    vFogMask, vFogMask, $v21              // Put 0s in elements 3,7
    vmov    vVpFgScale[1], $v20[1]                // Negate vscale[1] because RDP top = y=0
    vmov    vVpFgScale[5], $v20[1]                // Same for second half
    jr      $ra
     vmrg    vVpFgOffset, vVpFgOffset, $v23[1]    // Put fog offset in elements 3,7 of vtrans

.endif

vPairRGBATemp equ $v7

.if MOD_CLIP_CHANGES
    rClipRes equ $20
.elseif MOD_GENERAL
    rClipRes equ $19
.else
    rClipRes equ $10
.endif

.if !MOD_VL_REWRITE

G_VTX_handler:
    lhu     dmemAddr, (vertexTable)(cmd_w0) // Load the address of the provided vertex array
    jal     segmented_to_physical           // Convert the vertex array's segmented address (in cmd_w1_dram) to a virtual one
     lhu    $1, (inputBufferEnd - 0x07)(inputBufferPos) // Load the size of the vertex array to copy into reg $1
    sub     dmemAddr, dmemAddr, $1          // Calculate the address to DMA the provided vertices into
    jal     dma_read_write                  // DMA read the vertices from DRAM
     addi   dmaLen, $1, -1                  // Set up the DMA length
    lhu     $5, geometryModeLabel           // Load the geometry mode into $5
    srl     $1, $1, 3
    sub     outputVtxPos, cmd_w0, $1
    lhu     outputVtxPos, (vertexTable)(outputVtxPos)
    move    inputVtxPos, dmemAddr
    lbu     secondVtxPos, mvpValid          // used as temp reg
    andi    topLightPtr, $5, G_LIGHTING_H   // If no lighting, topLightPtr is 0, skips transforming light dirs and setting this up as a pointer
    bnez    topLightPtr, ovl23_lighting_entrypoint // Run overlay 2 for lighting, either directly or via overlay 3 loading overlay 2
     andi   $7, $5, G_FOG_H
after_light_dir_xfrm:
    bnez    secondVtxPos, vertex_skip_recalc_mvp  // Skip recalculating the mvp matrix if it's already up-to-date
     sll    $7, $7, 3                 // $7 is 8 if G_FOG is set, 0 otherwise
    sb      cmd_w0, mvpValid          // Set mvpValid
    li      input_mtx_0, pMatrix      // Arguments to mtx_multiply
    li      input_mtx_1, mvMatrix
    // Calculate the MVP matrix
    jal     mtx_multiply
     li     output_mtx, mvpMatrix

vertex_skip_recalc_mvp:
    /* Load MVP matrix as follows--note that translation is in the bottom row,
    not the right column.
    Elem   0   1   2   3   4   5   6   7      (Example data)
    I v8  00  02  04  06  00  02  04  06      Xscl Rot  Rot   0
    I v9  08  0A  0C  0E  08  0A  0C  0E      Rot  Yscl Rot   0
    I v10 10  12  14  16  10  12  14  16      Rot  Rot  Zscl  0
    I v11 18  1A  1C  1E  18  1A  1C  1E      Xpos Ypos Zpos  1
    F v12 20  22  24  26  20  22  24  26
    F v13 28  2A  2C  2E  28  2A  2C  2E
    F v14 30  32  34  36  30  32  34  36
    F v15 38  3A  3C  3E  38  3A  3C  3E
    Vector regs contain rows of original matrix (v11/v15 have translations)
    */
    lqv     mxr0i,    (mvpMatrix +  0)($zero)
    lqv     mxr2i,    (mvpMatrix + 16)($zero)
    lqv     mxr0f,    (mvpMatrix + 32)($zero)
    lqv     mxr2f,    (mvpMatrix + 48)($zero)
    vcopy   mxr1i, mxr0i
    ldv     mxr1i,    (mvpMatrix +  8)($zero)
    vcopy   mxr3i, mxr2i
    ldv     mxr3i,    (mvpMatrix + 24)($zero)
    vcopy   mxr1f, mxr0f
    ldv     mxr1f,    (mvpMatrix + 40)($zero)
    vcopy   mxr3f, mxr2f
    ldv     mxr3f,    (mvpMatrix + 56)($zero)
    ldv     mxr0i[8], (mvpMatrix +  0)($zero)
    ldv     mxr2i[8], (mvpMatrix + 16)($zero)
    jal     load_spfx_global_values
     ldv    mxr0f[8], (mvpMatrix + 32)($zero)
    jal     while_wait_dma_busy
     ldv    mxr2f[8], (mvpMatrix + 48)($zero)
    ldv     $v20[0], (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // load the position of the 1st vertex into v20's lower 8 bytes
.if !MOD_GENERAL
    vmov    vVpFgScale[5], vVpNegScale[1]          // Finish building vVpFgScale
.endif
    ldv     $v20[8], (VTX_IN_OB + inputVtxSize * 1)(inputVtxPos) // load the position of the 2nd vertex into v20's upper 8 bytes

vertices_process_pair:
    // Two verts pos in v20; multiply by MVP
    vmudn   $v29, mxr3f, vOne[0]
    lw      $11, (VTX_IN_CN + inputVtxSize * 1)(inputVtxPos) // load the color/normal of the 2nd vertex into $11
    vmadh   $v29, mxr3i, vOne[0]
    llv     vPairST[12], (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // load the texture coords of the 1st vertex into second half of vPairST
    vmadn   $v29, mxr0f, $v20[0h]
    move    curLight, topLightPtr
    vmadh   $v29, mxr0i, $v20[0h]
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight)    // First instruction of lights_dircoloraccum2 loop; load light transformed dir
    vmadn   $v29, mxr1f, $v20[1h]
    sw      $11, (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // Move the second vertex's colors/normals into the word before the first vertex's
    vmadh   $v29, mxr1i, $v20[1h]
    lpv     vPairRGBATemp[0], (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // Load both vertex's colors/normals into v7's elements RGBARGBA or XYZAXYZA
    vmadn   vPairMVPPosF, mxr2f, $v20[2h]          // vPairMVPPosF = MVP * vpos result frac
    bnez    topLightPtr, light_vtx                 // Zero if lighting disabled, pointer if enabled
     vmadh  vPairMVPPosI, mxr2i, $v20[2h]          // vPairMVPPosI = MVP * vpos result int
    // These two instructions are repeated at the end of all the lighting codepaths,
    // since they're skipped here if lighting is being performed
    // This is the original location of INSTR 1 and INSTR 2
    vge     $v27, $v25, $v31[3]                    // INSTR 1: Clamp W/fog to >= 0x7F00 (low byte is used)
    llv     vPairST[4], (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into first half of vPairST

vertices_store:
    // "First" and "second" vertices mean first and second in the input list,
    // which is also first and second in the output list.
    // This is also in the first half and second half of vPairMVPPosI / vPairMVPPosF.
    // However, they are reversed in vPairST and the vector regs used for lighting.
.if !BUG_NO_CLAMP_SCREEN_Z_POSITIVE        // Bugfixed version
    vge     $v3, $v25, vZero[0]            // Clamp Z to >= 0
.endif
    addi    $1, $1, -4                     // Decrement vertex count by 2
    vmudl   $v29, vPairMVPPosF, vVpMisc[4] // Persp norm
    // First time through, secondVtxPos is temp memory in the current RDP output buffer,
    // so these writes don't harm anything. On subsequent loops, this is finishing the
    // store of the previous two vertices.
    sub     $11, secondVtxPos, $7          // Points 8 above secondVtxPos if fog, else 0
    vmadm   $v2, vPairMVPPosI, vVpMisc[4]  // Persp norm
    sbv     $v27[15],         (VTX_COLOR_A + 8 - 1 * vtxSize)($11) // In VTX_SCR_Y if fog disabled...
    vmadn   $v21, vZero, vZero[0]
    sbv     $v27[7],          (VTX_COLOR_A + 8 - 2 * vtxSize)($11) // ...which gets overwritten below
.if !BUG_NO_CLAMP_SCREEN_Z_POSITIVE        // Bugfixed version
    vmov    $v26[1], $v3[2]
    ssv     $v3[12],          (VTX_SCR_Z      - 1 * vtxSize)(secondVtxPos)
.endif
    vmudn   $v7, vPairMVPPosF, vVpMisc[5]  // Clip ratio
.if BUG_NO_CLAMP_SCREEN_Z_POSITIVE
    sdv     $v25[8],          (VTX_SCR_VEC    - 1 * vtxSize)(secondVtxPos)
.else
    slv     $v25[8],          (VTX_SCR_VEC    - 1 * vtxSize)(secondVtxPos)
.endif
    vmadh   $v6, vPairMVPPosI, vVpMisc[5]  // Clip ratio
    sdv     $v25[0],          (VTX_SCR_VEC    - 2 * vtxSize)(secondVtxPos)
    vrcph   $v29[0], $v2[3]
    ssv     $v26[12],         (VTX_SCR_Z_FRAC - 1 * vtxSize)(secondVtxPos)
    vrcpl   $v5[3], $v21[3]
.if BUG_NO_CLAMP_SCREEN_Z_POSITIVE
    ssv     $v26[4],          (VTX_SCR_Z_FRAC - 2 * vtxSize)(secondVtxPos)
.else
    slv     $v26[2],          (VTX_SCR_Z      - 2 * vtxSize)(secondVtxPos)
.endif
    vrcph   $v4[3], $v2[7]
    ldv     $v3[0], 8(inputVtxPos)  // Load RGBARGBA for two vectors (was stored this way above)
    vrcpl   $v5[7], $v21[7]
    sra     $11, $1, 31             // -1 if only first vert of two is valid, else 0
    vrcph   $v4[7], vZero[0]
    andi    $11, $11, vtxSize       // vtxSize if only first vert of two is valid, else 0
    vch     $v29, vPairMVPPosI, vPairMVPPosI[3h] // Compare XYZW to W, two verts, MSB
    addi    outputVtxPos, outputVtxPos, (2 * vtxSize) // Advance two positions forward in the output vertices
    vcl     $v29, vPairMVPPosF, vPairMVPPosF[3h] // Compare XYZW to W, two verts, LSB
    // If only the first vert of two is valid,
    // (VTX_ABC - 1 * vtxSize)(secondVtxPos) == (VTX_ABC - 2 * vtxSize)(outputVtxPos)
    // secondVtxPos always writes first, so then outputVtxPos overwrites it with the
    // first-and-only vertex's data.
    // If both are valid, secondVtxPos == outputVtxPos,
    // so outputVtxPos is the first vertex and secondVtxPos is the second.
    sub     secondVtxPos, outputVtxPos, $11
    vmudl   $v29, $v21, $v5
    cfc2    rClipRes, $vcc               // Load 16 bit screen space clip results, two verts
    vmadm   $v29, $v2, $v5
    sdv     vPairMVPPosF[8],  (VTX_FRAC_VEC   - 1 * vtxSize)(secondVtxPos)
    vmadn   $v21, $v21, $v4
    ldv     $v20[0], (VTX_IN_OB + 2 * inputVtxSize)(inputVtxPos) // Load pos of 1st vector on next iteration
    vmadh   $v2, $v2, $v4
    sdv     vPairMVPPosF[0],  (VTX_FRAC_VEC   - 2 * vtxSize)(outputVtxPos)
    vge     $v29, vPairMVPPosI, vZero[0] // Int position XYZW >= 0
    lsv     vPairMVPPosF[14], (VTX_Z_FRAC     - 1 * vtxSize)(secondVtxPos) // load Z into W slot, will be for fog below
    vmudh   $v29, vOne, $v31[1]
    sdv     vPairMVPPosI[8],  (VTX_INT_VEC    - 1 * vtxSize)(secondVtxPos)
    vmadn   $v26, $v21, $v31[4]
    lsv     vPairMVPPosF[6],  (VTX_Z_FRAC     - 2 * vtxSize)(outputVtxPos) // load Z into W slot, will be for fog below
    vmadh   $v25, $v2, $v31[4]
    sdv     vPairMVPPosI[0],  (VTX_INT_VEC    - 2 * vtxSize)(outputVtxPos)
    vmrg    $v2, vZero, $v31[7] // Set to 0 where positive, 0x7FFF where negative
    ldv     $v20[8], (VTX_IN_OB + 3 * inputVtxSize)(inputVtxPos) // Load pos of 2nd vector on next iteration
    vch     $v29, vPairMVPPosI, $v6[3h] // Compare XYZZ to clip-ratio-scaled W (int part)
    slv     $v3[0],           (VTX_COLOR_VEC  - 1 * vtxSize)(secondVtxPos) // Store RGBA for first vector
    vmudl   $v29, $v26, $v5
    lsv     vPairMVPPosI[14], (VTX_Z_INT      - 1 * vtxSize)(secondVtxPos) // load Z into W slot, will be for fog below
    vmadm   $v29, $v25, $v5
    slv     $v3[4],           (VTX_COLOR_VEC  - 2 * vtxSize)(outputVtxPos) // Store RGBA for second vector
    vmadn   $v5, $v26, $v4
    lsv     vPairMVPPosI[6],  (VTX_Z_INT      - 2 * vtxSize)(outputVtxPos) // load Z into W slot, will be for fog below
    vmadh   $v4, $v25, $v4
.if MOD_CLIP_CHANGES
    // $12 = final value for first vertex
    // $24 = final value for second vertex
    // $11, rClipRes = temps
    srl     $24, rClipRes, 4            // Shift second vertex screen clipping to first slots
    andi    $12, rClipRes, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
.else
    sh      rClipRes,         (VTX_CLIP_SCRN  - 1 * vtxSize)(secondVtxPos) // XYZW/W second vtx results in bits 0xF0F0
.endif
    vmadh   $v2, $v2, $v31[7]           // Makes screen coords a large number if W < 0
.if MOD_CLIP_CHANGES
    andi    $24, $24, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
.else
    sll     $11, rClipRes, 4            // Shift first vtx screen space clip into positions 0xF0F0
.endif
    vcl     $v29, vPairMVPPosF, $v7[3h] // Compare XYZZ to clip-ratio-scaled W (frac part)
    cfc2    rClipRes, $vcc              // Load 16 bit clip-ratio-scaled results, two verts
    vmudl   $v29, vPairMVPPosF, $v5[3h] // Pos times inv W
    ssv     $v5[14],          (VTX_INV_W_FRAC - 1 * vtxSize)(secondVtxPos)
    vmadm   $v29, vPairMVPPosI, $v5[3h] // Pos times inv W
    addi    inputVtxPos, inputVtxPos, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadn   $v26, vPairMVPPosF, $v2[3h] // Makes screen coords a large number if W < 0
.if MOD_CLIP_CHANGES
    sll     $11, rClipRes, 4            // Shift first vertex scaled clipping to second slots
    andi    rClipRes, rClipRes, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
.else
    sh      rClipRes,         (VTX_CLIP_SCAL  - 1 * vtxSize)(secondVtxPos) // Clip scaled second vtx results in bits 0xF0F0
.endif
    vmadh   $v25, vPairMVPPosI, $v2[3h] // v25:v26 = pos times inv W
.if MOD_CLIP_CHANGES
    andi    $11, $11, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
    or      $24, $24, rClipRes          // Combine final results for second vertex
.else
    sll     rClipRes, rClipRes, 4       // Shift first vtx scaled clip into positions 0xF0F0
.endif
    vmudm   $v3, vPairST, vVpMisc       // Scale ST for two verts, using TexSScl and TexTScl in elems 2, 3, 6, 7
.if MOD_CLIP_CHANGES
    or      $12, $12, $11               // Combine final results for first vertex
    sh      $24,              (VTX_CLIP       - 1 * vtxSize)(secondVtxPos) // Store second vertex results
.else
    sh      $11,              (VTX_CLIP_SCRN  - 2 * vtxSize)(outputVtxPos) // Clip screen first vtx results
.endif
.if MOD_ATTR_OFFSETS
    vmadh   $v3, vFogMask, vOne[0]      // + 1 * ST offset
.endif
.if MOD_CLIP_CHANGES
    sh      $12,              (VTX_CLIP       - 2 * vtxSize)(outputVtxPos) // Store first vertex results
.else
    sh      rClipRes,         (VTX_CLIP_SCAL  - 2 * vtxSize)(outputVtxPos) // Clip scaled first vtx results
.endif
    vmudl   $v29, $v26, vVpMisc[4]      // Scale result by persp norm
    ssv     $v5[6],           (VTX_INV_W_FRAC - 2 * vtxSize)(outputVtxPos)
    vmadm   $v25, $v25, vVpMisc[4]      // Scale result by persp norm
    ssv     $v4[14],          (VTX_INV_W_INT  - 1 * vtxSize)(secondVtxPos)
    vmadn   $v26, vZero, vZero[0]       // Now v26:v25 = projected position
    ssv     $v4[6],           (VTX_INV_W_INT  - 2 * vtxSize)(outputVtxPos)
    slv     $v3[4],           (VTX_TC_VEC     - 1 * vtxSize)(secondVtxPos) // Store scaled S, T vertex 1
    vmudh   $v29, vVpFgOffset, vOne[0]  //   1 * vtrans (and fog offset in elems 3,7)
    slv     $v3[12],          (VTX_TC_VEC     - 2 * vtxSize)(outputVtxPos) // Store scaled S, T vertex 2
.if !MOD_GENERAL
    vmadh   $v29, vFogMask, $v31[3]     // + 0x7F00 in fog elements (because auto-clamp to 0x7FFF, and will clamp to 0x7F00 below)
.endif
    vmadn   $v26, $v26, vVpFgScale      // + pos frac * scale
    bgtz    $1, vertices_process_pair
     vmadh  $v25, $v25, vVpFgScale      // int part, v25:v26 is now screen space pos
    bltz    $ra, clipping_after_vtxwrite // Return to clipping if from clipping
.if !BUG_NO_CLAMP_SCREEN_Z_POSITIVE     // Bugfixed version
     vge    $v3, $v25, vZero[0]         // Clamp Z to >= 0
    slv     $v25[8],          (VTX_SCR_VEC    - 1 * vtxSize)(secondVtxPos)
    vge     $v27, $v25, $v31[3] // INSTR 1: Clamp W/fog to >= 0x7F00 (low byte is used)
    slv     $v25[0],          (VTX_SCR_VEC    - 2 * vtxSize)(outputVtxPos)
    ssv     $v26[12],         (VTX_SCR_Z_FRAC - 1 * vtxSize)(secondVtxPos)
    ssv     $v26[4],          (VTX_SCR_Z_FRAC - 2 * vtxSize)(outputVtxPos)
    ssv     $v3[12],          (VTX_SCR_Z      - 1 * vtxSize)(secondVtxPos)
    beqz    $7, run_next_DL_command
     ssv    $v3[4],           (VTX_SCR_Z      - 2 * vtxSize)(outputVtxPos)
.else // This is the F3DEX2 2.04H version
     vge    $v27, $v25, $v31[3] // INSTR 1: Clamp W/fog to >= 0x7F00 (low byte is used)
    sdv     $v25[8],          (VTX_SCR_VEC    - 1 * vtxSize)(secondVtxPos)
    sdv     $v25[0],          (VTX_SCR_VEC    - 2 * vtxSize)(outputVtxPos)
    // Int part of Z stored in VTX_SCR_Z by sdv above
    ssv     $v26[12],         (VTX_SCR_Z_FRAC - 1 * vtxSize)(secondVtxPos)
    beqz    $7, run_next_DL_command
     ssv    $v26[4],          (VTX_SCR_Z_FRAC - 2 * vtxSize)(outputVtxPos)
.endif
    sbv     $v27[15],         (VTX_COLOR_A    - 1 * vtxSize)(secondVtxPos)
    j       run_next_DL_command
     sbv    $v27[7],          (VTX_COLOR_A    - 2 * vtxSize)(outputVtxPos)

load_spfx_global_values:
    /*
    vscale = viewport shorts 0:3, vtrans = viewport shorts 4:7, VpFg = Viewport Fog
    v16 = vVpFgScale = [vscale[0], -vscale[1], vscale[2], fogMult, (repeat)]
                       (element 5 written just before vertices_process_pair)
    v17 = vVpFgOffset = [vtrans[0], vtrans[1], vtrans[2], fogOffset, (repeat)]
    v18 = vVpMisc = [???, ???, TexSScl, TexTScl, perspNorm, clipRatio, TexSScl, TexTScl]
    // Unused in MOD_GENERAL:
    v19 = vFogMask = [0x0000, 0x0000, 0x0000, 0x0001, 0x0000, 0x0000, 0x0000, 0x0001]
    v21 = vVpNegScale = -[vscale[0:3], vscale[0:3]]
    // With MOD_ATTR_OFFSETS:
    v19 = vFogMask = [???, ???, TexSOfs, TexTOfs, ???, ???, TexSOfs, TexTOfs]
    */
    li      spFxBaseReg, spFxBase
    ldv     vVpFgScale[0], (viewport)($zero)      // Load vscale duplicated in 0-3 and 4-7
    ldv     vVpFgScale[8], (viewport)($zero)
    llv     $v29[0], (fogFactor - spFxBase)(spFxBaseReg) // Load fog multiplier and offset
    ldv     vVpFgOffset[0], (viewport + 8)($zero) // Load vtrans duplicated in 0-3 and 4-7
    ldv     vVpFgOffset[8], (viewport + 8)($zero)
.if !MOD_GENERAL
    vlt     vFogMask, $v31, $v31[3]               // VCC = 11101110
    vsub    vVpNegScale, vZero, vVpFgScale        // -vscale
    llv     vVpMisc[4], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
    vmrg    vVpFgScale, vVpFgScale, $v29[0]       // Put fog multiplier in elements 3,7 of vscale
    llv     vVpMisc[12], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
    vmrg    vFogMask, vZero, vOne[0]              // Put 0 in most elems, 1 in elems 3,7
    llv     vVpMisc[8], (perspNorm)($zero)        // Perspective normalization long (actually short)
    vmrg    vVpFgOffset, vVpFgOffset, $v29[1]     // Put fog offset in elements 3,7 of vtrans
    lsv     vVpMisc[10], (clipRatio + 6 - spFxBase)(spFxBaseReg) // Clip ratio (-x version, but normally +/- same in all dirs)
    vmov    vVpFgScale[1], vVpNegScale[1]         // Negate vscale[1] because RDP top = y=0
    jr      $ra
     addi   secondVtxPos, rdpCmdBufPtr, 0x50      // Pointer to currently unused memory in command buffer
.else
.if MOD_ATTR_OFFSETS
.if MOD_VL_REWRITE
    .error "This part not updated yet!"
.endif
    // vFogMask is ST offset
    lhu     $8, (geometryModeLabel+2)($zero)      // $8 = secondVtxPos, about to be overwritten
    // Byte addr in vector, undocumented behavior that this works for unaligned vector element
    ldv     vFogMask[4], (attrOffsetST - spFxBase)(spFxBaseReg) // elems 2, 3, 4 = S, T, Z offset
    vne     $v2, $v31, $v31[2h]                   // VCC = 11011101
    andi    $11, $8, G_ATTROFFSET_Z_ENABLE
    vmrg    $v2, vZero, vFogMask[4]               // all zeros except elems 2, 6 are Z offset
    beqz    $11, after_attroffset_z
     llv    vFogMask[12], (attrOffsetST - spFxBase)(spFxBaseReg) // elems 6, 7 = S, T offset
    vadd    vVpFgOffset, vVpFgOffset, $v2         // add Z offset if enabled
after_attroffset_z:
    andi    $11, $8, G_ATTROFFSET_ST_ENABLE
    vne     $v2, $v31, $v31[3h]                   // VCC = 11101110
    bnez    $11, after_attroffset_st              // Branch if ST offset enabled
     addi    secondVtxPos, rdpCmdBufPtr, 0x50     // Pointer to currently unused memory in command buffer
    vclr    vFogMask                              // If disabled, clear ST offset
after_attroffset_st:
.else
    vne     $v2, $v31, $v31[3h]                   // VCC = 11101110
    addi    secondVtxPos, rdpCmdBufPtr, 0x50      // Pointer to currently unused memory in command buffer
.endif
    vsub    $v2, vZero, vVpFgScale                // -vscale
.if MOD_CLIP_CHANGES
    ldv     vVpMisc[4], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale and clip ratio
    lhu     $11, (perspNorm)($zero)               // Can't load this as a short because not enough reach
.else
    llv     vVpMisc[4], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
.endif
    vmrg    vVpFgScale, vVpFgScale, $v29[0]       // Put fog multiplier in elements 3,7 of vscale
    llv     vVpMisc[12], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
    vadd    $v29, $v29, $v31[3]                   // Add 0x7F00 to fog offset
.if !MOD_CLIP_CHANGES
    llv     vVpMisc[8], (perspNorm)($zero)        // Perspective normalization long (actually short)
.endif
    vmov    vVpFgScale[1], $v2[1]                 // Negate vscale[1] because RDP top = y=0
.if MOD_CLIP_CHANGES
    mtc2    $11, vVpMisc[8]
.else
    lsv     vVpMisc[10], (clipRatio + 6 - spFxBase)(spFxBaseReg) // Clip ratio (-x version, but normally +/- same in all dirs)
.endif
    vmov    vVpFgScale[5], $v2[1]                 // Finish building vVpFgScale
    jr      $ra
     vmrg    vVpFgOffset, vVpFgOffset, $v29[1]    // Put fog offset in elements 3,7 of vtrans
.endif

.endif // MOD_VL_REWRITE

.if MOD_VL_REWRITE
vtx_indices_to_addr:
    // Input and output in $v27
    vxor    $v28, $v28, $v28  // Zero
    lqv     $v30, v30Value($zero)
    vsub    $v28, $v28, $v31[1]   // One = 0 - -1
    vmudl   $v29, $v27, $v30[1]   // Multiply vtx indices times length
    jr      $11
     vmadn  $v27, $v28, $v30[0]   // Add address of vertex buffer
.endif

G_TRI2_handler:
G_QUAD_handler:
    jal     tri_to_rdp                   // Send second tri; return here for first tri
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Put second tri indices in temp memory
G_TRI1_handler:
    li      $ra, run_next_DL_command     // After done with this tri, run next cmd
    sw      cmd_w0, 4(rdpCmdBufPtr)      // Put first tri indices in temp memory
tri_to_rdp:
.if MOD_VL_REWRITE
    lpv     $v27[0], 0(rdpCmdBufPtr)     // Load tri indexes to 5,6,7
    vxor    vZero, vZero, vZero
    j       vtx_indices_to_addr
     la     $11, tri_return_from_addrs
 tri_return_from_addrs:
    mfc2    $1, $v27[10]
    vor     vOne, $v28, $v28             // 1 set up in function
    mfc2    $2, $v27[12]
    vor     $v4, $v27, $v27              // Need vtx 2 addr in elem 6
    mfc2    $3, $v27[14]
    vor     $v3, vZero, $v31[5]
.else
    lpv     $v2[0], 0(rdpCmdBufPtr)      // Load tri indexes to vector unit for shuffling
    // read the three vertex indices from the stored command word
    lbu     $1, 0x0005(rdpCmdBufPtr)     // $1 = vertex 1 index
    lbu     $2, 0x0006(rdpCmdBufPtr)     // $2 = vertex 2 index
    lbu     $3, 0x0007(rdpCmdBufPtr)     // $3 = vertex 3 index
    vor     $v3, vZero, $v31[5]
    lhu     $1, (vertexTable)($1) // convert vertex 1's index to its address
    vmudn   $v4, vOne, $v31[6]    // Move address of vertex buffer to accumulator mid
    lhu     $2, (vertexTable)($2) // convert vertex 2's index to its address
    vmadl   $v2, $v2, $v30[1]     // Multiply vtx indices times length and add addr
    lhu     $3, (vertexTable)($3) // convert vertex 3's index to its address
    vmadn   $v4, vZero, vZero[0]  // Load accumulator again (addresses) to v4; need vertex 2 addr in elem 6
.endif
    move    $4, $1                // Save original vertex 1 addr (pre-shuffle) for flat shading
.if MOD_CLIP_CHANGES
    la      $30, -1               // Normal tri drawing mode (check clip masks)
.endif
tri_to_rdp_noinit:
    // ra is next cmd, second tri in TRI2, or middle of clipping
    vnxor   $v5, vZero, $v31[7]     // v5 = 0x8000
    llv     $v6[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vnxor   $v7, vZero, $v31[7]     // v7 = 0x8000
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
.if MOD_VL_REWRITE
    vmov    $v6[6], $v27[5]         // elem 6 of v6 = vertex 1 addr
.else
    vmov    $v6[6], $v2[5]          // elem 6 of v6 = vertex 1 addr
.endif
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vnxor   $v9, vZero, $v31[7]     // v9 = 0x8000
.if MOD_CLIP_CHANGES
    lhu     $5, VTX_CLIP($1)
.else
    lw      $5, VTX_CLIP($1)
.endif
.if MOD_VL_REWRITE
    vmov    $v8[6], $v27[7]         // elem 6 of v8 = vertex 3 addr
.else
    vmov    $v8[6], $v2[7]          // elem 6 of v8 = vertex 3 addr
.endif
.if MOD_CLIP_CHANGES
    lhu     $6, VTX_CLIP($2)
.else
    lw      $6, VTX_CLIP($2)
.endif
    vadd    $v2, vZero, $v6[1] // v2 all elems = y-coord of vertex 1
.if MOD_CLIP_CHANGES
    lhu     $7, VTX_CLIP($3)
.else
    lw      $7, VTX_CLIP($3)
.endif
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
.if MOD_CLIP_CHANGES
    andi    $11, $5, CLIP_MOD_MASK_SCRN_ALL
.else
    andi    $11, $5, (CLIP_NX | CLIP_NY | CLIP_PX | CLIP_PY | CLIP_FAR | CLIP_NEAR) << CLIP_SHIFT_SCRN
.endif
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    and     $11, $6, $11
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    and     $11, $7, $11      // If there is any screen clipping plane where all three verts are past it...
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    vmrg    $v14, $v6, $v4    // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    bnez    $11, return_routine // ...whole tri is offscreen, cull.
     lbu    $11, geometryModeLabel + 2  // Loads the geometry mode byte that contains face culling settings
    vmudh   $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
.if MOD_CLIP_CHANGES
    sra     $12, $30, 31      // All 1s if $30 is negative, meaning clipping allowed
.else
    lw      $12, activeClipPlanes
.endif
    vmadh   $v29, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    or      $5, $5, $6
.if MOD_GENERAL && !MOD_CLIP_CHANGES
    andi    $11, $11, G_CULL_BOTH >> 8  // Only look at culling bits, so we can use others for other mods
.endif
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    or      $5, $5, $7        // If any verts are past any clipping plane...
    vmrg    $v10, $v6, $v4    // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
.if MOD_CLIP_CHANGES
    andi    $11, $11, G_CULL_BOTH >> 8  // Only look at culling bits, so we can use others for other mods
.else
    lw      $11, (gCullMagicNumbers)($11)
.endif
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    mfc2    $6, $v29[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    $v4, $v14, $v8    // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    and     $5, $5, $12       // ...which is in the set of currently enabled clipping planes (scaled for XY, screen for ZW)...
    vmrg    $v14, $v8, $v14   // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
.if MOD_CLIP_CHANGES
    andi    $12, $5, CLIP_NEAR >> 4 // If tri crosses camera plane, backface info is garbage
    bnez    $12, tri_mod_skip_check_backface
     lw     $11, (gCullMagicNumbers)($11)
    beqz    $6, return_routine  // If cross product is 0, tri is degenerate (zero area), cull.
     add    $11, $6, $11        // Add magic number; see description at gCullMagicNumbers
    bgez    $11, return_routine // If sign bit is clear, cull.
tri_mod_skip_check_backface:
    vlt     $v6, $v6, $v2     // v6 (thrown out), VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    andi    $12, $5, CLIP_MOD_MASK_SCAL_ALL // If any outside scaled bounds, do clipping
    vmrg    $v2, $v4, $v10   // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    bnez    $12, ovl23_clipping_entrypoint
     vmrg   $v10, $v10, $v4   // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    lhu     $6, modClipLargeTriThresh
    vsub    $v12, $v14, $v10  // VH - VL (negative)
    mfc2    $11, $v12[2]      // Y value of VH - VL (negative)
    andi    $12, $5, CLIP_MOD_MASK_SCRN_ALL // If any vertex outside screen bounds...
    add     $11, $11, $6      // Is triangle more than a certain number of scanlines high?
    sra     $11, $11, 31      // All 1s if tri is large, all 0s if it is small
    and     $12, $12, $11     // Large tri and partly outside screen bounds
    bnez    $12, ovl23_clipping_entrypoint // Do clipping
     vmudn  $v4, $v14, $v31[5]
    mfc2    $1, $v14[12]      // $v14 = lowest Y value = highest on screen (x, y, addr)
.else
    bnez    $5, ovl23_clipping_entrypoint // ...then run overlay 3 for clipping, either directly or via overlay 2 loading overlay 3.
     add    $11, $6, $11     // Add magic number; see description at gCullMagicNumbers
    vlt     $v6, $v6, $v2     // v6 (thrown out), VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    bgez    $11, return_routine // If sign bit is clear, cull.
     vmrg   $v2, $v4, $v10   // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    vmrg    $v10, $v10, $v4   // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    mfc2    $1, $v14[12]      // $v14 = lowest Y value = highest on screen (x, y, addr)
    vmudn   $v4, $v14, $v31[5]
    beqz    $6, return_routine // If cross product is 0, tri is degenerate (zero area), cull.
.endif
     vsub    $v6, $v2, $v14
    mfc2    $2, $v2[12]       // $v2 = mid vertex (x, y, addr)
    vsub    $v8, $v10, $v14
    mfc2    $3, $v10[12]      // $v10 = highest Y value = lowest on screen (x, y, addr)
    vsub    $v11, $v14, $v2
    lw      $6, geometryModeLabel
.if !MOD_CLIP_CHANGES
    vsub    $v12, $v14, $v10  // VH - VL (negative)
.endif
    llv     $v13[0], VTX_INV_W_VEC($1)
    vsub    $v15, $v10, $v2
    llv     $v13[8], VTX_INV_W_VEC($2)
    vmudh   $v16, $v6, $v8[0]
    llv     $v13[12], VTX_INV_W_VEC($3)
    vmadh   $v16, $v8, $v11[0]
    sll     $11, $6, 10             // Moves the value of G_SHADING_SMOOTH into the sign bit
    vreadacc $v17, ACC_UPPER
    bgez    $11, no_smooth_shading  // Branch if G_SHADING_SMOOTH isn't set
     vreadacc $v16, ACC_MIDDLE
    lpv     $v18[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
    vmov    $v15[2], $v6[0]
    lpv     $v19[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vrcp    $v20[0], $v15[1]
    lpv     $v21[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vrcph   $v22[0], $v17[1]
    vrcpl   $v23[1], $v16[1]
    j       shading_done
     vrcph   $v24[1], vZero[0]
no_smooth_shading:
    lpv     $v18[0], VTX_COLOR_VEC($4)
    vrcp    $v20[0], $v15[1]
    lbv     $v18[6], VTX_COLOR_A($1)
    vrcph   $v22[0], $v17[1]
    lpv     $v19[0], VTX_COLOR_VEC($4)
    vrcpl   $v23[1], $v16[1]
    lbv     $v19[6], VTX_COLOR_A($2)
    vrcph   $v24[1], vZero[0]
    lpv     $v21[0], VTX_COLOR_VEC($4)
    vmov    $v15[2], $v6[0]
    lbv     $v21[6], VTX_COLOR_A($3)
shading_done:
    // Not sure what the underlying reason for this change is, perhaps a bugfix
    // or a way to improve the fractional precision sent to the RDP.
    // Hopefully this will become clear once tri write is documented.
.if CFG_OLD_TRI_WRITE
.if MOD_VL_REWRITE
    .error "Rewrite not compatible with old tri write!"
.endif
    i1 equ 7 // v30[7] is 0x0100
    i2 equ 2 // v31[2] is 0x0008
    i3 equ 5 // v31[5] is 0x4000
    i4 equ 2 // v30[2] is 0x01CC
    i5 equ 5 // v30[5] is 0x0010
    i6 equ 6 // v30[6] is 0x0020
    vec1 equ v31
    vec2 equ v20
.else
    i1 equ 3 // v30[3] is 0x0100
    i2 equ 7 // v30[7] is 0x0020
    i3 equ 2 // v30[2] is 0x1000
    i4 equ 3 // v30[3] is 0x0100
    i5 equ 6 // v30[6] is 0x0010
    i6 equ 7 // v30[7] is 0x0020
    vec1 equ v30
    vec2 equ v22
.endif
    vrcp    $v20[2], $v6[1]
.if MOD_GENERAL
    // Get rid of any other bits so they can be used for other mods.
    // G_TEXTURE_ENABLE is defined as 0 in the F3DEX2 GBI, and whether the tri
    // commands are sent to the RDP as textured or not is set via enabling or
    // disabling the texture in SPTexture (textureSettings1 + 3 below).
    andi    $6, $6, G_SHADE | G_ZBUFFER
.endif
    vrcph   $v22[2], $v6[1]
    lw      $5, VTX_INV_W_VEC($1)
    vrcp    $v20[3], $v8[1]
    lw      $7, VTX_INV_W_VEC($2)
    vrcph   $v22[3], $v8[1]
    lw      $8, VTX_INV_W_VEC($3)
    // v30[i1] is 0x0100
    vmudl   $v18, $v18, $v30[i1] // vertex color 1 >>= 8
    lbu     $9, textureSettings1 + 3
    vmudl   $v19, $v19, $v30[i1] // vertex color 2 >>= 8
    sub     $11, $5, $7
    vmudl   $v21, $v21, $v30[i1] // vertex color 3 >>= 8
    sra     $12, $11, 31
    vmov    $v15[3], $v8[0]
    and     $11, $11, $12
    vmudl   $v29, $v20, $vec1[i2]
    sub     $5, $5, $11
    vmadm   $v22, $v22, $vec1[i2]
    sub     $11, $5, $8
    vmadn   $v20, vZero, vZero[0]
    sra     $12, $11, 31
    vmudm   $v25, $v15, $vec1[i3]
    and     $11, $11, $12
    vmadn   $v15, vZero, vZero[0]
    sub     $5, $5, $11
    vsubc   $v4, vZero, $v4
    sw      $5, 0x0010(rdpCmdBufPtr)
    vsub    $v26, vZero, vZero
    llv     $v27[0], 0x0010(rdpCmdBufPtr)
    vmudm   $v29, $v25, $v20
    mfc2    $5, $v17[1]
    vmadl   $v29, $v15, $v20
    lbu     $7, textureSettings1 + 2
    vmadn   $v20, $v15, $v22
    lsv     $v19[14], VTX_SCR_Z($2)
    vmadh   $v15, $v25, $v22
    lsv     $v21[14], VTX_SCR_Z($3)
    vmudl   $v29, $v23, $v16
    lsv     $v7[14], VTX_SCR_Z_FRAC($2)
    vmadm   $v29, $v24, $v16
    lsv     $v9[14], VTX_SCR_Z_FRAC($3)
    vmadn   $v16, $v23, $v17
    ori     $11, $6, G_TRI_FILL // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadh   $v17, $v24, $v17
    or      $11, $11, $9 // Incorporate whether textures are enabled into the triangle command id
.if !CFG_OLD_TRI_WRITE
    vand    $v22, $v20, $v30[5]
.endif
    vcr     $v15, $v15, $v30[i4]
    sb      $11, 0x0000(rdpCmdBufPtr) // Store the triangle command id
    vmudh   $v29, vOne, $v30[i5]
    ssv     $v10[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
    vmadn   $v16, $v16, $v30[4]     // v30[4] is 0xFFF0
    ssv     $v2[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadh   $v17, $v17, $v30[4]     // v30[4] is 0xFFF0
    ssv     $v14[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
    vmudn   $v29, $v3, $v14[0]
    andi    $12, $5, 0x0080 // Extract the left major flag from $5
    vmadl   $v29, $vec2, $v4[1]
    or      $12, $12, $7 // Combine the left major flag with the level and tile from the texture settings
    vmadm   $v29, $v15, $v4[1]
    sb      $12, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vmadn   $v2, $vec2, $v26[1]
    beqz    $9, no_textures // If textures are not enabled, skip texture coefficient calculation
     vmadh  $v3, $v15, $v26[1]
    vrcph   $v29[0], $v27[0]
    vrcpl   $v10[0], $v27[1]
    vadd    $v14, vZero, $v13[1q]
    vrcph   $v27[0], vZero[0]
    vor     $v22, vZero, $v31[7]
    vmudm   $v29, $v13, $v10[0]
    vmadl   $v29, $v14, $v10[0]
    llv     $v22[0], VTX_TC_VEC($1)
    vmadn   $v14, $v14, $v27[0]
    llv     $v22[8], VTX_TC_VEC($2)
    vmadh   $v13, $v13, $v27[0]
    vor     $v10, vZero, $v31[7]
    vge     $v29, $v30, $v30[7]
    llv     $v10[8], VTX_TC_VEC($3)
    vmudm   $v29, $v22, $v14[0h]
    vmadh   $v22, $v22, $v13[0h]
    vmadn   $v25, vZero, vZero[0]
    vmudm   $v29, $v10, $v14[6]     // acc = (v10 * v14[6]); v29 = mid(clamp(acc))
    vmadh   $v10, $v10, $v13[6]     // acc += (v10 * v13[6]) << 16; v10 = mid(clamp(acc))
    vmadn   $v13, vZero, vZero[0]   // v13 = lo(clamp(acc))
    sdv     $v22[0], 0x0020(rdpCmdBufPtr)
    vmrg    $v19, $v19, $v22
    sdv     $v25[0], 0x0028(rdpCmdBufPtr) // 8
    vmrg    $v7, $v7, $v25
    ldv     $v18[8], 0x0020(rdpCmdBufPtr) // 8
    vmrg    $v21, $v21, $v10
    ldv     $v5[8], 0x0028(rdpCmdBufPtr) // 8
    vmrg    $v9, $v9, $v13
no_textures:
    vmudl   $v29, $v16, $v23
    lsv     $v5[14], VTX_SCR_Z_FRAC($1)
    vmadm   $v29, $v17, $v23
    lsv     $v18[14], VTX_SCR_Z($1)
    vmadn   $v23, $v16, $v24
    lh      $1, VTX_SCR_VEC($2)
    vmadh   $v24, $v17, $v24
    addiu   $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
    vsubc   $v10, $v9, $v5
    andi    $3, $6, G_SHADE
    vsub    $v9, $v21, $v18
    sll     $1, $1, 14
    vsubc   $v13, $v7, $v5
    sw      $1, 0x0008(rdpCmdBufPtr)         // Store XL edge coefficient
    vsub    $v7, $v19, $v18
    ssv     $v3[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
    vmudn   $v29, $v10, $v6[1]
    ssv     $v2[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vmadh   $v29, $v9, $v6[1]
    ssv     $v3[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vmadn   $v29, $v13, $v12[1]
    ssv     $v2[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
    vmadh   $v29, $v7, $v12[1]
    ssv     $v15[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vreadacc $v2, ACC_MIDDLE
    ssv     $v20[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vreadacc $v3, ACC_UPPER
    ssv     $v15[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
    vmudn   $v29, $v13, $v8[0]
    ssv     $v20[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vmadh   $v29, $v7, $v8[0]
    ssv     $v15[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vmadn   $v29, $v10, $v11[0]
    ssv     $v20[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
    vmadh   $v29, $v9, $v11[0]
    sll     $11, $3, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vreadacc $v6, ACC_MIDDLE
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vreadacc $v7, ACC_UPPER
    sll     $11, $9, 5              // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
    vmudl   $v29, $v2, $v23[1]
    add     rdpCmdBufPtr, $1, $11            // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, $v3, $v23[1]
    andi    $6, $6, G_ZBUFFER       // Get the value of G_ZBUFFER from the current geometry mode
    vmadn   $v2, $v2, $v24[1]
    sll     $11, $6, 4              // Shift (geometry mode & G_ZBUFFER) by 4 to get 0x10 if G_ZBUFFER is set
    vmadh   $v3, $v3, $v24[1]
    add     rdpCmdBufPtr, rdpCmdBufPtr, $11           // Increment the triangle pointer by 0x10 bytes (depth coefficients) if G_ZBUFFER is set
    vmudl   $v29, $v6, $v23[1]
    vmadm   $v29, $v7, $v23[1]
    vmadn   $v6, $v6, $v24[1]
    sdv     $v2[0], 0x0018($2)      // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   $v7, $v7, $v24[1]
    sdv     $v3[0], 0x0008($2)      // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
    vmadl   $v29, $v2, $v20[3]
    sdv     $v2[8], 0x0018($1)      // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadm   $v29, $v3, $v20[3]
    sdv     $v3[8], 0x0008($1)      // Store DsDx, DtDx, DwDx texture coefficients (integer)
    vmadn   $v8, $v2, $v15[3]
    sdv     $v6[0], 0x0038($2)      // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   $v9, $v3, $v15[3]
    sdv     $v7[0], 0x0028($2)      // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
    vmudn   $v29, $v5, vOne[0]
    sdv     $v6[8], 0x0038($1)      // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadh   $v29, $v18, vOne[0]
    sdv     $v7[8], 0x0028($1)      // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadl   $v29, $v8, $v4[1]
    sdv     $v8[0], 0x0030($2)      // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadm   $v29, $v9, $v4[1]
    sdv     $v9[0], 0x0020($2)      // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    vmadn   $v5, $v8, $v26[1]
    sdv     $v8[8], 0x0030($1)      // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    vmadh   $v18, $v9, $v26[1]
    sdv     $v9[8], 0x0020($1)      // Store DsDe, DtDe, DwDe texture coefficients (integer)
    vmudn   $v10, $v8, $v4[1]
    beqz    $6, no_z_buffer
     vmudn  $v8, $v8, $v30[i6]      // v30[i6] is 0x0020
    vmadh   $v9, $v9, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v5[0], 0x0010($2)      // Store RGBA shade color (fractional)
    vmudn   $v2, $v2, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v18[0], 0x0000($2)     // Store RGBA shade color (integer)
    vmadh   $v3, $v3, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v5[8], 0x0010($1)      // Store S, T, W texture coefficients (fractional)
    vmudn   $v6, $v6, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v18[8], 0x0000($1)     // Store S, T, W texture coefficients (integer)
    vmadh   $v7, $v7, $v30[i6]      // v30[i6] is 0x0020
    ssv     $v8[14], -0x0006(rdpCmdBufPtr)
    vmudl   $v29, $v10, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v9[14], -0x0008(rdpCmdBufPtr)
    vmadn   $v5, $v5, $v30[i6]      // v30[i6] is 0x0020
    ssv     $v2[14], -0x000A(rdpCmdBufPtr)
    vmadh   $v18, $v18, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v3[14], -0x000C(rdpCmdBufPtr)
    ssv     $v6[14], -0x0002(rdpCmdBufPtr)
    ssv     $v7[14], -0x0004(rdpCmdBufPtr)
    ssv     $v5[14], -0x000E(rdpCmdBufPtr)
    j       check_rdp_buffer_full   // eventually returns to $ra, which is next cmd, second tri in TRI2, or middle of clipping
    ssv     $v18[14], -0x10(rdpCmdBufPtr)

no_z_buffer:
    sdv     $v5[0], 0x0010($2)      // Store RGBA shade color (fractional)
    sdv     $v18[0], 0x0000($2)     // Store RGBA shade color (integer)
    sdv     $v5[8], 0x0010($1)      // Store S, T, W texture coefficients (fractional)
    j       check_rdp_buffer_full   // eventually returns to $ra, which is next cmd, second tri in TRI2, or middle of clipping
     sdv    $v18[8], 0x0000($1)     // Store S, T, W texture coefficients (integer)

vtxPtr    equ $25 // = cmd_w0
endVtxPtr equ $24 // = cmd_w1_dram
G_CULLDL_handler:
    lhu     vtxPtr, (vertexTable)(cmd_w0)     // load start vertex address
    lhu     endVtxPtr, (vertexTable)(cmd_w1_dram) // load end vertex address
.if MOD_CLIP_CHANGES
    la      $1, CLIP_MOD_MASK_SCRN_ALL
    lhu     $11, VTX_CLIP(vtxPtr)
.else
    la      $1, (CLIP_NX | CLIP_NY | CLIP_PX | CLIP_PY | CLIP_FAR | CLIP_NEAR)
    lw      $11, VTX_CLIP(vtxPtr)             // read clip flags from vertex
.endif
culldl_loop:
    and     $1, $1, $11
    beqz    $1, run_next_DL_command           // Some vertex is on the screen-side of all clipping planes; have to render
.if MOD_CLIP_CHANGES
     lhu    $11, (vtxSize + VTX_CLIP)(vtxPtr) // next vertex clip flags
.else
     lw     $11, (vtxSize + VTX_CLIP)(vtxPtr) // next vertex clip flags
.endif
    bne     vtxPtr, endVtxPtr, culldl_loop    // loop until reaching the last vertex
     addiu  vtxPtr, vtxPtr, vtxSize           // advance to the next vertex
    j       G_ENDDL_handler                   // If got here, there's some clipping plane where all verts are outside it; skip DL
G_BRANCH_WZ_handler:
     lhu    vtxPtr, (vertexTable)(cmd_w0)     // get the address of the vertex being tested
.if CFG_G_BRANCH_W                            // BRANCH_W/BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      vtxPtr, VTX_W_INT(vtxPtr)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      vtxPtr, VTX_SCR_Z(vtxPtr)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, vtxPtr, cmd_w1_dram           // subtract the w/z value being tested
    bgez    $2, run_next_DL_command           // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val          // load the RDPHALF1 value as the location to branch to
    j       branch_dl
G_MODIFYVTX_handler:
     lbu    $1, (inputBufferEnd - 0x07)(inputBufferPos)
    j       do_moveword
     lhu    cmd_w0, (vertexTable)(cmd_w0)

     
.if . > 0x00001FAC
    .error "Not enough room in IMEM"
.endif
.org 0x1FAC

// This subroutine sets up the values to load overlay 0 and then falls through
// to load_overlay_and_enter to execute the load.
load_overlay_0_and_enter:
G_LOAD_UCODE_handler:
    li      postOvlRA, ovl0_start                    // Sets up return address
    li      ovlTableEntry, overlayInfo0              // Sets up ovl0 table address
// This subroutine accepts the address of an overlay table entry and loads that overlay.
// It then jumps to that overlay's address after DMA of the overlay is complete.
// ovlTableEntry is used to provide the overlay table entry
// postOvlRA is used to pass in a value to return to
load_overlay_and_enter:
    lw      cmd_w1_dram, overlay_load(ovlTableEntry) // Set up overlay dram address
    lhu     dmaLen, overlay_len(ovlTableEntry)       // Set up overlay length
    jal     dma_read_write                           // DMA the overlay
     lhu    dmemAddr, overlay_imem(ovlTableEntry)    // Set up overlay load address
    move    $ra, postOvlRA                // Set the return address to the passed in value

.if . > 0x1FC8
    .error "Constraints violated on what can be overwritten at end of ucode (relevant for G_LOAD_UCODE)"
.endif

while_wait_dma_busy:
    mfc0    ovlTableEntry, SP_DMA_BUSY    // Load the DMA_BUSY value into ovlTableEntry
while_dma_busy:
    bnez    ovlTableEntry, while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   ovlTableEntry, SP_DMA_BUSY    // Update ovlTableEntry's DMA_BUSY value
// This routine is used to return via conditional branch
return_routine:
    jr      $ra

dma_read_write:
     mfc0   $11, SP_DMA_FULL          // load the DMA_FULL value
while_dma_full:
    bnez    $11, while_dma_full       // Loop until DMA_FULL is cleared
     mfc0   $11, SP_DMA_FULL          // Update DMA_FULL value
    mtc0    dmemAddr, SP_MEM_ADDR     // Set the DMEM address to DMA from/to
    bltz    dmemAddr, dma_write       // If the DMEM address is negative, this is a DMA write, if not read
     mtc0   cmd_w1_dram, SP_DRAM_ADDR // Set the DRAM address to DMA from/to
    jr $ra
     mtc0   dmaLen, SP_RD_LEN         // Initiate a DMA read with a length of dmaLen
dma_write:
    jr $ra
     mtc0   dmaLen, SP_WR_LEN         // Initiate a DMA write with a length of dmaLen

.if . > 0x00002000
    .error "Not enough room in IMEM"
.endif

// first overlay table at 0x02E0
// overlay 0 (0x98 bytes loaded into 0x1000)

.headersize 0x00001000 - orga()

// Overlay 0 controls the RDP and also stops the RSP when work is done
// The action here is controlled by $1. If yielding, $1 > 0. If this was
// G_LOAD_UCODE, $1 == 0. If we got to the end of the parent DL, $1 < 0.
ovl0_start:
.if !CFG_XBUS // FIFO version
    sub     $11, rdpCmdBufPtr, rdpCmdBufEnd
    addiu   $12, $11, RDP_CMD_BUFSIZE - 1
    bgezal  $12, flush_rdp_buffer
     nop
    jal     while_wait_dma_busy
     lw     $24, rdpFifoPos
    bltz    $1, taskdone_and_break  // $1 < 0 = Got to the end of the parent DL
     mtc0   $24, DPC_END            // Set the end pointer of the RDP so that it starts the task
.else // CFG_XBUS
    bltz    $1, taskdone_and_break  // $1 < 0 = Got to the end of the parent DL
     nop
.endif
    bnez    $1, task_yield          // $1 > 0 = CPU requested yield
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
// If here, G_LOAD_UCODE was executed.
    lw      cmd_w1_dram, (inputBufferEnd - 0x04)(inputBufferPos) // word 1 = ucode code DRAM addr
    sw      taskDataPtr, OSTask + OSTask_data_ptr // Store where we are in the DL
    sw      cmd_w1_dram, OSTask + OSTask_ucode // Store pointer to new ucode about to execute
    la      dmemAddr, start         // Beginning of overwritable part of IMEM
    jal     dma_read_write          // DMA DRAM read -> IMEM write
     li     dmaLen, (while_wait_dma_busy - start) - 1 // End of overwritable part of IMEM
.if CFG_XBUS
ovl0_xbus_wait_for_rdp:
    mfc0 $11, DPC_STATUS
    andi $11, $11, DPC_STATUS_DMA_BUSY
    bnez $11, ovl0_xbus_wait_for_rdp // Keep looping while RDP is busy.
.endif
    lw      cmd_w1_dram, rdpHalf1Val // Get DRAM address of ucode data from rdpHalf1Val
    la      dmemAddr, spFxBase      // DMEM address is spFxBase
    andi    dmaLen, cmd_w0, 0x0FFF  // Extract DMEM length from command word
    add     cmd_w1_dram, cmd_w1_dram, dmemAddr // Start overwriting data from spFxBase
    jal     dma_read_write          // initate DMA read
     sub    dmaLen, dmaLen, dmemAddr // End that much before the end of DMEM
    j       while_wait_dma_busy
.if CFG_DONT_SKIP_FIRST_INSTR_NEW_UCODE
    // Not sure why we skip the first instruction of the new ucode; in this ucode, it's
    // zeroing vZero, but maybe it could be something else in other ucodes. But, starting
    // actually at the beginning is only in 2.04H, so skipping is likely the intended
    // behavior. Maybe some other ucodes use this for detecting whether they were run
    // from scratch or called from another ucode?
     li     $ra, start
.else
     li     $ra, start + 4
.endif

.if . > start
    .error "ovl0_start does not fit within the space before the start of the ucode loaded with G_LOAD_UCODE"
.endif

ucode equ $11
status equ $12
task_yield:
    lw      ucode, OSTask + OSTask_ucode
.if !CFG_XBUS // FIFO version
    sw      taskDataPtr, OS_YIELD_DATA_SIZE - 8
    sw      ucode, OS_YIELD_DATA_SIZE - 4
    li      status, SP_SET_SIG1 | SP_SET_SIG2   // yielded and task done signals
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    li      dmemAddr, 0x8000 // 0, but negative = write
    li      dmaLen, OS_YIELD_DATA_SIZE - 1
.else // CFG_XBUS
    // Instead of saving the whole first OS_YIELD_DATA_SIZE bytes of DMEM,
    // XBUS saves only up to inputBuffer, as everything after that can be erased,
    // and because the RDP may still be using the output buffer, which is where
    // we'd have to write taskDataPtr and ucode.
    sw      taskDataPtr, inputBuffer // save these values for below, somewhere outside
    sw      ucode, inputBuffer + 4   // the area being written
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    li      dmemAddr, 0x8000 // 0, but negative = write
    jal     dma_read_write
     li     dmaLen, inputBuffer - 1
    // At the end of the OS's yield buffer, write the taskDataPtr and ucode words.
    li      status, SP_SET_SIG1 | SP_SET_SIG2 // yielded and task done signals
    addiu   cmd_w1_dram, cmd_w1_dram, OS_YIELD_DATA_SIZE - 8
    li      dmemAddr, 0x8000 | inputBuffer // where they were saved above
    li      dmaLen, 8 - 1
.endif
    j       dma_read_write
     li     $ra, break

taskdone_and_break:
    li      status, SP_SET_SIG2   // task done signal
break:
.if CFG_XBUS
ovl0_xbus_wait_for_rdp_2:
    mfc0 $11, DPC_STATUS
    andi $11, $11, DPC_STATUS_DMA_BUSY
    bnez $11, ovl0_xbus_wait_for_rdp_2 // Keep looping while RDP is busy.
     nop
.endif
    mtc0    status, SP_STATUS
    break   0
    nop

.align 8
ovl0_end:

.if ovl0_end > ovl01_end
    .error "Automatic resizing for overlay 0 failed"
.endif

// overlay 1 (0x170 bytes loaded into 0x1000)
.headersize 0x00001000 - orga()

ovl1_start:

G_DL_handler:
    lbu     $1, displayListStackLength  // Get the DL stack length
    sll     $2, cmd_w0, 15              // Shifts the push/nopush value to the highest bit in $2
branch_dl:
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos
    bltz    $2, displaylist_dma         // If the operation is nopush (branch) then simply DMA the new displaylist
     move   taskDataPtr, cmd_w1_dram    // Set the task data pointer to the target display list
    sw      $3, (displayListStack)($1)
    addi    $1, $1, 4                   // Increment the DL stack length
f3dzex_ovl1_00001020:
    j       displaylist_dma
     sb     $1, displayListStackLength

G_TEXTURE_handler:
    li      $11, textureSettings1 - (texrectWord1 - G_TEXRECTFLIP_handler)  // Calculate the offset from texrectWord1 and $11 for saving to textureSettings
G_TEXRECT_handler:
G_TEXRECTFLIP_handler:
    // Stores first command word into textureSettings for gSPTexture, 0x00D0 for gSPTextureRectangle/Flip
    sw      cmd_w0, (texrectWord1 - G_TEXRECTFLIP_handler)($11)
G_RDPHALF_1_handler:
    j       run_next_DL_command
    // Stores second command word into textureSettings for gSPTexture, 0x00D4 for gSPTextureRectangle/Flip, 0x00D8 for G_RDPHALF_1
     sw     cmd_w1_dram, (texrectWord2 - G_TEXRECTFLIP_handler)($11)

G_MOVEWORD_handler:
    srl     $2, cmd_w0, 16                              // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $1, (movewordTable - (G_MOVEWORD << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    add     $1, $1, cmd_w0          // adds the offset in the command word to the address from the table (the upper 4 bytes are effectively ignored)
    j       run_next_DL_command     // process the next command
     sw     cmd_w1_dram, ($1)       // moves the specified value (in cmd_w1_dram) into the word (offset + moveword_table[index])

G_POPMTX_handler:
    lw      $11, matrixStackPtr             // Get the current matrix stack pointer
    lw      $2, OSTask + OSTask_dram_stack  // Read the location of the dram stack
    sub     cmd_w1_dram, $11, cmd_w1_dram           // Decrease the matrix stack pointer by the amount passed in the second command word
    sub     $1, cmd_w1_dram, $2                     // Subtraction to check if the new pointer is greater than or equal to $2
    bgez    $1, do_popmtx                   // If the new matrix stack pointer is greater than or equal to $2, then use the new pointer as is
     nop
    move    cmd_w1_dram, $2                         // If the new matrix stack pointer is less than $2, then use $2 as the pointer instead
do_popmtx:
    beq     cmd_w1_dram, $11, run_next_DL_command   // If no bytes were popped, then we don't need to make the mvp matrix as being out of date and can run the next command
     sw     cmd_w1_dram, matrixStackPtr             // Update the matrix stack pointer with the new value
    j       do_movemem
     sw     $zero, mvpValid                 // Mark the MVP matrix and light directions as being out of date (the word being written to contains both)

G_MTX_end: // Multiplies the loaded model matrix into the model stack
    lhu     output_mtx, (movememTable + G_MV_MMTX)($1) // Set the output matrix to the model or projection matrix based on the command
    jal     while_wait_dma_busy
     lhu    input_mtx_0, (movememTable + G_MV_MMTX)($1) // Set the first input matrix to the model or projection matrix based on the command
    li      $ra, run_next_DL_command
    // The second input matrix will correspond to the address that memory was moved into, which will be tempMtx for G_MTX

mtx_multiply:
.if MOD_VL_REWRITE
    vxor    vZero, vZero, vZero
.endif
    addi    $12, input_mtx_1, 0x0018
@@loop:
    vmadn   $v9, vZero, vZero[0]
    addi    $11, input_mtx_1, 0x0008
    vmadh   $v8, vZero, vZero[0]
    addi    input_mtx_0, input_mtx_0, -0x0020
    vmudh   $v29, vZero, vZero[0]
@@innerloop:
    ldv     $v5[0], 0x0040(input_mtx_0)
    ldv     $v5[8], 0x0040(input_mtx_0)
    lqv     $v3[0], 0x0020(input_mtx_1)
    ldv     $v4[0], 0x0020(input_mtx_0)
    ldv     $v4[8], 0x0020(input_mtx_0)
    lqv     $v2[0], 0x0000(input_mtx_1)
    vmadl   $v29, $v5, $v3[0h]
    addi    input_mtx_1, input_mtx_1, 0x0002
    vmadm   $v29, $v4, $v3[0h]
    addi    input_mtx_0, input_mtx_0, 0x0008
    vmadn   $v7, $v5, $v2[0h]
    bne     input_mtx_1, $11, @@innerloop
     vmadh  $v6, $v4, $v2[0h]
    bne     input_mtx_1, $12, @@loop
     addi   input_mtx_1, input_mtx_1, 0x0008
    // Store the results in the passed in matrix
    sqv     $v9[0], 0x0020(output_mtx)
    sqv     $v8[0], 0x0000(output_mtx)
    sqv     $v7[0], 0x0030(output_mtx)
    jr      $ra
     sqv    $v6[0], 0x0010(output_mtx)

G_MTX_handler:
    // The lower 3 bits of G_MTX are, from LSb to MSb (0 value/1 value),
    //  matrix type (modelview/projection)
    //  load type (multiply/load)
    //  push type (nopush/push)
    // In F3DEX2 (and by extension F3DZEX), G_MTX_PUSH is inverted, so 1 is nopush and 0 is push
    andi    $11, cmd_w0, G_MTX_P_MV | G_MTX_NOPUSH_PUSH // Read the matrix type and push type flags into $11
    bnez    $11, load_mtx                               // If the matrix type is projection or this is not a push, skip pushing the matrix
     andi   $2, cmd_w0, G_MTX_MUL_LOAD                  // Read the matrix load type into $2 (0 is multiply, 2 is load)
    lw      cmd_w1_dram, matrixStackPtr                 // Set up the DMA from dmem to rdram at the matrix stack pointer
    li      dmemAddr, -0x2000                           //
    jal     dma_read_write                              // DMA the current matrix from dmem to rdram
     li     dmaLen, 0x0040 - 1                          // Set the DMA length to the size of a matrix (minus 1 because DMA is inclusive)
    addi    cmd_w1_dram, cmd_w1_dram, 0x40              // Increase the matrix stack pointer by the size of one matrix
    sw      cmd_w1_dram, matrixStackPtr                 // Update the matrix stack pointer
    lw      cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Load command word 1 again
load_mtx:
    add     $12, $12, $2        // Add the load type to the command byte, selects the return address based on whether the matrix needs multiplying or just loading
    sw      $zero, mvpValid     // Mark the MVP matrix and light directions as being out of date (the word being written to contains both)
G_MOVEMEM_handler:
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
do_movemem:
     andi   $1, cmd_w0, 0x00FE                              // Move the movemem table index into $1 (bits 1-7 of the first command word)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Move the second byte of the first command word into dmaLen
    lhu     dmemAddr, (movememTable)($1)                    // Load the address of the memory location for the given movemem index
    srl     $2, cmd_w0, 5                                   // Left shifts the index by 5 (which is then added to the value read from the movemem table)
    lhu     $ra, (movememHandlerTable - (G_POPMTX | 0xFF00))($12)  // Loads the return address from movememHandlerTable based on command byte
    j       dma_read_write
G_SETOTHERMODE_H_handler: // These handler labels must be 4 bytes apart for the code below to work
     add    dmemAddr, dmemAddr, $2                          // This is for the code above, does nothing for G_SETOTHERMODE_H
G_SETOTHERMODE_L_handler:
    lw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($11) // resolves to othermode0 or othermode1 based on which handler was jumped to
    lui     $2, 0x8000
    srav    $2, $2, cmd_w0
    srl     $1, cmd_w0, 8
    srlv    $2, $2, $1
    nor     $2, $2, $zero
    and     $3, $3, $2
    or      $3, $3, cmd_w1_dram
    sw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($11)
    lw      cmd_w0, otherMode0
    j       G_RDP_handler
     lw     cmd_w1_dram, otherMode1

.align 8
ovl1_end:

.if ovl1_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif

.headersize ovl23_start - orga()

// Locals for vl_mod_lighting, but armips requires them to be defined on all codepaths.
vNormals equ $v28
vnPosXY equ $v23
vnZ equ $v24
vLtLvl equ $v30

// Locals for original code
xfrmLtPtr equ $20 // also input_mtx_1 and dmemAddr
curMatrix equ $12 // Value only matters during light_vtx for a single pair of vertices
ltColor equ $v29
vPairAlpha37 equ $v28 // Same as mvTc1f, but alpha values are left in elems 3, 7
vPairNX equ $v7 // also named vPairRGBATemp; with name vPairNX, uses X components = elems 0, 4
vPairNY equ $v6
vPairNZ equ $v5

ovl2_start:
ovl23_lighting_entrypoint:
.if MOD_VL_REWRITE
vl_mod_lighting:
    vmrg    vNormals, $v28, $v26          // Merge normals
    j       vl_mod_continue_lighting
     andi   $11, $5, G_PACKED_NORMALS >> 8
.else
    lbu     $11, lightsValid
    j       continue_light_dir_xfrm
     lbu    topLightPtr, numLightsx18
.endif

ovl23_clipping_entrypoint_copy:  // same IMEM address as ovl23_clipping_entrypoint
.if MOD_GENERAL
    sh      $ra, modSaveRA
.else
    move    savedRA, $ra
.endif
    li      ovlTableEntry, overlayInfo3       // set up a load of overlay 3
    j       load_overlay_and_enter            // load overlay 3
     li     postOvlRA, ovl3_clipping_nosavera // set up the return address in ovl3

.if MOD_VL_REWRITE

vl_mod_continue_lighting:
    // Inputs: $v20:$v21 vertices pos world int:frac, vPairRGBA, vPairST,
    // $v28 vNormals, $v30:$v25 (to be merged) packed normals
    // Outputs: vPairRGBA, vPairST, must leave alone $v20:$v21
    // Locals: $v29 temp, $v23 (will be vPairMVPPosF), $v24 (will be vPairMVPPosI),
    // $v25 after merge, $v26 after merge, whichever of $v28 or $v30 is unused
    vmrg    $v30, $v30, $v25          // Merge packed normals
    beqz    $11, vl_mod_skip_packed_normals
    // Packed normals algorithm. This produces a vector (one for each input vertex)
    // in vNormals such that |X| + |Y| + |Z| = 0x7F00 (called L1 norm), in the
    // same direction as the standard normal vector. The length is not "correct"
    // compared to the standard normal, but it's is normalized anyway after the M
    // matrix transform.
     vand   vnPosXY, $v30, $v31[6] // 0x7F00; positive X, Y
    vxor    $v29, $v29, $v29 // Zero
    vaddc   vnZ, vnPosXY, vnPosXY[1q] // elem 0, 4: pos X + pos Y, no clamping
    vadd    $v26, $v29, $v29 // Save carry bit, indicates use 0x7F00 - x and y
    vxor    vNormals, vnPosXY, $v31[6] // 0x7F00 - x, 0x7F00 - y
    vxor    vnZ, vnZ, $v31[6] // 0x7F00 - +X - +Y in elems 0, 4
    vne     $v29, $v29, $v26[0h] // set 0-3, 4-7 vcc if (+X + +Y) overflowed, discard result
    vmrg    vNormals, vNormals, vnPosXY // If so, use 0x7F00 - +X, else +X (same for Y)
    vne     $v29, $v31, $v31[2h] // set VCC to 11011101
    vabs    vNormals, $v30, vNormals // Apply sign of original X and Y to new X and Y
    vmrg    vNormals, vNormals, vnZ[0h] // Move Z to elements 2, 6
// End of lifetimes of vnPosXY and vnZ
vl_mod_skip_packed_normals:
    // Transform normals by M matrix and normalize
    // Also set up ambient occlusion: light *= (factor * (alpha - 1) + 1)
    vmudn   $v29, $v4, vNormals[0h]
    lbu     curLight, numLightsx18
    vmadh   $v29, $v0, vNormals[0h]
    vmadn   $v29, $v5, vNormals[1h]
    vmadh   $v29, $v1, vNormals[1h]
    addi    curLight, curLight, spFxBase - lightSize // Point to first non-ambient light
    vmadn   $v29, $v6, vNormals[2h]
    vmadh   vNormals, $v2, vNormals[2h] // Single precision should be plenty
    vsub    vPairRGBA, vPairRGBA, $v31[7] // 0x7FFF; offset alpha, will be fixed later
    vne     $v29, $v31, $v31[3h] // Set VCC to 11101110
    vmrg    vNormals, vNormals, vFogMask[3] // 0; set elems 3, 7 to 0
    vmudh   $v29, vNormals, vNormals // Transformed normal squared
    vsar    $v23, $v31, $v31[ACC_UPPER] // Load high component
    vmulf   $v26, vPairRGBA, vFogMask[2]  // aoAmb factor
    luv     vLtLvl, (ltBufOfs + lightSize + 0)(curLight) // Total light level, init to ambient
    vadd    $v23, $v23, $v23[1q] // Sum components
    vadd    $v26, $v26, $v31[7] // 0x7FFF = 1 in s.15
    vadd    $v23, $v23, $v23[2h]
    vmulf   vNormals, vNormals, $v31[5] // 0x4000 * transformed normal, effectively / 2
    vrsqh   $v25[2], $v23[0] // High input, garbage output
    vrsql   $v25[1], vFogMask[3] // 0 input, low output
    vrsqh   $v25[0], $v23[4] // High input, high output
    vrsql   $v25[5], vFogMask[3] // 0 input, low output
    vrsqh   $v25[4], vFogMask[3] // High output, 0 input
    vmulf   vLtLvl, vLtLvl, $v26[3h] // light color *= ambient factor
    sll     $12, $5, 17 // G_LIGHTING_POSITIONAL = 0x00400000; $5 is middle 16 bits so 0x00004000
    vmudm   $v29, vNormals, $v25[1h] // Normal * frac scaling
    sra     $12, $12, 31 // All 1s if point lighting enabled, else all 0s
    vmadh   vNormals, vNormals, $v25[0h] // Normal * int scaling
vl_mod_light_loop:
    ldv     $v23[0], (ltBufOfs + 8)(curLight) // Light position or direction
    ldv     $v23[8], (ltBufOfs + 8)(curLight)
    blt     curLight, spFxBaseReg, vl_mod_lighting_done
     lbu    $11, (3)(curLight) // Light type / constant attenuation
    vmulf   $v29, vPairRGBA, vFogMask[6] // aoDir factor
    and     $11, $11, $12 // Mask away if point lighting disabled
    vmulu   $v25, $v23, vNormals // Light dir * normalized normals, clamp to 0
    bnez    $11, vl_mod_point_light
     luv    $v26,    (ltBufOfs + 0)(curLight) // Light color
    vand    $v25, $v25, $v31[7] // vmulu produces 0xFFFF if 0x8000 * 0x8000; make this 0x7FFF instead
    vadd    $v29, $v29, $v31[7] // 0x7FFF
    vadd    $v25, $v25, $v25[1q] // Sum elements for dot product
    vmulf   $v26, $v26, $v29[3h] // light color *= ambient factor
    vadd    $v25, $v25, $v25[2h]
vl_mod_finish_light:
    addiu   curLight, curLight, -lightSize
    vmulf   $v29, vLtLvl, $v31[7] // 0x7FFF; Total light level * 1 in s.15
    j       vl_mod_light_loop
     vmacf  vLtLvl, $v26, $v25[0h] // + light color * dot product

vl_mod_point_light:
    // TODO replace this with real implementation
    j       vl_mod_finish_light
     vand   $v25, $v25, $v31[7] // for now, X component of dot product

vl_mod_lighting_done:
    vadd    vPairRGBA, vPairRGBA, $v31[7] // 0x7FFF; undo change for ambient occlusion
    ldv     $v24[0], (ltBufOfs - lightSize + 8)(curLight) // Lookat dir 0
    vmulf   $v23, vNormals, $v23 // Normal * lookat dir 1
    ldv     $v24[8], (ltBufOfs - lightSize + 8)(curLight) // Lookat dir 0
    andi    $11, $5, G_LIGHTTOALPHA >> 8
    andi    $12, $5, G_PACKED_NORMALS >> 8
    vmulf   $v25, vPairRGBA, vLtLvl     // Base output is RGB * light
    beqz    $11, vl_mod_skip_cel
     vmrg   $v26, vFogMask, vPairRGBA // $v26 = alpha output = vtx alpha (only 3, 7 matter)
    vmrg    $v26, vFogMask, vLtLvl[1h]  //                     = light green
    vor     $v25, vPairRGBA, vPairRGBA // Base output is just RGB
vl_mod_skip_cel:
    vadd    $v23, $v23, $v23[1q] // First part of summing dot product for dir 1 -> 0,4
    vmulf   $v24, vNormals, $v24 // Normal * lookat dir 0
// End of vNormals lifetime
    bnez    $12, vl_mod_skip_novtxcolor
     vxor   $v28, $v28, $v28 // Zero
    vor     $v25, vLtLvl, vLtLvl // Base output is just light
// End of vLtLvl lifetime
vl_mod_skip_novtxcolor:
    vadd    $v23, $v23, $v23[2h] // Second part of summing dot product for dir 1 -> 0,4
    andi    $11, $5, G_TEXTURE_GEN >> 8
    vadd    $v24, $v24, $v24[0q] // First part of summing dot product for dir 0 -> 1,5
    beqz    $11, vl_mod_return_from_lighting
     vmrg   vPairRGBA, $v25, $v26 // Merge base output and alpha output
    // Texgen: $v24 and $v23 are dirs 0 and 1, locals $v25, $v26, $v28, $v30
    // Output: vPairST; have to leave $v20:$v21, vPairRGBA
    vadd    $v24, $v24, $v24[3h] // Second part of summing dot product for dir 0 -> 1,5
    lqv     $v30[0], (linearGenerateCoefficients)($zero)
    vsub    $v28, $v28, $v31[1] // -1; $v28 = 1
    andi    $11, $5, G_TEXTURE_GEN_LINEAR >> 8
    vne     $v29, $v31, $v31[1h] // Set VCC to 10111011
    vmrg    $v23, $v23, $v24     // Dot products in elements 0, 1, 4, 5
    vmudh   $v29, $v28, $v31[5]  // 1 * 0x4000
    beqz    $11, vl_mod_return_from_lighting
     vmacf  vPairST, $v23, $v31[5] // + dot products * 0x4000
    // Texgen Linear
    vmadh   vPairST, $v28, $v30[0] // + 1 * 0xC000 (gets rid of the 0x4000?)
    vmulf   $v26, vPairST, vPairST // ST squared
    vmulf   $v25, vPairST, $v31[7] // 0x7FFF, move to accumulator
    vmacf   $v25, vPairST, $v2[2] // + ST * 0x6CB3
    vmudh   $v29, $v28, $v31[5] // 1 * 0x4000
    vmacf   vPairST, vPairST, $v2[1] // + ST * 0x44D3
    j       vl_mod_return_from_lighting
     vmacf  vPairST, $v26, $v25 // + ST squared * (ST + ST * coeff)

.else // MOD_VL_REWRITE

continue_light_dir_xfrm:
    // Transform light directions from camera space to model space, by
    // multiplying by modelview transpose, then normalize and store the results
    // (not overwriting original dirs). This is applied starting from the two
    // lookat lights and through all directional and point lights, but not
    // ambient. For point lights, the data is garbage but doesn't harm anything.
    bnez    $11, after_light_dir_xfrm // Skip calculating lights if they're not out of date
     addi   topLightPtr, topLightPtr, spFxBase - lightSize // With ltBufOfs, points at top/max light.
    sb      cmd_w0, lightsValid     // Set as valid, reusing state of w0
    /* Load MV matrix 3x3 transposed as:
    mxr0i 00 08 10 06 08 0A 0C 0E
    mxr1i 02 0A 12
    mxr2i 04 0C 14
    mxr3i 
    mxr0f 20 28 30 26 28 2A 2C 2E
    mxr1f 22 2A 32
    mxr2f 24 2C 34
    mxr3f 
    Vector regs now contain columns of the original matrix
    This is computing:
    vec3_s8 origDir = light[0x8:0xA];
    vec3_s16 newDir = origDir * transpose(mvMatrix[0:2][0:2]);
    newDir /= sqrt(newDir.x**2 + newDir.y**2 + newDir.z**2); //normalize
    light[0x10:0x12] = light[0x14:0x16] = (vec3_s8)newDir;
    */
    lqv     mxr0f,    (mvMatrix + 0x20)($zero)
    lqv     mxr0i,    (mvMatrix + 0x00)($zero)
    lsv     mxr1f[2], (mvMatrix + 0x2A)($zero)
    lsv     mxr1i[2], (mvMatrix + 0x0A)($zero)
    vmov    mxr1f[0], mxr0f[1]
    lsv     mxr2f[4], (mvMatrix + 0x34)($zero)
    vmov    mxr1i[0], mxr0i[1]
    lsv     mxr2i[4], (mvMatrix + 0x14)($zero)
    vmov    mxr2f[0], mxr0f[2]
    // With ltBufOfs immediate add, points two lights behind lightBufferMain, i.e. lightBufferLookat.
    li      xfrmLtPtr, spFxBase - 2 * lightSize
    vmov    mxr2i[0], mxr0i[2]                   
    lpv     $v7[0], (ltBufOfs + 0x8)(xfrmLtPtr) // Load light direction
    vmov    mxr2f[1], mxr0f[6]
    lsv     mxr1f[4], (mvMatrix + 0x32)($zero)
    vmov    mxr2i[1], mxr0i[6]
    lsv     mxr1i[4], (mvMatrix + 0x12)($zero)
    vmov    mxr0f[1], mxr0f[4]
    lsv     mxr0f[4], (mvMatrix + 0x30)($zero)
    vmov    mxr0i[1], mxr0i[4]
    lsv     mxr0i[4], (mvMatrix + 0x10)($zero)
@@loop:
    vmudn   $v29, mxr1f, $v7[1]         // light y direction (fractional)
    vmadh   $v29, mxr1i, $v7[1]         // light y direction (integer)
    vmadn   $v29, mxr0f, $v7[0]         // light x direction (fractional)
    spv     $v15[0], (ltBufOfs + 0x10)(xfrmLtPtr) // Store transformed light direction; first loop is garbage
    vmadh   $v29, mxr0i, $v7[0]         // light x direction (integer)
    lw      $12, (ltBufOfs + 0x10)(xfrmLtPtr) // Reload transformed light direction
    vmadn   $v29, mxr2f, $v7[2]         // light z direction (fractional)
    vmadh   $v29, mxr2i, $v7[2]         // light z direction (integer)
    // Square the low 32 bits of each accumulator element
    vreadacc $v11, ACC_MIDDLE           // read the middle (bits 16..31) of the accumulator elements into v11
    sw      $12, (ltBufOfs + 0x14)(xfrmLtPtr) // Store duplicate of transformed light direction
    vreadacc $v15, ACC_UPPER            // read the upper (bits 32..47) of the accumulator elements into v15
    beq     xfrmLtPtr, topLightPtr, after_light_dir_xfrm    // exit if equal
     vmudl  $v29, $v11, $v11            // calculate the low partial product of the accumulator squared (low * low)
    vmadm   $v29, $v15, $v11            // calculate the mid partial product of the accumulator squared (mid * low)
    vmadn   $v16, $v11, $v15            // calculate the mid partial product of the accumulator squared (low * mid)
    beqz    $11, @@skip_incr            // skip increment if $11 is 0 (first time through loop)
     vmadh  $v17, $v15, $v15            // calculate the high partial product of the accumulator squared (mid * mid)
    addi    xfrmLtPtr, xfrmLtPtr, lightSize // increment light pointer
@@skip_incr:
    vaddc   $v18, $v16, $v16[1]         // X**2 + Y**2 frac
    li      $11, 1                      // set flag to increment next time through loop
    vadd    $v29, $v17, $v17[1]         // X**2 + Y**2 int
    vaddc   $v16, $v18, $v16[2]         // + Z**2 frac
    vadd    $v17, $v29, $v17[2]         // + Z**2 int
    vrsqh   $v29[0], $v17[0]            // In upper rsq v17 (output discarded)
    lpv     $v7[0], (ltBufOfs + lightSize + 0x8)(xfrmLtPtr) // Load direction of next light
    vrsql   $v16[0], $v16[0]            // Lower rsq v16, do rsq, out lower to v16
    vrsqh   $v17[0], vZero[0]           // Out upper v17 (input zero)
    vmudl   $v29, $v11, $v16[0]         // Multiply vector by rsq to normalize
    vmadm   $v29, $v15, $v16[0]
    vmadn   $v11, $v11, $v17[0]
    vmadh   $v15, $v15, $v17[0]
    vmudn   $v11, $v11, $v30[i1]        // 0x0100; scale results to become bytes
    j       @@loop
     vmadh  $v15, $v15, $v30[i1]        // 0x0100; scale results to become bytes

light_vtx:
    vadd    vPairNY, vZero, vPairRGBATemp[1h] // Move vertex normals Y to separate reg
.if CFG_POINT_LIGHTING
    luv     ltColor[0], (ltBufOfs + lightSize + 0)(curLight) // Init to ambient light color
.else
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load next below transformed light direction as XYZ_XYZ_ for lights_dircoloraccum2
.endif
    vadd    vPairNZ, vZero, vPairRGBATemp[2h] // Move vertex normals Z to separate reg
    luv     vPairRGBA[0], 8(inputVtxPos)      // Load both verts' XYZAXYZA as unsigned
    vne     $v4, $v31, $v31[3h]               // Set VCC to 11101110
.if !CFG_POINT_LIGHTING
    luv     ltColor[0], (ltBufOfs + lightSize + 0)(curLight) // Init to ambient light color
.endif
// TODO mods go in here
.if CFG_POINT_LIGHTING
    andi    $11, $5, G_LIGHTING_POSITIONAL_H  // check if point lighting is enabled in the geometry mode
    beqz    $11, directional_lighting         // If not enabled, use directional algorithm for everything
     li     curMatrix, mvpMatrix + 0x8000     // Set flag in negative to indicate cur mtx is MVP
.if !MOD_GENERAL
    vaddc   vPairAlpha37, vPairRGBA, vZero[0] // Copy vertex alpha
    suv     ltColor[0], 8(inputVtxPos)        // Store ambient light color to two verts' RGBARGBA
.endif
    ori     $11, $zero, 0x0004
    vmov    $v30[7], $v30[6]                  // v30[7] = 0x0010 because v30[0:2,4:6] will get clobbered
    mtc2    $11, $v31[6]                      // v31[3] = 0x0004 (was previously 0x7F00)
next_light_dirorpoint:
    lbu     $11, (ltBufOfs + 0x3)(curLight)   // Load light type / constant attenuation value at light structure + 3
    bnez    $11, light_point                  // If not zero, this is a point light
     lpv    $v2[0], (ltBufOfs + 0x10)(curLight) // Load light transformed direction
.if !MOD_GENERAL
    luv     ltColor[0], 8(inputVtxPos)        // Load current light color of two verts RGBARGBA
.endif
    vmulu   $v20, vPairNX, $v2[0h]            // Vertex normals X * light transformed dir X
    vmacu   $v20, vPairNY, $v2[1h]            // + Vtx Y * light Y
    vmacu   $v20, vPairNZ, $v2[2h]            // + Vtx Z * light Z; only elements 0, 4 matter
    luv     $v2[0], (ltBufOfs + 0)(curLight)  // Load light RGB
.if !MOD_GENERAL
    vmrg    ltColor, ltColor, vPairAlpha37    // Select original alpha
.endif
    vand    $v20, $v20, $v31[7]               // 0x7FFF; vmulu/vmacu produces 0xFFFF when 0x8000*0x8000, change this to 0x7FFF
.if !MOD_GENERAL
    vmrg    $v2, $v2, vZero[0]                // Set elements 3 and 7 of light RGB to 0
.endif
    vmulf   ltColor, ltColor, $v31[7]         // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v2, $v20[0h]            // + light color * dot product
.if !MOD_GENERAL
    suv     ltColor[0], 8(inputVtxPos)        // Store new light color of two verts RGBARGBA
.endif
    bne     curLight, spFxBaseReg, next_light_dirorpoint // If at start of lights, done
     addi   curLight, curLight, -lightSize
after_dirorpoint_loop:
    lqv     $v31[0], (v31Value)($zero)        // Fix clobbered v31
    lqv     $v30[0], (v30Value)($zero)        // Fix clobbered v30
.if !MOD_GENERAL
    llv     vPairST[4], (inputVtxSize + 0x8)(inputVtxPos) // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
.endif
    bgezal  curMatrix, lights_loadmtxdouble   // Branch if current matrix is MV matrix
     li     curMatrix, mvpMatrix + 0x8000     // Load MVP matrix and set flag for is MVP
.if !MOD_GENERAL
    andi    $11, $5, G_TEXTURE_GEN_H
    vmrg    $v3, vZero, $v31[5]               // INSTR 3: Setup for texgen: 0x4000 in elems 3, 7
    beqz    $11, vertices_store               // Done if no texgen
     vge    $v27, $v25, $v31[3]               // INSTR 1: Clamp W/fog to >= 0x7F00 (low byte is used)
.endif
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight) // Load lookat 1 transformed dir for texgen (curLight was decremented)
.if MOD_GENERAL
    j       lights_effects
.endif
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load lookat 0 transformed dir for texgen
.if !MOD_GENERAL
    j       lights_texgenmain
     vmulf  $v21, vPairNX, $v2[0h]            // First instruction of texgen, vertex normal X * last transformed dir
.endif

lights_loadmtxdouble: // curMatrix is either positive mvMatrix or negative mvpMatrix
    /* Load MVP matrix as follows--note that translation is in the bottom row,
    not the right column.
        Elem   0   1   2   3   4   5   6   7      (Example data)
    I r0i v8  00  02  04  06  00  02  04  06      Xscl Rot  Rot   0
    I r1i v9  08  0A  0C  0E  08  0A  0C  0E      Rot  Yscl Rot   0
    I r2i v10 10  12  14  16  10  12  14  16      Rot  Rot  Zscl  0
    I r3i v11 18  1A  1C  1E  18  1A  1C  1E      Xpos Ypos Zpos  1
    F r0f v12 20  22  24  26  20  22  24  26
    F r1f v13 28  2A  2C  2E  28  2A  2C  2E
    F r2f v14 30  32  34  36  30  32  34  36
    F r3f v15 38  3A  3C  3E  38  3A  3C  3E
    Vector regs contain rows of original matrix (v11/v15 have translations)
    */
    lqv     mxr0i[0], 0x0000(curMatrix) // rows 0 and 1, int
    lqv     mxr2i[0], 0x0010(curMatrix) // rows 2 and 3, int
    lqv     mxr0f[0], 0x0020(curMatrix) // rows 0 and 1, frac
    lqv     mxr2f[0], 0x0030(curMatrix) // rows 2 and 3, frac
    vcopy   mxr1i, mxr0i
    ldv     mxr1i[0], 0x0008(curMatrix) // row 1 int twice
    vcopy   mxr3i, mxr2i
    ldv     mxr3i[0], 0x0018(curMatrix) // row 3 int twice
    vcopy   mxr1f, mxr0f
    ldv     mxr1f[0], 0x0028(curMatrix) // row 1 frac twice
    vcopy   mxr3f, mxr2f
    ldv     mxr3f[0], 0x0038(curMatrix) // row 3 frac twice
    ldv     mxr0i[8], 0x0000(curMatrix) // row 0 int twice
    ldv     mxr2i[8], 0x0010(curMatrix) // row 2 int twice
    ldv     mxr0f[8], 0x0020(curMatrix) // row 0 frac twice
    jr      $ra
     ldv    mxr2f[8], 0x0030(curMatrix) // row 2 frac twice

lights_loadmvtranspose3x3double:
    /* Load 3x3 portion of MV matrix in transposed orientation
    Vector regs now contain columns of original matrix; elems 3,7 not modified
    Importantly, v28 elements 3 and 7 contain vertices 1 and 2 alpha.
    This also clobbers v31 and v30 (except elements 3 and 7), which have to be
    restored after lighting.
            E 0   1   2   3   4   5   6   7
    I c0i  v4 00  08  10  -   00  08  10  - 
    I c1i v21 02  0A  12  -   02  0A  12  - 
    I c2i v30 04  0C  14 CNST 04  0C  14 CNST
    I XXX XXX -   -   -   -   -   -   -   - 
    F c0f  v3 20  28  30  -   20  28  30  - 
    F c1f v28 22  2A  32 V1A  22  2A  32 V2A
    F c2f v31 24  2C  34 CNST 24  2C  34 CNST
    F XXX XXX -   -   -   -   -   -   -   - 
    */
    lsv     mvTc0i[0], (mvMatrix)($zero)
    lsv     mvTc0f[0], (mvMatrix + 0x20)($zero)
    lsv     mvTc1i[0], (mvMatrix + 2)($zero)
    lsv     mvTc1f[0], (mvMatrix + 0x22)($zero)
    lsv     mvTc2i[0], (mvMatrix + 4)($zero)
    vmov    mvTc0i[4], mvTc0i[0]
    lsv     mvTc2f[0], (mvMatrix + 0x24)($zero)
    vmov    mvTc0f[4], mvTc0f[0]
    lsv     mvTc0i[2], (mvMatrix + 8)($zero)
    vmov    mvTc1i[4], mvTc1i[0]
    lsv     mvTc0f[2], (mvMatrix + 0x28)($zero)
    vmov    mvTc1f[4], mvTc1f[0]
    lsv     mvTc1i[2], (mvMatrix + 0xA)($zero)
    vmov    mvTc2i[4], mvTc2i[0]
    lsv     mvTc1f[2], (mvMatrix + 0x2A)($zero)
    vmov    mvTc2f[4], mvTc2f[0]
    lsv     mvTc2i[2], (mvMatrix + 0xC)($zero)
    vmov    mvTc0i[5], mvTc0i[1]
    lsv     mvTc2f[2], (mvMatrix + 0x2C)($zero)
    vmov    mvTc0f[5], mvTc0f[1]
    lsv     mvTc0i[4], (mvMatrix + 0x10)($zero)
    vmov    mvTc1i[5], mvTc1i[1]
    lsv     mvTc0f[4], (mvMatrix + 0x30)($zero)
    vmov    mvTc1f[5], mvTc1f[1]
    lsv     mvTc1i[4], (mvMatrix + 0x12)($zero)
    vmov    mvTc2i[5], mvTc2i[1]
    lsv     mvTc1f[4], (mvMatrix + 0x32)($zero)
    vmov    mvTc2f[5], mvTc2f[1]
    lsv     mvTc2i[4], (mvMatrix + 0x14)($zero)
    vmov    mvTc0i[6], mvTc0i[2]
    lsv     mvTc2f[4], (mvMatrix + 0x34)($zero)
    vmov    mvTc0f[6], mvTc0f[2]
    or      curMatrix, $zero, $zero // Set curMatrix = positive mvMatrix
    vmov    mvTc1i[6], mvTc1i[2]
    vmov    mvTc1f[6], mvTc1f[2]
    vmov    mvTc2i[6], mvTc2i[2]
    j       lights_loadmtxdouble
     vmov   mvTc2f[6], mvTc2f[2]

light_point:
    ldv     $v20[8], 0x0000(inputVtxPos) // Load v0 pos to upper 4 elements of v20
    bltzal  curMatrix, lights_loadmvtranspose3x3double // branch if curMatrix is MVP; need MV and MV^T
     ldv    $v20[0], 0x0010(inputVtxPos) // Load v1 pos to lower 4 elements of v20
    // Transform input vertices by MV; puts them in camera space
    vmudn   $v2, mxr3f, vOne[0]          // 1 * translation row
    ldv     $v29[0], (ltBufOfs + 0x8)(curLight) // Load light pos (shorts, same mem as non-transformed light dir) into lower 4 elements
    vmadh   $v2, mxr3i, vOne[0]          // 1 * translation row
    vmadn   $v2, mxr0f, $v20[0h]
    vmadh   $v2, mxr0i, $v20[0h]
    vmadn   $v2, mxr1f, $v20[1h]
    ldv     $v29[8], (ltBufOfs + 0x8)(curLight) // Load same light pos into upper 4
    vmadh   $v2, mxr1i, $v20[1h]
    vmadn   $v2, mxr2f, $v20[2h]
    vmadh   $v2, mxr2i, $v20[2h]
    vsub    $v20, $v29, $v2              // v20 = light pos - camera space verts pos
    vmrg    $v29, $v20, vZero[0]         // Set elems 3 and 7 to 0
    vmudh   $v2, $v29, $v29              // Squared
    vreadacc $v2, ACC_UPPER              // v2 = accumulator upper
    vreadacc $v29, ACC_MIDDLE            // v29 = accumulator middle
    vaddc   $v29, $v29, $v29[0q]         // Add X to Y, Z to alpha(0) (middle)
    vadd    $v2, $v2, $v2[0q]            // Add X to Y, Z to alpha(0) (upper)
    vaddc   $v29, $v29, $v29[2h]         // Add Z+alpha(0) to all (middle)
    vadd    $v2, $v2, $v2[2h]            // Add Z+alpha(0) to all (upper)
    vrsqh   $v29[3], $v2[1]              // Input upper sum vtx 1
    vrsql   $v29[3], $v29[1]             // Rsqrt lower
    vrsqh   $v29[2], $v2[5]              // Get upper result, input upper sum vtx 0
    vrsql   $v29[7], $v29[5]
    vrsqh   $v29[6], vZero[0]            // Results in v29[2:3, 6:7]
    // Transform vert-to-light vector by MV transpose. See note about why this is
    // not correct if non-uniform scale has been applied.
    vmudn   $v2, mvTc0f, $v20[0h]
    sll     $11, $11, 4                  // Holds light type / constant attenuation value (0x3)
    vmadh   $v2, mvTc0i, $v20[0h]
    lbu     $24, (ltBufOfs + 0xE)(curLight) // Quadratic attenuation factor byte from point light props
    vmadn   $v2, mvTc1f, $v20[1h]
.if MOD_GENERAL
    mtc2    $11, vPairST[0]              // vPairST elems 2, 3, 6, 7 in use, but using here 0, 1, 4, 5
.else
    mtc2    $11, $v27[0]                 // 0x3 << 4 -> v27 elems 0, 1
.endif
    vmadh   $v2, mvTc1i, $v20[1h]
    vmadn   $v2, mvTc2f, $v20[2h]
    vmadh   $v20, mvTc2i, $v20[2h]       // v20 = int result of vert-to-light in model space
    vmudm   $v2, $v20, $v29[3h]          // v2l_model * length normalization frac
    vmadh   $v20, $v20, $v29[2h]         // v2l_model * length normalization int
    vmudn   $v2, $v2, $v31[3]            // this is 0x0004; v31 is mvTc2f but elem 3 replaced, elem 7 left
    vmadh   $v20, $v20, $v31[3]          // 
    vmulu   $v2, vPairNX, $v20[0h]       // Normal X * normalized vert-to-light X
.if MOD_GENERAL
    mtc2    $11, vPairST[0]              // vPairST elems 2, 3, 6, 7 in use, but using here 0, 1, 4, 5
.else
    mtc2    $11, $v27[8]                 // 0x3 << 4 -> v27 elems 4, 5
.endif
    vmacu   $v2, vPairNY, $v20[1h]       // Y * Y
    lbu     $11, (ltBufOfs + 0x7)(curLight) // Linear attenuation factor byte from point light props
    vmacu   $v2, vPairNZ, $v20[2h]       // Z * Z
    sll     $24, $24, 5
    vand    $v20, $v2, $v31[7]           // 0x7FFF; vmulu/vmacu produces 0xFFFF when 0x8000*0x8000, change this to 0x7FFF
    mtc2    $24, $v20[14]                // 0xE << 5 -> v20 elem 7
    vrcph   $v29[0], $v29[2]             // rcp(rsqrt()) = sqrt = length of vert-to-light
    vrcpl   $v29[0], $v29[3]             // For vertex 1 in v29[0]
    vrcph   $v29[4], $v29[6]             // 
    vrcpl   $v29[4], $v29[7]             // For vertex 0 in v29[4]
    vmudh   $v2, $v29, $v30[7]           // scale by 0x0010 (value changed in light_vtx) (why?)
    mtc2    $11, $v20[6]                 // 0x7 -> v20 elem 3
    vmudl   $v2, $v2, $v2[0h]            // squared
    vmulf   $v29, $v29, $v20[3]          // Length * byte 0x7
    vmadm   $v29, $v2, $v20[7]           // + (scaled length squared) * byte 0xE << 5
.if MOD_GENERAL
    vmadh   $v29, vPairST, $v30[3]       // + (byte 0x3 << 4) * 0x0100
.else
    vmadn   $v29, $v27, $v30[3]          // + (byte 0x3 << 4) * 0x0100
.endif
    vreadacc $v2, ACC_MIDDLE
    vrcph   $v2[0], $v2[0]               // v2 int, v29 frac: function of distance to light
    vrcpl   $v2[0], $v29[0]              // Reciprocal = inversely proportional
    vrcph   $v2[4], $v2[4]
    vrcpl   $v2[4], $v29[4]
.if !MOD_GENERAL
    luv     ltColor[0], 0x0008(inputVtxPos) // Get current RGBARGBA for two verts
.endif
    vand    $v2, $v2, $v31[7]            // 0x7FFF; vrcp produces 0xFFFF when 1/0, change this to 0x7FFF
    vmulf   $v2, $v2, $v20               // Inverse dist factor * dot product (elems 0, 4)
    luv     $v20[0], (ltBufOfs + 0)(curLight) // Light color RGB_RGB_
.if !MOD_GENERAL
    vmrg    ltColor, ltColor, vPairAlpha37 // Select orig alpha; vPairAlpha37 = v28 = mvTc1f, but alphas were not overwritten
.endif
    vand    $v2, $v2, $v31[7]            // 0x7FFF; not sure what this is for, both inputs to the multiply are always positive
.if !MOD_GENERAL
    vmrg    $v20, $v20, vZero[0]         // Zero elements 3 and 7 of light color
.endif
    vmulf   ltColor, ltColor, $v31[7]    // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v20, $v2[0h]       // + light color * light amount
.if !MOD_GENERAL
    suv     ltColor[0], 0x0008(inputVtxPos) // Store new RGBARGBA for two verts
.endif
    bne     curLight, spFxBaseReg, next_light_dirorpoint
     addi   curLight, curLight, -lightSize
    j       after_dirorpoint_loop
directional_lighting:
     lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load next light transformed dir; this value is overwritten with the same thing
.endif

// Loop for dot product normals and multiply-add color for 2 lights
// curLight starts pointing to the top light, and v2 and v20 already have the dirs
lights_dircoloraccum2:
    vmulu   $v21, vPairNX, $v2[0h]       // vtx normals all (X) * light transformed dir 2n+1 X
    luv     $v4[0], (ltBufOfs + 0)(curLight) // color light 2n+1
    vmacu   $v21, vPairNY, $v2[1h]       // + vtx n Y only * light dir 2n+1 Y
    beq     curLight, spFxBaseReg, lights_finishone // Finish pipeline for odd number of lights
     vmacu  $v21, vPairNZ, $v2[2h]       // + vtx n Z only * light dir 2n+1 Z
    vmulu   $v28, vPairNX, $v20[0h]      // vtx normals all (X) * light transformed dir 2n X
    luv     $v3[0], (ltBufOfs - lightSize + 0)(curLight) // color light 2n
    vmacu   $v28, vPairNY, $v20[1h]      // + vtx n Y only * light dir 2n Y
    addi    $11, curLight, -lightSize    // Subtract 1 light for comparison at bottom of loop
    vmacu   $v28, vPairNZ, $v20[2h]      // + vtx n Y only * light dir 2n Y
    addi    curLight, curLight, -(2 * lightSize)
.if !MOD_GENERAL
    vmrg    ltColor, ltColor, vPairRGBA  // select orig alpha
    mtc2    $zero, $v4[6]                // light 2n+1 color comp 3 = 0 (to not interfere with alpha)
    vmrg    $v3, $v3, vZero[0]           // light 2n color components 3,7 = 0
    mtc2    $zero, $v4[14]               // light 2n+1 color comp 7 = 0 (to not interfere with alpha)
.endif
    vand    $v21, $v21, $v31[7]          // 0x7FFF; vmulu/vmacu produces 0xFFFF when 0x8000*0x8000, change this to 0x7FFF
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight) // Normal for light or lookat next slot down, 2n+1
    vand    $v28, $v28, $v31[7]          // 0x7FFF; vmulu/vmacu produces 0xFFFF when 0x8000*0x8000, change this to 0x7FFF
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Normal two slots down, 2n
    vmulf   ltColor, ltColor, $v31[7]    // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v4, $v21[0h]       // + color 2n+1 * dot product
    bne     $11, spFxBaseReg, lights_dircoloraccum2 // Pointer 1 behind, minus 1 light, if at base then done
     vmacf  ltColor, $v3, $v28[0h]       // + color 2n * dot product
// End of loop for even number of lights

.if MOD_GENERAL
lights_effects:
// What should be set by the time we arrive here:
// ltColor, vPairRGBA, v20 = lookat 0, v2 = lookat 1, VCC = 11101110
// INSTR 1, INSTR 2, INSTR 3 not done, ltColor not stored
.endif
    vmrg    $v3, vZero, $v31[5]          // INSTR 3: Setup for texgen: 0x4000 in elems 3, 7
.if MOD_GENERAL
lights_effects_noinstr3:
.endif
// TODO mods go here
    llv     vPairST[4], (inputVtxSize + 8)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
// and more mods here

lights_texgenpre:
// Texgen beginning
    vge     $v27, $v25, $v31[3]         // INSTR 1: Clamp W/fog to >= 0x7F00 (low byte is used)
    andi    $11, $5, G_TEXTURE_GEN_H
    vmulf   $v21, vPairNX, $v2[0h]      // Vertex normal X * lookat 1 dir X
    beqz    $11, vertices_store
     suv    ltColor[0], 0x0008(inputVtxPos) // write back color/alpha for two verts
lights_texgenmain:
// Texgen main
    vmacf   $v21, vPairNY, $v2[1h]      // VN Y * lookat 1 dir Y
    andi    $12, $5, G_TEXTURE_GEN_LINEAR_H
    vmacf   $v21, vPairNZ, $v2[2h]      // VN Z * lookat 1 dir Z
    vxor    $v4, $v3, $v31[5]           // v4 has 0x4000 in opposite pattern as v3, normally 11101110
    vmulf   $v28, vPairNX, $v20[0h]     // VN XYZ * lookat 0 dir XYZ
    vmacf   $v28, vPairNY, $v20[1h]     // Y
    vmacf   $v28, vPairNZ, $v20[2h]     // Z
    lqv     $v2[0], (linearGenerateCoefficients)($zero)
    vmudh   vPairST, vOne, $v31[5]      // S, T init to 0x4000 each
    vmacf   vPairST, $v3, $v21[0h]      // Add dot product with lookat 1 to T (elems 3, 7)
    beqz    $12, vertices_store
     vmacf  vPairST, $v4, $v28[0h]      // Add dot product with lookat 0 to S (elems 2, 6)
// Texgen Linear--not sure what formula this is implementing
    vmadh   vPairST, vOne, $v2[0]       // ST + Coefficient 0xC000
    vmulf   $v4, vPairST, vPairST       // ST squared
    vmulf   $v3, vPairST, $v31[7]       // Move to accumulator
    vmacf   $v3, vPairST, $v2[2]        // + ST * coefficient 0x6CB3
.if BUG_TEXGEN_LINEAR_CLOBBER_S_T
    vmudh   vPairST, vOne, $v31[5]      // Clobber S, T with 0x4000 each
.else
    vmudh   $v21, vOne, $v31[5]         // Initialize accumulator with 0x4000 each (v21 discarded)
.endif
    vmacf   vPairST, vPairST, $v2[1]    // + ST * coefficient 0x44D3
    j       vertices_store
     vmacf  vPairST, $v4, $v3           // + ST squared * (ST + ST * coeff)

lights_finishone:
.if !MOD_GENERAL
    vmrg    ltColor, ltColor, vPairRGBA // select orig alpha
    vmrg    $v4, $v4, vZero[0]          // clear alpha component of color
.endif
    vand    $v21, $v21, $v31[7]         // 0x7FFF; vmulu/vmacu produces 0xFFFF when 0x8000*0x8000, change this to 0x7FFF
.if !MOD_GENERAL
    veq     $v3, $v31, $v31[3h]         // set VCC to 00010001, opposite of 2 light case
.endif
    lpv     $v2[0], (ltBufOfs - 2 * lightSize + 0x10)(curLight) // Load second dir down, lookat 0, for texgen
    vmrg    $v3, vZero, $v31[5]         // INSTR 3 OPPOSITE: Setup for texgen: 0x4000 in 0,1,2,4,5,6
.if !MOD_GENERAL
    llv     vPairST[4], (inputVtxSize + 8)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
.endif
    vmulf   ltColor, ltColor, $v31[7]   // Move cur color to accumulator
.if MOD_GENERAL
    vxor    $v3, $v3, $v31[5]           // Invert V3 (so that VCC is not changed)
    j       lights_effects_noinstr3
.else
    j       lights_texgenpre
.endif
     vmacf  ltColor, $v4, $v21[0h]      // + light color * dot product

.endif // MOD_VL_REWRITE

.align 8
ovl2_end:

.close // CODE_FILE
