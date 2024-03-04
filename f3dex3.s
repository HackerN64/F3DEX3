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

// This version doesn't depend on $v0 to be vZero, which it usually is not in
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

//
// Profiling configurations. To make space for the profiling features, if any of
// the profiling configurations are enabled, G_LIGHTTORDP and !G_SHADING_SMOOTH
// are removed, i.e. G_LIGHTTORDP behaves as a no-op and all tris are smooth
// shaded.
//

// Config A TODO
// perfCounterA:
//     cycles RSP spent processing vertex commands (incl. vertex DMAs)
// perfCounterB:
//     upper 16 bits: fetched DL command count
//     lower 16 bits: DL command count
// perfCounterC:
//     cycles RSP was stalled because RDP FIFO was full
// perfCounterD:
//     cycles RSP spent processing triangle commands, NOT including buffer flushes
.if CFG_PROFILING_A
.if CFG_PROFILING_B || CFG_PROFILING_C
.error "At most one CFG_PROFILING_ option can be enabled at a time"
.endif
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 0
COUNTER_B_LOWER_CMD_COUNT equ 1
COUNTER_C_FIFO_FULL equ 1
NEED_START_COUNTER_DMEM equ 1

// Config B TODO
// perfCounterA:
//     upper 16 bits: vertex count
//     lower 16 bits: lit vertex count
// perfCounterB:
//     upper 18 bits: tris culled by occlusion plane count
//     lower 14 bits: clipped (input) tris count
// perfCounterC:
//     upper 18 bits: overlay (all 0-4) load count
//     lower 14 bits: overlay 2 (lighting) load count TODO
// perfCounterD:
//     upper 18 bits: overlay 3 (clipping) load count TODO
//     lower 14 bits: overlay 4 (misc) load count TODO
.elseif CFG_PROFILING_B
.if CFG_PROFILING_C
.error "At most one CFG_PROFILING_ option can be enabled at a time"
.endif
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 1
COUNTER_B_LOWER_CMD_COUNT equ 0
COUNTER_C_FIFO_FULL equ 0
NEED_START_COUNTER_DMEM equ 0

// Config C TODO
// perfCounterA:
//     cycles RSP believes it was running (this ucode only)
// perfCounterB:
//     upper 16 bits: samples GCLK was alive (sampled once per DL command count)
//     lower 16 bits: DL command count
// perfCounterC:
//     upper 18 bits: small RDP command count (all RDP cmds except tris)
//     lower 14 bits: matrix loads count
// perfCounterD:
//     cycles RSP was stalled waiting for miscellaneous DMAs to finish
.elseif CFG_PROFILING_C
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 0
COUNTER_B_LOWER_CMD_COUNT equ 1
COUNTER_C_FIFO_FULL equ 0
NEED_START_COUNTER_DMEM equ 1

// Default (extra profiling disabled)
// perfCounterA:
//     upper 16 bits: vertex count
//     lower 16 bits: RDP/out tri count
// perfCounterB:
//     upper 18 bits: RSP/in tri count
//     lower 14 bits: tex/fill rect count
// perfCounterC:
//     cycles RSP was stalled because RDP FIFO was full
// perfCounterD:
//     unused/zero
.else
ENABLE_PROFILING equ 0
COUNTER_A_UPPER_VERTEX_COUNT equ 1
COUNTER_B_LOWER_CMD_COUNT equ 0
COUNTER_C_FIFO_FULL equ 1
NEED_START_COUNTER_DMEM equ 0

.endif

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
    .dw 0x00000000 // first word, has command byte, level, tile, and on
    
textureSettings2:
    .dw 0xFFFFFFFF // second word, has s and t scale
    
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

// First half of RDP value for split commands; overwritten by numLightsxSize
rdpHalf1Val:
    .fill 4
    
    .db 0   // unused
numLightsxSize:
    .db 0   // Overwrites above

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
    .dh 0      // used often
    .dh 2      // used as clip ratio (vtx write, clipping) and in clipping
    .dh 4      // used for same Newton-Raphsons, occlusion plane scaling
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
tempTriRA:
    .skip 2 // Overwritten as part of camera world position, used as temp
lightBufferLookat:
    .skip 8 // s8 X0, Y0, Z0, dummy, X1, Y1, Z1, dummy
lightBufferMain:
    .skip (G_MAX_LIGHTS * lightSize)
lightBufferAmbient:
    .skip 8 // just colors for ambient light
ltBufOfs equ (lightBufferMain - altBase)

occlusionPlaneEdgeCoeffs:
/*
Vertex is in occlusion region if all five equations below are true:
4 * screenX[s13.2] * c0[s0.15] - 0.5 * screenY[s13.2] < c4[s14.1]
4 * screenY[s13.2] * c1[s0.15] - 0.5 * screenX[s13.2] < c5[s14.1]
4 * screenX[s13.2] * c2[s0.15] + 0.5 * screenY[s13.2] < c6[s14.1]
4 * screenY[s13.2] * c3[s0.15] + 0.5 * screenX[s13.2] < c7[s14.1]
      clamp_to_0.s15(clipX[s15.16] * kx[0.s15])
    + clamp_to_0.s15(clipY[s15.16] * ky[0.s15])
    + clamp_to_0.s15(clipZ[s15.16] * kz[0.s15])
    + kc[0.s15]
    >= 0
The first four can be rewritten as (again, vertex is occluded if all are true):
screenY > screenX *  8*c0 + -2*c4
screenX > screenY *  8*c1 + -2*c5
screenY < screenX * -8*c2 +  2*c6
screenX < screenY * -8*c3 +  2*c7
where screenX and screenY are in subpixels (e.g. screenX = 100 = 25.0 pixels),
c0-c3 are shorts representing -1:0.99997,
and c4-c7 are shorts representing "half pixels" (e.g. c4 = 50 = 25.0 pixels)

For the last equation, one option is to think of kx through kc as in s10.5 mode
instead, so a value of 0x0020 is 1.0 and they can range from -0x400.00 to
0x3FF.F8. This choice is because clipZ ranges from 0x0000.0000 at the camera
plane to 0x03FF.0000 at the maximum distance away. The normal distance Adult
Link is from the camera is about 0x00B0.0000.

A better option is to develop your plane equation in floating point, e.g.
clipX[f] * -0.2f + clipY[f] * 0.4f + clipZ[f] * 1.0f + -200.0f >= 0
then multiply everything by (32768.0f / max(abs(kx), abs(ky), abs(kz), abs(kc)))
(here 32768.0f / 200.0f = 163.84f)
clipX[f] * -32.77f + clipY[f] * 65.54f + clipZ[f] * 163.84f + -32768
*/
    .dh 0x0000 // c0
    .dh 0x0000 // c1
    .dh 0x0000 // c2
    .dh 0x0000 // c3
    .dh 0x8000 // c4
    .dh 0x8000 // c5
    .dh 0x8000 // c6
    .dh 0x8000 // c7
occlusionPlaneMidCoeffs:
    .dh 0x0000 // kx
    .dh 0x0000 // ky
    .dh 0x0000 // kz
    .dh 0x8000 // kc

// Alternate base address because vector load offsets can't reach all of DMEM.
// altBaseReg permanently points here.
altBase:

fxParams:

.if (. & 15) != 0
    .error "Wrong alignment for fxParams"
.endif
// First 8 values here loaded with lqv.

aoAmbientFactor:
    .dh 0xFFFF
aoDirectionalFactor:
    .dh 0xA000
aoPointFactor:
    .dh 0x0000
    
perspNorm:
    .dh 0xFFFF
    
texgenLinearCoeffs:
    .dh 0x44D3
    .dh 0x6CB3
    
fresnelScale:
    .dh 0x0000
fresnelOffset:
    .dh 0x0000

attrOffsetST:
    .dh 0x0100
    .dh 0xFF00
attrOffsetZ:
    .dh 0xFFFE
    
alphaCompareCullMode:
    .db 0x00 // 0 = disabled, 1 = cull if all < thresh, -1 = cull if all >= thresh
alphaCompareCullThresh:
    .db 0x00 // Alpha threshold, 00 - FF

materialCullMode: // Overwritten to 0 by SPNormalsMode, but that should not
    .db 0     // happen in the middle of tex setup
normalsMode:
    .db 0     // Overwrites materialCullMode

lastMatDLPhyAddr:
    .dw 0
    
.if NEED_START_COUNTER_DMEM
startCounterTime:
    .dw 0
.endif
    
// Constants for clipping algorithm
clipCondShifts:
    .db CLIP_SCAL_NY_SHIFT
    .db CLIP_SCAL_PY_SHIFT
    .db CLIP_SCAL_NX_SHIFT
    .db CLIP_SCAL_PX_SHIFT

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
    .dh 0                  // unused
    .dh segmentTable       // G_MW_SEGMENT
    .dh fogFactor          // G_MW_FOG
    .dh lightBufferMain    // G_MW_LIGHTCOL


.macro jumpTableEntry, addr
    .dh addr & 0xFFFF
.endmacro

// G_POPMTX, G_MTX, G_MOVEMEM Command Jump Table
movememHandlerTable:
jumpTableEntry G_POPMTX_end            // G_POPMTX
jumpTableEntry ovl234_ovl4_entrypoint  // G_MTX (multiply)
jumpTableEntry G_MOVEMEM_end           // G_MOVEMEM, G_MTX (load)

.macro miniTableEntry, addr
    .if addr < 0x1000 || addr >= 0x1400
        .error "Handler address out of range!"
    .endif
    .db (addr - 0x1000) >> 2
.endmacro

// RDP/Immediate Command Mini Table
// 1 byte per entry, after << 2 points to an addr in first 1/4 of IMEM
miniTableEntry ovl4_cmd_handler // G_DMA_IO
miniTableEntry G_TEXTURE_handler
miniTableEntry G_POPMTX_handler
miniTableEntry G_GEOMETRYMODE_handler
miniTableEntry G_MTX_handler
miniTableEntry G_MOVEWORD_handler
miniTableEntry G_MOVEMEM_handler
miniTableEntry G_LOAD_UCODE_handler
miniTableEntry G_DL_handler
miniTableEntry G_ENDDL_handler
miniTableEntry G_SPNOOP_handler
miniTableEntry G_RDPHALF_1_handler
miniTableEntry G_SETOTHERMODE_L_handler
miniTableEntry G_SETOTHERMODE_H_handler
miniTableEntry G_TEXRECT_handler
miniTableEntry G_TEXRECTFLIP_handler
miniTableEntry G_SYNC_handler // G_RDPLOADSYNC
miniTableEntry G_SYNC_handler // G_RDPPIPESYNC
miniTableEntry G_SYNC_handler // G_RDPTILESYNC
miniTableEntry G_SYNC_handler // G_RDPFULLSYNC
miniTableEntry G_RDP_handler // G_SETKEYGB
miniTableEntry G_RDP_handler // G_SETKEYR
miniTableEntry G_RDP_handler // G_SETCONVERT
miniTableEntry G_SETSCISSOR_handler
miniTableEntry G_RDP_handler // G_SETPRIMDEPTH
miniTableEntry G_RDPSETOTHERMODE_handler
miniTableEntry load_cmds_handler // G_LOADTLUT
miniTableEntry G_RDPHALF_2_handler
miniTableEntry G_RDP_handler // G_SETTILESIZE
miniTableEntry load_cmds_handler // G_LOADBLOCK
miniTableEntry load_cmds_handler // G_LOADTILE
miniTableEntry G_RDP_handler // G_SETTILE
miniTableEntry G_RDP_handler // G_FILLRECT
miniTableEntry G_RDP_handler // G_SETFILLCOLOR
miniTableEntry G_RDP_handler // G_SETFOGCOLOR
miniTableEntry G_RDP_handler // G_SETBLENDCOLOR
miniTableEntry G_RDP_handler // G_SETPRIMCOLOR
miniTableEntry G_RDP_handler // G_SETENVCOLOR
miniTableEntry G_RDP_handler // G_SETCOMBINE
miniTableEntry G_SETxIMG_handler // G_SETTIMG
miniTableEntry G_SETxIMG_handler // G_SETZIMG
miniTableEntry G_SETxIMG_handler // G_SETCIMG
cmdMiniTable:
miniTableEntry G_SYNC_handler // G_NOOP
miniTableEntry G_VTX_handler
miniTableEntry G_MODIFYVTX_handler
miniTableEntry G_CULLDL_handler
miniTableEntry ovl4_cmd_handler // G_BRANCH_WZ
miniTableEntry G_TRI1_handler
miniTableEntry G_TRI2_handler
miniTableEntry G_QUAD_handler
miniTableEntry G_TRISTRIP_handler
miniTableEntry G_TRIFAN_handler
miniTableEntry G_LIGHTTORDP_handler
miniTableEntry G_RELSEGMENT_handler
.if (. & 1) != 0
    .db 0  // align to 2 for everything following
.endif

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

.if . > yieldDataFooter
    // OS_YIELD_DATA_SIZE (0xC00) bytes of DMEM are saved. The last data in that is
    // the footer, which contains four perf counters, taskDataPtr, and ucode.
    // So, any data starting from the address of this footer will be clobbered,
    // so the vertex buffer and other data which needs to be save across yield
    // can't extend here. (The input buffer will be reloaded from the next
    // command in the source DL.)
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
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer1End:
    .skip 8
rdpCmdBuffer1EndPlus1Word:
    // This is so that we can temporarily store vector regs here with lqv/sqv
    .skip RDP_CMD_BUFSIZE_EXCESS - 8
// Second RDP Command Buffer
rdpCmdBuffer2:
    .skip RDP_CMD_BUFSIZE
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer2End:
    .skip 8
rdpCmdBuffer2EndPlus1Word:
    .skip RDP_CMD_BUFSIZE_EXCESS - 8

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
vVP2I  equ $v10
vVP3I  equ $v11
vVP0F  equ $v12
vVP1F  equ $v13
vVP2F  equ $v14
vVP3F  equ $v15
// Lighting and vertex load:
vPairNrml  equ $v16 // Vertex pair normals (model then world space)
vPairLt    equ $v17 // Vertex pair total light color/intensity (RGB-RGB-)
vNrmOut    equ $v18 // Output of lt_normalize (rarely used, but needed as all temps used)
// $v19 not used during vertex / lighting
vPairPosI  equ $v20 // Vertex pair model / world space position int/frac
vPairPosF  equ $v21
vPairST    equ $v22 // Vertex pair ST texture coordinates
vAAA       equ $v23 // Temps
vBBB       equ $v24
vCCC       equ $v25
vDDD       equ $v26
vPairRGBA  equ $v27 // Vertex pair color
// Vertex write, after lighting:
vPairTPosF equ $v23 // Vertex pair transformed (clip / screen) space position frac/int
vPairTPosI equ $v24
// Global:
vOne       equ $v28 // Global, all elements = 1
// $v29: permanent temp register, also write results here to discard
// $v30: parameters for vertex/lighting; other constants for tri write
// $v31: Only global constant vector register

// For tri write only:
vZero equ $v0  // all elements = 0

// Global and semi-global (i.e. one main function + occasional local) scalar regs:
//                 $zero // Hardwired zero scalar register
perfCounterD   equ $12   // Performance counter D (functions depend on config)
altBaseReg     equ $13   // Alternate base address register for vector loads
inputVtxPos    equ $14   // Pointer to loaded vertex to transform
outputVtxPos   equ $15   // Pointer to vertex buffer to store transformed verts
clipFlags      equ $16   // Current clipping flags being checked
clipPolyRead   equ $17   // Read pointer within current polygon being clipped
clipPolySelect equ $18   // Clip poly double buffer selection, or < 0 for normal tri write
clipPolyWrite  equ $21   // Write pointer within current polygon being clipped
rdpCmdBufEndP1 equ $22   // Pointer to one command word past "end" (middle) of RDP command buf
rdpCmdBufPtr   equ $23   // RDP command buffer current DMEM pointer
cmd_w1_dram    equ $24   // DL command word 1, which is also DMA DRAM addr
cmd_w0         equ $25   // DL command word 0, also holds next tris info
taskDataPtr    equ $26   // Task data (display list) DRAM pointer
inputBufferPos equ $27   // DMEM position within display list input buffer, relative to end
perfCounterA   equ $28   // Performance counter A (functions depend on config)
perfCounterB   equ $29   // Performance counter B (functions depend on config)
perfCounterC   equ $30   // Performance counter C (functions depend on config)
//                 $ra   // Return address

// Misc scalar regs:
clipMaskIdx  equ $6
secondVtxPos equ $8
curLight     equ $9

// Arguments to dma_read_write
dmaLen   equ $19 // also used by itself
dmemAddr equ $20
// cmd_w1_dram   // used for all dma_read_write DRAM addresses

// Argument to load_overlay*
postOvlRA equ $10 // Commonly used locally

// ==== Summary of uses of all registers
// $zero: Hardwired zero scalar register
// $1: vertex 1 addr, zero when command handler is called, count of
//     remaining vertices * 0x10, pointer to store texture coefficients, local
// $2: vertex 2 addr, vertex at end of edge during clipping, pointer to store
//     shade coefficients, local
// $3: vertex 3 addr, vertex at start of edge during clipping, local
// $4: pre-shuffle vertex 1 addr for flat shading during tri write (global)
// $5: geometry mode middle 2 bytes during vertex load / lighting, local
// $6: clipMaskIdx, geometry mode low byte during tri write, local
// $7: command byte when command handler is called, mIT recompute flag in
//     Overlay 4, local
// $8: secondVtxPos, local
// $9: curLight, clip mask during clipping, local
// $10: postOvlRA, common local
// $11: very common local
// $12: perfCounterD (global). This must be $12 for S2DEX compat in while_wait_dma_busy.
// $13: altBaseReg (global)
// $14: inputVtxPos, local
// $15: outputVtxPos, local
// $16: clipFlags (global)
// $17: clipPolyRead (global)
// $18: clipPolySelect (global)
// $19: dmaLen, onscreen vertex during clipping, local
// $20: dmemAddr, local
// $21: clipPolyWrite (global)
// $22: rdpCmdBufEndP1 (global)
// $23: rdpCmdBufPtr (global)
// $24: cmd_w1_dram, local
// $25: cmd_w0 (global); holds next tris info during tri write -> clipping ->
//      vtx write
// $26: taskDataPtr (global)
// $27: inputBufferPos (global)
// $28: perfCounterA (global)
// $29: perfCounterB (global)
// $30: perfCounterC (global)
// $ra: Return address for jal, b*al

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl0 and/or ovl1
start: // This is at IMEM 0x1080, not the start of IMEM
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    lqv     $v31[0], (v31Value)($zero)
    vclr    vOne
    li      altBaseReg, altBase
    li      rdpCmdBufPtr, rdpCmdBuffer1
    li      rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word
    lw      $11, rdpFifoPos
    lw      $10, OSTask + OSTask_flags
    vsub    vOne, vOne, $v31[1]             // 1 = 0 - -1
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // Clear task done and yielded signals
    beqz    $11, initialize_rdp             // If RDP FIFO not set up yet, starting ucode from scratch
     mtc0   $1, SP_STATUS
    andi    $10, $10, OS_TASK_YIELDED       // Resumed from yield or came from called ucode?
    beqz    $10, continue_from_os_task      // If latter, load DL (task data) pointer from OSTask
     sw     $zero, OSTask + OSTask_flags    // Clear all task flags, incl. yielded
continue_from_yield:
    // Perf counters saved here at yield
    lw      perfCounterA, yieldDataFooter + YDF_OFFSET_PERFCOUNTERA
    lw      perfCounterB, yieldDataFooter + YDF_OFFSET_PERFCOUNTERB
    lw      perfCounterC, yieldDataFooter + YDF_OFFSET_PERFCOUNTERC
    lw      perfCounterD, yieldDataFooter + YDF_OFFSET_PERFCOUNTERD
    j       finish_setup
     lw     taskDataPtr, yieldDataFooter + YDF_OFFSET_TASKDATAPTR

initialize_rdp:
    mfc0    $11, DPC_STATUS               // Read RDP status
    andi    $11, $11, DPC_STATUS_XBUS_DMA // Look at XBUS enabled bit
    bnez    $11, @@start_new_buf          // If XBUS is enabled, start new buffer
     mfc0   $2, DPC_END                   // Load RDP end pointer
    lw      $3, OSTask + OSTask_output_buff // Load start of FIFO
    sub     $11, $3, $2                   // If start of FIFO > RDP end,
    bgtz    $11, @@start_new_buf          // start new buffer
     mfc0   $1, DPC_CURRENT               // Load RDP current pointer
    lw      $3, OSTask + OSTask_output_buff_size // Load end of FIFO
    beqz    $1, @@start_new_buf           // If RDP current pointer is 0, start new buffer
     sub    $11, $1, $3                   // If RDP current > end of fifo,
    bgez    $11, @@start_new_buf          // start new buffer
     nop
    bne     $1, $2, @@continue_buffer     // If RDP current != RDP end, keep current buffer
@@start_new_buf:
    // There may be one buffer executing in the RDP, and another queued in the
    // double-buffered start/end regs. Wait for the latter to be available
    // (i.e. possibly one buffer executing, none waiting).
     mfc0   $11, DPC_STATUS               // Read RDP status
    andi    $11, $11, DPC_STATUS_START_VALID // Start valid = second start addr in dbl buf
    bnez    $11, @@start_new_buf          // Wait until double buffered start/end available
     li     $11, DPC_STATUS_CLR_XBUS      // Bit to disable XBUS mode
    mtc0    $11, DPC_STATUS               // Set bit, disable XBUS
    lw      $2, OSTask + OSTask_output_buff_size // Load FIFO "size" (actually end addr)
    // Set up the next buffer for the RDP to be zero size and at the end of the FIFO.
    mtc0    $2, DPC_START                 // Set RDP start addr to end of FIFO
    mtc0    $2, DPC_END                   // Set RDP end addr to end of FIFO
@@continue_buffer:
    // If we jumped here, the RDP is currently executing from the middle of the FIFO.
    // So we can just append commands to there and move the end pointer.
    sw      $2, rdpFifoPos                // Set FIFO position to end of FIFO or RDP end
    lw      $11, matrixStackPtr           // Initialize matrix stack pointer from OSTask
    bnez    $11, continue_from_os_task    // if not yet initialized
     lw     $11, OSTask + OSTask_dram_stack
    sw      $11, matrixStackPtr
continue_from_os_task:
    // Counters stored here if jumped to different ucode
    // If starting from scratch, these are zero
    lw      perfCounterA, mITMatrix + YDF_OFFSET_PERFCOUNTERA
    lw      perfCounterB, mITMatrix + YDF_OFFSET_PERFCOUNTERB
    lw      perfCounterC, mITMatrix + YDF_OFFSET_PERFCOUNTERC
    lw      perfCounterD, mITMatrix + YDF_OFFSET_PERFCOUNTERD
    lw      taskDataPtr, OSTask + OSTask_data_ptr
finish_setup:
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    sw      $11, startCounterTime
.endif
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
    andi    inputBufferPos, cmd_w0, 0x00F8             // Byte 3, how many cmds to drop from load (max 0xA0)
displaylist_dma:
    // Load INPUT_BUFFER_LEN - inputBufferPos cmds (inputBufferPos >= 0, mult of 8)
    addi    inputBufferPos, inputBufferPos, -INPUT_BUFFER_LEN // inputBufferPos = - num cmds
.if CFG_PROFILING_A
    sll     $11, inputBufferPos, 16 - 3                // Divide by 8 for num cmds to load, then move to upper 16
    sub     perfCounterB, perfCounterB, $11            // Negative so subtract
.endif
    nor     dmaLen, inputBufferPos, $zero              // DMA length = -inputBufferPos - 1 = ones compliment
    move    cmd_w1_dram, taskDataPtr                   // set up the DRAM address to read from
    jal     dma_read_write                             // initiate the DMA read
     addi   dmemAddr, inputBufferPos, inputBufferEnd   // set the address to DMA read to
    sub     taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
wait_for_dma_and_run_next_command:
G_POPMTX_end:
G_MOVEMEM_end:
    jal     while_wait_dma_busy                         // wait for the DMA read to finish
.if ENABLE_PROFILING
G_LIGHTTORDP_handler:
.endif
.if !CFG_PROFILING_A
vertex_end:
tri_end:
.endif
G_SPNOOP_handler:
run_next_DL_command:
     mfc0   $1, SP_STATUS                               // load the status word into register $1
    beqz    inputBufferPos, displaylist_dma             // load more DL commands if none are left
     andi   $1, $1, SP_STATUS_SIG0                      // check if the task should yield
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // load the command word into cmd_w0
    bnez    $1, load_overlay_0_and_enter                // load and execute overlay 0 if yielding; $1 > 0
     sra    $7, cmd_w0, 24                              // extract DL command byte from command word
    lw      cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // load the next DL word into cmd_w1_dram
    addi    inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
.if CFG_PROFILING_C
    mfc0    $11, DPC_STATUS
    andi    $11, $11, DPC_STATUS_GCLK_ALIVE             // Sample whether GCLK is active now
    sll     $11, $11, 16 - 3                            // move from bit 3 to bit 16
    add     perfCounterB, perfCounterB, $11             // Add to the perf counter
.endif
.if CFG_PROFILING_A
    mfc0    $11, DPC_CLOCK
.endif
.if COUNTER_B_LOWER_CMD_COUNT
    addi    perfCounterB, perfCounterB, 1               // Count commands
.endif
.if CFG_PROFILING_A
    move    $4, perfCounterC                            // Save initial FIFO stall time
    sw      $11, startCounterTime
.endif
    // $1 must remain zero
    // $7 must retain the command byte for load_mtx and overlay 4 stuff
    // $11 must contain the handler called for several handlers
    lbu     $11, (cmdMiniTable)($7)                     // Load mini table entry
    sll     $11, $11, 2                                 // Convert to a number of instructions
    jr      $11                                         // Jump to handler
     // Delay slot must not affect $1, $7, $11
G_DL_handler:
     sll    $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
branch_dl:
    lbu     $1, displayListStackLength      // Get the DL stack length
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
    sub     $11, cmd_w1_dram, taskDataPtr   // Negative how far new target is behind current end
    bltz    $2, call_ret_common             // Nopush = branch = flag is set
     move   taskDataPtr, cmd_w1_dram        // Set the new DL to the target display list
    sw      $3, (displayListStack)($1)
    addi    $1, $1, 4                       // Increment the DL stack length
call_ret_common:
    sb      $zero, materialCullMode         // This covers call, branch, return, and cull and branchZ successes
    j       displaylist_dma_with_count
     sb     $1, displayListStackLength

.if !ENABLE_PROFILING
G_LIGHTTORDP_handler:
    lbu     $11, numLightsxSize          // Ambient light
    lbu     $1, (inputBufferEnd - 0x6)(inputBufferPos) // Byte 2 = light count from end * size
    andi    $2, cmd_w0, 0x00FF           // Byte 3 = alpha
    sub     $1, $11, $1                  // Light address; byte 2 counts from end
    lw      $3, (lightBufferMain-1)($1)  // Load light RGB into lower 3 bytes
    move    cmd_w0, cmd_w1_dram          // Move second word to first (cmd byte, prim level)
    sll     $3, $3, 8                    // Shift light RGB to upper 3 bytes and clear alpha byte
    j       G_RDP_handler                // Send to RDP
     or     cmd_w1_dram, $3, $2          // Combine RGB and alpha in second word
.endif

G_SETxIMG_handler:
    lb      $3, materialCullMode            // Get current mode
    jal     segmented_to_physical           // Convert image to physical address
     lw     $2, lastMatDLPhyAddr            // Get last material physical addr
    bnez    $3, G_RDP_handler               // If not in normal mode (0), exit
     add    $10, taskDataPtr, inputBufferPos // Current material physical addr
    beq     $10, $2, @@skip                 // Branch if we are executing the same mat again
     sw     $10, lastMatDLPhyAddr           // Store material physical addr
    li      $7, 1                           // > 0: in material first time
@@skip:                                     // Otherwise $7 was < 0: cull mode (in mat second time)
    j       G_RDP_handler
     sb     $7, materialCullMode

ovl4_cmd_handler:
    j       ovl234_ovl4_entrypoint          // Delay slot is harmless
load_cmds_handler:
     lb     $3, materialCullMode
    bltz    $3, run_next_DL_command  // If cull mode is < 0, in mat second time, skip the load
G_RDP_handler:
     sw     cmd_w1_dram, 4(rdpCmdBufPtr)     // Add the second word of the command to the RDP command buffer
G_SYNC_handler:
.if CFG_PROFILING_C
    addi    perfCounterC, perfCounterC, 0x4000 // Increment small RDP command count
.endif
    sw      cmd_w0, 0(rdpCmdBufPtr)          // Add the command word to the RDP command buffer
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8    // Increment the next RDP command pointer by 2 words
check_rdp_buffer_full_and_run_next_cmd:
    li      $ra, run_next_DL_command         // Set up running the next DL command as the return address
check_rdp_buffer_full:
     sub    $11, rdpCmdBufPtr, rdpCmdBufEndP1
    bltz    $11, return_routine              // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
flush_rdp_buffer:
     mfc0   $10, SP_DMA_BUSY                 // Check if any DMA is in flight
    lw      cmd_w1_dram, rdpFifoPos          // FIFO pointer = end of RDP read, start of RSP write
    addi    dmaLen, $11, RDP_CMD_BUFSIZE + 8 // dmaLen = size of DMEM buffer to copy
.if CFG_PROFILING_C
    // This is a wait for DMA busy loop, but written inline to avoid overwriting ra.
    addi    perfCounterD, perfCounterD, 10   // 6 instr + 2 between end load and mfc + 0 taken branch overlaps with last + 2 between mfc and load
.endif
    bnez    $10, flush_rdp_buffer            // Wait until no DMAs are active
     lw     $10, OSTask + OSTask_output_buff_size // Load FIFO "size" (actually end addr)
    mtc0    cmd_w1_dram, DPC_END             // Set RDP to execute until FIFO end (buf pushed last time)
    add     $11, cmd_w1_dram, dmaLen         // $11 = future FIFO pointer if we append this new buffer
    sub     $10, $10, $11                    // $10 = FIFO end addr - future pointer
    bgez    $10, @@has_room                  // Branch if we can fit this
@@await_rdp_dblbuf_avail:
     mfc0   $11, DPC_STATUS                  // Read RDP status
    andi    $11, $11, DPC_STATUS_START_VALID // Start valid = second start addr in dbl buf
    bnez    $11, @@await_rdp_dblbuf_avail    // Wait until double buffered start/end available
.if COUNTER_C_FIFO_FULL
     addi   perfCounterC, perfCounterC, 7    // 4 instr + 2 after mfc + 1 taken branch
.endif
     lw     cmd_w1_dram, OSTask + OSTask_output_buff // Start of FIFO
@@await_past_first_instr:
    mfc0    $11, DPC_CURRENT                 // Load RDP current pointer
    beq     $11, cmd_w1_dram, @@await_past_first_instr // Wait until RDP moved past start
.if COUNTER_C_FIFO_FULL
     addi   perfCounterC, perfCounterC, 6    // 3 instr + 2 after mfc + 1 taken branch
.else
     nop
.endif
    // Start was previously the start of the FIFO, unless this is the first buffer,
    // in which case it was the end of the FIFO. Normally, when the RDP gets to end, if we
    // have a new end value waiting (END_VALID), it'll load end but leave current. By
    // setting start here, it will also load current with start.
    mtc0    cmd_w1_dram, DPC_START           // Set RDP start to start of FIFO
@@keep_waiting:
.if COUNTER_C_FIFO_FULL
    // This is here so we only count it when stalling below or on FIFO end codepath
    addi    perfCounterC, perfCounterC, 10   // 7 instr + 2 after mfc + 1 taken branch
.endif
@@has_room:
    mfc0    $11, DPC_CURRENT                 // Load RDP current pointer
    sub     $11, $11, cmd_w1_dram            // Current - current end (rdpFifoPos or start)
    blez    $11, @@copy_buffer               // Current is behind or at current end, can do copy
     sub    $11, $11, dmaLen                 // If amount current is ahead of current end
    blez    $11, @@keep_waiting              // is <= size of buffer to copy, keep waiting
@@copy_buffer:
     add    $11, cmd_w1_dram, dmaLen         // New end is current end + buffer size
    sw      $11, rdpFifoPos
    // Set up the DMA from DMEM to the RDP fifo in RDRAM
    addi    dmaLen, dmaLen, -1                                  // subtract 1 from the length
    addi    dmemAddr, rdpCmdBufEndP1, -(0x2000 | (RDP_CMD_BUFSIZE + 8)) // The 0x2000 is meaningless, negative means write
    xori    rdpCmdBufEndP1, rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word ^ rdpCmdBuffer2EndPlus1Word // Swap between the two RDP command buffers
    j       dma_read_write
     addi   rdpCmdBufPtr, rdpCmdBufEndP1, -(RDP_CMD_BUFSIZE + 8)

G_LOAD_UCODE_handler:
    j       load_overlay_0_and_enter         // Delay slot is harmless
G_MODIFYVTX_handler:
    // Command byte 3 = vtx being modified; its addr -> $10
     li     $11, do_moveword  // Moveword adds cmd_w0 to $10 for final addr
    lbu     cmd_w0, (inputBufferEnd - 0x07)(inputBufferPos)  // offset in vtx
vtx_addrs_from_cmd:
    // Treat eight bytes of last command each as vertex indices << 1
    // inputBufferEnd is close enough to the end of DMEM to fit in signed offset
    lpv     $v27[0], (-(0x1000 - (inputBufferEnd - 0x08)))(inputBufferPos)
vtx_indices_to_addr:
    // Input and output in $v27
    // Also out elem 3 -> $10, elem 7 -> $3 because these are used more than once
    lqv     $v30, (v30Value)($zero)
    vmudl   $v29, $v27, $v30[1]   // Multiply vtx indices times length
    vmadn   $v27, vOne, $v30[0]   // Add address of vertex buffer
    sb      $zero, materialCullMode // This covers all tri cmds, vtx, modify vtx, branchZ, cull
    mfc2    $10, $v27[6]
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
    beq     $11, cmd_w0, tri_end         // If off end of command, exit
     sll    $10, cmd_w1_dram, 24         // Put sign bit of vtx 3 in sign bit
    bltz    $10, tri_end                 // If negative, exit
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Store non-shuffled indices
    bltz    $ra, tri_fan_store           // Finish handling G_TRIFAN
     addi   cmd_w0, cmd_w0, 1            // Increment
    andi    $11, cmd_w0, 1               // If odd, this is the 1st/3rd/5th tri
    bnez    $11, tri_main                // Draw as is
     srl    $10, cmd_w1_dram, 8          // Move vtx 2 to LSBs
    sb      cmd_w1_dram, 6(rdpCmdBufPtr) // Store vtx 3 to spot for 2
    j       tri_main
     sb     $10, 7(rdpCmdBufPtr)         // Store vtx 2 to spot for 3

G_TRI2_handler:
G_QUAD_handler:
    jal     tri_main                     // Send second tri; return here for first tri
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Put second tri indices in temp memory
G_TRI1_handler:
    li      $ra, tri_end                 // After done with this tri, exit tri processing
    sw      cmd_w0, 4(rdpCmdBufPtr)      // Put first tri indices in temp memory
tri_main:
    lpv     $v27[0], 0(rdpCmdBufPtr)     // Load tri indexes to elems 5, 6, 7
    j       vtx_indices_to_addr          // elem 7 -> $3; rest in $v27
     li     $11, tri_return_from_addrs

G_VTX_handler:
    lhu     $1, (inputBufferEnd - 0x07)(inputBufferPos) // $1 = size in bytes = vtx count * 0x10
    lhu     $5, geometryModeLabel + 1          // Load middle 2 bytes of geom mode
    srl     $2, cmd_w0, 11                     // n << 1
    sub     $2, cmd_w0, $2                     // v0 << 1
    sb      $2, (inputBufferEnd - 0x06)(inputBufferPos) // Store v0 << 1 as byte 2
.if COUNTER_A_UPPER_VERTEX_COUNT
    sll     $11, $1, 12                        // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
.endif
    j       vtx_addrs_from_cmd                 // v0 << 1 is elem 2, (v0 + n) << 1 is elem 3 = $10
     li     $11, vtx_return_from_addrs
vtx_return_from_addrs:
    andi    $10, $10, 0xFFF8                   // Round down end addr to DMA word; one input vtx still fits in one internal vtx
    mfc2    outputVtxPos, $v27[4]              // Address of start in vtxSize units
    jal     segmented_to_physical              // Convert address in cmd_w1_dram to physical
     sub    dmemAddr, $10, $1                  // Start addr = end addr - size
    jal     dma_read_write
     addi   dmaLen, $1, -1                     // DMA length is always offset by -1
    move    inputVtxPos, dmemAddr
    lqv     vM0I,     (mMatrix + 0x00)($zero)  // Load M matrix
    lqv     vM2I,     (mMatrix + 0x10)($zero)
    lqv     vM0F,     (mMatrix + 0x20)($zero)
    lqv     vM2F,     (mMatrix + 0x30)($zero)
    lbu     $11, mITValid                      // 0 if matrix invalid, 1 if valid
    vcopy   vM1I,  vM0I
    lbu     $10, normalsMode                   // bit 0 clear if don't compute mIT, set if do
    vcopy   vM3I,  vM2I
    ldv     vM1I[0],  (mMatrix + 0x08)($zero)
    vcopy   vM1F,  vM0F
    ldv     vM3I[0],  (mMatrix + 0x18)($zero)
    vcopy   vM3F,  vM2F
    ldv     vM1F[0],  (mMatrix + 0x28)($zero)
    sltiu   $11, $11, 1                        // 0 if matrix valid, 1 if invalid
    srl     $7, $5, 9                          // G_LIGHTING in bit 1
    and     $7, $7, $11                        // If lighting enabled and need to update matrix,
    and     $7, $7, $10                        // and computing mIT,
    ldv     vM3F[0],  (mMatrix + 0x38)($zero)
    ldv     vM0I[8],  (mMatrix + 0x00)($zero)
    ldv     vM2I[8],  (mMatrix + 0x10)($zero)
    ldv     vM0F[8],  (mMatrix + 0x20)($zero)
    bnez    $7, ovl234_ovl4_entrypoint         // run overlay 4 to compute M inverse transpose
     ldv    vM2F[8],  (mMatrix + 0x30)($zero)
vtx_after_calc_mit:
    lqv     vVP0I,    (vpMatrix  + 0x00)($zero)
    lqv     vVP2I,    (vpMatrix  + 0x10)($zero)
    lqv     vVP0F,    (vpMatrix  + 0x20)($zero)
    lqv     vVP2F,    (vpMatrix  + 0x30)($zero)
    addi    outputVtxPos, outputVtxPos, -2*vtxSize // Going to increment this by 2 verts in loop
    vcopy   vVP1I,  vVP0I
    li      $ra, 0                             // Flag to not return to clipping
    vcopy   vVP3I, vVP2I
    ldv     vVP1I[0], (vpMatrix  + 0x08)($zero)
    vcopy   vVP1F, vVP0F
    ldv     vVP3I[0], (vpMatrix  + 0x18)($zero)
    vcopy   vVP3F, vVP2F
    ldv     vVP1F[0], (vpMatrix  + 0x28)($zero)
    ldv     vVP3F[0], (vpMatrix  + 0x38)($zero)
    ldv     vVP0I[8], (vpMatrix  + 0x00)($zero)
    ldv     vVP2I[8], (vpMatrix  + 0x10)($zero)
    ldv     vVP0F[8], (vpMatrix  + 0x20)($zero)
    ldv     vVP2F[8], (vpMatrix  + 0x30)($zero)
vtx_setup_constants:
    // Computes modified viewport scale and offset including fog info, and stores
    // these to temp memory in the RDP buffer. This is only used during vertex write
    // and the first half of clipping, so that memory is not used then.
    lsv     $v21[0], (attrOffsetZ - altBase)(altBaseReg) // Z offset
    ldv     $v26[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
    ldv     $v26[8], (viewport + 8)($zero)
    lw      $10, (geometryModeLabel)($zero)
    ldv     $v25[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    ldv     $v25[8], (viewport)($zero)
    vne     $v29, $v31, $v31[2h]                  // VCC = 11011101
    andi    $11, $10, G_ATTROFFSET_Z_ENABLE
    vadd    $v21, $v26, $v21[0]                   // Add Z offset to all terms (care about 2, 6)
    beqz    $11, @@skipz                          // Skip if Z offset disabled
     llv    $v23[0], (fogFactor)($zero)           // Load fog multiplier 0 and offset 1
    vmrg    $v26, $v26, $v21                      // Move Z + Z offset into elems 2, 6
@@skipz:
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    lqv     $v30, (fxParams - altBase)(altBaseReg) // Parameters for vtx and lighting
    vmudh   $v20, $v25, $v31[1]                   // -1; -vscale
    andi    $11, $10, G_AMBOCCLUSION
    vmrg    $v25, $v25, $v23[0]                   // Put fog multiplier in elements 3,7 of vscale
    vmrg    $v26, $v26, $v23[1]                   // Put fog offset in elements 3,7 of vtrans
    vge     $v29, $v31, $v31[3]                   // VCC = 00011111
    vmov    $v25[1], $v20[1]                      // Negate vscale[1] because RDP top = y=0
    vmov    $v25[5], $v20[1]                      // Same for second half
    bnez    $11, @@skipzeroao                     // Continue if AO disabled
     sqv    $v26, (0x10)(rdpCmdBufEndP1)          // Store viewport offset to temp mem
    vmrg    $v30, $v30, $v31[2]                   // 0; zero AO values
@@skipzeroao:
    bnez    $ra, clip_after_constants             // Return to clipping if from there
     sqv    $v25, (0x00)(rdpCmdBufEndP1)          // Store viewport scale to temp mem
    jal     while_wait_dma_busy                   // Wait for vertex load to finish
vtx_load_loop:
     vlt    $v29, $v31, $v31[4]                   // Set VCC to 11110000
    ldv     vPairPosI[8],      (VTX_IN_OB + inputVtxSize * 1)(inputVtxPos)
    ldv     vPairPosI[0],      (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos)
    vmudn   $v29, vM3F, vOne
    // Element access wraps in lpv/luv, but not intuitively. Basically the named
    // element and above do get the values at the specified address, but the earlier
    // elements get the values before that, except masked to 0xF. So for example here,
    // elems 4-7 get bytes 0-3 of the vertex as it looks like they should, but elems
    // 0-3 get bytes C-F of the vertex (which is what we want).
    luv     vPairRGBA[4], (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Colors as unsigned, lower 4
    vmadh   $v29, vM3I, vOne
    luv     vCCC[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, vM0F, vPairPosI[0h]
    lpv     vPairNrml[4], (VTX_IN_OB + inputVtxSize * 0)(inputVtxPos) // Normals as signed, lower 4
    vmadh   $v29, vM0I, vPairPosI[0h]
    lpv     vDDD[0],      (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // Upper 4
    vmadn   $v29, vM1F, vPairPosI[1h]
    llv     vPairST[0],   (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // ST in 0:1
    vmadh   $v29, vM1I, vPairPosI[1h]
    llv     vPairST[8],   (VTX_IN_TC + inputVtxSize * 1)(inputVtxPos) // ST in 4:5
    vmadn   vPairPosF, vM2F, vPairPosI[2h]
    andi    $11, $5, G_LIGHTING >> 8
    vmadh   vPairPosI, vM2I, vPairPosI[2h] // vPairPosI/F = vertices world coords
    // Elems 0-1 get bytes 6-7 of the following vertex (0)
    lpv     vAAA[2],      (VTX_IN_TC - inputVtxSize * 1)(inputVtxPos) // Packed normals as signed, lower 2
    vmrg    vPairRGBA, vPairRGBA, vCCC // Merge colors
    bnez    $11, ovl234_lighting_entrypoint
     // Elems 4-5 get bytes 6-7 of the following vertex (1)
     lpv    vBBB[6],      (VTX_IN_TC + inputVtxSize * 0)(inputVtxPos) // Upper 2 in 4:5
 vtx_return_from_lighting:
    vclr    $v26
    andi    $11, $5, G_ATTROFFSET_ST_ENABLE >> 8
    vmudn   $v29, vVP3F, vOne
    beqz    $11, @@skipoffset
     vmadh  $v29, vVP3I, vOne
    llv     $v26[0], (attrOffsetST - altBase)(altBaseReg) // elems 0, 1 = S, T offset
    llv     $v26[8], (attrOffsetST - altBase)(altBaseReg) // elems 4, 5 = S, T offset
@@skipoffset:
    vmadl   $v29, vVP0F, vPairPosF[0h]
    llv     $v25[0], (textureSettings2)($zero)  // Texture ST scale in 0, 1
    vmadm   $v29, vVP0I, vPairPosF[0h]
    llv     $v25[8], (textureSettings2)($zero)  // Texture ST scale in 4, 5
    vmadn   $v29, vVP0F, vPairPosI[0h]
    vmadh   $v29, vVP0I, vPairPosI[0h]
    addi    inputVtxPos, inputVtxPos, 2*inputVtxSize
    vmadl   $v29, vVP1F, vPairPosF[1h]
    addi    outputVtxPos, outputVtxPos, 2*vtxSize
    vmadm   $v29, vVP1I, vPairPosF[1h]
    addi    $1, $1, -2*inputVtxSize     // Counter of remaining verts * inputVtxSize
    vmadn   $v29, vVP1F, vPairPosI[1h]
    move    secondVtxPos, outputVtxPos  // Second and output vertices write to same mem...
    vmadh   $v29, vVP1I, vPairPosI[1h]
    bltz    $1, @@skipsecond            // ...if < 0 verts remain, ...
     vmadl  $v29, vVP2F, vPairPosF[2h]
    addi    secondVtxPos, outputVtxPos, vtxSize // ...otherwise, second vtx is next vtx
@@skipsecond:
    vmadm   $v29, vVP2I, vPairPosF[2h]
    vmadn   vPairTPosF, vVP2F, vPairPosI[2h]
    li      $ra, vertex_end             // Done with vertex processing...
    vmadh   vPairTPosI, vVP2I, vPairPosI[2h]
    blez    $1, @@skiploop              // ...if <= 0 verts remain, ...
     vmudm  $v29, vPairST, $v25         // Scale ST; must be after texgen
    li      $ra, vtx_load_loop          // ...otherwise keep looping
@@skiploop:
    vmadh   vPairST, $v26, vOne         // + 1 * (ST offset or zero)
vtx_store:
    // Inputs: vPairTPosI, vPairTPosF, vPairST, vPairRGBA
    // Locals: $v20, $v21, $v25, $v26, $v16, $v17 ($v29 is temp)
    // Scalar regs: secondVtxPos, outputVtxPos; set to the same thing if only write 1 vtx
    // temps $11, $10, $20, $24
    ldv     $v17[0], (occlusionPlaneMidCoeffs - altBase)(altBaseReg)
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    ldv     $v17[8], (occlusionPlaneMidCoeffs - altBase)(altBaseReg)
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
    vmadm   $v20, vPairTPosI, $v30[3] // Persp norm
    vmadn   $v21, $v31, $v31[2] // 0
    cfc2    $10, $vcc // Load screen clipping results
    vmudn   $v29, vPairTPosF, $v17 // X * kx, Y * ky, Z * kz
    vmadh   $v29, vPairTPosI, $v17 // Int * int
    vreadacc $v16, ACC_UPPER // Load int * int portion
    veq     $v29, $v31, $v31[3h] // Set VCC to 00010001
    vmudn   $v26, vPairTPosF, $v31[3] // W * clip ratio for scaled clipping
    vmadh   $v25, vPairTPosI, $v31[3] // W * clip ratio for scaled clipping
    vmrg    $v16, $v17, $v16  // Put constant factor in elems 3, 7
    sdv     vPairTPosF[8],  (VTX_FRAC_VEC  )(secondVtxPos)
    vrcph   $v29[0], $v20[3]
    sdv     vPairTPosF[0],  (VTX_FRAC_VEC  )(outputVtxPos)
    vrcpl   $v17[2], $v21[3]
    sdv     vPairTPosI[8],  (VTX_INT_VEC   )(secondVtxPos)
    vrcph   $v17[3], $v20[7]
    sdv     vPairTPosI[0],  (VTX_INT_VEC   )(outputVtxPos)
    vrcpl   $v17[6], $v21[7]
    suv     vPairRGBA[4],     (VTX_COLOR_VEC )(secondVtxPos)
    vadd    $v16, $v16, $v16[0q] // Add pairs upwards
    suv     vPairRGBA[0],     (VTX_COLOR_VEC )(outputVtxPos)
    vrcph   $v17[7], $v31[2] // 0
    slv     vPairST[8],       (VTX_TC_VEC    )(secondVtxPos)
    vch     $v29, vPairTPosI, $v25[3h] // Clip scaled high
    slv     vPairST[0],       (VTX_TC_VEC    )(outputVtxPos)
    vcl     $v29, vPairTPosF, $v26[3h] // Clip scaled low
    vadd    $v16, $v16, $v16[1h] // Add elems 1, 5 to 3, 7
    cfc2    $20, $vcc // Load scaled clipping results
    vmudl   $v29, $v21, $v17[2h]
    srl     $24, $10, 4            // Shift second vertex screen clipping to first slots
    vmadm   $v29, $v20, $v17[2h]
    andi    $24, $24, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmadn   $v21, $v21, $v17[3h]
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(secondVtxPos) // load Z into W slot, will be for fog below
    vmadh   $v20, $v20, $v17[3h]
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outputVtxPos) // load Z into W slot, will be for fog below
    vge     $v29, $v16, $v31[2] // Occlusion plane equation >= 0 in elems 3, 7
    vmudh   $v29, vOne, $v31[4] // 4 * 1 in elems 3, 7
    cfc2    $11, $vcc // Load occlusion plane mid results to bits 3 and 7 (garbage in others)
    vmadn   $v21, $v21, $v31[0] // -4
    andi    $10, $10, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmadh   $v20, $v20, $v31[0] // -4
    ori     $10, $10, CLIP_VTX_USED // Write for all first verts, only matters for generated verts
    vmudl   $v29, $v21, $v17[2h]
    lsv     vPairTPosI[14], (VTX_Z_INT     )(secondVtxPos) // load Z into W slot, will be for fog below
    vmadm   $v29, $v20, $v17[2h]
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outputVtxPos) // load Z into W slot, will be for fog below
    vmadn   $v16, $v21, $v17[3h]
    lqv     $v26, (0x10)(rdpCmdBufEndP1) // Load viewport offset from temp mem
    vmadh   $v17, $v20, $v17[3h] // $v17:$v16 is 1/W
    lqv     $v21, (0x00)(rdpCmdBufEndP1) // Load viewport scale from temp mem
    andi    $20, $20, ~(CLIP_OCCLUDED | (CLIP_OCCLUDED >> 4)) // Mask out bits we will or in    
    vmudl   $v29, vPairTPosF, $v16[3h]
    ssv     $v16[14],         (VTX_INV_W_FRAC)(secondVtxPos)
    vmadm   $v29, vPairTPosI, $v16[3h]
    ssv     $v16[6],          (VTX_INV_W_FRAC)(outputVtxPos)
    vmadn   vPairTPosF, vPairTPosF, $v17[3h]
    ssv     $v17[14],         (VTX_INV_W_INT )(secondVtxPos)
    vmadh   vPairTPosI, vPairTPosI, $v17[3h] // pos * 1/W
    ssv     $v17[6],          (VTX_INV_W_INT )(outputVtxPos)
    ldv     $v17[0], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // Load coeffs 0-3
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
    ldv     $v17[8], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // and for vtx 2
    vmadm   vPairTPosI, vPairTPosI, $v30[3] // Persp norm
    andi    $11, $11, CLIP_OCCLUDED | (CLIP_OCCLUDED >> 4) // Only meaningful bits from occlusion
    vmadn   vPairTPosF, $v31, $v31[2] // 0
    or      $20, $20, $11          // Combine occlusion results with scaled results
    vge     $v29, $v31, $v31[2h] // Set VCC to 00110011
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vmudh   $v29, $v26, vOne // offset * 1
    andi    $20, $20, CLIP_SCAL_NPXY | CLIP_OCCLUDED // Mask to only bits we care about
    vmadn   vPairTPosF, vPairTPosF, $v21 // + XYZ * scale
    andi    $11, $11, CLIP_SCAL_NPXY | CLIP_OCCLUDED // Mask to only bits we care about
    vmadh   vPairTPosI, vPairTPosI, $v21
    or      $24, $24, $20          // Combine results for second vertex
    vmadh   $v21, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
    or      $10, $10, $11          // Combine results for first vertex
    vmrg    $v26, vOne, $v31[1] // Signs of $v26 are --++--++
    andi    $11, $5, G_FOG >> 8    // Nonzero if fog enabled
    vmudh   $v16, vPairTPosI, $v31[4] // 4; scale up x and y
    slv     vPairTPosI[8],  (VTX_SCR_VEC   )(secondVtxPos)
    vmudh   $v26, $v26, $v31[5] // $v26 is 0xC000, 0xC000, 0x4000, 0x4000, repeat
    slv     vPairTPosI[0],  (VTX_SCR_VEC   )(outputVtxPos)
    vge     $v21, $v21, $v31[6] // 0x7F00; clamp fog to >= 0 (want low byte only)
    ssv     vPairTPosF[12], (VTX_SCR_Z_FRAC)(secondVtxPos)
    vge     $v20, vPairTPosI, $v31[2] // 0; clamp Z to >= 0
    ssv     vPairTPosF[4],  (VTX_SCR_Z_FRAC)(outputVtxPos)
    vmulf   $v29, $v17, $v16[0h]       //    4*X1*c0, --,    4*X1*c2, --, repeat vtx 2
    beqz    $11, vtx_skip_fog
     vmacf  $v25, $v26, vPairTPosI[1h] // -0x4000*Y1, --, +0x4000*Y1, --, repeat vtx 2
    sbv     $v21[15],         (VTX_COLOR_A   )(secondVtxPos)
    sbv     $v21[7],          (VTX_COLOR_A   )(outputVtxPos)
vtx_skip_fog:
    vmulf   $v29, $v17, $v16[1h]       // --,    4*Y1*c1, --,    4*Y1*c3, repeat vtx 2
    ssv     $v20[12],         (VTX_SCR_Z     )(secondVtxPos)
    vmacf   $v26, $v26, vPairTPosI[0h] // --, -0x4000*X1, --, +0x4000*X1, repeat vtx 2
    ssv     $v20[4],          (VTX_SCR_Z     )(outputVtxPos)
    veq     $v29, $v31, $v31[0q]       // Set VCC to 10101010
    ldv     $v17[0], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // Load coeffs 4-7
    vmrg    $v25, $v25, $v26           // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
    ldv     $v17[8], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // and for vtx 2
    vge     $v29, $v25, $v17           // Each compare to coeffs 4-7
    cfc2    $20, $vcc
    andi    $11, $20, 0x00F0 // Bits 4-7 for vtx 2
    beqz    $11, @@skipv2    // If 0, all equations true, don't clear occluded flag
     andi   $20, $20, 0x000F // Bits 0-3 for vtx 1
    andi    $24, $24, ~CLIP_OCCLUDED // At least one eqn false, clear vtx 2 occluded flag
@@skipv2:
    beqz    $20, @@skipv1    // If 0, all equations true, don't clear occluded flag
     sh     $24,              (VTX_CLIP      )(secondVtxPos) // Store second vertex clip flags
    andi    $10, $10, ~CLIP_OCCLUDED // At least one eqn false, clear vtx 1 occluded flag
@@skipv1:    
    jr      $ra
     sh     $10,              (VTX_CLIP      )(outputVtxPos) // Store first vertex results

    
.if (. & 4)
    .warning "One instruction of padding before ovl234"
.endif

.align 8
ovl234_start:

ovl3_start:
// Clipping overlay.

// Jump here to do lighting. If overlay 3 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_lighting_entrypoint_ovl3ver:        // same IMEM address as ovl234_lighting_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2

// Jump here for all overlay 4 features. If overlay 3 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ovl4_entrypoint_ovl3ver:            // same IMEM address as ovl234_ovl4_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here to do clipping. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl234_clipping_entrypoint:
.if CFG_PROFILING_B
    addi    perfCounterB, perfCounterB, 1  // Increment clipped (input) tris count
.endif
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
    li      $9, CLIP_CAMPLANE                        // Initial clip mask for no nearclipping
// Available locals here: $11, $1, $7, $20, $24, $10
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
    addi    $10, outputVtxPos, -clipTempVerts  // This is within the loop rather than before b/c delay after lhu
    blez    $10, clip_done                 // If can't find one (should never happen), give up
     andi   $11, $11, CLIP_VTX_USED
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
    // This is computing vClDiffI:F = vClBaseI:F / vClDiffI:F to high precision.
    // The first step is a sort of range reduction, where $v2 becomes a scale factor
    // (roughly min(1.0f, abs(1.0f / vClDiffI:F))) which scales down vClDiffI:F and
    // the final result. Then the reciprocal of vClDiffI:F is computed with a Newton-
    // Raphson iteration and multiplied by vClBaseI:F. Finally scale down by $v2.
    vor     $v29, vClDiffI, vOne[0]       // round up int sum to odd; this ensures the value is not 0, otherwise v29 will be 0 instead of +/- 2
    vrcph   $v3[3], vClDiffI[3]
    vrcpl   $v2[3], vClDiffF[3]           // frac: 1 / (x+y+z+w), vtx on screen - vtx off screen
    vrcph   $v3[3], $v31[2]               // 0; get int result of reciprocal
    vabs    $v29, $v29, $v31[3]           // 2; v29 = +/- 2 based on sum positive (incl. zero) or negative
    vmudn   $v2, $v2, $v29[3]             // multiply reciprocal by +/- 2
    vmadh   $v3, $v3, $v29[3]
    veq     $v3, $v3, $v31[2]             // 0; if reciprocal high is 0
    vmrg    $v2, $v2, $v31[1]             // keep reciprocal low, otherwise set to -1
    vmudl   $v29, vClDiffF, $v2[3]        // sum frac * reciprocal, discard
    vmadm   vClDiffI, vClDiffI, $v2[3]    // sum int * reciprocal, frac out
    vmadn   vClDiffF, $v31, $v31[2]       // 0; get int out
    vrcph   $v13[3], vClDiffI[3]          // reciprocal again (discard result)
    vrcpl   $v12[3], vClDiffF[3]          // frac part
    vrcph   $v13[3], $v31[2]              // 0; int part
    vmudl   $v29, $v12, vClDiffF          // self * own reciprocal? frac*frac discard
    vmadm   $v29, $v13, vClDiffF          // self * own reciprocal? int*frac discard
    vmadn   vClDiffF, $v12, vClDiffI      // self * own reciprocal? frac out
    vmadh   vClDiffI, $v13, vClDiffI      // self * own reciprocal? int out
    vmudh   $v29, vOne, $v31[4]           // 4 (int part), Newton-Raphson algorithm
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
    vmadn   vClDiffF, $v31, $v31[2]       // End of computing vClDiff = vClBase / vClDiff
    vlt     vClDiffI, vClDiffI, vOne[0]   // If integer part of factor less than 1,
    vmrg    vClDiffF, vClDiffF, $v31[1]   // keep frac part of factor, else set to 0xFFFF (max val)
    vsubc   $v29, vClDiffF, vOne[0]       // frac part - 1 for carry
    vge     vClDiffI, vClDiffI, $v31[2]   // 0; If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    vmrg    vClFade1, vClDiffF, vOne[0]   // keep frac part of factor, else set to 1 (min val)
    vmudn   vClFade2, vClFade1, $v31[1]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for on screen vert
    // Fade between attributes for on screen and off screen vert
    // Also, colors are now in $v12 and $v13.
    // Also, texture coords are now in $v14 and vPairST.
    vmudm   $v29, $v12, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color and TC
    lhu     $11, VTX_CLIP($3)             // Load clip flags for off screen vert
    vmadm   vPairRGBA, $v13, vClFade2[3]  // + Fade factor for on  screen vert * on  screen vert color
    lhu     $5, geometryModeLabel + 1     // Load middle 2 bytes of geom mode, incl fog setting
    vmudm   $v29, $v14, vClFade1[3]       //   Fade factor for off screen vert * off screen vert TC
    move    secondVtxPos, outputVtxPos    // Writes garbage second vertex and then output vertex to same place
    vmadm   vPairST, vPairST, vClFade2[3] // + Fade factor for on  screen vert * on  screen vert TC
    andi    $11, $11, ~CLIP_VTX_USED  // Clear used flag from off screen vert
    vmudl   $v29, $v6, vClFade1[3]        //   Fade factor for off screen vert * off screen vert pos frac
    sh      outputVtxPos, (clipPoly)(clipPolyWrite) // Write pointer to generated vertex to polygon
    vmadm   $v29, $v7, vClFade1[3]        // + Fade factor for off screen vert * off screen vert pos int
    addi    clipPolyWrite, clipPolyWrite, 2  // Increment write ptr
    vmadl   $v29, $v4, vClFade2[3]        // + Fade factor for on screen vert * on screen vert pos frac
    sh      $11, VTX_CLIP($3)             // Store modified clip flags for off screen vert
    vmadm   vPairTPosI, $v5, vClFade2[3]  // + Fade factor for on screen vert * on screen vert pos int
    jal     vtx_store                     // Write new vertex
     vmadn  vPairTPosF, $v31, $v31[2]     // 0; load resulting frac pos
clip_nextedge:
    bnez    clipFlags, clip_edgelooptop   // Discard V2 if it was off screen (whether inserted vtx or not)
     move   $3, $2                        // Move what was the end of the edge to be the new start of the edge
    sh      $3, (clipPoly)(clipPolyWrite) // Former V2 was on screen, so add it to the output polygon
    j       clip_edgelooptop
     addi   clipPolyWrite, clipPolyWrite, 2

clip_w:
    vcopy   vClBaseF, $v4                 // Result is just W
    j       clip_skipxy
     vcopy  vClBaseI, $v5

clip_nextcond:
    sub     $11, clipPolyWrite, clipPolySelect // Are there less than 3 verts in the output polygon?
    bltz    $11, clip_done                    // If so, degenerate result, quit
     sh     $zero, (clipPoly)(clipPolyWrite)  // Terminate the output polygon with a 0
    lhu     $3, (clipPoly - 2)(clipPolyWrite) // Initialize the edge start (V3) to the last vert
    beqz    clipMaskIdx, clip_draw_tris
     lbu    $11, (clipCondShifts - 1)(clipMaskIdx) // Load next clip condition shift amount
    li      $9, 1
    sllv    $9, $9, $11                       // $9 is clip mask
    j       clip_condlooptop
     addi   clipMaskIdx, clipMaskIdx, -1
    
clip_draw_tris:
    lqv     $v30, (v30Value)($zero)
// Current polygon starts 6 (3 verts) below clipPolySelect, ends 2 (1 vert) below clipPolyWrite
    addi    clipPolySelect, clipPolySelect, -6 // = Pointer to first vertex
    // Available locals: most registers ($5, $6, $7, $8, $9, $11, $10, etc.)
    // Available regs which won't get clobbered by tri write: 
    // clipPolySelect, clipPolyWrite, $14 (inputVtxPos), $15 (outputVtxPos), (more)
    // Find vertex highest on screen (lowest screen Y)
    li      $5, 0x7FFF                // current best value
    move    $7, clipPolySelect        // initial vertex pointer
    lhu     $10, (clipPoly)($7)       // Load vertex address
clip_search_highest_loop:
    lh      $9, VTX_SCR_Y($10)        // Load screen Y
    sub     $11, $9, $5               // Branch if new vtx Y >= best vtx Y
    bgez    $11, clip_search_skip_better
     addi   $7, $7, 2                 // Next vertex
    addi    $14, $7, -2               // Save pointer to best/current vertex
    move    $5, $9                    // Save best value
clip_search_skip_better:
    bne     clipPolyWrite, $7, clip_search_highest_loop
     lhu    $10, (clipPoly)($7)       // Next vertex address
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
    // $1, $2, $3, $5 are vertices at $11=prev, $14, $15, $10=next
    bne     $14, clipPolySelect, @@skip1
     addi   $11, $14, -2
    move    $11, clipPolyWrite
@@skip1:
    beq     $11, $15, clip_done // If previous is $15, we only have two verts left, done
     lhu    $1, (clipPoly)($11)     // From the group below, need something in the delay slot
    bne     $15, clipPolyWrite, @@skip2
     addi   $10, $15, 2
    move    $10, clipPolySelect
@@skip2:
    lhu     $2, (clipPoly)($14)
    lhu     $3, (clipPoly)($15)
    lhu     $5, (clipPoly)($10)
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
    move    $15, $10           // Update $15 to be next
clip_final_draw:
    mtc2    $1, $v27[10]              // Addresses go in vector regs too
    mtc2    $2, $v4[12]
    mtc2    $3, $v27[14]
    j       tri_noinit         // Draw tri
     li     $ra, clip_draw_loop // When done, return to top of loop

clip_done:
    lh      $ra, tempTriRA
    jr      $ra
     li     clipPolySelect, -1  // Back to normal tri drawing mode (check clip masks)

ovl3_end:
.align 8
ovl3_padded_end:

.orga max(max(ovl2_padded_end - ovl2_start, ovl4_padded_end - ovl4_start) + orga(ovl3_start), orga())
ovl234_end:

.if CFG_PROFILING_A
vertex_end:
    li      $ra, 0                           // Flag for coming from vtx
tri_end:
    mfc0    $11, DPC_CLOCK
    lw      $10, startCounterTime
    sub     $11, $11, $10
    beqz    $ra, run_next_DL_command         // $ra != 0 if from tri cmds
     add    perfCounterA, perfCounterA, $11  // Add to vert cycles perf counter
    sub     perfCounterA, perfCounterA, $11  // From tris, undo add to vert perf counter
    sub     $10, perfCounterC, $4            // How long we stalled for RDP FIFO during this cmd
    sub     $11, $11, $10                    // Subtract that from the tri cycles
    j       run_next_DL_command
     add    perfCounterD, perfCounterD, $11  // Add to tri cycles perf counter
.endif

tri_fan_store:
    lb      $11, (inputBufferEnd - 7)(inputBufferPos) // Load vtx 1
    j       tri_main
     sb     $11, 5(rdpCmdBufPtr)         // Store vtx 1

tri_return_from_addrs:
    mfc2    $1, $v27[10]
    vcopy   $v4, $v27                    // Need vtx 2 addr in $v4 elem 6
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 0x4000  // Increment number of tris requested
.endif
    mfc2    $2, $v27[12]
.if !ENABLE_PROFILING
    move    $4, $1                // Save original vertex 1 addr (pre-shuffle) for flat shading
.endif
    li      clipPolySelect, -1    // Normal tri drawing mode (check clip masks)
    sh      $ra, tempTriRA        // If end up clipping, where to go after
tri_noinit:
    // ra is next cmd, second tri in TRI2, or middle of clipping
    llv     $v6[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vclr    vZero
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vmov    $v6[6], $v27[5]         // elem 6 of v6 = vertex 1 addr
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    lhu     $5, VTX_CLIP($1)
    vmov    $v8[6], $v27[7]         // elem 6 of v8 = vertex 3 addr
    lhu     $7, VTX_CLIP($2)
    vmudh   $v2, vOne, $v6[1] // v2 all elems = y-coord of vertex 1
    lhu     $8, VTX_CLIP($3)
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    lw      $6, geometryModeLabel // Load full geometry mode word
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    and     $9, $5, $7
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    and     $9, $9, $8 // $9 = all clip bits which are true for all three verts
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    andi    $11, $9, CLIP_SCRN_NPXY | CLIP_CAMPLANE // All three verts on wrong side of same plane
    vmrg    $v14, $v6, $v4    // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    bnez    $11, return_routine // Then the whole tri is offscreen, cull
     or     $5, $5, $7
    vmudh   $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    or      $5, $5, $8        // $5 = all clip bits which are true for any verts
    vmadh   $v29, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    andi    $5, $5, CLIP_SCAL_NPXY | CLIP_CAMPLANE // Does tri cross scaled bounds or cam plane?
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    sra     $11, clipPolySelect, 31 // All 1s if negative, meaning clipping allowed
    vmrg    $v10, $v6, $v4    // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    and     $5, $5, $11       // Clear this if clipping not allowed
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    bnez    $5, ovl234_clipping_entrypoint // Facing info and occlusion may be garbage if need to clip
     mfc2   $8, $v29[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    $v4, $v14, $v8    // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    andi    $9, $9, CLIP_OCCLUDED
    vmrg    $v14, $v8, $v14   // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    bnez    $9, tri_culled_by_occlusion_plane // Cull if all verts occluded
     srl    $11, $8, 31       // = 0 if x prod positive (back facing), 1 if x prod negative (front facing)
    vlt     $v6, $v6, $v2     // v6 (thrown out), VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    beqz    $8, return_routine  // If cross product is 0, tri is degenerate (zero area), cull.
     addi   $11, $11, 21      // = 21 if back facing, 22 if front facing
    vmudh   $v3, vOne, $v31[5]   // 0x4000; some rounding factor
    sllv    $11, $6, $11      // Sign bit = bit 10 of geom mode if back facing, bit 9 if front facing
    vmrg    $v2, $v4, $v10   // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    bltz    $11, return_routine // Cull if bit is set (culled based on facing)
     vmrg   $v10, $v10, $v4   // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    vmudn   $v4, $v14, $v31[5] // 0x4000
tV1AtF equ $v5
tV2AtF equ $v7
tV3AtF equ $v9
tV1AtI equ $v18
tV2AtI equ $v19
tV3AtI equ $v21
    vnxor   tV1AtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    mfc2    $1, $v14[12]      // $v14 = lowest Y value = highest on screen (x, y, addr)
    vsub    $v6, $v2, $v14
    vnxor   tV2AtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    mfc2    $2, $v2[12]       // $v2 = mid vertex (x, y, addr)
    vsub    $v8, $v10, $v14
    vnxor   tV3AtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    mfc2    $3, $v10[12]      // $v10 = highest Y value = lowest on screen (x, y, addr)
    vsub    $v11, $v14, $v2
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
.if !ENABLE_PROFILING
    lpv     $v25[0], VTX_COLOR_VEC($4)  // Load RGB from vertex 4 (flat shading vtx)
.endif
    vrcp    $v20[0], $v15[1]
.if !ENABLE_PROFILING
    sll     $11, $6, 10                 // Moves the value of G_SHADING_SMOOTH into the sign bit
.endif
    vrcph   $v22[0], $v17[1]
    andi    $6, $6, (G_SHADE | G_ZBUFFER)
    vrcpl   $v23[1], $v16[1]
.if !ENABLE_PROFILING
    bltz    $11, tri_skip_flat_shading  // Branch if G_SHADING_SMOOTH is set
.endif
     vrcph  $v24[1], $v31[2]            // 0
.if !ENABLE_PROFILING
    vlt     $v29, $v31, $v31[3]         // Set vcc to 11100000
    vmrg    tV1AtI, $v25, tV1AtI        // RGB from $4, alpha from $1
    vmrg    tV2AtI, $v25, tV2AtI        // RGB from $4, alpha from $2
    vmrg    tV3AtI, $v25, tV3AtI        // RGB from $4, alpha from $3
tri_skip_flat_shading:
.endif
    vrcp    $v20[2], $v6[1]
    lb      $20, (alphaCompareCullMode)($zero)
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
    sra     $10, $11, 31
    vmov    $v15[3], $v8[0]
    and     $11, $11, $10
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
    vmadn   $v20, $v31, $v31[2] // 0
    sra     $10, $11, 31
    vmudm   $v25, $v15, $v30[2] // 0x1000
    and     $11, $11, $10
    vmadn   $v15, $v31, $v31[2] // 0
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
    andi    $10, $5, 0x0080 // Extract the left major flag from $5
    vmadl   $v29, $v22, $v4[1]
    or      $10, $10, $7 // Combine the left major flag with the level and tile from the texture settings
    vmadm   $v29, $v15, $v4[1]
    sb      $10, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vmadn   $v2, $v22, $v26[1]
    beqz    $9, tri_skip_tex // If textures are not enabled, skip texture coefficient calculation
     vmadh  $v3, $v15, $v26[1]
    vrcph   $v29[0], $v27[0]
    vrcpl   $v10[0], $v27[1]
    vmudh   $v14, vOne, $v13[1q]
    vrcph   $v27[0], $v31[2]     // 0
    vmudh   $v22, vOne, $v31[7]  // 0x7FFF
    vmudm   $v29, $v13, $v10[0]
    vmadl   $v29, $v14, $v10[0]
    llv     $v22[0], VTX_TC_VEC($1)
    vmadn   $v14, $v14, $v27[0]
    llv     $v22[8], VTX_TC_VEC($2)
    vmadh   $v13, $v13, $v27[0]
    vmudh   $v10, vOne, $v31[7]  // 0x7FFF
    vge     $v29, $v30, $v30[7]  // Set VCC to 11110001; select RGBA___Z or ____STW_
    llv     $v10[8], VTX_TC_VEC($3)
    vmudm   $v29, $v22, $v14[0h]
    vmadh   $v22, $v22, $v13[0h]
    vmadn   $v25, $v31, $v31[2]  // 0
    vmudm   $v29, $v10, $v14[6]  // acc = (v10 * v14[6]); v29 = mid(clamp(acc))
    vmadh   $v10, $v10, $v13[6]  // acc += (v10 * v13[6]) << 16; v10 = mid(clamp(acc))
    vmadn   $v13, $v31, $v31[2]  // 0; v13 = lo(clamp(acc))
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
.if !ENABLE_PROFILING
    addi    perfCounterA, perfCounterA, 1 // Increment number of tris sent to RDP
.endif
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
    // All values start in element 7. "a", attribute, is Z. Need
    // tV1AtI, tV1AtF, tDaDxI, tDaDxF, tDaDeI, tDaDeF, tDaDyI, tDaDyF
    vmov    tDaDyF[5], tDaDeF[7]    // DaDy already in elem 7; DaDe to elem 5
    sdv     tV1AtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    vmov    tDaDyI[5], tDaDeI[7]
    sdv     tV1AtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    vmov    tDaDyF[3], tDaDxF[7]    // DaDx to elem 3
    sdv     tV1AtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    vmov    tDaDyI[3], tDaDxI[7]
    sdv     tV1AtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)
    vmudn   tV1AtFF, tDaDeF, $v4[1] // Super-frac (frac * frac) part; assumes v4 factor >= 0
    beqz    $6, check_rdp_buffer_full // see below
     veq    $v29, $v31, $v31[1q] // Set VCC to 01010101
    vmudn   tDaDyF, tDaDyF, $v30[7] // 0x0020
    vmadh   tDaDyI, tDaDyI, $v30[7] // 0x0020
    vmudl   $v29,  tV1AtFF, $v30[7] // 0x0020
    vmadn   tV1AtF, tV1AtF, $v30[7] // 0x0020
    vmadh   tV1AtI, tV1AtI, $v30[7] // 0x0020
    vmrg    tDaDyF, tDaDyF, tDaDyI[1q] // Move int elems 3, 5, 7 to result 2, 4, 6
    ssv     tV1AtF[14], -0x0E(rdpCmdBufPtr)
    ssv     tV1AtI[14], -0x10(rdpCmdBufPtr)
    slv     tDaDyF[4],  -0x0C(rdpCmdBufPtr) // DaDx i/f
    j       check_rdp_buffer_full   // eventually returns to $ra, which is next cmd, second tri in TRI2, or middle of clipping
     sdv    tDaDyF[8],  -0x08(rdpCmdBufPtr) // DaDe i/f, DaDy i/f

.if CFG_PROFILING_B
tri_culled_by_occlusion_plane:
    jr      $ra
     addi   perfCounterB, perfCounterB, 0x4000
.endif


load_overlay_0_and_enter:
    li      postOvlRA, 0x1000                        // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)            // Sets up ovl0 table address
// To use these: set postOvlRA ($10) to the address to execute after the load is
// done, and set cmd_w1_dram to orga(your_overlay).
load_overlays_0_1:
    li      dmaLen, ovl01_end - 0x1000 - 1
    j       load_overlay_inner
     li     dmemAddr, 0x1000

load_overlays_2_3_4:
    addi    postOvlRA, $ra, -8  // Got here with jal, but want to return to addr of jal itself
    li      dmaLen, ovl234_end - ovl234_start - 1
    li      dmemAddr, ovl234_start
load_overlay_inner:
    lw      $11, OSTask + OSTask_ucode
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 0x4000  // Increment overlay (all 0-4) load count
.endif
.if CFG_PROFILING_C
    mfc0    $9, DPC_CLOCK  // see below
.endif
    jal     dma_read_write
     add    cmd_w1_dram, cmd_w1_dram, $11
    move    $ra, postOvlRA
    // Fall through to while_wait_dma_busy
.if CFG_PROFILING_C
// ...except if profiling DMA time. According to Tharo's testing, and in contradiction
// to the manual, almost no instructions are issued while an IMEM DMA is happening.
// So we have to time it using counters.
    mfc0    $11, SP_DMA_BUSY
overlay_load_while_dma_busy:
    bnez    $11, overlay_load_while_dma_busy
     mfc0   $11, SP_DMA_BUSY
    mfc0    $11, DPC_CLOCK
    sub     $11, $11, $9
    jr      $ra
     add    perfCounterD, perfCounterD, $11
.endif

totalImemUseUpTo1FC8:

.if . > 0x1FC8
    .error "Constraints violated on what can be overwritten at end of ucode (relevant for G_LOAD_UCODE)"
.endif
.org 0x1FC8

// The code from here to the end is shared with S2DEX, so great care is needed for changes.
while_wait_dma_busy:
    mfc0    $11, SP_DMA_BUSY    // Load the DMA_BUSY value
.if CFG_PROFILING_C
    bnez    $11, while_wait_dma_busy
     // perfCounterD is $12, which is a temp register in S2DEX, which happens to
     // never have state carried over while_wait_dma_busy.
     addi   perfCounterD, perfCounterD, 6  // 3 instr + 2 after mfc + 1 taken branch
.else
@@while_dma_busy:
    bnez    $11, @@while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   $11, SP_DMA_BUSY      // Update DMA_BUSY value
.endif
// This routine is used to return via conditional branch
.if !CFG_PROFILING_B
tri_culled_by_occlusion_plane:
.endif
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

// Overlay 0 handles three cases of stopping the current microcode.
// The action here is controlled by $1. If yielding, $1 > 0. If this was
// G_LOAD_UCODE, $1 == 0. If we got to the end of the parent DL, $1 < 0.
ovl0_start:
    sub     $11, rdpCmdBufPtr, rdpCmdBufEndP1
    addi    $10, $11, (RDP_CMD_BUFSIZE + 8) - 1 // Does the current buffer contain anything?
    bgezal  $10, flush_rdp_buffer   // - 1 because there is no bgtzal instruction
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
    jal     while_wait_dma_busy     // Wait for possible RDP flush to finish
     lw     $24, rdpFifoPos
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    lw      $10, startCounterTime
    sub     $11, $11, $10
    add     perfCounterA, perfCounterA, $11
.endif
    bnez    $1, task_done_or_yield  // Continue to load ucode if 0
     mtc0   $24, DPC_END            // Set the end pointer of the RDP so that it starts the task
load_ucode:
    lw      cmd_w1_dram, (inputBufferEnd - 0x04)(inputBufferPos) // word 1 = ucode code DRAM addr
    sw      taskDataPtr, OSTask + OSTask_data_ptr // Store where we are in the DL
    sw      cmd_w1_dram, OSTask + OSTask_ucode // Store pointer to new ucode about to execute
    // Store counters in mITMatrix; first 0x180 of DMEM will be preserved in ucode swap AND
    // if other ucode yields
    sw      perfCounterA, mITMatrix + YDF_OFFSET_PERFCOUNTERA
    sw      perfCounterB, mITMatrix + YDF_OFFSET_PERFCOUNTERB
    sw      perfCounterC, mITMatrix + YDF_OFFSET_PERFCOUNTERC
    sw      perfCounterD, mITMatrix + YDF_OFFSET_PERFCOUNTERD
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

task_done_or_yield:
    sw      perfCounterA, yieldDataFooter + YDF_OFFSET_PERFCOUNTERA
    sw      perfCounterB, yieldDataFooter + YDF_OFFSET_PERFCOUNTERB
    sw      perfCounterC, yieldDataFooter + YDF_OFFSET_PERFCOUNTERC
    bltz    $1, task_done           // $1 < 0 = Got to the end of the parent DL
     sw     perfCounterD, yieldDataFooter + YDF_OFFSET_PERFCOUNTERD
task_yield: // Otherwise $1 > 0 = CPU requested yield
    lw      $11, OSTask + OSTask_ucode         // Save pointer to current ucode
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    li      dmemAddr, 0x8000                   // 0, but negative = write
    li      dmaLen, OS_YIELD_DATA_SIZE - 1
    li      $10, SP_SET_SIG1 | SP_SET_SIG2     // yielded and task done signals
    sw      taskDataPtr, yieldDataFooter + YDF_OFFSET_TASKDATAPTR // Save pointer to where in DL
    sw      $11, yieldDataFooter + YDF_OFFSET_UCODE
    j       dma_read_write
     li     $ra, set_status_and_break

task_done:
    // Copy just the yield data footer, which has the perf counters.
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    addi    cmd_w1_dram, cmd_w1_dram, yieldDataFooter
    li      dmemAddr, 0x8000 | yieldDataFooter // negative = write
    jal     dma_read_write
     li     dmaLen, YIELD_DATA_FOOTER_SIZE - 1
    jal     while_wait_dma_busy
     li     $10, SP_SET_SIG2   // task done signal
set_status_and_break: // $10 is the status to set
    mtc0    $10, SP_STATUS
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
.if CFG_PROFILING_C
    addi    perfCounterC, perfCounterC, 1  // Increment matrix count
.endif
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

G_RDPSETOTHERMODE_handler:
    li      $1, 8      // Offset from scissor DMEM to othermode DMEM
G_SETSCISSOR_handler:  // $1 is 0 if jumped here
    sw      cmd_w0, (scissorUpLeft)($1) // otherMode0 = scissorUpLeft + 8
    j       G_RDP_handler                // Send the command to the RDP
     sw     cmd_w1_dram, (scissorBottomRight)($1) // otherMode1 = scissorBottomRight + 8

G_GEOMETRYMODE_handler: // $7 = G_GEOMETRYMODE (as negative) if jumped here
    lw      $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7) // load the geometry mode value
    and     $11, $11, cmd_w0        // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      $11, $11, cmd_w1_dram   // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    j       run_next_DL_command     // run the next DL command
     sw     $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7)  // update the geometry mode value

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

G_RDPHALF_2_handler:
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 1   // Increment number of tex/fill rects
.endif
    sb      $zero, materialCullMode         // This covers tex and fill rects
    j       G_RDP_handler
     sdv    $v29[0], -8(rdpCmdBufPtr)

G_RELSEGMENT_handler:
    jal     segmented_to_physical    // Resolve new segment address relative to existing segment
G_MOVEWORD_handler:
     srl    $2, cmd_w0, 16           // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $10, (movewordTable - (G_MOVEWORD << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    sll     $11, cmd_w0, 16          // Sign bit = upper bit of offset
    add     $10, $10, cmd_w0         // Offset + base; only lower 12 bits matter
    bltz    $11, run_next_DL_command // If upper bit of offset is set, exit after halfword
     sh     cmd_w1_dram, ($10)       // Store value from cmd into halfword
    j       run_next_DL_command
     sw     cmd_w1_dram, ($10)       // Store value from cmd into word (offset + moveword_table[index])

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
    j       vtx_addrs_from_cmd              // Load start vtx addr in $10, end vtx in $3
     li     $11, culldl_return_from_addrs
culldl_return_from_addrs:
    /*
    CLIP_OCCLUDED can't be included here because: Suppose the list consists of N-1
    verts which are behind the occlusion plane, and 1 vert which is behind the camera
    plane and therefore randomly erroneously also set as behind the occlusion plane.
    However, the convex hull of all the verts goes through visible area. This will be
    incorrectly culled here. We can't afford the extra few instructions to disable
    the occlusion plane if the vert is behind the camera, because this only matters for
    G_CULLDL and not for tris.
    */
    li      $1, (CLIP_SCRN_NPXY | CLIP_CAMPLANE)
    lhu     $11, VTX_CLIP($10)
culldl_loop:
    and     $1, $1, $11
    beqz    $1, run_next_DL_command         // Some vertex is on the screen-side of all clipping planes; have to render
     lhu    $11, (vtxSize + VTX_CLIP)($10)  // next vertex clip flags
    bne     $10, $3, culldl_loop            // loop until reaching the last vertex
     addi   $10, $10, vtxSize               // advance to the next vertex
    li      cmd_w0, 0                       // Clear count of DL cmds to skip loading
G_ENDDL_handler:
    lbu     $1, displayListStackLength      // Load the DL stack index; if end stack,
    beqz    $1, load_overlay_0_and_enter    // load overlay 0; $1 < 0 signals end
     addi   $1, $1, -4                      // Decrement the DL stack index
    j       call_ret_common                 // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($1) // Load addr of DL to return to


ovl1_end:
.align 8
ovl1_padded_end:

.if ovl1_padded_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif

.headersize ovl234_start - orga()

ovl2_start:
// Lighting overlay.

// Jump here to do lighting. If overlay 2 is loaded (this code), jumps into the
// rest of the lighting code below.
ovl234_lighting_entrypoint:
.if CFG_PROFILING_B
    addi    perfCounterA, perfCounterA, 2    // Increment lit vertex count by 2
.endif
    j       lt_continue_setup
     andi   $11, $5, G_PACKED_NORMALS >> 8

// Jump here for all overlay 4 features. If overlay 2 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ovl4_entrypoint_ovl2ver:            // same IMEM address as ovl234_ovl4_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here to do clipping. If overlay 2 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipping_entrypoint_ovl2ver:        // same IMEM address as ovl234_clipping_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

lt_continue_setup:
    // Inputs: vPairPosI/F vertices pos world int:frac, vPairRGBA, vPairST,
    // vPairNrml, vAAA:vBBB (to be merged) packed normals
    // Outputs: leave alone vPairPosI/F; update vPairRGBA, vPairST 
    // Locals: vAAA and vBBB after merge and normals selection, vCCC, vDDD, vPairLt, vNrmOut
    // New available locals: $6, $7 (existing: $11, $10, $20, $24)
    vmrg    vPairNrml, vPairNrml, vDDD       // Merge normals
    beqz    $11, lt_skip_packed_normals
     vmrg   vAAA, vAAA, vBBB          // Merge packed normals
    // Packed normals algorithm. This produces a vector (one for each input vertex)
    // in vPairNrml such that |X| + |Y| + |Z| = 0x7F00 (called L1 norm), in the
    // same direction as the standard normal vector. The length is not "correct"
    // compared to the standard normal, but it's is normalized anyway after the M
    // matrix transform.
vPackPXY   equ $v25 // = vCCC; positive X and Y in packed normals
vPackZ     equ $v26 // = vDDD; Z in packed normals
    vand    vPackPXY, vAAA, $v31[6]          // 0x7F00; positive X, Y
    vmudh   $v29, vOne, $v31[1]              // -1; set all elems of $v29 to -1
    vaddc   vBBB, vPackPXY, vPackPXY[1q]     // elems 0, 4: +X + +Y, no clamping; VCO always 0
    vxor    vPairNrml, vPackPXY, $v31[6]     // 0x7F00 - x, 0x7F00 - y
    vxor    vPackZ, vBBB, $v31[6]            // 0x7F00 - +X - +Y in elems 0, 4
    vge     $v29, $v29, vBBB[0h]             // set 0-3, 4-7 vcc if -1 >= (+X + +Y), = negative
    vmrg    vPairNrml, vPairNrml, vPackPXY   // If so, use 0x7F00 - +X, else +X (same for Y)
    vne     $v29, $v31, $v31[2h]             // Set VCC to 11011101
    vabs    vPairNrml, vAAA, vPairNrml       // Apply sign of original X and Y to new X and Y
    vmrg    vPairNrml, vPairNrml, vPackZ[0h] // Move Z to elements 2, 6
lt_skip_packed_normals:
    // Transform normals by M, in case normalsMode = G_NORMALSMODE_FAST.
    vsub    vPairRGBA, vPairRGBA, $v31[7] // 0x7FFF; offset alpha, will be fixed later
    lbu     curLight, numLightsxSize
    vmudn   $v29, vM0F, vPairNrml[0h]
    lbu     $11, (normalsMode)($zero)
    vmadh   $v29, vM0I, vPairNrml[0h]
    andi    $6, $5, G_LIGHTING_SPECULAR >> 8
    vmadn   $v29, vM1F, vPairNrml[1h]
    addi    curLight, curLight, altBase // Point to ambient light
    vmadh   $v29, vM1I, vPairNrml[1h]
    andi    $10, $5, (G_LIGHTING_SPECULAR | G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vmadn   vBBB, vM2F, vPairNrml[2h] // vBBB = normals frac
    beqz    $11, lt_after_xfrm_normals // Skip if G_NORMALSMODE_FAST
     vmadh  vAAA, vM2I, vPairNrml[2h] // vAAA = normals int
    // Transform normals by M inverse transpose, for G_NORMALSMODE_AUTO or G_NORMALSMODE_MANUAL
vLtMIT0I   equ $v26 // = vDDD
vLtMIT1I   equ $v25 // = vCCC
vLtMIT2I   equ $v23 // = vAAA; last in multiply
vLtMIT0F   equ $v29 // = temp; first
vLtMIT1F   equ $v17 // = vPairLt
vLtMIT2F   equ $v24 // = vBBB; second to last
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
    // At this point we have stuffed two and three quarters matrices into registers at once.
    // Nintendo was only able to fit one and three quarters matrices into registers at once.
    vmudn   $v29, vLtMIT0F, vPairNrml[0h] // vLtMIT0F = $v29
    vmadh   $v29, vLtMIT0I, vPairNrml[0h]
    vmadn   $v29, vLtMIT1F, vPairNrml[1h]
    vmadh   $v29, vLtMIT1I, vPairNrml[1h]
    vmadn   vBBB, vLtMIT2F, vPairNrml[2h] // vLtMIT2F = vBBB = normals frac
    vmadh   vAAA, vLtMIT2I, vPairNrml[2h] // vLtMIT2I = vAAA = normals int
lt_after_xfrm_normals:
    // Normalize normals; in vAAA:vBBB i/f, out vNrmOut
    jal     lt_normalize
     luv    vPairLt, (ltBufOfs + 0)(curLight) // Total light level, init to ambient
    // Set up ambient occlusion: light *= (factor * (alpha - 1) + 1)
.if CFG_DEBUG_NORMALS
.warning "Debug normals visualization is enabled"
    vmudh   $v29, vOne, $v31[5] // 0x4000; middle gray
    j       vtx_return_from_lighting
     vmacf  vPairRGBA, vNrmOut, $v31[5] // 0x4000; + 0.5 * normal
.else
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   vCCC, vPairRGBA, $v30[0] // + (alpha - 1) * aoAmb factor; elems 3, 7
    vcopy   vPairNrml, vNrmOut
.endif
    beqz    $10, lt_loop // Not specular or fresnel
     vmulf  vPairLt, vPairLt, vCCC[3h] // light color *= ambient factor
    // Get vNrmOut = normalize(camera - vertex), vAAA = (vPairNrml dot vNrmOut)
    ldv     vAAA[0], (cameraWorldPos - altBase)(altBaseReg) // Camera world pos
    j       lt_normal_to_vertex
     ldv    vAAA[8], (cameraWorldPos - altBase)(altBaseReg)
lt_after_camera:
    // If specular, replace vPairNrml with reflected vector
    vne     $v29, $v31, $v31[3h]      // Set VCC to 11101110
    beqz    $6, @@skip
     li     $10, 0                    // Clear flag for specular or fresnel
    vmulf   vBBB, vPairNrml, vAAA[0h] // Projection of camera vec onto normal
    vmudh   $v29, vNrmOut, $v31[1]    // -camera vec
    vmadh   vPairNrml, vBBB, $v31[3]  // + 2 * projection
@@skip:
    vmrg    vPairNrml, vPairNrml, vAAA[0h] // Dot product for fresnel in vPairNrml[3h]
lt_loop:
    // Valid: vPairPosI/F, vPairST, modified vPairRGBA ([3h] = alpha - 1),
    // vPairNrml normals [0h:2h] fresnel [3h], vPairLt [0h:2h]
    lpv     vAAA[0], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 0-2
    vlt     $v29, $v31, $v31[4] // Set VCC to 11110000
    lpv     vCCC[4], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 4-6
    lbu     $11,     (ltBufOfs + 3 - lightSize)(curLight) // Light type / constant attenuation
    beq     curLight, altBaseReg, lt_post
     vmrg   vAAA, vAAA, vCCC                            // vAAA = light direction
    bnez    $11, lt_point
     luv    vDDD,    (ltBufOfs + 0 - lightSize)(curLight) // Light color
    vmulf   vAAA, vAAA, vPairNrml // Light dir * normalized normals
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   vCCC, vPairRGBA, $v30[1] // + (alpha - 1) * aoDir factor; elems 3, 7
    vcopy   vBBB, vOne // Directional light dot scaling = 0001.0001, approx == 1.0
    vmudh   $v29, vOne, vAAA[0h] // Sum components of dot product as signed
    vmadh   $v29, vOne, vAAA[1h]
    vmadh   vAAA, vOne, vAAA[2h]
lt_finish_light:
    // vAAA is unclamped dot product, vBBB[2h:3h] is point light scaling on dot product,
    // vCCC is amb occ factor, vDDD is light color
    beqz    $6, lt_skip_specular
     vmulf  vDDD, vDDD, vCCC[3h] // light color *= dir or point light factor
    lb      $20, (ltBufOfs + 0xF - lightSize)(curLight) // Light size factor
    mtc2    $20, vCCC[0]        // Light size factor
    vxor    vAAA, vAAA, $v31[7] // = 0x7FFF - dot product
    vmudh   vAAA, vAAA, vCCC[0] // * size factor
    vxor    vAAA, vAAA, $v31[7] // = 0x7FFF - result
lt_skip_specular:
    vge     vAAA, vAAA, $v31[2] // 0; clamp dot product to >= 0
    vmudm   $v29, vAAA, vBBB[2h] // Dot product int * scale frac
    vmadh   vAAA, vAAA, vBBB[3h] // Dot product int * scale int, clamp to 0x7FFF
    addi    curLight, curLight, -lightSize
    vmudh   $v29, vOne, vPairLt // Load accum mid with current light level
    j       lt_loop
     vmacf  vPairLt, vDDD, vAAA[0h] // + light color * dot product
    
lt_post:
    // Valid: vPairPosI/F, vPairST, modified vPairRGBA ([3h] = alpha - 1),
    // vPairNrml normal [0h:2h] fresnel [3h], vPairLt [0h:2h], vAAA lookat 0 dir
vLtRGBOut  equ $v25 // = vCCC: light / effects RGB output
vLtAOut    equ $v26 // = vDDD: light / effects alpha output
vLookat1   equ $v23 // = vAAA: lookat direction 1
vLookat0   equ $v17 // = vPairLt:   lookat direction 0 (not initially)
    vadd    vPairRGBA, vPairRGBA, $v31[7]  // 0x7FFF; undo change for ambient occlusion
    andi    $11, $5, G_LIGHTTOALPHA >> 8
    andi    $20, $5, G_PACKED_NORMALS >> 8
    andi    $10, $5, G_TEXTURE_GEN >> 8
    vmulf   vLtRGBOut, vPairRGBA, vPairLt  // RGB output is RGB * light
    beqz    $11, lt_skip_cel
     vcopy  vLtAOut, vPairRGBA             // Alpha output = vertex alpha (only 3, 7 matter)
    // Cel: alpha = max of light components, RGB = vertex color
    vge     vLtAOut, vPairLt, vPairLt[1h]  // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    vge     vLtAOut, vLtAOut, vLtAOut[2h]  // elem 0 = max(R0, G0, B0); equiv for elem 4
    vcopy   vLtRGBOut, vPairRGBA           // RGB output is vertex color
    vmudh   vLtAOut, vOne, vLtAOut[0h]     // move light level elem 0, 4 to 3, 7
lt_skip_cel:
    vne     $v29, $v31, $v31[3h]           // Set VCC to 11101110
    bnez    $20, lt_skip_novtxcolor
     andi   $24, $5, (G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vcopy   vLtRGBOut, vPairLt             // If no packed normals, base output is just light
lt_skip_novtxcolor:
    vmulf   vLookat0, vPairNrml, vAAA      // Normal * lookat 0 dir; vLookat0 = vPairLt
    beqz    $24, lt_skip_fresnel
     vmrg   vPairRGBA, vLtRGBOut, vLtAOut  // Merge base output and alpha output
    // Fresnel: dot product in vPairNrml[3h]. Also valid rest of vPairNrml for texgen,
    // vLookat0, vPairRGBA. Available: vAAA, vBBB, vNrmOut.
    lqv     vBBB, (v30Value)($zero)     // Need 0x0100 constant, in elem 3
    vabs    vAAA, vPairNrml, vPairNrml  // Absolute value of dot product for underwater
    andi    $11, $5, G_FRESNEL_COLOR >> 8
    vmudh   $v29, vOne, $v30[7]         // Fresnel offset
    vmacf   vAAA, vAAA, $v30[6]         // + factor * scale
    beqz    $11, @@skip
     vmudh  vAAA, vAAA, vBBB[3]         // Result * 0x0100, clamped to 0x7FFF
    veq     $v29, $v31, $v31[3h]        // Set VCC to 00010001 if G_FRESNEL_COLOR
@@skip:
    vmrg    vPairRGBA, vPairRGBA, vAAA[3h] // Replace color or alpha with fresnel
    vge     vPairRGBA, vPairRGBA, $v31[2]  // Clamp to >= 0 for fresnel; doesn't affect others
lt_skip_fresnel:
    beqz    $10, vtx_return_from_lighting  // no texgen
    // Texgen: vLookat0, vPairNrml, have to leave vPairPosI/F, vPairRGBA; output vPairST
     vmudh  $v29, vOne, vLookat0[0h]
    lpv     vLookat1[4], (ltBufOfs + 0 - lightSize)(curLight) // Lookat 1 dir in elems 0-2
    vmadh   $v29, vOne, vLookat0[1h]
    lpv     vDDD[0],     (ltBufOfs + 8 - lightSize)(curLight) // Lookat 1 dir in elems 4-6
    vmadh   vLookat0, vOne, vLookat0[2h]   // vLookat0 = dot product 0
    vlt     $v29, $v31, $v31[4]            // Set VCC to 11110000
    vmrg    vLookat1, vLookat1, vDDD       // vLookat1 = lookat 1 dir
    vmulf   vLookat1, vPairNrml, vLookat1  // Normal * lookat 1 dir
    vmudh   $v29, vOne, vLookat1[0h]
    vmadh   $v29, vOne, vLookat1[1h]
    vmadh   vLookat1, vOne, vLookat1[2h]   // vLookat1 = dot product 1
    vne     $v29, $v31, $v31[1h]           // Set VCC to 10111011
    andi    $11, $5, G_TEXTURE_GEN_LINEAR >> 8
    vmrg    vLookat0, vLookat0, vLookat1[0h] // Dot products in elements 0, 1, 4, 5
    vmudh   $v29, vOne, $v31[5]            // 1 * 0x4000
    beqz    $11, vtx_return_from_lighting
     vmacf  vPairST, vLookat0, $v31[5]     // + dot products * 0x4000 ( / 2)
    // Texgen_Linear:
    vmulf   vPairST, vLookat0, $v31[5]     // dot products * 0x4000 ( / 2)
    vmulf   vDDD, vPairST, vPairST         // ST squared
    vmulf   $v29, vPairST, $v31[7]         // Move ST to accumulator (0x7FFF = 1)
    vmacf   vCCC, vPairST, $v30[5]         // + ST * 0x6CB3
    vmudh   $v29, vOne, $v31[5]            // 1 * 0x4000
    vmacf   vPairST, vPairST, $v30[4]      // + ST * 0x44D3
    j       vtx_return_from_lighting
     vmacf  vPairST, vDDD, vCCC            // + ST squared * (ST + ST * coeff)
    
lt_point:
    /*
    Input vector 1 elem size 7FFF.0000 -> len^2 3FFF0001 -> 1/len 0001.0040 -> vec +801E.FFC0 -> clamped 7FFF
        len^2 * 1/len = 400E.FFC1 so about half actual length
    Input vector 1 elem size 0100.0000 -> len^2 00010000 -> 1/len 007F.FFC0 -> vec  7FFF.C000 -> clamped 7FFF
        len^2 * 1/len = 007F.FFC0 so about half actual length
    Input vector 1 elem size 0010.0000 -> len^2 00000100 -> 1/len 07FF.FC00 -> vec  7FFF.C000
    Input vector 1 elem size 0001.0000 -> len^2 00000001 -> 1/len 7FFF.C000 -> vec  7FFF.C000
    */
    ldv     vAAA[0], (ltBufOfs + 8 - lightSize)(curLight) // Light position int part 0-3
    ldv     vAAA[8], (ltBufOfs + 8 - lightSize)(curLight) // 4-7
lt_normal_to_vertex:
    // This reused for fresnel; scalar unit stuff all garbage in that case
    // Input point (light / camera) in vAAA; computes vNrmOut = normalize(input - vertex)
    // and vAAA = (vPairNrml dot vNrmOut)
    // Uses temps vBBB, vCCC, vDDD, $v29
    vclr    vBBB                       // Both: Zero input frac part
    vsubc   vBBB, vBBB, vPairPosF      // Both: Vector from vertex to input, frac
    lbu     $20,     (ltBufOfs + 7 - lightSize)(curLight) // PL: Linear factor
    vsub    vAAA, vAAA, vPairPosI      // Both: Int
    jal     lt_normalize               // Both: Input vAAA:vBBB; output vNrmOut
     lbu    $24,     (ltBufOfs + 0xE - lightSize)(curLight) // PL: Quadratic factor
    // vNrmOut = normalized vector from vertex to light, $v29[0h:1h] = 1/len, vCCC[0h] = len^2
    vmudm   vBBB, vCCC, $v29[1h]       // PL: len^2 int * 1/len frac
    vmadn   vBBB, vDDD, $v29[0h]       // PL: len^2 frac * 1/len int = len frac
    mtc2    $20, vCCC[14]              // PL: Quadratic int part in elem 7
    vmadh   $v29, vCCC, $v29[0h]       // PL: len^2 int * 1/len int = len int
    vmulf   vAAA, vNrmOut, vPairNrml   // Both: Normalized light dir * normalized normals
    vmudl   vBBB, vBBB, vPairLt[7]     // PL:   len frac * linear factor frac
    vmadm   vBBB, $v29, vPairLt[7]     // PL: + len int * linear factor frac
    vmadm   vBBB, vOne, vPairLt[3]     // PL: + 1 * constant factor frac
    vmadl   vBBB, vDDD, vCCC[3]        // PL: + len^2 frac * quadratic factor frac
    vmadm   vBBB, vCCC, vCCC[3]        // PL: + len^2 int * quadratic factor frac
    vmadn   $v29, vDDD, vCCC[7]        // PL: + len^2 frac * quadratic factor int = $v29 frac
    vmadh   vCCC, vCCC, vCCC[7]        // PL: + len^2 int * quadratic factor int  = vCCC int
    vmudh   vBBB, vOne, vAAA[0h]       // Both: Sum components of dot product as signed
    vmadh   vBBB, vOne, vAAA[1h]       // Both:
    bnez    $10, lt_after_camera       // $10 set if computing specular or fresnel
     vmadh  vAAA, vOne, vAAA[2h]       // Both: vAAA dot product
    vrcph   vBBB[1], vCCC[0]     // 1/(2*light factor), input of 0000.8000 -> no change normals
    luv     vDDD,    (ltBufOfs + 0 - lightSize)(curLight) // vDDD = light color
    vrcpl   vBBB[2], $v29[0]     // Light factor 0001.0000 -> normals /= 2
    vrcph   vBBB[3], vCCC[4]     // Light factor 0000.1000 -> normals *= 8 (with clamping)
    vrcpl   vBBB[6], $v29[4]     // Light factor 0010.0000 -> normals /= 32
    vrcph   vBBB[7], $v31[2]     // 0
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    j       lt_finish_light
     vmadm  vCCC, vPairRGBA, $v30[2] // + (alpha - 1) * aoPoint factor; elems 3, 7

lt_normalize:
    // Normalize vector in vAAA:vBBB i/f, output in vNrmOut. Secondary outputs for
    // point lighting in $v29[0h:1h] and vCCC[0h]. Also uses temps vDDD, $11, $20, $24
    // Doing point light scalar stuff too.
    // Also overwrites vPairLt elems 3, 7
    vmudm   $v29, vAAA, vBBB             // Squared. Don't care about frac*frac term
    sll     $11, $11, 8                  // Constant factor, 00000100 - 0000FF00
    vmadn   $v29, vBBB, vAAA
    sll     $20, $20, 6                  // Linear factor, 00000040 - 00003FC0
    vmadh   $v29, vAAA, vAAA
    vreadacc vDDD, ACC_MIDDLE
    vreadacc vCCC, ACC_UPPER
    mtc2    $11, vPairLt[6] // Constant frac part in elem 3
    vmudm   $v29, vOne, vDDD[2h] // Sum of squared components
    vmadh   $v29, vOne, vCCC[2h]
    srl     $11, $24, 5 // Top 3 bits
    vmadm   $v29, vOne, vDDD[1h]
    mtc2    $20, vPairLt[14] // Linear frac part in elem 7
    vmadh   $v29, vOne, vCCC[1h]
    andi    $20, $24, 0x1F // Bottom 5 bits
    vmadn   vDDD, vDDD, vOne // elem 0; swapped so we can do vmadn and get result
    ori     $20, $20, 0x20 // Append leading 1 to mantissa
    vmadh   vCCC, vCCC, vOne
    sllv    $20, $20, $11 // Left shift to create floating point
    vrsqh   $v29[2], vCCC[0] // High input, garbage output
    sll     $20, $20, 8 // Min range 00002000, 00002100... 00003F00, max 00100000...001F8000
    vrsql   $v29[1], vDDD[0] // Low input, low output
    bnez    $24, @@skip // If original value is zero, set to zero
     vrsqh  $v29[0], vCCC[4] // High input, high output
    li      $20, 0
@@skip:
    vrsql   $v29[5], vDDD[4] // Low input, low output
    vrsqh   $v29[4], $v31[2] // 0 input, high output
    mtc2    $20, vCCC[6] // Quadratic frac part in elem 3
    vmudn   vBBB, vBBB, $v29[0h] // Vec frac * int scaling, discard result
    srl     $20, $20, 16
    vmadm   vBBB, vAAA, $v29[1h] // Vec int * frac scaling, discard result
    jr      $ra
     vmadh  vNrmOut, vAAA, $v29[0h] // Vec int * int scaling

ovl2_end:
.align 8
ovl2_padded_end:

.headersize ovl234_start - orga()

ovl4_start:
// Contains M inverse transpose (mIT) computation, and some rarely-used command handlers.

// Jump here to do lighting. If overlay 4 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_lighting_entrypoint_ovl4ver:        // same IMEM address as ovl234_lighting_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2
     
// Jump here for all overlay 4 features. If overlay 4 is loaded (this code), jumps
// to the instruction selection below.
ovl234_ovl4_entrypoint:
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       ovl4_select_instr
     li     $2, 1                // $7 = 1 (lighting && mIT invalid) if doing calc_mit

// Jump here to do clipping. If overlay 4 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipping_entrypoint_ovl4ver:        // same IMEM address as ovl234_clipping_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

ovl4_select_instr:
    beq     $2, $7, calc_mit // otherwise $7 = command byte
     li     $3, G_BRANCH_WZ
    beq     $3, $7, G_BRANCH_WZ_handler
     li     $2, (0xFF00 | G_DMA_IO)
    beq     $2, $7, G_DMA_IO_handler
     // Otherwise G_MTX_end, which starts with a harmless instruction

G_MTX_end: // Multiplies the temp loaded matrix into the M or VP matrix
    lhu     $5, (movememTable + G_MV_MMTX)($1) // Output; $1 holds 0 for M or 4 for VP.
    move    $2, $5 // Input 0 = output
    jal     while_wait_dma_busy // If ovl4 already in memory, was not done
     li     $3, tempMemRounded // Input 1 = temp mem (loaded mtx)
    addi    $10, $3, 0x0018
@@loop:
    vmadn   $v9, $v31, $v31[2]  // 0
    addi    $11, $3, 0x0008
    vmadh   $v8, $v31, $v31[2]  // 0
    addi    $2, $2, -0x0020
    vmudh   $v29, $v31, $v31[2] // 0
@@innerloop:
    ldv     $v5[0], 0x0040($2)
    ldv     $v5[8], 0x0040($2)
    lqv     $v3[0], 0x0020($3) // Input 1
    ldv     $v4[0], 0x0020($2)
    ldv     $v4[8], 0x0020($2)
    lqv     $v2[0], 0x0000($3) // Input 1
    vmadl   $v29, $v5, $v3[0h]
    addi    $3, $3, 0x0002
    vmadm   $v29, $v4, $v3[0h]
    addi    $2, $2, 0x0008 // Increment input 0 pointer
    vmadn   $v7, $v5, $v2[0h]
    bne     $3, $11, @@innerloop
     vmadh  $v6, $v4, $v2[0h]
    bne     $3, $10, @@loop
     addi   $3, $3, 0x0008
    // Store the results in M or VP
    sqv     $v9[0], 0x0020($5)
    sqv     $v8[0], 0x0000($5)
    sqv     $v7[0], 0x0030($5)
    j       run_next_DL_command
     sqv    $v6[0], 0x0010($5)

G_DMA_IO_handler:
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra     dmemAddr, dmemAddr, 2
    j       dma_read_write  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     li     $ra, wait_for_dma_and_run_next_command  // Setup the return address for running the next DL command

G_BRANCH_WZ_handler:
    j       vtx_addrs_from_cmd          // byte 3 = vtx being tested; addr -> $10
     li     $11, branchwz_return_from_addrs
branchwz_return_from_addrs:
.if CFG_G_BRANCH_W                      // G_BRANCH_W/G_BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      $10, VTX_W_INT($10)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      $10, VTX_SCR_Z($10)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, $10, cmd_w1_dram        // subtract the w/z value being tested
    bgez    $2, run_next_DL_command     // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val    // load the RDPHALF1 value as the location to branch to
    j       branch_dl                   // need $2 < 0 for nopush and cmd_w1_dram
     move   cmd_w0, $zero               // No count of DL cmds to skip

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
    li      $10, mMatrix + 0xE                               // For right rotates with lrv/ldv
    vxor    $v20, vM0I, $v31[1] // One's complement of X int part
    sb      $7, mITValid                                     // $7 is 1 if we got here, mark valid
    vlt     $v29, vM0I, $v31[2] // X int part < 0
    li      $11, mMatrix + 2                                 // For left rotates with lqv/ldv
    vabs    $v21, vM0I, vM0F    // Apply sign of X int part to X frac part
    lrv     $v10[0], (0x00)($10)                              // X int right shifted
    vxor    $v22, vM1I, $v31[1] // One's complement of Y int part
    lrv     $v11[0], (0x20)($10)                              // X frac right shifted
    vmrg    $v20, $v20, vM0I    // $v20:$v21 = abs(X int:frac)
    lqv     $v16[0], (0x10)($11)                              // Z int left shifted
    vlt     $v29, vM1I, $v31[2] // Y int part < 0
    lqv     $v17[0], (0x30)($11)                              // Z frac left shifted
    vabs    $v23, vM1I, vM1F    // Apply sign of Y int part to Y frac part
    lsv     $v10[0], (0x02)($11)                              // X int right rot elem 2->0
    vxor    $v24, vM2I, $v31[1] // One's complement of Z int part
    lsv     $v11[0], (0x22)($11)                              // X frac right rot elem 2->0
    vmrg    $v22, $v22, vM1I    // $v22:$v23 = abs(Y int:frac)
    lsv     $v16[4],  (0x0E)($11)                             // Z int left rot elem 0->2
    vlt     $v29, vM2I, $v31[2] // Z int part < 0
    lsv     $v17[4],  (0x2E)($11)                             // Z frac left rot elem 0->2
    vabs    $v25, vM2I, vM2F    // Apply sign of Z int part to Z frac part
    lrv     $v18[0], (0x10)($10)                              // Z int right shifted
    vmrg    $v24, $v24, vM2I    // $v24:$v25 = abs(Z int:frac)
    lrv     $v19[0], (0x30)($10)                              // Z frac right shifted
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
    ldv     $v14[0], (-0x08)($10)                             // Y int right shifted
    vor     $v20, $v20, $v20[1h]
    ldv     $v15[0], (0x18)($10)                              // Y frac right shifted
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
    vrcp    $v25[1], $v21[0] // low in, low out (discarded)
    vrcph   $v25[0], $v31[2] // zero in, high out (only care about elem 0)
    vadd    $v22, $v25, $v25 // *2
    vmudh   $v25, $v22, $v25 // (1/max) * (1/(2*max)), clamp to 0x7FFF
    veq     $v29, $v20, $v31[2] // elem 0 (all int parts) == 0
    vmrg    $v25, $v25, vOne // If so, use computed normalization, else use 1 (elem 0)
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
    vmudn   $v9,  $v9,  $v25[0] // Scale XL
    vmadh   $v8,  $v8,  $v25[0]
    vmudn   $v11, $v11, $v25[0] // Scale XR
    vmadh   $v10, $v10, $v25[0]
    // Z output vector: XL*YR + XR*YL, with each term having had scale and/or negative applied
    vmudl   $v29, $v9,  $v15
    vmadm   $v29, $v8,  $v15
    vmadn   $v29, $v9,  $v14
    vmadh   $v29, $v8,  $v14
    vmadl   $v29, $v11, $v13
    vmadm   $v29, $v10, $v13
    vmadn   $v21, $v11, $v12
    vmadh   $v20, $v10, $v12 // $v20:$v21 = Z output
    vmudn   $v13, $v13, $v25[0] // Scale YL
    vmadh   $v12, $v12, $v25[0]
    vmudn   $v15, $v15, $v25[0] // Scale YR
    vmadh   $v14, $v14, $v25[0]
    // Y output vector: XL*ZR + XR*ZL, with each term having had scale and/or negative applied
    vmudl   $v29, $v9,  $v27 // Negated copy of ZR
    vmadm   $v29, $v8,  $v27
    vmadn   $v29, $v9,  $v26
    vmadh   $v29, $v8,  $v26
    sdv     $v21[0], (mITMatrix + 0x28)($zero)
    vmadl   $v29, $v11, $v17
    sdv     $v20[0], (mITMatrix + 0x10)($zero)
    vmadm   $v29, $v10, $v17
    vmadn   $v21, $v11, $v16
    vmadh   $v20, $v10, $v16 // $v20:$v21 = Y output
    // X output vector: YL*ZR + YR*ZL, with each term having had scale and/or negative applied
    vmudl   $v29, $v13, $v19
    vmadm   $v29, $v12, $v19
    vmadn   $v29, $v13, $v18
    vmadh   $v29, $v12, $v18
    sdv     $v21[0], (mITMatrix + 0x20)($zero)
    vmadl   $v29, $v15, $v17
    sdv     $v20[0], (mITMatrix + 0x08)($zero)
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
