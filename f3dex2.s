.rsp

.include "rsp/rsp_defs.inc"
.include "rsp/gbi.inc"

// This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

.macro li, reg, imm
    addi    reg, $zero, imm
.endmacro

.macro move, dst, src
    ori     dst, src, 0
.endmacro

// Prohibit macros involving slt; this silently clobbers $1. You can of course
// manually write the slt and branch instructions if you want this behavior.
.macro blt, ra, rb, lbl
    .error "blt is a macro using slt, and silently clobbers $1!"
.endmacro

.macro bgt, ra, rb, lbl
    .error "bgt is a macro using slt, and silently clobbers $1!"
.endmacro

.macro ble, ra, rb, lbl
    .error "ble is a macro using slt, and silently clobbers $1!"
.endmacro

.macro bge, ra, rb, lbl
    .error "bge is a macro using slt, and silently clobbers $1!"
.endmacro

// This version doesn't depend on $v0 to be vZero, which it often is not in
// F3DEX3, and also doesn't get corrupted if $vco is set / consume $vco which
// may be needed for a subsequent instruction.
.macro vcopy, dst, src
    vor     dst, src, src
.endmacro

.macro vclr, dst
    vxor    dst, dst, dst
.endmacro

ACC_UPPER equ 0
ACC_MIDDLE equ 1
ACC_LOWER equ 2
.macro vreadacc, dst, N
    vsar    dst, dst, dst[N]
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

Overlay 2           Overlay 3       Overlay 4
(Lighting)          (Clipping)      (mIT, rare cmds)

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
Overlay 4
*/

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
// 0x0000-0x0040: model matrix
mMatrix:
    .fill 64

// 0x0040-0x0080: view * projection matrix
vpMatrix:
    .fill 64

// model inverse transpose matrix; first three rows only
mITMatrix:
    .fill 0x30
    
fogFactor:
    .dw 0x00000000

textureSettings1:
    .dw 0x00000000 // first word, has command byte, bowtie val, level, tile, and on
    
textureSettings2:
    .dw 0x00000000 // second word, has s and t scale
    
geometryModeLabel:
    .dw 0x00000000 // originally initialized to G_CLIPPING, but that does nothing
    
.if . != 0x00C0
.error "Scissor and othermode must be at 0x00C0 for S2DEX"
.endif
    
// scissor (four 12-bit values)
scissorUpLeft: // the command byte is included since the command word is copied verbatim
    .dw (G_SETSCISSOR << 24) | ((  0 * 4) << 12) | ((  0 * 4) << 0)
scissorBottomRight:
    .dw ((320 * 4) << 12) | ((240 * 4) << 0)

// othermode
otherMode0: // command byte included, same as above
    .dw (G_RDPSETOTHERMODE << 24) | (0x080CFF)
otherMode1:
    .dw 0x00000000

// Saved texrect state for combining the multiple input commands into one RDP texrect command
texrectWord1:
    .fill 4 // first word, has command byte, xh and yh
texrectWord2:
    .fill 4 // second word, has tile, xl, yl

// First half of RDP value for split commands (shared by perspNorm moveword to be able to write a 32-bit value)
rdpHalf1Val:
    .fill 4

// perspective norm
perspNorm:
    .dh 0xFFFF

// displaylist stack length
displayListStackLength:
    .db 0x00 // starts at 0, increments by 4 for each "return address" pushed onto the stack
    
// Is M inverse transpose valid or does it need to be recomputed. Zeroed when modifying M.
mITValid:
    .db 0

// viewport
viewport:
    .fill 16

// Current RDP fifo output position
rdpFifoPos:
    .fill 4

matrixStackPtr:
    .dw 0x00000000

// segment table
segmentTable:
    .fill (4 * 16) // 16 DRAM pointers

// displaylist stack
displayListStack:

// ucode text (shared with DL stack)
    .ascii ID_STR, 0x0A

.align 16
.if . - displayListStack != 0x48
    .warning "ID_STR incorrect length, affects displayListStack"
.endif

endSharedDMEM:
.if . != 0x180
    .error "endSharedDMEM at incorrect address, matters for G_LOAD_UCODE / S2DEX"
.endif

// constants for register $v31
.if (. & 15) != 0
    .error "Wrong alignment for v31value"
.endif
v31Value:
// v31 must go from lowest to highest (signed) values for vcc patterns.
    .dh -4     // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh -1     // used often
    .dh 1      // used to load accumulator when vOne or vLtOne not available
    .dh 2      // used as clip ratio (vtx write, clipping) and in clipping
    .dh 4      // used to initialize 4s in vSTScl in vtx setup
    .dh 0x4000 // used in tri write, texgen
    .dh 0x7F00 // used in fog, normals unpacking
    .dh 0x7FFF // used often

// constants for register $v30; only used in tri write and vtx_indices_to_addr
.if (. & 15) != 0
    .error "Wrong alignment for v30value"
.endif
// Only one VCC pattern used:
// vge xxx, $v30, $v30[7] = 11110001 in tri write
v30Value:
    .dh vertexBuffer // this and next used in vtx_indices_to_addr
    .dh vtxSize << 7 // 0x1300; it's not 0x2600 because vertex indices are *2
    .dh 0x1000 // used once in tri write, some multiplier
    .dh 0x0100 // used several times in tri write
    .dh -16    // used in tri write for Newton-Raphson reciprocal 
    .dh 0xFFF8 // used once in tri write, mask away lower ST bits
    .dh 0x0010 // used once in tri write for Newton-Raphson reciprocal
    .dh 0x0020 // used in tri write, both signed and unsigned multipliers

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

cameraWorldPos:
    .skip 6
tempHalfword2:
    .skip 2 // Overwritten as part of camera world position, but can be used as temp
lightBufferLookat:
    .skip 8 // s8 X0, Y0, Z0, dummy, X1, Y1, Z1, dummy
lightBufferMain:
    .skip (G_MAX_LIGHTS * lightSize)
lightBufferAmbient:
    .skip 8 // just colors for ambient light
ltBufOfs equ (lightBufferMain - altBase)

// Alternate base address because vector load offsets can't reach all of DMEM.
// altBaseReg permanently points here.
altBase:

texgenLinearCoeffs:
    .dh 0x44D3
    .dh 0x6CB3
    
// For SPFlagsVerts / SPCullFlags* / etc.
cullFlags:
    .dw 0x00000000

fxParams:

aoAmbientFactor:
    .dh 0xFFFF
aoDirectionalFactor:
    .dh 0xA000
    
/*
fresnelOffset = Dot product value, in 0000 - 7FFF, which gives shade alpha = 0
Let k = dot product value, in 0000 - 7FFF, which gives shade alpha = FF.
Then fresnelScale = 0.7FFF / (k - fresnelOffset) as s7.8 fixed point.
Alternatively, shade alpha [0000 - 7FFF] =
fresnelScale [-80.00 - 7F.FF] * (dot product [0000 - 7FFF] - fresnelOffset)
Examples:
1. Grazing -> 00; normal -> FF
   Then set fresnelOffset = 0000, fresnelScale = 01.00
2. Grazing -> FF; normal -> 00
   Then set fresnelOffset = 7FFF, fresnelScale = FF.00 (-01.00)
3. 30 degrees (0.5f or 4000) -> FF; 60 degrees (0.86f or 6ED9) -> 00
   Then set fresnelOffset = 6ED9, fresnelScale = FD.45 (-02.BB = 1 / (0.5f - 0.86f))
*/
fresnelOffset:
    .dh 0x0000 // See above
fresnelScale:
    .dh 0x0000 // See above

.if (. & 7) != 0
    .error "Wrong alignment before attrOffsetST"
.endif
attrOffsetST:
    .dh 0x0100
    .dh 0xFF00

attrOffsetZ:
    .dh 0xFFFE
tempHalfword1:
    .dh 0x0000 // Overwritten by movewords to above and below, can be used as temp

    .db 0
normalsMode:
    .db 0     // Overwrites above

alphaCompareCullMode:
    .db 0x00 // 0 = disabled, 1 = cull if all < thresh, -1 = cull if all >= thresh
alphaCompareCullThresh:
    .db 0x00 // Alpha threshold, 00 - FF
tempHalfword3:
    .dh 0x0000 // Overwritten by movewords to above and below, can be used as temp

    .db 0
numLightsxSize:
    .db 0   // Overwrites above
    
// Constants for clipping algorithm
clipCondShifts:
    .db CLIP_SHIFT_NY
    .db CLIP_SHIFT_PY
    .db CLIP_SHIFT_NX
    .db CLIP_SHIFT_PX

// "Forward declaration" of temporary matrix in clipTempVerts scratch space, aligned to 16 bytes
tempMemRounded equ ((clipTempVerts + 15) & ~15)

// Movemem table
movememTable:
    .dh tempMemRounded    // G_MTX multiply temp matrix (model)
    .dh mMatrix           // G_MV_MMTX
    .dh tempMemRounded    // G_MTX multiply temp matrix (projection)
    .dh vpMatrix          // G_MV_PMTX
    .dh viewport          // G_MV_VIEWPORT
    .dh cameraWorldPos    // G_MV_LIGHT

// moveword table
movewordTable:
    .dh fxParams           // G_MW_FX
    .dh numLightsxSize - 3 // G_MW_NUMLIGHT
    .dh perspNorm - 2      // G_MW_PERSPNORM
    .dh segmentTable       // G_MW_SEGMENT
    .dh fogFactor          // G_MW_FOG
    .dh lightBufferMain    // G_MW_LIGHTCOL

// G_POPMTX, G_MTX, G_MOVEMEM Command Jump Table
movememHandlerTable:
jumpTableEntry G_POPMTX_end            // G_POPMTX
jumpTableEntry ovl234_ovl4_entrypoint  // G_MTX (multiply)
jumpTableEntry G_MOVEMEM_end           // G_MOVEMEM, G_MTX (load)

// RDP/Immediate Command Jump Table
jumpTableEntry ovl234_ovl4_entrypoint // G_DMA_IO
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
cmdJumpTableForwardBack:
jumpTableEntry G_SETSCISSOR_handler
jumpTableEntry G_RDP_handler     // G_SETPRIMDEPTH
jumpTableEntry G_RDPSETOTHERMODE_handler
jumpTableEntry G_RDP_handler     // G_LOADTLUT
jumpTableEntry G_RDPHALF_2_handler
cmdJumpTablePositive:
jumpTableEntry G_VTX_handler
jumpTableEntry ovl234_ovl4_entrypoint // G_MODIFYVTX
jumpTableEntry G_CULLDL_handler
jumpTableEntry ovl234_ovl4_entrypoint // G_BRANCH_WZ
jumpTableEntry G_TRI1_handler
jumpTableEntry G_TRI2_handler
jumpTableEntry G_QUAD_handler
jumpTableEntry G_TRISTRIP_handler
jumpTableEntry G_TRIFAN_handler
jumpTableEntry G_FLAGSMASKS_handler
jumpTableEntry G_FLAGSVERTS_handler
jumpTableEntry G_FLAGS1VERT_handler
jumpTableEntry ovl234_ovl4_entrypoint // G_FLAGSDRAM
jumpTableEntry ovl234_ovl4_entrypoint // G_LIGHTTORDP

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

// The maximum number of generated vertices in a clip polygon. In reality, this
// is equal to MAX_CLIP_POLY_VERTS, but for testing we can change them separately.
// In case you're wondering if it's possible to have a 7-vertex polygon where all
// 7 verts are generated, it looks like this (X = generated vertex):
//                         ___----=>
//    +---------------__X----X _-^
//    |         __--^^       X^
//    |   __--^^          _-^|
//   _X^^^             _-^   |
//  C |             _-^      |
//   ^X          _-^         |
//    |\      _-^            |
//    +-X--_X^---------------+
//       V^
MAX_CLIP_GEN_VERTS equ 7
// Normally, each clip plane can cut off a "tip" of a polygon, turning one vert
// into two. (It can also cut off more of the polygon and remove additional verts,
// but the maximum is one more vert per clip plane.) So with 5 clip planes, we
// could have a maximum of 8 verts in the final polygon. However, the verts
// generated by the no-nearclipping plane will always be at infinity, so they
// will always get replaced by generated verts from one of the other clip planes.
// Put another way, if there are 8 verts in the final polygon, there are 8 edges,
// which are portions of the 3 original edges plus portions of 5 edges along the
// 5 clip planes. But the edge portion along the no-nearclipping plane is at
// infinity, so that edge can't be on screen.
MAX_CLIP_POLY_VERTS equ 7
clipPoly:
    .skip (MAX_CLIP_POLY_VERTS+1) * 2   // 3   5   7 + term 0
clipPoly2:                              //  \ / \ / \
    .skip (MAX_CLIP_POLY_VERTS+1) * 2   //   4   6   7 + term 0

// Vertex buffer in RSP internal format
vertexBuffer:
    .skip (G_MAX_VERTS * vtxSize)

.if . > OS_YIELD_DATA_SIZE - 8
    // OS_YIELD_DATA_SIZE (0xC00) bytes of DMEM are saved; the last two words are
    // the ucode and the DL pointer. Make sure anything past there is temporary.
    // (Input buffer will be reloaded from next instruction in the source DL.)
    .error "Important things in DMEM will not be saved at yield!"
.endif

// Space for temporary verts for clipping code
// tempMemRounded defined above = this rounded up to 16 bytes, for temp mtx etc.
clipTempVerts:
    .skip MAX_CLIP_GEN_VERTS * vtxSize
clipTempVertsEnd:

.if (. - tempMemRounded) < 0x40
    .error "Not enough space for temp matrix!"
.endif

RDP_CMD_BUFSIZE equ 0xB0
RDP_CMD_BUFSIZE_EXCESS equ 0xB0 // Maximum size of an RDP triangle command
RDP_CMD_BUFSIZE_TOTAL equ (RDP_CMD_BUFSIZE + RDP_CMD_BUFSIZE_EXCESS)
INPUT_BUFFER_CMDS equ 21
INPUT_BUFFER_LEN equ (INPUT_BUFFER_CMDS * 8)
END_VARIABLE_LEN_DMEM equ (0xFC0 - INPUT_BUFFER_LEN - (2 * RDP_CMD_BUFSIZE_TOTAL))

endVariableDmemUse:

.if . > END_VARIABLE_LEN_DMEM
    .error "Out of DMEM space"
.endif

.org END_VARIABLE_LEN_DMEM

// First RDP Command Buffer
rdpCmdBuffer1:
    .skip RDP_CMD_BUFSIZE
rdpCmdBuffer1End:
    .skip RDP_CMD_BUFSIZE_EXCESS
// Second RDP Command Buffer
rdpCmdBuffer2:
    .skip RDP_CMD_BUFSIZE
rdpCmdBuffer2End:
    .skip RDP_CMD_BUFSIZE_EXCESS

// Input buffer. After RDP cmd buffers so it can be vector addressed from end.
inputBuffer:
    .skip INPUT_BUFFER_LEN
inputBufferEnd:

.if . != 0xFC0
    .error "DMEM organization incorrect"
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

// $v31: Only global constant vector register

// Vertex / lighting all regs:
vM0I   equ $v0  // mMatrix rows int/frac
vM1I   equ $v1  // Valid in vertex, lighting, and M inverse transpose
vM2I   equ $v2
vM3I   equ $v3
vM0F   equ $v4
vM1F   equ $v5
vM2F   equ $v6
vM3F   equ $v7
vVP0I  equ $v8  // vpMatrix rows int/frac
vVP1I  equ $v9  // Valid in vertex and lighting only
vVP2I  equ $v10 // $v10 also used as temp in lighting, then reloaded with vVP2I
vVP3I  equ $v11
vVP0F  equ $v12
vVP1F  equ $v13
vVP2F  equ $v14
vVP3F  equ $v15
vVpScl equ $v16 // Vertex constants (viewport scale, offset, ST scale, offset)
vVpOfs equ $v17 // Also contain other constants, see comment in vtx_setup_constants
vSTScl equ $v18 // Valid in vertex, lighting, and first half of clipping
vSTOfs equ $v19
// Remaining regs sometimes valid in vertex and lighting, also used as temps
vPairPosI  equ $v20 // Vertex pair model / world space position int/frac
vPairPosF  equ $v21
vPairST    equ $v22 // Vertex pair ST texture coordinates
vPairTPosF equ $v23 // Vertex pair transformed (clip / screen) space position frac/int
vPairTPosI equ $v24
// $v25: temp
// $v26: temp
vPairRGBA  equ $v27 // Vertex pair color
vPairNrml  equ $v28 // Vertex pair normals (model then world space)
// $v29: permanent temp register, also write results here to discard
vPairLt    equ $v30 // Vertex pair total light color/intensity (RGB-RGB-)

// Some extra defines for lighting:
vPackPXY   equ $v23 // Positive X and Y in packed normals
vPackZ     equ $v24 // Z in packed normals
vLtOne     equ $v24 // 1 in each vector lane, for adding into accumulator for fast dot products
vLtRGBOut  equ $v25 // Light / effects RGB output
vLtAOut    equ $v26 // Light / effects alpha output
vLtColor   equ $v26 // Light color
vLookat1   equ $v28 // Lookat direction 1
vLookat0   equ $v30 // Lookat direction 0
// M inverse transpose matrix in regs briefly:
vLtMIT0I   equ $v26
vLtMIT1I   equ $v25
vLtMIT2I   equ $v23
vLtMIT0F   equ $v29
vLtMIT1F   equ $v30
vLtMIT2F   equ $v10


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
clipPolySelect        equ $18 // global (mods: >= 0 indicates clipping, < 0 normal tri write)
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
vtxPtr    equ $25 // = cmd_w0
endVtxPtr equ $24 // = cmd_w1_dram

// Must keep values during the full vertex process: load, lighting, and vertex write
// $1: count of remaining vertices
curLight     equ $9   // Used locally elsewhere
inputVtxPos  equ $14  // global


// Values set up by load_spfx_global_values, which must be kept during the full
// vertex process, and which are reloaded for each vert during clipping. See
// that routine for the detailed contents of each of these registers.
// secondVtxPos
altBaseReg equ $13  // global

// Arguments to dma_read_write
dmaLen   equ $19 // also used by itself
dmemAddr equ $20
// cmd_w1_dram   // used for all dma_read_write DRAM addresses, not just second word of command

// Argument to load_overlay*
postOvlRA equ $12 // Commonly used locally

// ==== Summary of uses of all registers
// $zero: Hardwired zero scalar register
// $1: vertex 1 addr, count of remaining vertices, pointer to store texture coefficients, local
// $2: vertex 2 addr, vertex at end of edge in clipping, pointer to store shade coefficients, local
// $3: vertex 3 addr, vertex at start of edge in clipping, local
// $4: pre-shuffle vertex 1 addr for flat shading (mods: got rid of, available local), local
// $5: clipMaskIdx, geometry mode high short during vertex load / lighting, local
// $6: geometry mode low byte during tri write, local
// $7: fog flag in vtx write, local
// $8: secondVtxPos, local
// $9: curLight, local
// $10: briefly used local in vtx write (mods: got rid of, not used!)
// $11: very common local
// $12: postOvlRA, local
// $13: altBaseReg
// $14: inputVtxPos
// $15: outputVtxPos
// $16: clipFlags
// $17: clipPolyRead
// $18: clipPolySelect
// $19: dmaLen, briefly used local
// $20: dmemAddr
// $21: clipPolyWrite
// $22: rdpCmdBufEnd
// $23: rdpCmdBufPtr
// $24: cmd_w1_dram, local
// $25: cmd_w0
// $26: taskDataPtr
// $27: inputBufferPos
// $28: not used!
// $29: savedActiveClipPlanes (mods, got rid of, not used!)
// $30: savedRA (unused in MOD_GENERAL)
// $ra: Return address for jal, b*al
// $v0: vZero (every element 0)
// $v1: vOne (every element 1)
// $v2: very common local
// $v3: local
// $v4: local
// $v5: local
// $v6: local
// $v7: local
// $v8: local
// $v9: local
// $v10: local
// $v11: local
// $v12: local
// $v13: local
// $v14: local
// $v15: local
// $v16: vVpScl, local
// $v17: vVpOfs, local
// $v18: vSTScl, local
// $v19: vSTOfs, local
// $v20: local
// $v21: local
// $v22: vPairST, local
// $v23: vPairTPosF, local
// $v24: vPairTPosI, local
// $v25: prev vertex data, local
// $v26: prev vertex data, local
// $v27: vPairRGBA, local
// $v28: local
// $v29: register to write to discard results, local
// $v30: constant values for tri write
// $v31: general constant values

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl0 and/or ovl1
start: // This is at IMEM 0x1080, not the start of IMEM
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    lqv     $v31[0], (v31Value)($zero)
    li      altBaseReg, altBase
    li      rdpCmdBufPtr, rdpCmdBuffer1
    li      rdpCmdBufEnd, rdpCmdBuffer1End
    lw      $11, rdpFifoPos
    lw      $12, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // task done and yielded signals
    beqz    $11, task_init
     mtc0   $1, SP_STATUS
    andi    $12, $12, OS_TASK_YIELDED
    beqz    $12, load_task_ptr    // skip init if resumed from yield?
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
    lw      $11, matrixStackPtr
    bnez    $11, load_task_ptr
     lw     $11, OSTask + OSTask_dram_stack
    sw      $11, matrixStackPtr
load_task_ptr:
    lw      taskDataPtr, OSTask + OSTask_data_ptr
load_overlay1_init:
    li      inputBufferPos, 0
    li      cmd_w1_dram, orga(ovl1_start)
    j       load_overlays_0_1
     li     postOvlRA, displaylist_dma

start_end:
.align 8
start_padded_end:

.orga max(orga(), max(ovl0_padded_end - ovl0_start, ovl1_padded_end - ovl1_start) - 0x80)
ovl01_end:

displaylist_dma_with_count:
    andi    inputBufferPos, cmd_w0, 0x00F8             // Byte 3, how many cmds to drop from load
displaylist_dma:
    // Load INPUT_BUFFER_LEN - inputBufferPos cmds (inputBufferPos >= 0, mult of 8)
    addi    inputBufferPos, inputBufferPos, -INPUT_BUFFER_LEN // inputBufferPos = - num cmds
    sub     dmaLen, $zero, inputBufferPos              // DMA length = -inputBufferPos
    addi    dmaLen, dmaLen, -1                         // DMA length is always 1 less
    move    cmd_w1_dram, taskDataPtr                   // set up the DRAM address to read from
    jal     dma_read_write                             // initiate the DMA read
     li     dmemAddr, inputBuffer                      // set the address to DMA read to
    sub     taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
wait_for_dma_and_run_next_command:
G_POPMTX_end:
G_MOVEMEM_end:
    jal     while_wait_dma_busy                         // wait for the DMA read to finish
G_SPNOOP_handler:
run_next_DL_command:
     mfc0   $1, SP_STATUS                               // load the status word into register $1
    vclr    vZero                                       // Zero vZero for each command
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // load the command word into cmd_w0
    beqz    inputBufferPos, displaylist_dma             // load more DL commands if none are left
     andi   $1, $1, SP_STATUS_SIG0                      // check if the task should yield
    sra     $7, cmd_w0, 24                              // extract DL command byte from command word
    bnez    $1, load_overlay_0_and_enter                // load and execute overlay 0 if yielding; $1 > 0
     lw     cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // load the next DL word into cmd_w1_dram
    vadd    vOne, vZero, $v31[2]                        // 1; set up vOne for each command
    addi    inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
    // $7 must retain the command byte for load_mtx and overlay 4 stuff
    // $11 must contain the handler called for G_SETOTHERMODE_H_handler and G_TEXRECTFLIP_handler
    // $1 must remain zero to save an instr in G_FLAGS1VERT_handler
    addi    $3, $7, -G_FLAGSOPBASE                      // If >= G_FLAGSOPBASE, use handler
    bgez    $3, G_FLAGSOPBASE_handler
     addi   $2, $7, -G_VTX                              // If >= G_VTX, use jump table
    bgez    $2, do_cmd_jump_table                       // $2 is the index
     addi   $11, $2, (cmdJumpTablePositive - cmdJumpTableForwardBack) / 2 // Will be interpreted relative to other jump table
    addi    $2, $2, G_VTX - (0xFF00 | G_SETTIMG)        // If >= G_SETTIMG, use handler; for G_NOOP, this puts
    bgez    $2, G_SETxIMG_handler                       // garbage in second word, but normal handler does anyway
     addi   $3, $2, G_SETTIMG - G_SETTILESIZE           // If >= G_SETTILESIZE, use handler
    bgez    $3, G_RDP_handler
     addi   $11, $3, G_SETTILESIZE - G_SETSCISSOR       // If >= G_SETSCISSOR, use jump table
    bgez    $11, do_cmd_jump_table
     nop
    addi    $11, $11, G_SETSCISSOR - G_RDPLOADSYNC      // If >= G_RDPLOADSYNC, use handler; for the syncs, this
    bgez    $11, G_RDP_handler                          // stores the second command word, but that's fine
do_cmd_jump_table:
     sll    $11, $11, 1                                 // Multiply jump table index in $2 by 2 for addr offset
    lhu     $11, cmdJumpTableForwardBack($11)           // Load address of handler from jump table
    jr      $11                                         // Jump to handler
     // Delay slot is harmless; $ra never holds anything useful here.
     
G_SETxIMG_handler:
    li      $ra, G_RDP_handler            // Load the RDP command handler into the return address, then fall through to convert the address to virtual
// Converts the segmented address in cmd_w1_dram to the corresponding physical address
segmented_to_physical:
    srl     $11, cmd_w1_dram, 22          // Copy (segment index << 2) into $11
    andi    $11, $11, 0x3C                // Clear the bottom 2 bits that remained during the shift
    lw      $11, (segmentTable)($11)      // Get the current address of the segment
    sll     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address to the left so that the top 8 bits are shifted out
    srl     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr      $ra
     add    cmd_w1_dram, cmd_w1_dram, $11 // Add the segment's address to the masked input address, resulting in the virtual address

G_CULLDL_handler:
    j       vtx_addrs_from_cmd           // Load start vtx addr in $12, end vtx in $3
     li     $11, culldl_return_from_addrs
culldl_return_from_addrs:
    li      $1, CLIP_MOD_MASK_SCRN_ALL
    lhu     $11, VTX_CLIP($12)
culldl_loop:
    and     $1, $1, $11
    beqz    $1, run_next_DL_command           // Some vertex is on the screen-side of all clipping planes; have to render
     lhu    $11, (vtxSize + VTX_CLIP)($12) // next vertex clip flags
    bne     $12, $3, culldl_loop    // loop until reaching the last vertex
     addi   $12, $12, vtxSize           // advance to the next vertex
end_dl_no_count:
    la      cmd_w0, 0                    // Clear count of DL cmds to skip loading
G_ENDDL_handler:
    lbu     $1, displayListStackLength          // Load the DL stack index
    beqz    $1, load_overlay_0_and_enter        // Load overlay 0 if there is no DL return address, to end the graphics task processing; $1 < 0
     addi   $1, $1, -4                          // Decrement the DL stack index
    j       call_ret_common                // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($1) // Load the address of the DL to return to into the taskDataPtr (the current DL address)

G_MOVEWORD_handler:
    srl     $2, cmd_w0, 16                              // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $12, (movewordTable - (G_MOVEWORD << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    add     $12, $12, cmd_w0        // adds the offset in the command word to the address from the table (the upper 4 bytes are effectively ignored)
    j       run_next_DL_command     // process the next command
     sw     cmd_w1_dram, ($12)      // moves the specified value (in cmd_w1_dram) into the word (offset + moveword_table[index])

G_RDPHALF_2_handler:
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val                 // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
    sdv     $v29[0], -8(rdpCmdBufPtr)
G_RDP_handler:
    sw      cmd_w1_dram, 4(rdpCmdBufPtr)        // Add the second word of the command to the RDP command buffer
G_SYNC_handler:
    sw      cmd_w0, 0(rdpCmdBufPtr)         // Add the command word to the RDP command buffer
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8   // Increment the next RDP command pointer by 2 words
check_rdp_buffer_full_and_run_next_cmd:
    li      $ra, run_next_DL_command    // Set up running the next DL command as the return address
check_rdp_buffer_full:
     sub    $11, rdpCmdBufPtr, rdpCmdBufEnd
    blez    $11, return_routine         // Return if rdpCmdBufEnd >= rdpCmdBufPtr
flush_rdp_buffer:
     mfc0   $12, SP_DMA_BUSY
    lw      cmd_w1_dram, rdpFifoPos
    addi    dmaLen, $11, RDP_CMD_BUFSIZE
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

.if (. & 4)
    .warning "One instruction of padding before ovl234"
.endif

.align 8
ovl234_start:

ovl3_start:

// Jump here to do lighting. If overlay 3 is loaded (this code), loads and jumps
// to overlay 2 (same address as right here).
ovl234_lighting_entrypoint_ovl3ver:  // same IMEM address as ovl234_lighting_entrypoint
    li      cmd_w1_dram, orga(ovl2_start)        // set up a load for overlay 2
    j       load_overlays_2_3_4                  // load overlay 2
     li     postOvlRA, ovl234_lighting_entrypoint // set the return address

// Jump here for all overlay 4 features. If overlay 3 is loaded (this code),
// loads and jumps to overlay 4 (ovl234_start).
ovl234_ovl4_entrypoint_ovl3ver: // same IMEM address as ovl234_ovl4_entrypoint
    li      cmd_w1_dram, orga(ovl4_start)        // set up a load for overlay 4
    j       load_overlays_2_3_4                  // load overlay 4
     li     postOvlRA, ovl234_ovl4_entrypoint    // set the return address

// Jump here to do clipping. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl234_clipping_entrypoint:
    sh      $ra, tempHalfword1
ovl3_clipping_nosavera:
    sh      $4, tempHalfword2
    jal     vtx_setup_constants
     li     clipMaskIdx, 4
clip_after_constants:
    // Clear all temp vertex slots used.
    li      $11, (MAX_CLIP_GEN_VERTS - 1) * vtxSize
clip_init_used_loop:
    sh      $zero, (VTX_CLIP + clipTempVerts)($11)
    bgtz    $11, clip_init_used_loop
     addi   $11, $11, -vtxSize
    // This being >= 0 also indicates that tri writes are in clipping mode.
    li      clipPolySelect, 6  // Everything being indexed from 6 saves one instruction at the end of the loop
    // Write the current three verts as the initial polygon
    sh      $1, (clipPoly - 6 + 0)(clipPolySelect)
    sh      $2, (clipPoly - 6 + 2)(clipPolySelect)
    sh      $3, (clipPoly - 6 + 4)(clipPolySelect)
    sh      $zero, (clipPoly)(clipPolySelect) // Zero to mark end of polygon
    li      $9, CLIP_NEAR >> 4                       // Initial clip mask for no nearclipping
// Available locals here: $11, $1, $7, $20, $24, $12
clip_condlooptop: // Loop over six clipping conditions: near, far, +y, +x, -y, -x
    lhu     clipFlags, VTX_CLIP($3)                  // Load flags for V3, which will be the final vertex of the last polygon
    and     clipFlags, clipFlags, $9                 // Mask V3's flags to current clip condition
    addi    clipPolyRead,   clipPolySelect, -6       // Start reading at the beginning of the old polygon
    xori    clipPolySelect, clipPolySelect, 6 ^ (clipPoly2 + 6 - clipPoly) // Swap to the other polygon memory
    addi    clipPolyWrite,  clipPolySelect, -6       // Start writing at the beginning of the new polygon
clip_edgelooptop: // Loop over edges connecting verts, possibly subdivide the edge
    // Edge starts from V3, ends at V2
    lhu     $2, (clipPoly)(clipPolyRead)       // Read next vertex of input polygon as V2 (end of edge)
    addi    clipPolyRead, clipPolyRead, 0x0002 // Increment read pointer
    beqz    $2, clip_nextcond              // If V2 is 0, done with input polygon
     lhu    $11, VTX_CLIP($2)                  // Load flags for V2
    and     $11, $11, $9                       // Mask V2's flags to current clip condition
    beq     $11, clipFlags, clip_nextedge  // Both set or both clear = both off screen or both on screen, no subdivision
     move   clipFlags, $11                     // clipFlags = masked V2's flags
    // Going to subdivide this edge. Find available temp vertex slot.
    li      outputVtxPos, clipTempVerts + MAX_CLIP_GEN_VERTS * vtxSize
clip_find_unused_loop:
    lhu     $11, (VTX_CLIP - vtxSize)(outputVtxPos)
    addi    $12, outputVtxPos, -clipTempVerts  // This is within the loop rather than before b/c delay after lhu
    blez    $12, clip_done                 // If can't find one (should never happen), give up
     andi   $11, $11, CLIP_MOD_VTX_USED
    bnez    $11, clip_find_unused_loop
     addi   outputVtxPos, outputVtxPos, -vtxSize
    beqz    clipFlags, clip_skipswap23     // V2 flag is clear / on screen, therefore V3 is set / off screen
     move   $19, $2                            // 
    move    $19, $3                            // Otherwise swap V2 and V3; note we are overwriting $3 but not $2
    move    $3, $2                             // 
clip_skipswap23: // After possible swap, $19 = vtx not meeting clip cond / on screen, $3 = vtx meeting clip cond / off screen
    // Interpolate between these two vertices; create a new vertex which is on the
    // clipping boundary (e.g. at the screen edge)
vClBaseF equ $v8
vClBaseI equ $v9
vClDiffF equ $v10
vClDiffI equ $v11
vClFade1 equ $v10 // = vClDiffF
vClFade2 equ $v2
    /*
    Five clip conditions (these are in a different order from vanilla):
           vClBaseI/vClBaseF[3]     vClDiffI/vClDiffF[3]
    4 W=0:             W1                 W1  -         W2
    3 +X :      X1 - 2*W1         (X1 - 2*W1) - (X2 - 2*W2) <- the 2 is clip ratio
    2 -X :      X1 + 2*W1         (X1 + 2*W1) - (X2 + 2*W2)
    1 +Y :      Y1 - 2*W1         (Y1 - 2*W1) - (Y2 - 2*W2)
    0 -Y :      Y1 + 2*W1         (Y1 + 2*W1) - (Y2 + 2*W2)
    */
    xori    $11, clipMaskIdx, 1              // Invert sign of condition
    ldv     $v4[0], VTX_FRAC_VEC($19)        // Vtx on screen, frac pos
    ctc2    $11, $vcc                        // Conditions 1 (+y) or 3 (+x) -> vcc[0] = 0
    ldv     $v5[0], VTX_INT_VEC ($19)        // Vtx on screen, int pos
    vmrg    $v29, vOne, $v31[1]              // elem 0 is 1 if W or neg cond, -1 if pos cond
    andi    $11, clipMaskIdx, 4              // W condition and screen clipping
    ldv     $v4[8], VTX_FRAC_VEC($3)         // Vtx off screen, frac pos
    bnez    $11, clip_w              // If so, use 1 or -1
     ldv    $v5[8], VTX_INT_VEC ($3)         // Vtx off screen, int pos
    vmudh   $v29, $v29, $v31[3]              // elem 0 is (1 or -1) * 2 (clip ratio)
    andi    $11, clipMaskIdx, 2              // Conditions 2 (-x) or 3 (+x)
    vmudm   vClBaseF, vOne, $v4[0h]          // Set accumulator (care about 3, 7) to X
    bnez    $11, clip_skipy
     vmadh  vClBaseI, vOne, $v5[0h]
    vmudm   vClBaseF, vOne, $v4[1h]          // Discard that and set accumulator 3, 7 to Y
    vmadh   vClBaseI, vOne, $v5[1h]
clip_skipy:
    vmadn   vClBaseF, $v4, $v29[0]           // + W * +/- 2
    vmadh   vClBaseI, $v5, $v29[0]
clip_skipxy:
    vsubc   vClDiffF, vClBaseF, vClBaseF[7]  // Vtx on screen - vtx off screen
    vsub    vClDiffI, vClBaseI, vClBaseI[7]
    // Not sure what the first reciprocal is for.
    vor     $v29, vClDiffI, vOne[0]       // round up int sum to odd; this ensures the value is not 0, otherwise v29 will be 0 instead of +/- 2
    vrcph   $v3[3], vClDiffI[3]
    vrcpl   $v2[3], vClDiffF[3]           // frac: 1 / (x+y+z+w), vtx on screen - vtx off screen
    vrcph   $v3[3], vZero[0]              // get int result of reciprocal
    vabs    $v29, $v29, $v31[3]           // 2; v29 = +/- 2 based on sum positive (incl. zero) or negative
    vmudn   $v2, $v2, $v29[3]             // multiply reciprocal by +/- 2
    vmadh   $v3, $v3, $v29[3]
    veq     $v3, $v3, vZero[0]            // if reciprocal high is 0
    vmrg    $v2, $v2, $v31[1]             // keep reciprocal low, otherwise set to -1
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
    vmudh   $v29, vOne, vSTScl[3]        // 4 (int part), Newton-Raphson algorithm
    vmadn   vClDiffF, vClDiffF, $v31[0]   // - 4 * prev result frac part
    vmadh   vClDiffI, vClDiffI, $v31[0]   // - 4 * prev result frac part
    vmudl   $v29, $v12, vClDiffF          // * own reciprocal again? frac*frac discard
    vmadm   $v29, $v13, vClDiffF          // * own reciprocal again? int*frac discard
    vmadn   $v12, $v12, vClDiffI          // * own reciprocal again? frac out
    vmadh   $v13, $v13, vClDiffI          // * own reciprocal again? int out
    vmudl   $v29, vClBaseF, $v12
    // Have to load $v6 and $v7 because they were not loaded above.
    // Also, put color/TC in $v12 and $v13 instead of $v26 and $v25 as the former
    // will survive vertices_store.
    ldv     $v6[0], VTX_FRAC_VEC($3)      // Vtx off screen, frac pos
    vmadm   $v29, vClBaseI, $v12
    ldv     $v7[0], VTX_INT_VEC ($3)      // Vtx off screen, int pos
    vmadn   vClDiffF, vClBaseF, $v13
    luv     $v12[0], VTX_COLOR_VEC($3)    // Vtx off screen, RGBA
    vmadh   vClDiffI, vClBaseI, $v13      // 11:10 = vtx on screen sum * prev calculated value
    llv     $v14[0], VTX_TC_VEC   ($3)    // Vtx off screen, ST
    vmudl   $v29, vClDiffF, $v2[3]
    luv     $v13[0], VTX_COLOR_VEC($19)   // Vtx on screen, RGBA
    vmadm   vClDiffI, vClDiffI, $v2[3]
    llv     vPairST[0], VTX_TC_VEC($19)   // Vtx on screen, ST
    vmadn   vClDiffF, vClDiffF, vZero[0]  // * one of the reciprocals above
    vlt     vClDiffI, vClDiffI, vOne[0]   // If integer part of factor less than 1,
    vmrg    vClDiffF, vClDiffF, $v31[1]   // keep frac part of factor, else set to 0xFFFF (max val)
    vsubc   $v29, vClDiffF, vOne[0]       // frac part - 1 for carry
    vge     vClDiffI, vClDiffI, vZero[0]  // If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    vmrg    vClFade1, vClDiffF, vOne[0]   // keep frac part of factor, else set to 1 (min val)
    vmudn   vClFade2, vClFade1, $v31[1]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for on screen vert
    // Fade between attributes for on screen and off screen vert
    // Also, colors are now in $v12 and $v13.
    // Also, texture coords are now in $v14 and vPairST.
    vmudm   $v29, $v12, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color and TC
    lhu     $11, VTX_CLIP($3)             // Load clip flags for off screen vert
    vmadm   vPairRGBA, $v13, vClFade2[3]  // + Fade factor for on  screen vert * on  screen vert color
    li      $7, 0x0000                    // Set no fog
    vmudm   $v29, $v14, vClFade1[3]       //   Fade factor for off screen vert * off screen vert TC
    move    secondVtxPos, outputVtxPos    // Writes garbage second vertex and then output vertex to same place
    vmadm   vPairST, vPairST, vClFade2[3] // + Fade factor for on  screen vert * on  screen vert TC
    andi    $11, $11, ~CLIP_MOD_VTX_USED  // Clear used flag from off screen vert
    vmudl   $v29, $v6, vClFade1[3]        //   Fade factor for off screen vert * off screen vert pos frac
    sh      outputVtxPos, (clipPoly)(clipPolyWrite) // Write pointer to generated vertex to polygon
    vmadm   $v29, $v7, vClFade1[3]        // + Fade factor for off screen vert * off screen vert pos int
    addi    clipPolyWrite, clipPolyWrite, 2  // Increment write ptr
    vmadl   $v29, $v4, vClFade2[3]        // + Fade factor for on screen vert * on screen vert pos frac
    sh      $11, VTX_CLIP($3)             // Store modified clip flags for off screen vert
    vmadm   vPairTPosI, $v5, vClFade2[3] // + Fade factor for on screen vert * on screen vert pos int
    jal     vtx_store              // Write new vertex
     vmadn  vPairTPosF, vZero, vZero[0] // Load resulting frac pos
clip_nextedge:
    bnez    clipFlags, clip_edgelooptop  // Discard V2 if it was off screen (whether inserted vtx or not)
     move   $3, $2                           // Move what was the end of the edge to be the new start of the edge
    sh      $3, (clipPoly)(clipPolyWrite)    // Former V2 was on screen, so add it to the output polygon
    j       clip_edgelooptop
     addi   clipPolyWrite, clipPolyWrite, 2

clip_w:
    vcopy   vClBaseF, $v4                    // Result is just W
    j       clip_skipxy
     vcopy  vClBaseI, $v5

clip_nextcond:
    sub     $11, clipPolyWrite, clipPolySelect // Are there less than 3 verts in the output polygon?
    bltz    $11, clip_done                 // If so, degenerate result, quit
     sh     $zero, (clipPoly)(clipPolyWrite)   // Terminate the output polygon with a 0
    lhu     $3, (clipPoly - 2)(clipPolyWrite)  // Initialize the edge start (V3) to the last vert
clip_nextcond_skip:
    beqz    clipMaskIdx, clip_draw_tris
     lbu    $11, (clipCondShifts - 1)(clipMaskIdx) // Load next clip condition shift amount
    li      $9, 1
    sllv    $9, $9, $11                        // $9 is clip mask
    j       clip_condlooptop
     addi   clipMaskIdx, clipMaskIdx, -1
    
clip_draw_tris:
    lhu     $4, tempHalfword2         // Pointer to original first vertex for flat shading
    lqv     $v30, v30Value($zero)
// Current polygon starts 6 (3 verts) below clipPolySelect, ends 2 (1 vert) below clipPolyWrite
    addi    clipPolySelect, clipPolySelect, -6 // = Pointer to first vertex
    // Available locals: most registers ($5, $6, $7, $8, $9, $11, $12, etc.)
    // Available regs which won't get clobbered by tri write: 
    // clipPolySelect, clipPolyWrite, $14 (inputVtxPos), $15 (outputVtxPos), (more)
    // Find vertex highest on screen (lowest screen Y)
    li      $5, 0x7FFF                // current best value
    move    $7, clipPolySelect        // initial vertex pointer
    lhu     $12, (clipPoly)($7)       // Load vertex address
clip_search_highest_loop:
    lh      $9, VTX_SCR_Y($12)        // Load screen Y
    sub     $11, $9, $5               // Branch if new vtx Y >= best vtx Y
    bgez    $11, clip_search_skip_better
     addi   $7, $7, 2                 // Next vertex
    addi    $14, $7, -2               // Save pointer to best/current vertex
    move    $5, $9                    // Save best value
clip_search_skip_better:
    bne     clipPolyWrite, $7, clip_search_highest_loop
     lhu    $12, (clipPoly)($7)       // Next vertex address
    addi    clipPolyWrite, clipPolyWrite, -2   // = Pointer to last vertex
    // Find next closest vertex, from the two on either side
    bne     $14, clipPolySelect, @@skip1
     addi   $6, $14, -2               // $6 = previous vertex
    move    $6, clipPolyWrite
@@skip1:
    lhu     $7, (clipPoly)($6)
    bne     $14, clipPolyWrite, @@skip2
     addi   $8, $14, 2                // $8 = next vertex
    move    $8, clipPolySelect
@@skip2:
    lhu     $9, (clipPoly)($8)
    lh      $7, VTX_SCR_Y($7)
    lh      $9, VTX_SCR_Y($9)
    sub     $11, $7, $9               // If value from prev vtx >= value from next, use next
    bgez    $11, clip_draw_loop
     move   $15, $8                   // $14 is first, $8 -> $15 is next
    move    $15, $14                  // $14 -> $15 is next
    move    $14, $6                   // $6 -> $14 is first
clip_draw_loop:
    // Current edge is $14 - $15 (pointers to clipPoly). We can either draw
    // (previous) - $14 - $15, or we can draw $14 - $15 - (next). We want the
    // one where the lower edge covers the fewest scanlines. This edge is
    // (previous) - $15 or $14 - (next).
    // $1, $2, $3, $5 are vertices at $11=prev, $14, $15, $12=next
    bne     $14, clipPolySelect, @@skip1
     addi   $11, $14, -2
    move    $11, clipPolyWrite
@@skip1:
    beq     $11, $15, clip_done // If previous is $15, we only have two verts left, done
     lhu    $1, (clipPoly)($11)     // From the group below, need something in the delay slot
    bne     $15, clipPolyWrite, @@skip2
     addi   $12, $15, 2
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
    beqz    $9, clip_final_draw // Skip the change if second diff greater than or equal to first diff
     move   $14, $11           // If skipping, drawing prev-$14-$15, so update $14 to be prev
    move    $1, $2             // Drawing $14, $15, next
    move    $2, $3
    move    $3, $5
    move    $14, $8            // Restore overwritten $14
    move    $15, $12           // Update $15 to be next
clip_final_draw:
    mtc2    $1, $v27[10]              // Addresses go in vector regs too
    mtc2    $2, $v4[12]
    mtc2    $3, $v27[14]
    j       tri_noinit         // Draw tri
     li     $ra, clip_draw_loop // When done, return to top of loop

clip_done:
    lh      $ra, tempHalfword1
    jr      $ra
     li     clipPolySelect, -1  // Back to normal tri drawing mode (check clip masks)

ovl3_end:
.align 8
ovl3_padded_end:

.orga max(max(ovl2_padded_end - ovl2_start, ovl4_padded_end - ovl4_start) + orga(ovl3_start), orga())
ovl234_end:

G_FLAGS1VERT_handler:
    // $1 is zero (0 vertices left to process, treated like 1) from run_next_DL_command
    li      $6, 0                              // Output bit 1, whether any vtx near enough
    addi    inputVtxPos, inputBufferPos, -6    // Input vertex starts 2 bytes into last cmd
    j       vtx_setup_skip_load
     // Intentionally executing next instr to set $5 = 0

G_FLAGSVERTS_handler:
    li      $5, 0                              // Disable lighting (all geometry mode bits)
    lhu     $1, (inputBufferEnd - 0x06)(inputBufferPos) // Bytes 2-3 = size in bytes
    li      $6, 0                              // Output bit 1, whether any vtx near enough
    j       vtx_common_setup
     li     $12, (clipTempVertsEnd & 0xFFF8)   // Address of end of load region

flagsverts_setup_end:
    jal     while_wait_dma_busy                // Wait for vertex load to finish
     llv    vVpScl[0], rdpHalf1Val($zero)  // Dist compare int / frac; reg not used on this path
    ldv     vVpOfs[0], (cameraWorldPos - altBase)(altBaseReg) // Camera world pos
    ldv     vVpOfs[8], (cameraWorldPos - altBase)(altBaseReg)
    li      $9, CLIP_MOD_MASK_SCRN_ALL         // Output bit 0, whether all vertices offscreen
flagsverts_loop:
    j       vtx_load_skip1st
     ldv    vPairPosI[8], (8)(inputVtxPos)          // Load second vertex
flagsverts_after_xfrm:
    // World space XYZ in vPairPosI/F; clip space coords in vPairTPosI/F elem 3 and 7.
    vsub    $v28, vPairPosI, vVpOfs            // Vertex - camera
    addi    $1, $1, 0x10                       // Has had - 2*inputVtxsize, need - 2*8 instead
    vmudh   $v29, $v28, $v28                   // Squared
    vreadacc $v28, ACC_MIDDLE                  // Have to separately read because clamped
    vreadacc $v30, ACC_UPPER
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    vaddc   $v28, $v28, $v28[1h]               // Sum into X
    cfc2    $20, $vcc
    vadd    $v30, $v30, $v30[1h]
    vaddc   $v28, $v28, $v28[2h]
    vadd    $v30, $v30, $v30[2h]
    vsubc   $v29, $v28, vVpScl[1]          // Compare dist frac
    and     $9, $9, $20                        // Combine screen clip mask for first vtx
    vlt     $v29, $v30, vVpScl[0]          // Compare dist int, bits 0 and 4
    cfc2    $11, $vcc                          // Get compare results
    bltz    $1, @@skip                         // Only one of two verts valid
     or     $6, $6, $11                        // Combine first vtx near result
    srl     $11, $11, 4                        // Second vtx near result -> bit 0
    or      $6, $6, $11                        // Combine second vtx near result
    srl     $20, $20, 4                        // Shift second vertex screen clipping to first slots
    and     $9, $9, $20                        // Combine screen clip mask for second vtx
@@skip:
    sltiu   $24, $9, 1                         // Set bit 0 if no clip planes left
    and     $24, $24, $6                       // And at least one vertex near enough
    bnez    $24, flagsverts_early_return       // If 1, early return
     addi   inputVtxPos, inputVtxPos, -0x10    // Has had + 2*inputVtxSize, need + 2*8 instead
    bgtz    $1, flagsverts_loop                // > 0 verts remain, continue
flagsverts_early_return:
     lbu    $11, (inputBufferEnd - 0x07)(inputBufferPos) // Shift amount
    lw      $20, cullFlags                     // Current flags
    sll     $6, $6, 1                          // Shift near result to bit 1
    or      $24, $24, $6                       // Bit 1 = near, bit 0 = near and on screen
    li      $12, 3                             // Initial bitmask
    sllv    $12, $12, $11                      // Shift 3 to desired bits
    sllv    $24, $24, $11                      // Shift new flags to desired bits
    nor     $12, $12, $zero                    // Negate shifted 3
    and     $20, $20, $12                      // Mask away old values of bits
    or      $20, $20, $24                      // Insert new values of bits
    j       run_next_DL_command
     sw     $20, cullFlags                     // Store updated flags

G_VTX_handler:
    lhu     $1, (inputBufferEnd - 0x07)(inputBufferPos) // Size in inputVtxSize units
    srl     $2, cmd_w0, 11                     // n << 1
    sub     $2, cmd_w0, $2                     // v0 << 1
    sb      $2, (inputBufferEnd - 0x06)(inputBufferPos) // Store v0 << 1 as byte 2
    j       vtx_addrs_from_cmd                 // v0 << 1 is elem 2, (v0 + n) << 1 is elem 3 = $12
     li     $11, vtx_return_from_addrs
vtx_return_from_addrs:
    lhu     $5, geometryModeLabel + 1          // Middle 2 bytes
    li      $6, -1                             // For flagsverts, negative means normal vtx load
    andi    $12, $12, 0xFFF8                   // Round down end addr to DMA word; one input vtx still fits in one internal vtx
    mfc2    outputVtxPos, $v27[4]              // Address of start in vtxSize units
vtx_common_setup:
    // $1 = load size in bytes, $12 = load end addr, cmd_w1_dram, $5 = geom mode middle,
    // $6 = mode flag, outputVtxPos if G_VTX_handler
    jal     segmented_to_physical              // Convert address in cmd_w1_dram to physical
     sub    dmemAddr, $12, $1                  // Start addr = end addr - size
    jal     dma_read_write
     addi   dmaLen, $1, -1                     // DMA length is always offset by -1
    move    inputVtxPos, dmemAddr
vtx_setup_skip_load:
    // $1 = vertex count * 0x10, $5 = geom mode middle, $6 = mode flag, inputVtxPos
    lqv     vM0I,     (mMatrix + 0x00)($zero)  // Load M matrix
    lqv     vM2I,     (mMatrix + 0x10)($zero)
    lqv     vM0F,     (mMatrix + 0x20)($zero)
    lqv     vM2F,     (mMatrix + 0x30)($zero)
    lbu     $11, mITValid                      // 0 if matrix invalid, 1 if valid
    vcopy   vM1I,  vM0I
    lbu     $12, normalsMode                   // bit 0 clear if don't compute mIT, set if do
    vcopy   vM3I,  vM2I
    ldv     vM1I[0],  (mMatrix + 0x08)($zero)
    vcopy   vM1F,  vM0F
    ldv     vM3I[0],  (mMatrix + 0x18)($zero)
    vcopy   vM3F,  vM2F
    ldv     vM1F[0],  (mMatrix + 0x28)($zero)
    sltiu   $11, $11, 1                        // 0 if matrix valid, 1 if invalid
    srl     $7, $5, 9                          // G_LIGHTING in bit 1
    and     $7, $7, $11                        // If lighting enabled and need to update matrix,
    and     $7, $7, $12                        // and computing mIT,
    ldv     vM3F[0],  (mMatrix + 0x38)($zero)
    ldv     vM0I[8],  (mMatrix + 0x00)($zero)
    ldv     vM2I[8],  (mMatrix + 0x10)($zero)
    ldv     vM0F[8],  (mMatrix + 0x20)($zero)
    bnez    $7, ovl234_ovl4_entrypoint         // run overlay 4 to compute M inverse transpose
     ldv    vM2F[8],  (mMatrix + 0x30)($zero)
vtx_after_calc_mit:
    lqv     vVP0I,     (vpMatrix  + 0x00)($zero)
    lqv     vVP2I,    (vpMatrix  + 0x10)($zero)
    lqv     vVP0F,    (vpMatrix  + 0x20)($zero)
    lqv     vVP2F,    (vpMatrix  + 0x30)($zero)
    addi    outputVtxPos, outputVtxPos, -2*vtxSize // Going to increment this by 2 verts in loop
    vcopy   vVP1I,  vVP0I
    li      $ra, 0                             // Flag to not return to clipping
    vcopy   vVP3I, vVP2I
    ldv     vVP1I[0],  (vpMatrix  + 0x08)($zero)
    vcopy   vVP1F, vVP0F
    ldv     vVP3I[0], (vpMatrix  + 0x18)($zero)
    vcopy   vVP3F, vVP2F
    ldv     vVP1F[0], (vpMatrix  + 0x28)($zero)
    ldv     vVP3F[0], (vpMatrix  + 0x38)($zero)
    ldv     vVP0I[8],  (vpMatrix  + 0x00)($zero)
    ldv     vVP2I[8], (vpMatrix  + 0x10)($zero)
    ldv     vVP0F[8], (vpMatrix  + 0x20)($zero)
    bgez    $6, flagsverts_setup_end
     ldv    vVP2F[8], (vpMatrix  + 0x30)($zero)
vtx_setup_constants:
/*
vVpScl = [vscale[0], -vscale[1], vscale[2], fogMult,   (repeat)]
vVpOfs = [vtrans[0],  vtrans[1], vtrans[2], fogOffset, (repeat)]
vSTScl = [TexSScl,   TexTScl,    perspNorm, 4,         TexSScl,   TexTScl, ---,       4     ]
vSTOfs = [TexSOfs,   TexTOfs,    aoAmb,     0,         TexSOfs,   TexTOfs, aoDir,     0     ]
$v31   = [-4,        -1,         1,         2,         4,         0x4000,  0x7F00,    0x7FFF]
aoAmb, aoDir set to 0 if ambient occlusion disabled
TexSOfs, TexTOfs set to 0 if ST attr offset disabled;
vtrans[2] not incremented by Z attr offset if disabled
*/
    vne     $v29, $v31, $v31[2h]                  // VCC = 11011101
    ldv     vSTOfs[0], (attrOffsetST - altBase)(altBaseReg) // elems 0, 1, 2 = S, T, Z offset
    vclr    $v21                                  // Zero
    ldv     vVpOfs[0], (viewport + 8)($zero) // Load vtrans duplicated in 0-3 and 4-7
    ldv     vVpOfs[8], (viewport + 8)($zero)
    lhu     $12, (geometryModeLabel+2)($zero)
    vmrg    $v29, $v21, vSTOfs[2]               // all zeros except elems 2, 6 are Z offset
    ldv     vSTOfs[8], (attrOffsetST - altBase)(altBaseReg) // Duplicated in 4-6
    andi    $11, $12, G_ATTROFFSET_Z_ENABLE
    beqz    $11, @@skipz                          // Skip if Z offset disabled
     llv    $v20[4], (aoAmbientFactor - altBase)(altBaseReg) // Load aoAmb 2 and aoDir 3
    vadd    vVpOfs, vVpOfs, $v29        // add Z offset if enabled
@@skipz:
    andi    $11, $12, G_ATTROFFSET_ST_ENABLE
    bnez    $11, @@skipst                         // Skip if ST offset enabled
     llv    vSTScl[0], (textureSettings2)($zero) // Texture ST scale in 0, 1
    vclr    vSTOfs                              // If disabled, clear ST offset
@@skipst:
    andi    $11, $12, G_AMBOCCLUSION
    vmov    $v20[6], $v20[3]                      // move aoDir to 6
    bnez    $11, @@skipao                         // Skip if ambient occlusion enabled
     llv    vSTScl[8], (textureSettings2)($zero) // Texture ST scale in 4, 5
    vcopy   $v20, $v21                            // Set aoAmb and aoDir to 0
@@skipao:
    ldv     vVpScl[0], (viewport)($zero)      // Load vscale duplicated in 0-3 and 4-7
    ldv     vVpScl[8], (viewport)($zero)
    llv     vSTScl[4], (perspNorm)($zero)        // perspNorm in elem 2, garbage in 3
    llv     $v23[0], (fogFactor)($zero)           // Load fog multiplier 0 and offset 1
    vmrg    vSTOfs, vSTOfs, $v20              // move aoAmb and aoDir into vSTOfs
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    vsub    $v20, $v21, vVpScl                // -vscale
    vmrg    vSTScl, vSTScl, $v31[4]             // Put 4s in elements 3,7
    vmrg    vVpScl, vVpScl, $v23[0]       // Put fog multiplier in elements 3,7 of vscale
    vadd    $v23, $v23, $v31[6]                   // Add 0x7F00 to fog offset
    vmrg    vSTOfs, vSTOfs, $v21              // Put 0s in elements 3,7
    vmov    vVpScl[1], $v20[1]                // Negate vscale[1] because RDP top = y=0
    vmov    vVpScl[5], $v20[1]                // Same for second half
    bnez    $ra, clip_after_constants     // Return to clipping if from there
     vmrg    vVpOfs, vVpOfs, $v23[1]    // Put fog offset in elements 3,7 of vtrans
    jal     while_wait_dma_busy                   // Wait for vertex load to finish
     andi   $7, $5, G_FOG >> 8                    // Nonzero if fog enabled
vtx_load_loop:
    ldv     vPairPosI[8],      (VTX_IN_OB + inputVtxSize * 1)(inputVtxPos)
vtx_load_skip1st:
    vlt     $v29, $v31, $v31[4] // Set VCC to 11110000
    ldv     vPairPosI[0],      (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos)
    vmudn   $v29, vM3F, $v31[2]  // 1
    // Element access wraps in lpv/luv, but not intuitively. Basically the named
    // element and above do get the values at the specified address, but the earlier
    // elements get the values before that, except masked to 0xF. So for example here,
    // elems 4-7 get bytes 0-3 of the vertex as it looks like they should, but elems
    // 0-3 get bytes C-F of the vertex (which is what we want).
    luv     vPairRGBA[4], (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Colors as unsigned, lower 4
    vmadh   $v29, vM3I, $v31[2]
    luv     $v25[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, vM0F, vPairPosI[0h]
    lpv     $v28[4],      (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Normals as signed, lower 4
    vmadh   $v29, vM0I, vPairPosI[0h]
    lpv     $v26[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, vM1F, vPairPosI[1h]
    llv     vPairST[0],   (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // ST in 0:1
    vmadh   $v29, vM1I, vPairPosI[1h]
    llv     vPairST[8],   (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // ST in 4:5
    vmadn   vPairPosF, vM2F, vPairPosI[2h]
    andi    $11, $5, G_LIGHTING >> 8
    vmadh   vPairPosI, vM2I, vPairPosI[2h] // vPairPosI/F = vertices world coords
    // Elems 0-1 get bytes 6-7 of the following vertex (0)
    lpv     $v30[2],      (VTX_IN_TC - inputVtxSize * 1)(inputVtxPos) // Packed normals as signed, lower 2
    vmrg    vPairRGBA, vPairRGBA, $v25 // Merge colors
    bnez    $11, ovl234_lighting_entrypoint
     // Elems 4-5 get bytes 6-7 of the following vertex (1)
     lpv    $v25[6],      (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // Upper 2 in 4:5
 vtx_return_from_lighting:
    vmudn   $v29, vVP3F, $v31[2] // 1
    addi    inputVtxPos, inputVtxPos, 2*inputVtxSize
    vmadh   $v29, vVP3I, $v31[2] // 1
    addi    outputVtxPos, outputVtxPos, 2*vtxSize
    vmadl   $v29, vVP0F, vPairPosF[0h]
    addi    $1, $1, -2*inputVtxSize // Counter of remaining verts * inputVtxSize
    vmadm   $v29, vVP0I,  vPairPosF[0h]
    addi    secondVtxPos, outputVtxPos, vtxSize
    vmadn   $v29, vVP0F, vPairPosI[0h]
    bgez    $1, @@skip1 // If < 0 verts remain, second and output vertices write to same mem
     vmadh  $v29, vVP0I,  vPairPosI[0h]
    move    secondVtxPos, outputVtxPos
@@skip1:
    vmadl   $v29, vVP1F, vPairPosF[1h]
    li      $ra, vtx_load_loop
    vmadm   $v29, vVP1I,  vPairPosF[1h]
    bgtz    $1, @@skip2 // If <= 0 verts remain, run next DL command
     vmadn  $v29, vVP1F, vPairPosI[1h]
    li      $ra, run_next_DL_command
@@skip2:
    vmadh   $v29, vVP1I,  vPairPosI[1h]
    vmadl   $v29, vVP2F, vPairPosF[2h]
    vmadm   $v29, vVP2I, vPairPosF[2h]
    vmadn   vPairTPosF, vVP2F, vPairPosI[2h]
    bgez    $6, flagsverts_after_xfrm // >= 0 for flagsverts, < 0 for normal vtx
     vmadh  vPairTPosI, vVP2I, vPairPosI[2h]
    vmudm   $v29, vPairST, vSTScl     // Scale ST; must be after texgen
    vmadh   vPairST, vSTOfs, $v31[2] // + 1 * ST offset
vtx_store:
    // Inputs: vPairTPosI, vPairTPosF, vPairST, vPairRGBA
    // Locals: $v20, $v21, $v25, $v26, $v28, $v30 ($v29 is temp)
    // Alive at end for clipping: $v30:$v28 = 1/W, vPairRGBA
    // Scalar regs: secondVtxPos, outputVtxPos; set to the same thing if only write 1 vtx
    // $7 != 0 if fog; temps $11, $12, $20, $24
    vmudl   $v29, vPairTPosF, vSTScl[2] // Persp norm
    sdv     vPairTPosF[8],  (VTX_FRAC_VEC  )(secondVtxPos)
    vmadm   $v20, vPairTPosI, vSTScl[2] // Persp norm
    sdv     vPairTPosF[0],  (VTX_FRAC_VEC  )(outputVtxPos)
    vmadn   $v21, vSTOfs, vSTOfs[3] // Zero
    sdv     vPairTPosI[8],  (VTX_INT_VEC   )(secondVtxPos)
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    sdv     vPairTPosI[0],  (VTX_INT_VEC   )(outputVtxPos)
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    suv     vPairRGBA[4],     (VTX_COLOR_VEC )(secondVtxPos)
    vmudn   $v26, vPairTPosF, $v31[3] // Clip ratio
    suv     vPairRGBA[0],     (VTX_COLOR_VEC )(outputVtxPos)
    vmadh   $v25, vPairTPosI, $v31[3] // Clip ratio
    slv     vPairST[8],       (VTX_TC_VEC    )(secondVtxPos)
    vrcph   $v29[0], $v20[3]
    slv     vPairST[0],       (VTX_TC_VEC    )(outputVtxPos)
    vrcpl   $v28[3], $v21[3]
    cfc2    $20, $vcc
    vrcph   $v30[3], $v20[7]
    vrcpl   $v28[7], $v21[7]
    vrcph   $v30[7], vSTOfs[3] // Zero
    srl     $24, $20, 4            // Shift second vertex screen clipping to first slots
    vch     $v29, vPairTPosI, $v25[3h] // Clip scaled high
    andi    $12, $20, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
    vcl     $v29, vPairTPosF, $v26[3h] // Clip scaled low
    andi    $24, $24, CLIP_MOD_MASK_SCRN_ALL // Mask to only screen bits we care about
    vmudl   $v29, $v21, $v28
    cfc2    $20, $vcc
    vmadm   $v29, $v20, $v28
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(secondVtxPos) // load Z into W slot, will be for fog below
    vmadn   $v21, $v21, $v30
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outputVtxPos) // load Z into W slot, will be for fog below
    vmadh   $v20, $v20, $v30
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vge     $v29, vPairTPosI, vSTOfs[3] // Zero; vcc set if w >= 0
    andi    $20, $20, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
    vmudh   $v29, vSTScl, $v31[2] // 4 * 1 in elems 3, 7
    andi    $11, $11, CLIP_MOD_MASK_SCAL_ALL // Mask to only scaled bits we care about
    vmadn   $v21, $v21, $v31[0] // -4
    or      $24, $24, $20          // Combine final results for second vertex
    vmadh   $v20, $v20, $v31[0] // -4
    or      $12, $12, $11               // Combine final results for first vertex
    vmrg    $v25, vSTOfs, $v31[7] // 0 or 0x7FFF in elems 3, 7, latter if w < 0
    lsv     vPairTPosI[14], (VTX_Z_INT     )(secondVtxPos) // load Z into W slot, will be for fog below
    vmudl   $v29, $v21, $v28
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outputVtxPos) // load Z into W slot, will be for fog below
    vmadm   $v29, $v20, $v28
    ori     $12, $12, CLIP_MOD_VTX_USED // Write for all verts, only matters for generated verts
    vmadn   $v28, $v21, $v30
    vmadh   $v30, $v20, $v30    // $v30:$v28 is 1/W
    vmadh   $v25, $v25, $v31[7] // 0x7FFF; $v25:$v28 is 1/W but large number if W negative
    vmudl   $v29, vPairTPosF, $v28[3h]
    sh      $24,              (VTX_CLIP      )(secondVtxPos) // Store second vertex results
    vmadm   $v29, vPairTPosI, $v28[3h]
    sh      $12,              (VTX_CLIP      )(outputVtxPos) // Store first vertex results
    vmadn   vPairTPosF, vPairTPosF, $v25[3h]
    ssv     $v28[14],         (VTX_INV_W_FRAC)(secondVtxPos)
    vmadh   vPairTPosI, vPairTPosI, $v25[3h] // pos * 1/W
    ssv     $v28[6],          (VTX_INV_W_FRAC)(outputVtxPos)
    vmudl   $v29, vPairTPosF, vSTScl[2] // Persp norm
    ssv     $v30[14],         (VTX_INV_W_INT )(secondVtxPos)
    vmadm   vPairTPosI, vPairTPosI, vSTScl[2] // Persp norm
    ssv     $v30[6],          (VTX_INV_W_INT )(outputVtxPos)
    vmadn   vPairTPosF, vSTOfs, vSTOfs[3] // Zero
    vmudh   $v29, vVpOfs, $v31[2] // offset * 1
    vmadn   vPairTPosF, vPairTPosF, vVpScl // + XYZ * scale
    vmadh   vPairTPosI, vPairTPosI, vVpScl
    vge     $v21, vPairTPosI, $v31[6] // 0x7F00; clamp fog to >= 0 (low byte only)
    slv     vPairTPosI[8],  (VTX_SCR_VEC   )(secondVtxPos)
    vge     $v20, vPairTPosI, vSTOfs[3] // Zero; clamp Z to >= 0
    slv     vPairTPosI[0],  (VTX_SCR_VEC   )(outputVtxPos)
    ssv     vPairTPosF[12], (VTX_SCR_Z_FRAC)(secondVtxPos)
    beqz    $7, vtx_skip_fog
     ssv    vPairTPosF[4],  (VTX_SCR_Z_FRAC)(outputVtxPos)
    sbv     $v21[15],         (VTX_COLOR_A   )(secondVtxPos)
    sbv     $v21[7],          (VTX_COLOR_A   )(outputVtxPos)
vtx_skip_fog:
    ssv     $v20[12],         (VTX_SCR_Z     )(secondVtxPos)
    jr      $ra
     ssv    $v20[4],          (VTX_SCR_Z     )(outputVtxPos)

vtx_addrs_from_cmd:
    // Treat eight bytes of last command each as vertex indices << 1
    // inputBufferEnd is close enough to the end of DMEM to fit in signed offset
    lpv     $v27[0], (-(0x1000 - (inputBufferEnd - 0x08)))(inputBufferPos)
vtx_indices_to_addr:
    // Input and output in $v27
    // Also out elem 3 -> $12, elem 7 -> $3 because these are used more than once
    lqv     $v30, v30Value($zero)
    vmudl   $v29, $v27, $v30[1]   // Multiply vtx indices times length
    vmadn   $v27, vOne, $v30[0]   // Add address of vertex buffer
    mfc2    $12, $v27[6]
    jr      $11
     mfc2   $3, $v27[14]

G_TRISTRIP_handler:
    j       tri_strip_fan_start
     li     $ra, tri_strip_fan_loop
G_TRIFAN_handler:
    li      $ra, tri_strip_fan_loop + 0x8000 // Negative = flag for G_TRIFAN
tri_strip_fan_start:
    addi    cmd_w0, inputBufferPos, inputBufferEnd - 8 // Start pointing to cmd byte
tri_strip_fan_loop:
    lw      cmd_w1_dram, 0(cmd_w0)       // Load tri indices to lower 3 bytes of word
    addi    $11, inputBufferPos, inputBufferEnd - 3 // Off end of command
    beq     $11, cmd_w0, run_next_DL_command // If off end of command, exit
     sll    $12, cmd_w1_dram, 24         // Put sign bit of vtx 3 in sign bit
    bltz    $12, run_next_DL_command     // If negative, exit
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Store non-shuffled indices
    bltz    $ra, tri_fan_store           // Finish handling G_TRIFAN
     addi   cmd_w0, cmd_w0, 1            // Increment
    andi    $11, cmd_w0, 1               // If odd, this is the 1st/3rd/5th tri
    bnez    $11, tri_main              // Draw as is
     srl    $12, cmd_w1_dram, 8          // Move vtx 2 to LSBs
    sb      cmd_w1_dram, 6(rdpCmdBufPtr) // Store vtx 3 to spot for 2
    j       tri_main
     sb     $12, 7(rdpCmdBufPtr)         // Store vtx 2 to spot for 3

tri_fan_store:
    lb      $11, (inputBufferEnd - 7)(inputBufferPos) // Load vtx 1
    j       tri_main
     sb     $11, 5(rdpCmdBufPtr)         // Store vtx 1

G_TRI2_handler:
G_QUAD_handler:
    jal     tri_main                     // Send second tri; return here for first tri
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Put second tri indices in temp memory
G_TRI1_handler:
    li      $ra, run_next_DL_command     // After done with this tri, run next cmd
    sw      cmd_w0, 4(rdpCmdBufPtr)      // Put first tri indices in temp memory
tri_main:
    lpv     $v27[0], 0(rdpCmdBufPtr)     // Load tri indexes to elems 5, 6, 7
    j       vtx_indices_to_addr          // elem 7 -> $3; rest in $v27
     li     $11, tri_return_from_addrs
tri_return_from_addrs:
    mfc2    $1, $v27[10]
    vcopy   $v4, $v27                    // Need vtx 2 addr in $v4 elem 6
    mfc2    $2, $v27[12]
    move    $4, $1                // Save original vertex 1 addr (pre-shuffle) for flat shading
    li      clipPolySelect, -1    // Normal tri drawing mode (check clip masks)
tri_noinit:
    // ra is next cmd, second tri in TRI2, or middle of clipping
tV1AtF equ $v5
tV2AtF equ $v7
tV3AtF equ $v9
tV1AtI equ $v18
tV2AtI equ $v19
tV3AtI equ $v21
    vnxor   tV1AtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    llv     $v6[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vnxor   tV2AtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vmov    $v6[6], $v27[5]         // elem 6 of v6 = vertex 1 addr
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vnxor   tV3AtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    lhu     $5, VTX_CLIP($1)
    vmov    $v8[6], $v27[7]         // elem 6 of v8 = vertex 3 addr
    lhu     $6, VTX_CLIP($2)
    vadd    $v2, vZero, $v6[1] // v2 all elems = y-coord of vertex 1
    lhu     $7, VTX_CLIP($3)
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    andi    $11, $5, CLIP_MOD_MASK_SCRN_ALL
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    and     $11, $6, $11
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    and     $11, $7, $11      // If there is any screen clipping plane where all three verts are past it...
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    bnez    $11, return_routine // ...whole tri is offscreen, cull.
     vmrg   $v14, $v6, $v4    // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    vor     $v3, vZero, $v31[5]   // 0x4000; some rounding factor
    lbu     $11, geometryModeLabel + 2  // Loads the geometry mode byte that contains face culling settings
    vmudh   $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    sra     $12, clipPolySelect, 31 // All 1s if negative, meaning clipping allowed
    vmadh   $v29, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    or      $5, $5, $6
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    or      $5, $5, $7        // If any verts are past any clipping plane...
    vmrg    $v10, $v6, $v4    // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    andi    $11, $11, G_CULL_BOTH >> 8  // Only look at culling bits, so we can use others for other mods
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    mfc2    $6, $v29[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    $v4, $v14, $v8    // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    and     $5, $5, $12       // ...which is in the set of currently enabled clipping planes (scaled for XY, screen for ZW)...
    vmrg    $v14, $v8, $v14   // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    // If tri crosses camera plane or scaled bounds, go directly to clipping
    andi    $12, $5, CLIP_MOD_MASK_SCAL_ALL | (CLIP_NEAR >> 4)
    vlt     $v6, $v6, $v2     // v6 (thrown out), VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    bnez    $12, ovl234_clipping_entrypoint // Backface info is garbage, don't check it
     lw     $11, (gCullMagicNumbers)($11)
    vmrg    $v2, $v4, $v10   // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    beqz    $6, return_routine  // If cross product is 0, tri is degenerate (zero area), cull.
     add    $11, $6, $11        // Add magic number; see description at gCullMagicNumbers
    vmrg    $v10, $v10, $v4   // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    bgez    $11, return_routine // If sign bit is clear, cull.
     vmudn  $v4, $v14, $v31[5] // 0x4000
    mfc2    $1, $v14[12]      // $v14 = lowest Y value = highest on screen (x, y, addr)
    vsub    $v6, $v2, $v14
    mfc2    $2, $v2[12]       // $v2 = mid vertex (x, y, addr)
    vsub    $v8, $v10, $v14
    mfc2    $3, $v10[12]      // $v10 = highest Y value = lowest on screen (x, y, addr)
    vsub    $v11, $v14, $v2
    lw      $6, geometryModeLabel
    vsub    $v12, $v14, $v10  // VH - VL (negative)
    llv     $v13[0], VTX_INV_W_VEC($1)
    vsub    $v15, $v10, $v2
    llv     $v13[8], VTX_INV_W_VEC($2)
    vmudh   $v16, $v6, $v8[0]
    llv     $v13[12], VTX_INV_W_VEC($3)
    vmadh   $v16, $v8, $v11[0]
    lpv     tV1AtI[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
    vreadacc $v17, ACC_UPPER
    lpv     tV2AtI[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vreadacc $v16, ACC_MIDDLE
    lpv     tV3AtI[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vmov    $v15[2], $v6[0]
    lpv     $v25[0], VTX_COLOR_VEC($4)  // Load RGB from vertex 4 (flat shading vtx)
    vrcp    $v20[0], $v15[1]
    sll     $11, $6, 10                 // Moves the value of G_SHADING_SMOOTH into the sign bit
    vrcph   $v22[0], $v17[1]
    // TODO If everything else is done and we still have an instruction to spare,
    // this will prevent a hang if G_TEXTURE_ENABLE is set in the geometry mode
    //andi    $6, $6, (G_SHADE | G_ZBUFFER)
    vrcpl   $v23[1], $v16[1]
    bltz    $11, tri_skip_flat_shading  // Branch if G_SHADING_SMOOTH is set
     vrcph  $v24[1], vZero[0]
    vlt     $v29, $v31, $v31[3]         // Set vcc to 11100000
    vmrg    tV1AtI, $v25, tV1AtI        // RGB from $4, alpha from $1
    vmrg    tV2AtI, $v25, tV2AtI        // RGB from $4, alpha from $2
    vmrg    tV3AtI, $v25, tV3AtI        // RGB from $4, alpha from $3
tri_skip_flat_shading:
    vrcp    $v20[2], $v6[1]
    lb      $20, alphaCompareCullMode($zero)
    vrcph   $v22[2], $v6[1]
    lw      $5, VTX_INV_W_VEC($1)
    vrcp    $v20[3], $v8[1]
    lw      $7, VTX_INV_W_VEC($2)
    vrcph   $v22[3], $v8[1]
    lw      $8, VTX_INV_W_VEC($3)
    vmudl   tV1AtI, tV1AtI, $v30[3] // 0x0100; vertex color 1 >>= 8
    lbu     $9, textureSettings1 + 3
    vmudl   tV2AtI, tV2AtI, $v30[3] // 0x0100; vertex color 2 >>= 8
    sub     $11, $5, $7
    vmudl   tV3AtI, tV3AtI, $v30[3] // 0x0100; vertex color 3 >>= 8
    sra     $12, $11, 31
    vmov    $v15[3], $v8[0]
    and     $11, $11, $12
    vmudl   $v29, $v20, $v30[7] // 0x0020
    beqz    $20, tri_skip_alpha_compare_cull
     sub    $5, $5, $11
    // Alpha compare culling
    vge     $v26, tV1AtI, tV2AtI
    lbu     $19, alphaCompareCullThresh
    vlt     $v27, tV1AtI, tV2AtI
    bgtz    $20, @@skip1
     vge    $v26, $v26, tV3AtI // If alphaCompareCullMode > 0, $v26 = max of 3 verts
    vlt     $v26, $v27, tV3AtI // else if < 0, $v26 = min of 3 verts
@@skip1: // $v26 elem 3 has max or min alpha value
    mfc2    $24, $v26[6]
    sub     $24, $24, $19 // sign bit set if (max/min) < thresh
    xor     $24, $24, $20 // invert sign bit if other cond. Sign bit set -> cull
    bltz    $24, return_routine // if max < thresh or if min >= thresh.
tri_skip_alpha_compare_cull:
     vmadm  $v22, $v22, $v30[7] // 0x0020
    sub     $11, $5, $8
    vmadn   $v20, vZero, vZero[0]
    sra     $12, $11, 31
    vmudm   $v25, $v15, $v30[2] // 0x1000
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
    lsv     tV2AtI[14], VTX_SCR_Z($2)
    vmadh   $v15, $v25, $v22
    lsv     tV3AtI[14], VTX_SCR_Z($3)
    vmudl   $v29, $v23, $v16
    lsv     tV2AtF[14], VTX_SCR_Z_FRAC($2)
    vmadm   $v29, $v24, $v16
    lsv     tV3AtF[14], VTX_SCR_Z_FRAC($3)
    vmadn   $v16, $v23, $v17
    ori     $11, $6, G_TRI_FILL // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadh   $v17, $v24, $v17
    or      $11, $11, $9 // Incorporate whether textures are enabled into the triangle command id
    vand    $v22, $v20, $v30[5] // 0xFFF8
    vcr     $v15, $v15, $v30[3] // 0x0100
    sb      $11, 0x0000(rdpCmdBufPtr) // Store the triangle command id
    vmudh   $v29, vOne, $v30[6] // 0x0010
    ssv     $v10[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
    vmadn   $v16, $v16, $v30[4] // -16
    ssv     $v2[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadh   $v17, $v17, $v30[4] // -16
    ssv     $v14[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
    vmudn   $v29, $v3, $v14[0]
    andi    $12, $5, 0x0080 // Extract the left major flag from $5
    vmadl   $v29, $v22, $v4[1]
    or      $12, $12, $7 // Combine the left major flag with the level and tile from the texture settings
    vmadm   $v29, $v15, $v4[1]
    sb      $12, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vmadn   $v2, $v22, $v26[1]
    beqz    $9, tri_skip_tex // If textures are not enabled, skip texture coefficient calculation
     vmadh  $v3, $v15, $v26[1]
    vrcph   $v29[0], $v27[0]
    vrcpl   $v10[0], $v27[1]
    vadd    $v14, vZero, $v13[1q]
    vrcph   $v27[0], vZero[0]
    vor     $v22, vZero, $v31[7] // 0x7FFF
    vmudm   $v29, $v13, $v10[0]
    vmadl   $v29, $v14, $v10[0]
    llv     $v22[0], VTX_TC_VEC($1)
    vmadn   $v14, $v14, $v27[0]
    llv     $v22[8], VTX_TC_VEC($2)
    vmadh   $v13, $v13, $v27[0]
    vor     $v10, vZero, $v31[7] // 0x7FFF
    vge     $v29, $v30, $v30[7] // Set VCC to 11110001; select RGBA___Z or ____STW_
    llv     $v10[8], VTX_TC_VEC($3)
    vmudm   $v29, $v22, $v14[0h]
    vmadh   $v22, $v22, $v13[0h]
    vmadn   $v25, vZero, vZero[0]
    vmudm   $v29, $v10, $v14[6]     // acc = (v10 * v14[6]); v29 = mid(clamp(acc))
    vmadh   $v10, $v10, $v13[6]     // acc += (v10 * v13[6]) << 16; v10 = mid(clamp(acc))
    vmadn   $v13, vZero, vZero[0]   // v13 = lo(clamp(acc))
    sdv     $v22[0], 0x0020(rdpCmdBufPtr)
    vmrg    tV2AtI, tV2AtI, $v22 // Merge S, T, W into elems 4-6
    sdv     $v25[0], 0x0028(rdpCmdBufPtr) // 8
    vmrg    tV2AtF, tV2AtF, $v25 // Merge S, T, W into elems 4-6
    ldv     tV1AtI[8], 0x0020(rdpCmdBufPtr) // 8
    vmrg    tV3AtI, tV3AtI, $v10 // Merge S, T, W into elems 4-6
    ldv     tV1AtF[8], 0x0028(rdpCmdBufPtr) // 8
    vmrg    tV3AtF, tV3AtF, $v13 // Merge S, T, W into elems 4-6
tri_skip_tex:
    vmudl   $v29, $v16, $v23
    lsv     tV1AtF[14], VTX_SCR_Z_FRAC($1)
    vmadm   $v29, $v17, $v23
    lsv     tV1AtI[14], VTX_SCR_Z($1)
    vmadn   $v23, $v16, $v24
    lh      $1, VTX_SCR_VEC($2)
    vmadh   $v24, $v17, $v24
    addi    $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
// tV*At* contains R, G, B, A, S, T, W, Z. tD31* = vtx 3 - vtx 1, tD21* = vtx 2 - vtx 1
tD31F equ $v10
tD31I equ $v9
tD21F equ $v13
tD21I equ $v7
    vsubc   tD31F, tV3AtF, tV1AtF
    andi    $3, $6, G_SHADE
    vsub    tD31I, tV3AtI, tV1AtI
    sll     $1, $1, 14
    vsubc   tD21F, tV2AtF, tV1AtF
    sw      $1, 0x0008(rdpCmdBufPtr)         // Store XL edge coefficient
    vsub    tD21I, tV2AtI, tV1AtI
    ssv     $v3[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
// DaDx = (v3 - v1) * factor + (v2 - v1) * factor
tDaDxF equ $v2
tDaDxI equ $v3
    vmudn   $v29, tD31F, $v6[1]
    ssv     $v2[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vmadh   $v29, tD31I, $v6[1]
    ssv     $v3[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vmadn   $v29, tD21F, $v12[1]
    ssv     $v2[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
    vmadh   $v29, tD21I, $v12[1]
    ssv     $v15[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vreadacc tDaDxF, ACC_MIDDLE
    ssv     $v20[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vreadacc tDaDxI, ACC_UPPER
    ssv     $v15[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
// DaDy = (v2 - v1) * factor + (v3 - v1) * factor
tDaDyF equ $v6
tDaDyI equ $v7
    vmudn   $v29, tD21F, $v8[0]
    ssv     $v20[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vmadh   $v29, tD21I, $v8[0]
    ssv     $v15[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vmadn   $v29, tD31F, $v11[0]
    ssv     $v20[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
    vmadh   $v29, tD31I, $v11[0]
    sll     $11, $3, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vreadacc tDaDyF, ACC_MIDDLE
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vreadacc tDaDyI, ACC_UPPER
    sll     $11, $9, 5              // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
// DaDx, DaDy *= more factors
    vmudl   $v29, tDaDxF, $v23[1]
    add     rdpCmdBufPtr, $1, $11   // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, tDaDxI, $v23[1]
    andi    $6, $6, G_ZBUFFER       // Get the value of G_ZBUFFER from the current geometry mode
    vmadn   tDaDxF, tDaDxF, $v24[1]
    sll     $11, $6, 4              // Shift (geometry mode & G_ZBUFFER) by 4 to get 0x10 if G_ZBUFFER is set
    vmadh   tDaDxI, tDaDxI, $v24[1]
    add     rdpCmdBufPtr, rdpCmdBufPtr, $11  // Increment the triangle pointer by 0x10 bytes (depth coefficients) if G_ZBUFFER is set
    vmudl   $v29, tDaDyF, $v23[1]
    vmadm   $v29, tDaDyI, $v23[1]
    vmadn   tDaDyF, tDaDyF, $v24[1]
    sdv     tDaDxF[0], 0x0018($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   tDaDyI, tDaDyI, $v24[1]
    sdv     tDaDxI[0], 0x0008($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
// DaDe = DaDx * factor
tDaDeF equ $v8
tDaDeI equ $v9
    vmadl   $v29, tDaDxF, $v20[3]
    sdv     tDaDxF[8], 0x0018($1)   // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadm   $v29, tDaDxI, $v20[3]
    sdv     tDaDxI[8], 0x0008($1)   // Store DsDx, DtDx, DwDx texture coefficients (integer)
    vmadn   tDaDeF, tDaDxF, $v15[3]
    sdv     tDaDyF[0], 0x0038($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   tDaDeI, tDaDxI, $v15[3]
    sdv     tDaDyI[0], 0x0028($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
// Base value += DaDe * factor
    vmudn   $v29, tV1AtF, vOne[0]
    sdv     tDaDyF[8], 0x0038($1)   // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadh   $v29, tV1AtI, vOne[0]
    sdv     tDaDyI[8], 0x0028($1)   // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadl   $v29, tDaDeF, $v4[1]
    sdv     tDaDeF[0], 0x0030($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadm   $v29, tDaDeI, $v4[1]
    sdv     tDaDeI[0], 0x0020($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    vmadn   tV1AtF, tDaDeF, $v26[1]
    sdv     tDaDeF[8], 0x0030($1)   // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    vmadh   tV1AtI, tDaDeI, $v26[1]
    sdv     tDaDeI[8], 0x0020($1)   // Store DsDe, DtDe, DwDe texture coefficients (integer)
tV1AtFF equ $v10
    vmudn   tV1AtFF, tDaDeF, $v4[1] // Super-frac (frac * frac) part; assumes v4 factor >= 0
    vmudn   tDaDeF, tDaDeF, $v30[7] // 0x0020
    vmadh   tDaDeI, tDaDeI, $v30[7] // 0x0020
    sdv     tV1AtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    vmudn   tDaDxF, tDaDxF, $v30[7] // 0x0020
    sdv     tV1AtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    vmadh   tDaDxI, tDaDxI, $v30[7] // 0x0020
    sdv     tV1AtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    vmudn   tDaDyF, tDaDyF, $v30[7] // 0x0020
    beqz    $6, check_rdp_buffer_full // see below
     sdv    tV1AtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)
    vmadh   tDaDyI, tDaDyI, $v30[7] // 0x0020
    ssv     tDaDeF[14], -0x0006(rdpCmdBufPtr)
    vmudl   $v29,  tV1AtFF, $v30[7] // 0x0020
    ssv     tDaDeI[14], -0x0008(rdpCmdBufPtr)
    vmadn   tV1AtF, tV1AtF, $v30[7] // 0x0020
    ssv     tDaDxF[14], -0x000A(rdpCmdBufPtr)
    vmadh   tV1AtI, tV1AtI, $v30[7] // 0x0020
    ssv     tDaDxI[14], -0x000C(rdpCmdBufPtr)
    ssv     tDaDyF[14], -0x0002(rdpCmdBufPtr)
    ssv     tDaDyI[14], -0x0004(rdpCmdBufPtr)
    ssv     tV1AtF[14], -0x000E(rdpCmdBufPtr)
    j       check_rdp_buffer_full   // eventually returns to $ra, which is next cmd, second tri in TRI2, or middle of clipping
     ssv    tV1AtI[14], -0x10(rdpCmdBufPtr)

load_overlay_0_and_enter:
G_LOAD_UCODE_handler:
    li      postOvlRA, 0x1000                        // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)            // Sets up ovl0 table address
// To use these: set postOvlRA ($12) to the address to execute after the load is
// done, and set cmd_w1_dram to orga(your_overlay).
load_overlays_0_1:
    li      dmaLen, ovl01_end - 0x1000 - 1
    j       load_overlay_inner
     li     dmemAddr, 0x1000
load_overlays_2_3_4:
    li      dmaLen, ovl234_end - ovl234_start - 1
    li      dmemAddr, ovl234_start
load_overlay_inner:
    lw      $11, OSTask + OSTask_ucode
    jal     dma_read_write
     add    cmd_w1_dram, cmd_w1_dram, $11
    move    $ra, postOvlRA
    // Fall through to while_wait_dma_busy
    
totalImemUseUpTo1FC8:

.if . > 0x1FC8
    .error "Constraints violated on what can be overwritten at end of ucode (relevant for G_LOAD_UCODE)"
.endif
.org 0x1FC8

while_wait_dma_busy:
    mfc0    $11, SP_DMA_BUSY    // Load the DMA_BUSY value
while_dma_busy:
    bnez    $11, while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   $11, SP_DMA_BUSY    // Update DMA_BUSY value
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
    jr      $ra
     mtc0   dmaLen, SP_RD_LEN         // Initiate a DMA read with a length of dmaLen
dma_write:
    jr      $ra
     mtc0   dmaLen, SP_WR_LEN         // Initiate a DMA write with a length of dmaLen

.if . > 0x00002000
    .error "Not enough room in IMEM"
.endif

.headersize 0x00001000 - orga()

// Overlay 0 controls the RDP and also stops the RSP when work is done
// The action here is controlled by $1. If yielding, $1 > 0. If this was
// G_LOAD_UCODE, $1 == 0. If we got to the end of the parent DL, $1 < 0.
ovl0_start:
    sub     $11, rdpCmdBufPtr, rdpCmdBufEnd
    addi    $12, $11, RDP_CMD_BUFSIZE - 1
    bgezal  $12, flush_rdp_buffer
     nop
    jal     while_wait_dma_busy
     lw     $24, rdpFifoPos
    bltz    $1, taskdone_and_break  // $1 < 0 = Got to the end of the parent DL
     mtc0   $24, DPC_END            // Set the end pointer of the RDP so that it starts the task
    bnez    $1, task_yield          // $1 > 0 = CPU requested yield
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
// If here, G_LOAD_UCODE was executed.
    lw      cmd_w1_dram, (inputBufferEnd - 0x04)(inputBufferPos) // word 1 = ucode code DRAM addr
    sw      taskDataPtr, OSTask + OSTask_data_ptr // Store where we are in the DL
    sw      cmd_w1_dram, OSTask + OSTask_ucode // Store pointer to new ucode about to execute
    li      dmemAddr, start         // Beginning of overwritable part of IMEM
    jal     dma_read_write          // DMA DRAM read -> IMEM write
     li     dmaLen, (while_wait_dma_busy - start) - 1 // End of overwritable part of IMEM
    lw      cmd_w1_dram, rdpHalf1Val // Get DRAM address of ucode data from rdpHalf1Val
    li      dmemAddr, endSharedDMEM // DMEM address is endSharedDMEM
    andi    dmaLen, cmd_w0, 0x0FFF  // Extract DMEM length from command word
    add     cmd_w1_dram, cmd_w1_dram, dmemAddr // Start overwriting data from endSharedDMEM
    jal     dma_read_write          // initate DMA read
     sub    dmaLen, dmaLen, dmemAddr // End that much before the end of DMEM
    j       while_wait_dma_busy
    // Jumping to actual start of new ucode, which normally zeros vZero. Not sure why later ucodes
    // jumped one instruction in.
     li     $ra, start

.if . > start
    .error "ovl0_start does not fit within the space before the start of the ucode loaded with G_LOAD_UCODE"
.endif

ucode equ $11
status equ $12
task_yield:
    lw      ucode, OSTask + OSTask_ucode
    sw      taskDataPtr, OS_YIELD_DATA_SIZE - 8
    sw      ucode, OS_YIELD_DATA_SIZE - 4
    li      status, SP_SET_SIG1 | SP_SET_SIG2   // yielded and task done signals
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    li      dmemAddr, 0x8000 // 0, but negative = write
    li      dmaLen, OS_YIELD_DATA_SIZE - 1
    j       dma_read_write
     li     $ra, break

taskdone_and_break:
    li      status, SP_SET_SIG2   // task done signal
break:
    mtc0    status, SP_STATUS
    break   0
    nop

ovl0_end:
.align 8
ovl0_padded_end:

.if ovl0_padded_end > ovl01_end
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
    bltz    $2, displaylist_dma_with_count  // If the operation is nopush (branch) then simply DMA the new displaylist
     move   taskDataPtr, cmd_w1_dram    // Set the task data pointer to the target display list
    sw      $3, (displayListStack)($1)
    addi    $1, $1, 4                   // Increment the DL stack length
call_ret_common:
    j       displaylist_dma_with_count
     sb     $1, displayListStackLength

G_TEXTURE_handler:
    li      $11, textureSettings1 - (texrectWord1 - G_TEXRECTFLIP_handler)  // Calculate the offset from texrectWord1 and $11 for saving to textureSettings
G_TEXRECT_handler: // $11 contains address of handler
G_TEXRECTFLIP_handler:
    // Stores first command word into textureSettings for gSPTexture, 0x00D0 for gSPTextureRectangle/Flip
    sw      cmd_w0, (texrectWord1 - G_TEXRECTFLIP_handler)($11)
G_RDPHALF_1_handler:
    j       run_next_DL_command
    // Stores second command word into textureSettings for gSPTexture, 0x00D4 for gSPTextureRectangle/Flip, 0x00D8 for G_RDPHALF_1
     sw     cmd_w1_dram, (texrectWord2 - G_TEXRECTFLIP_handler)($11)
     
G_SETSCISSOR_handler:
    li      $11, scissorUpLeft - (otherMode0 - G_RDPSETOTHERMODE_handler)
G_RDPSETOTHERMODE_handler: // $11 contains address of handler
    sw      cmd_w0, (otherMode0 - G_RDPSETOTHERMODE_handler)($11) // Record the local otherMode0 copy
    j       G_RDP_handler            // Send the command to the RDP
     sw     cmd_w1_dram, (otherMode1 - G_RDPSETOTHERMODE_handler)($11) // Record the local otherMode1 copy

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
     sb     $zero, mITValid

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
    add     $7, $7, $2        // Add the load type to the command byte in $7, selects the return address based on whether the matrix needs multiplying or just loading
    sb      $zero, mITValid
G_MOVEMEM_handler:
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
do_movemem:
     andi   $1, cmd_w0, 0x00FE                              // Move the movemem table index into $1 (bits 1-7 of the first command word)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Move the second byte of the first command word into dmaLen
    lhu     dmemAddr, (movememTable)($1)                    // Load the address of the memory location for the given movemem index
    srl     $2, cmd_w0, 5                                   // ((w0) >> 8) << 3; top 3 bits of idx must be 0; lower 1 bit of len byte must be 0
    lh      $ra, (movememHandlerTable - (G_POPMTX | 0xFF00))($7)  // Loads the return address from movememHandlerTable based on command byte
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

G_FLAGSOPBASE_handler:
    lw      $1, cullFlags
    sll     $11, $7, 30             // Shift bit 1 of cmd (none / all) into sign bit
    sra     $11, $11, 31            // Copy to all bits
    xor     $1, $1, $11             // Invert current flags if all / notall
    and     $1, $1, cmd_w0          // Mask to only the flags we care about
    sltiu   $1, $1, 1               // Set bit 0 if less than 1 unsigned (== 0)
    xor     $1, $1, $7              // Invert condition if some / notall
    andi    $1, $1, 1               // Only look at bit 0; is 1 if flags cond met
    beqz    $1, run_next_DL_command // Condition not met
     addi   $11, $7, -(G_FLAGSOPBASE + G_FLAGSOP_CALL)
    bltz    $11, end_dl_no_count    // Was one of the cull commands
     sll    $2, $7, 28              // Put bit 3 (1=branch, 0=call) into sign bit of $2
branch_dl_no_count:
    j       branch_dl               // Call or branch based on $2 < 0
     la     cmd_w0, 0               // Clear count of DL cmds to skip loading

G_FLAGSMASKS_handler:
    li      $7, (cullFlags - geometryModeLabel - (0x100 - G_GEOMETRYMODE))
G_GEOMETRYMODE_handler: // $7 = G_GEOMETRYMODE (as negative) if jumped here
    lw      $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7) // load the geometry mode value
    and     $11, $11, cmd_w0        // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      $11, $11, cmd_w1_dram   // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    j       run_next_DL_command     // run the next DL command
     sw     $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7)  // update the geometry mode value

ovl1_end:
.align 8
ovl1_padded_end:

.if ovl1_padded_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif

.headersize ovl234_start - orga()

ovl2_start:
ovl234_lighting_entrypoint:
    vmrg    vPairNrml, $v28, $v26          // Merge normals
    j       lt_continue_setup
     andi   $11, $5, G_PACKED_NORMALS >> 8

ovl234_ovl4_entrypoint_ovl2ver: // same IMEM address as ovl234_ovl4_entrypoint
    li      cmd_w1_dram, orga(ovl4_start)        // set up a load for overlay 4
    j       load_overlays_2_3_4                  // load overlay 4
     li     postOvlRA, ovl234_ovl4_entrypoint    // set the return address

ovl234_clipping_entrypoint_ovl2ver:  // same IMEM address as ovl234_clipping_entrypoint
    sh      $ra, tempHalfword1
    li      cmd_w1_dram, orga(ovl3_start)     // set up a load of overlay 3
    j       load_overlays_2_3_4               // load overlay 3
     li     postOvlRA, ovl3_clipping_nosavera // set up the return address in ovl3

lt_continue_setup:
    // Inputs: vPairPosI/F vertices pos world int:frac, vPairRGBA, vPairST,
    // $v28 vPairNrml, $v30:$v25 (to be merged) packed normals
    // Outputs: vPairRGBA, vPairST, must leave alone vPairPosI/F
    // Locals: $v29 temp, $v23 (will be vPairTPosF), $v24 (will be vPairTPosI),
    // $v25 (after merge), $v26, whichever of $v28 or $v30 is unused
    // Use $v10 (vVP2I) as an extra local, restore before return
    beqz    $11, lt_skip_packed_normals
     vmrg   $v30, $v30, $v25          // Merge packed normals
    // Packed normals algorithm. This produces a vector (one for each input vertex)
    // in vPairNrml such that |X| + |Y| + |Z| = 0x7F00 (called L1 norm), in the
    // same direction as the standard normal vector. The length is not "correct"
    // compared to the standard normal, but it's is normalized anyway after the M
    // matrix transform.
    vand    vPackPXY, $v30, $v31[6]       // 0x7F00; positive X, Y
    vclr    $v29                         // Zero
    vaddc   vPackZ, vPackPXY, vPackPXY[1q]    // elem 0, 4: pos X + pos Y, no clamping
    vadd    $v26, $v29, $v29             // Save carry bit, indicates use 0x7F00 - x and y
    vxor    vPairNrml, vPackPXY, $v31[6]   // 0x7F00 - x, 0x7F00 - y
    vxor    vPackZ, vPackZ, $v31[6]            // 0x7F00 - +X - +Y in elems 0, 4
    vne     $v29, $v29, $v26[0h]         // set 0-3, 4-7 vcc if (+X + +Y) overflowed, discard result
    vmrg    vPairNrml, vPairNrml, vPackPXY  // If so, use 0x7F00 - +X, else +X (same for Y)
    vne     $v29, $v31, $v31[2h]         // set VCC to 11011101
    vabs    vPairNrml, $v30, vPairNrml     // Apply sign of original X and Y to new X and Y
    vmrg    vPairNrml, vPairNrml, vPackZ[0h]  // Move Z to elements 2, 6
lt_skip_packed_normals:
    // Transform normals by M, in case normalsMode = G_NORMALSMODE_FAST.
    vclr    vLtOne
    vsub    vPairRGBA, vPairRGBA, $v31[7] // 0x7FFF; offset alpha, will be fixed later
    lbu     curLight, numLightsxSize
    vmudn   $v29, vM0F, vPairNrml[0h]
    lbu     $11, normalsMode($zero)
    vmadh   $v29, vM0I, vPairNrml[0h]
    vmadn   $v29, vM1F, vPairNrml[1h]
    addi    curLight, curLight, altBase // Point to ambient light
    vmadh   $v29, vM1I, vPairNrml[1h]
    vmadn   $v10, vM2F, vPairNrml[2h] // $v10 = normals frac
    vmadh   $v23, vM2I, vPairNrml[2h] // $v23 = normals int
    beqz    $11, lt_after_xfrm_normals // Skip if G_NORMALSMODE_FAST
     vadd   vLtOne, vLtOne, $v31[2] // 1; vLtOne = 1
    // Transform normals by M inverse transpose, for G_NORMALSMODE_AUTO or G_NORMALSMODE_MANUAL
    lqv     vLtMIT0I,    (mITMatrix + 0x00)($zero) // x int, y int
    lqv     vLtMIT2I,    (mITMatrix + 0x10)($zero) // z int, x frac
    lqv     vLtMIT1F,    (mITMatrix + 0x20)($zero) // y frac, z frac
    vcopy   vLtMIT1I, vLtMIT0I
    vcopy   vLtMIT0F, vLtMIT2I
    ldv     vLtMIT1I[0], (mITMatrix + 0x08)($zero)
    vcopy   vLtMIT2F, vLtMIT1F
    ldv     vLtMIT0F[0], (mITMatrix + 0x18)($zero)
    ldv     vLtMIT0I[8], (mITMatrix + 0x00)($zero)
    ldv     vLtMIT1F[8], (mITMatrix + 0x20)($zero)
    ldv     vLtMIT2F[0], (mITMatrix + 0x28)($zero)
    ldv     vLtMIT2I[8], (mITMatrix + 0x10)($zero)
    // Transform normals by M inverse transpose matrix.
    // At this point we have stuffed two and three quarters matrices into registers at once.
    // Nintendo was only able to fit one and three quarters matrices into registers at once.
    // ($v10 is stolen from VP but $v24=vLtOne could be available here, so if we
    // swapped the use below of those two regs and moved down the init of vLtOne, it
    // really would be the full 2 & 3/4 matrices.) This is 22/32 registers full of matrices.
    // The remaining 10 registers are: vVp/ST Scl/Ofs and $v31 constants, vPairPosI/F,
    // vPairST, vPairRGBA, vPairNrml.
    vmudn   $v29, vLtMIT0F, vPairNrml[0h] // vLtMIT0F = $v29
    vmadh   $v29, vLtMIT0I, vPairNrml[0h]
    vmadn   $v29, vLtMIT1F, vPairNrml[1h]
    vmadh   $v29, vLtMIT1I, vPairNrml[1h]
    vmadn   $v10, vLtMIT2F, vPairNrml[2h] // vLtMIT2F = $v10 = normals frac
    vmadh   $v23, vLtMIT2I, vPairNrml[2h] // vLtMIT2I = $v23 = normals int
lt_after_xfrm_normals:
    // Normalize normals; in $v23:$v10 i/f, out $v23
    jal     lt_normalize
     luv    vPairLt, (ltBufOfs + 0)(curLight) // Total light level, init to ambient
    // Set up ambient occlusion: light *= (factor * (alpha - 1) + 1)
    vmudm   $v25, vPairRGBA, vSTOfs[2] // (alpha - 1) * aoAmb factor; elems 3, 7
    //sll     $12, $5, 17 // G_LIGHTING_POSITIONAL = 0x00400000; $5 is middle 16 bits so 0x00004000
    vcopy   vPairNrml, $v23
    //sra     $12, $12, 31 // All 1s if point lighting enabled, else all 0s
    vadd    $v25, $v25, $v31[7] // 0x7FFF = 1 in s.15; elems 3, 7
    vmulf   vPairLt, vPairLt, $v25[3h] // light color *= ambient factor
lt_loop:
    // vPairPosI/F, vPairST, $v23 light pos/dir (then local), $v10 $v25 locals,
    // vLtColor, vPairRGBA, vPairNrml, $v29 temp, vPairLt, vLtOne
    lpv     $v23[0], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 0-2
    vlt     $v29, $v31, $v31[4] // Set VCC to 11110000
    lpv     $v25[4], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 4-6
    lbu     $11,     (ltBufOfs + 3 - lightSize)(curLight) // Light type / constant attenuation
    beq     curLight, altBaseReg, lt_post
     vmrg   $v23, $v23, $v25                              // $v23 = light direction
    //and     $11, $11, $12 // Mask away if point lighting disabled
    bnez    $11, lt_point
     luv    vLtColor,    (ltBufOfs + 0 - lightSize)(curLight) // Light color
    vmulf   $v23, $v23, vPairNrml // Light dir * normalized normals
    vmudh   $v29, vLtOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   $v10, vPairRGBA, vSTOfs[6] // + (alpha - 1) * aoDir factor
    vmudh   $v29, vLtOne, $v23[0h] // Sum components of dot product as signed
    vmadh   $v29, vLtOne, $v23[1h]
    vmadh   $v23, vLtOne, $v23[2h]
    vmulf   vLtColor, vLtColor, $v10[3h] // light color *= ambient or point light factor
    vge     $v23, $v23, vSTOfs[3] // Clamp dot product to >= 0
lt_finish_light:
    addi    curLight, curLight, -lightSize
    vmudh   $v29, vLtOne, vPairLt // Load accum mid with current light level
    j       lt_loop
     vmacf  vPairLt, vLtColor, $v23[0h] // + light color * dot product

lt_post:
    vadd    vPairRGBA, vPairRGBA, $v31[7] // 0x7FFF; undo change for ambient occlusion
    andi    $11, $5, G_LIGHTTOALPHA >> 8
    andi    $20, $5, G_PACKED_NORMALS >> 8
    andi    $12, $5, G_TEXTURE_GEN >> 8
    vmulf   vLtRGBOut, vPairRGBA, vPairLt     // RGB output is RGB * light
    beqz    $11, lt_skip_cel
     vcopy  vLtAOut, vPairRGBA             // Alpha output = vertex alpha (only 3, 7 matter)
    // Cel: alpha = max of light components, RGB = vertex color
    vge     vLtAOut, vPairLt, vPairLt[1h]  // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    vge     vLtAOut, vLtAOut, vLtAOut[2h]  // elem 0 = max(R0, G0, B0); equiv for elem 4
    vcopy   vLtRGBOut, vPairRGBA             //      RGB output is vertex color
    vmudh   vLtAOut, vLtOne, vLtAOut[0h]   // move elem 0, 4 to 3, 7
lt_skip_cel:
    vne     $v29, $v31, $v31[3h]        // Set VCC to 11101110
    bnez    $20, lt_skip_novtxcolor
     andi   $24, $5, G_FRESNEL >> 8
    vcopy   vLtRGBOut, vPairLt                // If no packed normals, base output is just light
lt_skip_novtxcolor:
    vmulf   vLookat0, vPairNrml, $v23        // Normal * lookat 0 dir; vLookat0 = $v30 = vPairLt
    beqz    $24, lt_skip_fresnel
     vmrg   vPairRGBA, vLtRGBOut, vLtAOut       // Merge base output and alpha output
    // Fresnel: call point lighting; camera pos in $v23
    ldv     $v23[0], (cameraWorldPos - altBase)(altBaseReg) // Camera world pos
    j       lt_normal_to_vertex
     ldv    $v23[8], (cameraWorldPos - altBase)(altBaseReg)
lt_finish_fresnel: // output in $v23
    llv     $v10[0], (fresnelOffset - altBase)(altBaseReg) // Load fresnel offset and scale
    vabs    $v23, $v23, $v23            // Absolute value
    vmudn   $v26, $v31, $v10[1]         // Elem 4 = low part of 0x0100 * scale
    vmadh   $v25, $v31, vSTOfs[3]     // + 0; elem 4 = high part of 0x0100 * scale
    vsub    $v23, $v23, $v10[0]         // Subtract offset
    vmudl   $v29, $v23, $v26[4]         // Unsigned Fresnel value * low part shifted scale
    vmadn   $v23, $v23, $v25[4]         // Alpha = unsigned Fresnel value * high part
    vmrg    vPairRGBA, vPairRGBA, $v23  // Merge base output and alpha output
lt_skip_fresnel:
    ldv     vVP2I[0], (vpMatrix  + 0x10)($zero) // Restore $v10 = vVP2I before returning
    beqz    $12, vtx_return_from_lighting // no texgen
     ldv    vVP2I[8], (vpMatrix  + 0x10)($zero)
    // Texgen: vLookat0, vLookat1, locals $v25, $v26, $v23, have vLtOne = $v24
    // Output: vPairST; have to leave vPairPosI/F, vPairRGBA
    vmudh   $v29, vLtOne, vLookat0[0h]
    lpv     vLookat1[4], (ltBufOfs + 0 - lightSize)(curLight) // Lookat 1 dir in elems 0-2
    vmadh   $v29, vLtOne, vLookat0[1h]
    lpv     $v26[0], (ltBufOfs + 8 - lightSize)(curLight) // Lookat 1 dir in elems 4-6
    vmadh   vLookat0, vLtOne, vLookat0[2h]      // vLookat0 = dot product 0
    vlt     $v29, $v31, $v31[4]         // Set VCC to 11110000
    vmrg    vLookat1, vLookat1, $v26            // vLookat1 = lookat 1 dir
    vmulf   vLookat1, vPairNrml, vLookat1        // Normal * lookat 1 dir
    vmudh   $v29, vLtOne, vLookat1[0h]
    vmadh   $v29, vLtOne, vLookat1[1h]
    vmadh   vLookat1, vLtOne, vLookat1[2h]      // vLookat1 = dot product 1
    vne     $v29, $v31, $v31[1h] // Set VCC to 10111011
    llv     $v23[0], (texgenLinearCoeffs - altBase)(altBaseReg)
    vmrg    vLookat0, vLookat0, vLookat1[0h]  // Dot products in elements 0, 1, 4, 5
    andi    $11, $5, G_TEXTURE_GEN_LINEAR >> 8
    vmudh   $v29, vLtOne, $v31[5]  // 1 * 0x4000
    beqz    $11, vtx_return_from_lighting
     vmacf  vPairST, vLookat0, $v31[5] // + dot products * 0x4000 ( / 2)
    // Texgen_Linear:
    vmulf   vPairST, vLookat0, $v31[5] // dot products * 0x4000 ( / 2)
    vmulf   $v26, vPairST, vPairST // ST squared
    vmulf   $v25, vPairST, $v31[7] // Move ST to accumulator (0x7FFF = 1)
    vmacf   $v25, vPairST, $v23[1] // + ST * 0x6CB3
    vmudh   $v29, vLtOne, $v31[5] // 1 * 0x4000
    vmacf   vPairST, vPairST, $v23[0] // + ST * 0x44D3
    j       vtx_return_from_lighting
     vmacf  vPairST, $v26, $v25 // + ST squared * (ST + ST * coeff)
     
lt_point:
    /*
    Input vector 1 elem size 7FFF.0000 -> len^2 3FFF0001 -> 1/len 0001.0040 -> vec +801E.FFC0 -> clamped 7FFF
        len^2 * 1/len = 400E.FFC1 so about half actual length
    Input vector 1 elem size 0100.0000 -> len^2 00010000 -> 1/len 007F.FFC0 -> vec  7FFF.C000 -> clamped 7FFF
        len^2 * 1/len = 007F.FFC0 so about half actual length
    Input vector 1 elem size 0010.0000 -> len^2 00000100 -> 1/len 07FF.FC00 -> vec  7FFF.C000
    Input vector 1 elem size 0001.0000 -> len^2 00000001 -> 1/len 7FFF.C000 -> vec  7FFF.C000
    */
    ldv     $v23[0], (ltBufOfs + 8 - lightSize)(curLight) // Light position int part 0-3
    ldv     $v23[8], (ltBufOfs + 8 - lightSize)(curLight) // 4-7
lt_normal_to_vertex:
    // This reused for fresnel; scalar unit stuff all garbage in that case
    // Input point (light / camera) in $v23; computes $v23 = (vPairNrml dot (input - vertex))
    // Uses temps $v10, $v25, $v26, $v29
    vclr    $v10                         // Zero light pos frac part
    vsubc   $v10, $v10, vPairPosF             // Vector from vertex to light, frac
    lbu     $20,     (ltBufOfs + 7 - lightSize)(curLight) // Linear factor
    vsub    $v23, $v23, vPairPosI             // Int
    jal     lt_normalize
     lbu    $24,     (ltBufOfs + 0xE - lightSize)(curLight) // Quadratic factor
    // $v23 = normalized vector from vertex to light, $v29[0h:1h] = 1/len, $v25 = len^2
    vmudm   $v10, $v25, $v29[1h] // len^2 int * 1/len frac
    vmadn   $v10, $v26, $v29[0h] // len^2 frac * 1/len int = len frac
    mtc2    $20, vPairLt[14] // Quadratic int part in elem 7
    vmadh   $v29, $v25, $v29[0h] // len^2 int * 1/len int = len int
    vmulf   $v23, $v23, vPairNrml // Normalized light dir * normalized normals
    vmudl   $v10, $v10, vPairNrml[7]   //   len frac * linear factor frac
    vmadm   $v10, $v29, vPairNrml[7]   // + len int * linear factor frac
    vmadm   $v10, vLtOne, vPairNrml[3] // + 1 * constant factor frac
    vmadl   $v10, $v26, vPairLt[3]     // + len^2 frac * quadratic factor frac
    vmadm   $v10, $v25, vPairLt[3]     // + len^2 int * quadratic factor frac
    vmadn   $v29, $v26, vPairLt[7]     // + len^2 frac * quadratic factor int
    vmadh   $v25, $v25, vPairLt[7]     // + len^2 int * quadratic factor int
    luv     vLtColor,    (ltBufOfs + 0 - lightSize)(curLight) // vLtColor = $v26
    vmudh   $v10, vLtOne, $v23[0h] // Sum components of dot product as signed
    vmadh   $v10, vLtOne, $v23[1h]
    beq     curLight, altBaseReg, lt_finish_fresnel // If finished light loop, is fresnel
     vmadh  $v23, vLtOne, $v23[2h]
    vrcph   $v10[1], $v25[0] // 1/(2*light factor), input of 0000.8000 -> no change normals
    vrcpl   $v10[2], $v29[0] // Light factor 0001.0000 -> normals /= 2
    vrcph   $v10[3], $v25[4] // Light factor 0000.1000 -> normals *= 8 (with clamping)
    vrcpl   $v10[6], $v29[4] // Light factor 0010.0000 -> normals /= 32
    vrcph   $v10[7], vSTOfs[3] // 0
    vge     $v23, $v23, vSTOfs[3] // Clamp dot product to >= 0
    vmudm   $v29, $v23, $v10[2h] // Dot product int * rcp frac
    j       lt_finish_light
     vmadh  $v23, $v23, $v10[3h] // Dot product int * rcp int, clamp to 0x7FFF

lt_normalize:
    // Normalize vector in $v23:$v10 i/f, output in $v23. Also continue point
    // light scalar unit stuff. Uses temps $v25, $v26, $v29, also $11, $20, $24
    // Also overwrites vPairNrml and vPairLt elems 3, 7
    vmudm   $v29, $v23, $v10             // Squared. Don't care about frac*frac term
    sll     $11, $11, 8                  // Constant factor, 00000100 - 0000FF00
    vmadn   $v29, $v10, $v23
    sll     $20, $20, 6                  // Linear factor, 00000040 - 00003FC0
    vmadh   $v29, $v23, $v23
    vreadacc $v26, ACC_MIDDLE
    vreadacc $v25, ACC_UPPER
    mtc2    $11, vPairNrml[6] // Constant frac part in elem 3
    vmudm   $v29, vLtOne, $v26[2h] // Sum of squared components
    vmadh   $v29, vLtOne, $v25[2h]
    srl     $11, $24, 5 // Top 3 bits
    vmadm   $v29, vLtOne, $v26[1h]
    mtc2    $20, vPairNrml[14] // Linear frac part in elem 7
    vmadh   $v29, vLtOne, $v25[1h]
    andi    $20, $24, 0x1F // Bottom 5 bits
    vmadn   $v26, $v26, vLtOne // elem 0; swapped so we can do vmadn and get result
    ori     $20, $20, 0x20 // Append leading 1 to mantissa
    vmadh   $v25, $v25, vLtOne
    sllv    $20, $20, $11 // Left shift to create floating point
    vrsqh   $v29[2], $v25[0] // High input, garbage output
    sll     $20, $20, 8 // Min range 00002000, 00002100... 00003F00, max 00100000...001F8000
    vrsql   $v29[1], $v26[0] // Low input, low output
    bnez    $24, @@skip // If original value is zero, set to zero
     vrsqh  $v29[0], $v25[4] // High input, high output
    li      $20, 0
@@skip:
    vrsql   $v29[5], $v26[4] // Low input, low output
    vrsqh   $v29[4], vSTOfs[3] // 0 input, high output
    mtc2    $20, vPairLt[6] // Quadratic frac part in elem 3
    vmudn   $v10, $v10, $v29[0h] // Vec frac * int scaling, discard result
    srl     $20, $20, 16
    vmadm   $v10, $v23, $v29[1h] // Vec int * frac scaling, discard result
    jr      $ra
     vmadh  $v23, $v23, $v29[0h] // Vec int * int scaling

ovl2_end:
.align 8
ovl2_padded_end:

.headersize ovl234_start - orga()

ovl4_start:
// Contains M inverse transpose (mIT) computation, and some rarely-used command handlers.

ovl234_lighting_entrypoint_ovl4ver:  // same IMEM address as ovl234_lighting_entrypoint
    li      cmd_w1_dram, orga(ovl2_start)        // set up a load for overlay 2
    j       load_overlays_2_3_4                  // load overlay 2
     li     postOvlRA, ovl234_lighting_entrypoint // set the return address

ovl234_ovl4_entrypoint:
    vclr    $v30                  // $v30 = 0 for calc_mit
    j       ovl4_select_instr
     li     $11, 1                // $7 = 1 (lighting & mIT invalid) if doing calc_mit

ovl234_clipping_entrypoint_ovl4ver:  // same IMEM address as ovl234_clipping_entrypoint
    sh      $ra, tempHalfword1
    li      cmd_w1_dram, orga(ovl3_start)     // set up a load of overlay 3
    j       load_overlays_2_3_4               // load overlay 3
     li     postOvlRA, ovl3_clipping_nosavera // set up the return address in ovl3

ovl4_select_instr:
    beq     $11, $7, calc_mit // otherwise $7 = command byte
     li     $12, G_MTX
    beq     $12, $7, G_MTX_end
     li     $11, G_BRANCH_WZ
    beq     $11, $7, G_BRANCH_WZ_handler
     li     $12, G_FLAGSDRAM
    beq     $12, $7, G_FLAGSDRAM_handler
     li     $11, G_MODIFYVTX
    beq     $11, $7, G_MODIFYVTX_handler
     li     $12, G_DMA_IO
    beq     $12, $7, G_DMA_IO_handler
     // Otherwise G_LIGHTTORDP, which starts with a harmless instruction

G_LIGHTTORDP_handler:
    lbu     $11, numLightsxSize          // Ambient light
    lbu     $1, (inputBufferEnd - 0x6)(inputBufferPos) // Byte 2 = light count from end * size
    andi    $2, cmd_w0, 0x00FF           // Byte 3 = alpha
    sub     $1, $11, $1                  // Light address; byte 2 counts from end
    lw      $3, (lightBufferMain)($1)    // Load light RGB
    move    cmd_w0, cmd_w1_dram          // Move second word to first (cmd byte, prim level)
    andi    $3, $3, 0xFF00               // Get rid of whatever was in alpha value
    j       G_RDP_handler                // Send to RDP
     or     cmd_w1_dram, $3, $2          // Combine RGB and alpha in second word
    
G_FLAGSDRAM_handler:
    jal     segmented_to_physical
     li     dmemAddr, tempMemRounded
    jal     dma_read_write
     li     dmaLen, 7
    jal     while_wait_dma_busy
     nop
    lw      cmd_w0, tempMemRounded($zero)
    j       G_FLAGSMASKS_handler
     lw     cmd_w1_dram, (tempMemRounded + 4)($zero)

G_DMA_IO_handler:
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra     dmemAddr, dmemAddr, 2
    j       dma_read_write  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     li     $ra, wait_for_dma_and_run_next_command  // Setup the return address for running the next DL command

G_MODIFYVTX_handler:
    j       vtx_addrs_from_cmd          // byte 3 = vtx being modified; addr -> $12
     li     $11, modifyvtx_return_from_addrs
modifyvtx_return_from_addrs:
    j       do_moveword                 // Moveword adds cmd_w0 to $12 for final addr
     lbu    cmd_w0, (inputBufferEnd - 0x07)(inputBufferPos)

G_BRANCH_WZ_handler:
    j       vtx_addrs_from_cmd          // byte 3 = vtx being tested; addr -> $12
     li     $11, branchwz_return_from_addrs
branchwz_return_from_addrs:
.if CFG_G_BRANCH_W                            // G_BRANCH_W/G_BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      $12, VTX_W_INT($12)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      $12, VTX_SCR_Z($12)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, $12, cmd_w1_dram           // subtract the w/z value being tested
    bgez    $2, run_next_DL_command           // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val          // load the RDPHALF1 value as the location to branch to
    j       branch_dl_no_count         // need $2 < 0 for nopush and cmd_w1_dram
     // Next instr is harmless

G_MTX_end: // Multiplies the temp loaded matrix into the M or VP matrix
output_mtx  equ $19
input_mtx_1 equ $20
input_mtx_0 equ $21
    lhu     output_mtx, (movememTable + G_MV_MMTX)($1) // $1 holds 0 for M or 4 for VP.
    move    input_mtx_0, output_mtx
    jal     while_wait_dma_busy // If ovl4 already in memory, was not done
     li     input_mtx_1, tempMemRounded
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
    j       run_next_DL_command
     sqv    $v6[0], 0x0010(output_mtx)

calc_mit:
    /*
    Compute M inverse transpose. All regs available except vM0I::vM3F and $v31.
    $v31 constants present, but no other constants.
    Register use (all only elems 0-2):
    $v8:$v9   X left rotated int:frac, $v10:$v11 X right rotated int:frac
    $v12:$v13 Y left rotated int:frac, $v14:$v15 Y right rotated int:frac
    $v16:$v17 Z left rotated int:frac, $v18:$v19 Z right rotated int:frac
    Rest temps.
    Scale factor can be arbitrary, but final matrix must only reduce a vector's
    magnitude (rotation * scale < 1). So want components of matrix to be < 0001.0000.
    However, if input matrix has components on the order of 0000.0100, multiplying
    two terms will reduce that to the order of 0000.0001, which kills all the precision.
    */
    // Get absolute value of all terms of M matrix.
    li      $12, mMatrix + 0xE                              // For right rotates with lrv/ldv
    vxor    $v20, vM0I, $v31[1] // One's complement of X int part
    sb      $7, mITValid                                     // $7 is 1 if we got here, mark valid
    vlt     $v29, vM0I, $v30[0] // X int part < 0
    li      $11, mMatrix + 2                                // For left rotates with lqv/ldv
    vabs    $v21, vM0I, vM0F     // Apply sign of X int part to X frac part
    lrv     $v10[0], (0x00)($12)                              // X int right shifted
    vxor    $v22, vM1I, $v31[1] // One's complement of Y int part
    lrv     $v11[0], (0x20)($12)                              // X frac right shifted
    vmrg    $v20, $v20, vM0I    // $v20:$v21 = abs(X int:frac)
    lqv     $v16[0], (0x10)($11)                              // Z int left shifted
    vlt     $v29, vM1I, $v30[0] // Y int part < 0
    lqv     $v17[0], (0x30)($11)                              // Z frac left shifted
    vabs    $v23, vM1I, vM1F     // Apply sign of Y int part to Y frac part
    lsv     $v10[0], (0x02)($11)                              // X int right rot elem 2->0
    vxor    $v24, vM2I, $v31[1] // One's complement of Z int part
    lsv     $v11[0], (0x22)($11)                              // X frac right rot elem 2->0
    vmrg    $v22, $v22, vM1I    // $v22:$v23 = abs(Y int:frac)
    lsv     $v16[4],  (0x0E)($11)                             // Z int left rot elem 0->2
    vlt     $v29, vM2I, $v30[0] // Z int part < 0
    lsv     $v17[4],  (0x2E)($11)                             // Z frac left rot elem 0->2
    vabs    $v25, vM2I, vM2F     // Apply sign of Z int part to Z frac part
    lrv     $v18[0], (0x10)($12)                              // Z int right shifted
    vmrg    $v24, $v24, vM2I    // $v24:$v25 = abs(Z int:frac)
    lrv     $v19[0], (0x30)($12)                              // Z frac right shifted
    // See if any of the int parts are nonzero. Also, get the maximum of the frac parts.
    vge     $v21, $v21, $v23
    lqv     $v8[0],  (0x00)($11)                              // X int left shifted
    vor     $v20, $v20, $v22
    lqv     $v9[0],  (0x20)($11)                              // X frac left shifted
    vmudn   $v11, $v11, $v31[1] // -1; negate X right rot
    lsv     $v18[0], (0x12)($11)                              // Z int right rot elem 2->0
    vmadh   $v10, $v10, $v31[1]
    lsv     $v19[0], (0x32)($11)                              // Z frac right rot elem 2->0
    vge     $v21, $v21, $v25
    lsv     $v8[4],  (-0x02)($11)                             // X int left rot elem 0->2
    vor     $v20, $v20, $v24
    lsv     $v9[4],  (0x1E)($11)                              // X frac left rot elem 0->2
    vmudn   $v17, $v17, $v31[1] // -1; negate Z left rot
    ldv     $v12[0], (0x08)($11)                              // Y int left shifted
    vmadh   $v16, $v16, $v31[1]
    ldv     $v13[0], (0x28)($11)                              // Y frac left shifted
    vge     $v21, $v21, $v21[1h]
    ldv     $v14[0], (-0x08)($12)                             // Y int right shifted
    vor     $v20, $v20, $v20[1h]
    ldv     $v15[0], (0x18)($12)                              // Y frac right shifted
    vmudn   $v27, $v19, $v31[1] // -1; $v26:$v27 is negated copy of Z right rot
    lsv     $v12[4], (0x06)($11)                              // Y int left rot elem 0->2
    vmadh   $v26, $v18, $v31[1]
    lsv     $v13[4], (0x26)($11)                              // Y frac left rot elem 0->2
    vge     $v21, $v21, $v21[2h]
    lsv     $v14[0], (0x0A)($11)                              // Y int right rot elem 2->0
    vor     $v20, $v20, $v20[2h]
    lsv     $v15[0], (0x2A)($11)                              // Y frac right rot elem 2->0
    // Scale factor is 1/(2*(max^2)) (clamped if overflows).
    // 1/(2*max) is what vrcp provides, so we multiply that by 2 and then by the rcp
    // output. If we used the scale factor of 1/(max^2), the output matrix would have
    // components on the order of 0001.0000, but we want the components to be smaller than this.
    vrcp    $v28[1], $v21[0] // low in, low out (discarded)
    vrcph   $v28[0], $v30[0] // zero in, high out (only care about elem 0)
    vadd    $v22, $v28, $v28 // *2
    vmudh   $v28, $v22, $v28 // (1/max) * (1/(2*max)), clamp to 0x7FFF
    veq     $v29, $v20, $v30[0] // elem 0 (all int parts) == 0
    vmrg    $v28, $v28, $v31[2] // If so, use computed normalization, else use 1 (elem 0)
    /*
    The original equations for the matrix rows are (XL = X rotated left, etc., n = normalization):
    n*(YL*ZR - YR*ZL)
    n*(ZL*XR - ZR*XL)
    n*(XL*YR - XR*YL)
    We need to apply the normalization to one of each of the terms before the multiply,
    and also there's no multiply-subtract instruction, only multiply-add. Converted to:
    (n*YL)*  ZR  + (n*  YR )*(-ZL)
    (n*XL)*(-ZR) + (n*(-XR))*(-ZL)
    (n*XL)*  YR  + (n*(-XR))*  YL
    So the steps are:
    Negate XR, negate ZL, negated copy of ZR (all done above)
    Scale XL, scale negated XR
    Do multiply-adds for Y and Z output vectors
    Scale YL, scale YR
    Do multiply-adds for X output vector
    */
    vmudn   $v9,  $v9,  $v28[0] // Scale XL
    vmadh   $v8,  $v8,  $v28[0]
    vmudn   $v11, $v11, $v28[0] // Scale XR
    vmadh   $v10, $v10, $v28[0]
    // Z output vector: XL*YR + XR*YL, with each term having had scale and/or negative applied
    vmudl   $v29, $v9,  $v15
    vmadm   $v29, $v8,  $v15
    vmadn   $v29, $v9,  $v14
    vmadh   $v29, $v8,  $v14
    vmadl   $v29, $v11, $v13
    vmadm   $v29, $v10, $v13
    vmadn   $v25, $v11, $v12
    vmadh   $v24, $v10, $v12 // $v24:$v25 = Z output
    vmudn   $v13, $v13, $v28[0] // Scale YL
    vmadh   $v12, $v12, $v28[0]
    vmudn   $v15, $v15, $v28[0] // Scale YR
    vmadh   $v14, $v14, $v28[0]
    // Y output vector: XL*ZR + XR*ZL, with each term having had scale and/or negative applied
    vmudl   $v29, $v9,  $v27 // Negated copy of ZR
    vmadm   $v29, $v8,  $v27
    vmadn   $v29, $v9,  $v26
    vmadh   $v29, $v8,  $v26
    sdv     $v25[0], (mITMatrix + 0x28)($zero)
    vmadl   $v29, $v11, $v17
    sdv     $v24[0], (mITMatrix + 0x10)($zero)
    vmadm   $v29, $v10, $v17
    vmadn   $v23, $v11, $v16
    vmadh   $v22, $v10, $v16 // $v22:$v23 = Y output
    // X output vector: YL*ZR + YR*ZL, with each term having had scale and/or negative applied
    vmudl   $v29, $v13, $v19
    vmadm   $v29, $v12, $v19
    vmadn   $v29, $v13, $v18
    vmadh   $v29, $v12, $v18
    sdv     $v23[0], (mITMatrix + 0x20)($zero)
    vmadl   $v29, $v15, $v17
    sdv     $v22[0], (mITMatrix + 0x08)($zero)
    vmadm   $v29, $v14, $v17
    vmadn   $v21, $v15, $v16
    vmadh   $v20, $v14, $v16 // $v20:$v21 = X output
    sdv     $v21[0], (mITMatrix + 0x18)($zero)
    j       vtx_after_calc_mit
     sdv    $v20[0], (mITMatrix + 0x00)($zero)

ovl4_end:
.align 8
ovl4_padded_end:

.close // CODE_FILE
