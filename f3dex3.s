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

// Using $v31 instead of dst as the source because $v31 doesn't change, whereas
// dst might have been modified 2 or 3 cycles ago, causing a stall.
.macro vclr, dst
    vxor    dst, $v31, $v31
.endmacro

// Also using $v31 for the dummy args here to avoid stalls. dst was once written
// in vanilla tri code just before reading (should have been $v29), leading to
// stalls!
ACC_UPPER equ 0
ACC_MIDDLE equ 1
ACC_LOWER equ 2
.macro vreadacc, dst, N
    vsar    dst, $v31, $v31[N]
.endmacro

//
// Profiling configurations. To make space for the profiling features, if any of
// the profiling configurations are enabled, G_LIGHTTORDP and !G_SHADING_SMOOTH
// are removed, i.e. G_LIGHTTORDP behaves as a no-op and all tris are smooth
// shaded.
//

// Profiling Configuration A
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

// Profiling Configuration B
// perfCounterA:
//     upper 16 bits: vertex count
//     lower 16 bits: lit vertex count
// perfCounterB:
//     upper 18 bits: tris culled by occlusion plane count
//     lower 14 bits: clipped (input) tris count
// perfCounterC:
//     upper 18 bits: overlay (all 0-4) load count
//     lower 14 bits: overlay 2 (lighting) load count
// perfCounterD:
//     upper 18 bits: overlay 3 (clipping) load count
//     lower 14 bits: overlay 4 (misc) load count
.elseif CFG_PROFILING_B
.if CFG_PROFILING_C
.error "At most one CFG_PROFILING_ option can be enabled at a time"
.endif
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 1
COUNTER_B_LOWER_CMD_COUNT equ 0
COUNTER_C_FIFO_FULL equ 0

// Profiling Configuration C
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

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// DMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

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
    
dirLightsXfrmValid:
    .db 0
numLightsxSize:
    .db 0   // Overwrites rdpHalf1Val when written

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
endIdStr:
.if endIdStr < 0x180
    .fill (0x180 - endIdStr)
.elseif endIdStr > 0x180
    .error "ID_STR is too long"
    .align 16  // to suppress subsequent errors 
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
// Also relies on the fact that $v31[0h] is -4,-4,-4,-4, 4, 4, 4, 4.
    .dh -4     // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh -1     // used often
    .dh 0      // used often
    .dh 2      // used as clip ratio (vtx write, clipping) and in clipping
    .dh 4      // used for same Newton-Raphsons, occlusion plane scaling
    .dh 0x4000 // used in tri write, texgen
    .dh 0x7F00 // used in fog, normals unpacking
    .dh 0x7FFF // used often

// constants for register $v30
.if (. & 15) != 0
    .error "Wrong alignment for v30value"
.endif
v30Value:
decalFixMult equ 0x0400
decalFixOff equ (-(decalFixMult / 2))
    .dh vertexBuffer // currently 0x02DE; for converting vertex index to address
    .dh vtxSize << 7 // 0x1300; it's not 0x2600 because vertex indices are *2
    .dh 0x1000 // some multiplier in tri write, increment in vertex indices
    .dh decalFixMult
    .dh 0x0020 // some edge write thing in tri write; formerly Z scale factor
    .dh 0xFFF8 // used once in tri write, mask away lower ST bits
    .dh decalFixOff // negative
    .dh 0x0100 // used several times in tri write
.macro set_vcc_11110001  // Only VCC pattern used with $v30
    vge    $v29, $v30, $v30[7]
.endmacro
.if (vertexBuffer < 0x0100 || decalFixMult < 0x100)
    .error "VCC pattern for $v30 corrupted"
.endif
v30_VB   equ $v30[0] // Vertex Buffer
v30_VS   equ $v30[1] // Vertex Size
v30_1000 equ $v30[2]
v30_DM   equ $v30[3] // Decal Multiplier
v30_0020 equ $v30[4]
v30_FFF8 equ $v30[5]
v30_DO   equ $v30[6] // Decal Offset
v30_0100 equ $v30[7]

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
NOTE: This explanation is outdated; see cpu/occlusionplane.c
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
    
activeClipPlanes:
    .dh CLIP_SCAL_NPXY | CLIP_CAMPLANE  // Normal tri write, set to zero when clipping
    
// Constants for clipping algorithm
clipCondShifts:
    .db CLIP_SCAL_NY_SHIFT
    .db CLIP_SCAL_PY_SHIFT
    .db CLIP_SCAL_NX_SHIFT
    .db CLIP_SCAL_PX_SHIFT

// Movemem table
movememTable:
    .dh tempMatrix      // G_MTX multiply temp matrix (model)
    .dh mMatrix         // G_MV_MMTX
    .dh tempMatrix      // G_MTX multiply temp matrix (projection)
    .dh vpMatrix        // G_MV_PMTX
    .dh viewport        // G_MV_VIEWPORT
    .dh cameraWorldPos  // G_MV_LIGHT

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
jumpTableEntry G_POPMTX_end   // G_POPMTX
jumpTableEntry G_MTX_end      // G_MTX (multiply)
jumpTableEntry G_MOVEMEM_end  // G_MOVEMEM, G_MTX (load)

.macro miniTableEntry, addr
    .if addr < 0x1000 || addr >= 0x1400
        .error "Handler address out of range!"
    .endif
    .db (addr - 0x1000) >> 2
.endmacro

// RDP/Immediate Command Mini Table
// 1 byte per entry, after << 2 points to an addr in first 1/4 of IMEM
miniTableEntry G_MEMSET_handler
miniTableEntry G_DMA_IO_handler
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
miniTableEntry G_BRANCH_WZ_handler
miniTableEntry G_TRI1_handler
miniTableEntry G_TRI2_handler
miniTableEntry G_QUAD_handler
miniTableEntry G_TRISTRIP_handler
miniTableEntry G_TRIFAN_handler
miniTableEntry G_LIGHTTORDP_handler
miniTableEntry G_RELSEGMENT_handler


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
// It is rare but possible for these assumptions to be violated and a polygon
// with more than 7 verts to be generated. For example, numerical precision
// issues could cause the polygon to be slightly non-convex at one of the clip
// planes, causing the plane to cut off more than one tip. However, this
// implementation checks for an imminent overflow and aborts clipping (draws no
// tris) if this occurs. Because this is caused by extreme/degenerate cases like
// the camera exactly on a tri, not drawing anything is an okay result.
MAX_CLIP_POLY_VERTS equ 7
CLIP_POLY_SIZE_BYTES equ (MAX_CLIP_POLY_VERTS+1) * 2
CLIP_TEMP_VERTS_SIZE_BYTES equ (MAX_CLIP_GEN_VERTS * vtxSize)

VERTEX_BUFFER_SIZE_BYTES equ (G_MAX_VERTS * vtxSize)

RDP_CMD_BUFSIZE equ 0xB0
RDP_CMD_BUFSIZE_EXCESS equ 0xB0 // Maximum size of an RDP triangle command
RDP_CMD_BUFSIZE_TOTAL equ (RDP_CMD_BUFSIZE + RDP_CMD_BUFSIZE_EXCESS)

INPUT_BUFFER_CMDS equ 21
INPUT_BUFFER_SIZE_BYTES equ (INPUT_BUFFER_CMDS * 8)

END_VARIABLE_LEN_DMEM equ (0xFC0 - INPUT_BUFFER_SIZE_BYTES - (2 * RDP_CMD_BUFSIZE_TOTAL) - (2 * CLIP_POLY_SIZE_BYTES) - CLIP_TEMP_VERTS_SIZE_BYTES - VERTEX_BUFFER_SIZE_BYTES)

startFreeDmem:
.org END_VARIABLE_LEN_DMEM
endFreeDmem:

// Main vertex buffer in RSP internal format
vertexBuffer:
    .skip VERTEX_BUFFER_SIZE_BYTES
    
// Space for temporary verts for clipping code, and reused for other things
clipTempVerts:

// Round up to 0x10
.org ((clipTempVerts + 0xF) & 0xFF0)
// Vertex addresses, to avoid a multiply-add for each vertex index lookup
vertexTable:
    .skip ((G_MAX_VERTS + 8) * 2) // halfword for each vertex; need 1 extra end addr, easier to write 8 extra
    
.if . > yieldDataFooter
    // Need to fit everything through vertex buffer in yield buffer, would like
    // to also fit vertexTable to avoid recompute after yield
    .error "Too much being stored in yieldable DMEM"
.endif

tempMatrix:
    .skip 0x40

.if . > (clipTempVerts + CLIP_TEMP_VERTS_SIZE_BYTES)
    .error "Too much in clipTempVerts"
.endif
.org (clipTempVerts + CLIP_TEMP_VERTS_SIZE_BYTES)
clipTempVertsEnd:

clipPoly:
    .skip CLIP_POLY_SIZE_BYTES  // 3   5   7 + term 0
clipPoly2:                      //  \ / \ / \
    .skip CLIP_POLY_SIZE_BYTES  //   4   6   7 + term 0

    
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
    .skip INPUT_BUFFER_SIZE_BYTES
inputBufferEnd:
inputBufferEndSgn equ -(0x1000 - inputBufferEnd) // Underflow DMEM address

.if . != 0xFC0
    .error "DMEM organization incorrect"
.endif

.org 0xFC0

// 0x0FC0-0x1000: OSTask
OSTask:
    .skip 0x40
// The only thing used in the first 16 bytes of OSTask is flags, which we now
// set up correctly (zero) when loading another ucode. This is a negative offset
// relative to $zero to wrap around DMEM to the top.
fourthQWMVP equ -(0x1000 - (OSTask + OSTask_type))
// This word is not used by F3DEX3, S2DEX, or even boot. Reuse it as a temp.
startCounterTime equ (OSTask + OSTask_ucode_size)
// These two words are used by boot, but not by F3DEX3 or S2DEX.
xfrmLookatDirs equ -(0x1000 - (OSTask + OSTask_ucode_data)) // and OSTask_ucode_data_size


memsetBufferStart equ ((vertexBuffer + 0xF) & 0xFF0)
memsetBufferMaxEnd equ (rdpCmdBuffer1 & 0xFF0)
memsetBufferMaxSize equ (memsetBufferMaxEnd - memsetBufferStart)
memsetBufferSize equ (memsetBufferMaxSize > 0x800 ? 0x800 : memsetBufferMaxSize)


.close // DATA_FILE

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Naming ////////////////////////////////
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
vPairTPosF equ $v23 // Vertex pair transformed (clip / screen) space position frac/int
vPairTPosI equ $v24
.if CFG_LEGACY_VTX_PIPE // One pair is outputs of vert mtx xfrm, other is temps
vAAA       equ $v20
vBBB       equ $v21
sOUTF equ vPairTPosF
sOUTI equ vPairTPosI
.else
sOUTF equ vPairPosF
sOUTI equ vPairPosI
vAAA       equ $v23 // Temps
vBBB       equ $v24
.endif
vCCC       equ $v25
vDDD       equ $v26
vPairRGBA  equ $v27 // Vertex pair color
// Vertex write, after lighting:
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
inVtx    equ $14   // Pointer to loaded vertex to transform
outVtxBase     equ $15   // Pointer to vertex buffer to store transformed verts
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
outVtx2      equ $8
curLight     equ $9
outVtx1      equ $19

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
// $8: outVtx2, local
// $9: curLight, clip mask during clipping, local
// $10: postOvlRA, common local
// $11: very common local
// $12: perfCounterD (global). This must be $12 for S2DEX compat in while_wait_dma_busy.
// $13: altBaseReg (global)
// $14: inVtx, local
// $15: outVtxBase, local
// $16: clipFlags (global)
// $17: clipPolyRead (global)
// $18: clipPolySelect (global)
// $19: dmaLen, outVtx1, local
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

// vtx_store registers. They all start with s for store.

// armips only executes "equ" statements on the codepath where they are defined.
// However, it always parses all assembly instructions, even if they current codepath
// is not active. So, code like "A equ $20; add A, $11, $11" will cause an error
// on a disabled codepath, as the first statement is not executed but the second
// is parsed and A is not defined.
// For CFG_LEGACY_VTX_PIPE, use the registers which would normally be the VP matrix
// to store constants from setup, including through clipping. This does not save
// cycles during vertex processing because the loads are always hidden, but it saves
// two instructions each to save and restore them. (For ST it saves cycles too)

// Common for all
s1WI equ $v16
s1WF equ $v17
sRTF equ $v25
sRTI equ $v26
sSCF equ $v20
sSCI equ $v21

// Viewport scale/offset, ST scale/offset
.if CFG_LEGACY_VTX_PIPE
sVPS equ $v8
sVPO equ $v9
sSTS equ $v10
sSTO equ $v29 // not supported on LVP
.else
.if CFG_NO_OCCLUSION_PLANE
sVPS equ $v26
.else
sVPS equ $v16
.endif
sVPO equ $v17
sSTS equ $v25
sSTO equ $v26
.endif

// Misc
.if CFG_NO_OCCLUSION_PLANE
sFOG equ $v25
.if CFG_LEGACY_VTX_PIPE
sCLZ equ $v19
sTCL equ $v19
.else
sCLZ equ $v21
sTCL equ $v21
.endif
sTPN equ $v16
.else
sFOG equ $v16
sCLZ equ $v25
sTCL equ $v29 // does not exist on this codepath
sTPN equ $v18
.endif

// New LVP_NOC only
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE
sKPI equ $v11
sKPF equ $v18
sKPG equ vBBB
sST2 equ $v11
sFGM equ $v12
.else
sKPI equ $v29 // do not exist
sKPF equ $v29
sKPG equ $v29
sST2 equ $v29
sFGM equ $v29
.endif

// Occlusion plane
.if CFG_NO_OCCLUSION_PLANE
sO03 equ $v29 // none of these exist
sO47 equ $v29
sOCM equ $v29
sOC1 equ $v29
sOC2 equ $v29
sOC3 equ $v29
sOPM equ $v29
sOPMs equ $v29
sOSC equ $v29
.else
sO03 equ $v26
sO47 equ $v23
sOCM equ $v22
sOC1 equ $v21
sOC2 equ $v27
sOC3 equ $v21
.if CFG_LEGACY_VTX_PIPE
sOPM equ $v12  // Kept here through whole processing
sOPMs equ $v12 // so these are the same
.else
sOPM equ $v17  // When used
sOPMs equ $v24 // Just another temp register
.endif
sOSC equ $v21
.endif

.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE
ltLookAt equ vCCC
.elseif CFG_LEGACY_VTX_PIPE
ltLookAt equ $v18
.else
ltLookAt equ $v29
.endif
vLookat0 equ vPairLt
vLookat1 equ vAAA

// Temp storage after rdpCmdBufEndP1. There is 0xA8 of space here which will
// always be free during vtx load or clipping.
tempViewportScale equ 0x00
tempViewportOffset equ 0x10
tempOccPlusMinus equ 0x20
tempVpRGBA equ 0x30
tempVpPkNorm equ 0x40
tempXfrmSingle equ 0x50
tempPrevVtxGarbage equ 0x50 // Up to 2 * 0x26 = 0x4C used -> to 0x9C


////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// IMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// Macros for placing code in different places based on the microcode version

.macro instantiate_mtx_end_begin
// Multiplies the temp loaded matrix into the M or VP matrix
    lhu     $6, (movememTable + G_MV_MMTX)($1) // Output; $1 holds 0 for M or 4 for VP.
    li      $3, tempMatrix // Input 1 = temp mem (loaded mtx)
    jal     while_wait_dma_busy
     move   $2, $6 // Input 0 = output
    // Followed immediately by instantiate_mtx_multiply. These need to be broken
    // up so we can insert the global mtx_multiply label between them.
.endmacro
.macro instantiate_mtx_multiply
// $3, $2 are input matrices; $6 is output matrix; $7 is 0 for return to vtx
    addi    $10, $3, 0x0018
@@loop:
    vmadn   $v7, $v31, $v31[2]  // 0
    addi    $11, $3, 0x0008
    vmadh   $v6, $v31, $v31[2]  // 0
    addi    $2, $2, -0x0020
    vmudh   $v29, $v31, $v31[2] // 0
@@innerloop:
    ldv     $v3[0], 0x0040($2)
    ldv     $v3[8], 0x0040($2)
    lqv     $v1[0], 0x0020($3) // Input 1
    ldv     $v2[0], 0x0020($2)
    ldv     $v2[8], 0x0020($2)
    lqv     $v0[0], 0x0000($3) // Input 1
    vmadl   $v29, $v3, $v1[0h]
    addi    $3, $3, 0x0002
    vmadm   $v29, $v2, $v1[0h]
    addi    $2, $2, 0x0008 // Increment input 0 pointer
    vmadn   $v5, $v3, $v0[0h]
    bne     $3, $11, @@innerloop
     vmadh  $v4, $v2, $v0[0h]
    bne     $3, $10, @@loop
     addi   $3, $3, 0x0008
    sqv     $v7[0], (0x0020)($6)
    sqv     $v6[0], (0x0000)($6)
.if CFG_LEGACY_VTX_PIPE
    beqz    $7, vtx_after_mtx_multiply
.endif
     sqv    $v4[0], (0x0010)($6)
    j       run_next_DL_command
     sqv    $v5[0], (0x0030)($6)
.endmacro

.macro instantiate_branch_wz
    lhu     $10, (vertexTable)(cmd_w0)  // Vertex addr from byte 3
.if CFG_G_BRANCH_W                      // G_BRANCH_W/G_BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      $10, VTX_W_INT($10)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      $10, VTX_SCR_Z($10)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, $10, cmd_w1_dram        // subtract the w/z value being tested
    bgez    $2, run_next_DL_command     // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val    // load the RDPHALF1 value as the location to branch to
    j       branch_dl                   // need $2 < 0 for nopush and cmd_w1_dram
     li     cmd_w0, 0                   // No count of DL cmds to skip
.endmacro

.macro instantiate_dma_io
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra     dmemAddr, dmemAddr, 2
    j       dma_read_write  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     li     $ra, wait_for_dma_and_run_next_command  // Setup the return address for running the next DL command
.endmacro

.macro instantiate_memset
    llv     $v2[0], (rdpHalf1Val)($zero) // Load the memset value
    sll     cmd_w0, cmd_w0, 8           // Clear upper byte
    jal     segmented_to_physical
     srl    cmd_w0, cmd_w0, 8           // Number of bytes to memset (must be mult of 16)
    li      $3, memsetBufferStart + 0x10 // Last qword set is memsetBufferStart
    jal     @@clamp_to_memset_buffer
     vmudh  $v2, vOne, $v2[1]           // Move element 1 (lower bytes) to all
    addi    $2, $2, memsetBufferStart   // First qword set is one below end
@@pre_loop:
    sqv     $v2, (-0x10)($2)
    bne     $2, $3, @@pre_loop
     addi   $2, -0x10
@@transaction_loop:
    jal     @@clamp_to_memset_buffer
     li     dmemAddr, 0x8000 | memsetBufferStart  // Always write from start of buffer
    jal     dma_read_write
     addi   dmaLen, $2, -1
    sub     cmd_w0, cmd_w0, $2
    bgtz    cmd_w0, @@transaction_loop
     add    cmd_w1_dram, cmd_w1_dram, $2
    j       wait_for_dma_and_run_next_command
     // Delay slot harmless
@@clamp_to_memset_buffer:
    addi    $11, cmd_w0, -memsetBufferSize // $2 = min(cmd_w0, memsetBufferSize)
    sra     $10, $11, 31
    and     $11, $11, $10
    jr      $ra
     addi   $2, $11, memsetBufferSize
.endmacro


// RSP IMEM
.create CODE_FILE, 0x00001080

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl0 and/or ovl1
start: // This is at IMEM 0x1080, not the start of IMEM
    vnop    // Return to here from S2DEX overlay 0 G_LOAD_UCODE jumps to start+4!
    lqv     $v31[0], (v31Value)($zero)      // Actual start is here
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    lqv     $v30, (v30Value)($zero)         // Always as this value except vtx_store
    li      altBaseReg, altBase
    li      rdpCmdBufPtr, rdpCmdBuffer1
    vclr    vOne
    li      rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word
    lw      $11, rdpFifoPos
    lw      $10, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // Clear task done and yielded signals
    vsub    vOne, vOne, $v31[1]             // 1 = 0 - -1
    beqz    $11, initialize_rdp             // If RDP FIFO not set up yet, starting ucode from scratch
     mtc0   $1, SP_STATUS
    andi    $10, $10, OS_TASK_YIELDED       // Resumed from yield or came from called ucode?
    beqz    $10, continue_from_os_task      // If latter, load DL (task data) pointer from OSTask
     // Otherwise continuing from yield; perf counters saved here at yield
     lw     perfCounterA, yieldDataFooter + YDF_OFFSET_PERFCOUNTERA
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
    jal     fill_vertex_table
     lw     taskDataPtr, OSTask + OSTask_data_ptr
finish_setup:
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    sw      $11, startCounterTime
.endif
    sb      $zero, mITValid
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
    // Load INPUT_BUFFER_SIZE_BYTES - inputBufferPos cmds (inputBufferPos >= 0, mult of 8)
    addi    inputBufferPos, inputBufferPos, -INPUT_BUFFER_SIZE_BYTES // inputBufferPos = - num cmds
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
    j       while_wait_dma_busy                         // wait for the DMA read to finish
     li     $ra, run_next_DL_command

.if !CFG_LEGACY_VTX_PIPE
G_DMA_IO_handler:
G_BRANCH_WZ_handler:
G_MEMSET_handler:
    j       ovl234_ovl4_entrypoint          // Delay slot is harmless
.endif
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
    sub     $8, rdpCmdBufPtr, rdpCmdBufEndP1
    bgezal  $8, flush_rdp_buffer
     // $1 on next instr survives flush_rdp_buffer
.if CFG_NO_OCCLUSION_PLANE && CFG_LEGACY_VTX_PIPE && !CFG_PROFILING_A
vertex_end:
.endif
.if !CFG_PROFILING_A
tris_end:
.endif
.if ENABLE_PROFILING
G_LIGHTTORDP_handler:
.endif
G_SPNOOP_handler:
run_next_DL_command:
     mfc0   $1, SP_STATUS                               // load the status word into register $1
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // load the command word into cmd_w0
    beqz    inputBufferPos, displaylist_dma             // load more DL commands if none are left
     andi   $1, $1, SP_STATUS_SIG0                      // check if the task should yield
    sra     $7, cmd_w0, 24                              // extract DL command byte from command word
    lbu     $11, (cmdMiniTable)($7)                     // Load mini table entry
    bnez    $1, load_overlay_0_and_enter                // load and execute overlay 0 if yielding; $1 > 0
     lw     cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // load the next DL word into cmd_w1_dram
    sll     $11, $11, 2                                 // Convert to a number of instructions
.if CFG_PROFILING_C
    mfc0    $10, DPC_STATUS
    andi    $10, $10, DPC_STATUS_GCLK_ALIVE             // Sample whether GCLK is active now
    sll     $10, $10, 16 - 3                            // move from bit 3 to bit 16
    add     perfCounterB, perfCounterB, $10             // Add to the perf counter
.endif
.if CFG_PROFILING_A
    mfc0    $10, DPC_CLOCK
.endif
.if COUNTER_B_LOWER_CMD_COUNT
    addi    perfCounterB, perfCounterB, 1               // Count commands
.endif
.if CFG_PROFILING_A
    move    $4, perfCounterC                            // Save initial FIFO stall time
    sw      $10, startCounterTime
.endif
    jr      $11                                         // Jump to handler
     addi   inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
    // $1 must remain zero
    // $7 must retain the command byte for load_mtx and overlay 4 stuff
    // $11 must contain the handler called for several handlers

G_DL_handler:
    sll     $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
branch_dl:
    lbu     $1, displayListStackLength      // Get the DL stack length
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
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

.if CFG_LEGACY_VTX_PIPE

G_DMA_IO_handler:
    instantiate_dma_io
    
G_BRANCH_WZ_handler:
    instantiate_branch_wz
    
G_MEMSET_handler:
    instantiate_memset

.endif

G_LOAD_UCODE_handler:
    j       load_overlay_0_and_enter         // Delay slot is harmless
G_MODIFYVTX_handler:
     lhu    $10, (vertexTable)(cmd_w0)       // Byte 3 = vtx being modified
    j       do_moveword  // Moveword adds cmd_w0 to $10 for final addr
     lbu    cmd_w0, (inputBufferEnd - 0x07)(inputBufferPos)  // offset in vtx, bit 15 clear

G_VTX_handler:
    lhu     dmemAddr, (vertexTable)(cmd_w0)    // (v0 + n) end address; up to 56 inclusive
    jal     segmented_to_physical              // Convert address in cmd_w1_dram to physical
     lhu    $1, (inputBufferEnd - 0x07)(inputBufferPos) // $1 = size in bytes = vtx count * 0x10
    sub     dmemAddr, dmemAddr, $1             // Start addr = end addr - size. Rounded down to DMA word by H/W
    addi    dmaLen, $1, -1                     // DMA length is always offset by -1
    j       dma_read_write
     li     $ra, 0x8000 | vtx_after_dma        // Negative = flag to not to return to clipping in vtx_setup_constants

G_TRIFAN_handler:
    li      $1, 0x8000 // $ra negative = flag for G_TRIFAN
G_TRISTRIP_handler:
    addi    $ra, $1, tri_strip_fan_loop // otherwise $1 == 0
    addi    cmd_w0, inputBufferPos, inputBufferEnd - 8 // Start pointing to cmd byte
tri_strip_fan_loop:
    lw      cmd_w1_dram, 0(cmd_w0)       // Load tri indices to lower 3 bytes of word
    addi    $11, inputBufferPos, inputBufferEnd - 3 // Off end of command
    beq     $11, cmd_w0, tris_end         // If off end of command, exit
     sll    $10, cmd_w1_dram, 24         // Put sign bit of vtx 3 in sign bit
    bltz    $10, tris_end                 // If negative, exit
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Store non-shuffled indices
    bltz    $ra, tri_fan_store           // Finish handling G_TRIFAN
     addi   cmd_w0, cmd_w0, 1            // Increment
    andi    $11, cmd_w0, 1               // If odd, this is the 1st/3rd/5th tri
    bnez    $11, tri_main                // Draw as is
     srl    $10, cmd_w1_dram, 8          // Move vtx 2 to LSBs
    sb      cmd_w1_dram, 6(rdpCmdBufPtr) // Store vtx 3 to spot for 2
    j       tri_main
     sb     $10, 7(rdpCmdBufPtr)         // Store vtx 2 to spot for 3

// H = highest on screen = lowest Y value; then M = mid, L = low
tHAtF equ $v5
tMAtF equ $v7
tLAtF equ $v9
tHAtI equ $v18
tMAtI equ $v19
tLAtI equ $v21
tHPos equ $v14
tMPos equ $v2
tLPos equ $v10
tPosMmH equ $v6
tPosLmH equ $v8
tPosHmM equ $v11

G_TRI2_handler:
G_QUAD_handler:
    jal     tri_main                     // Send second tri; return here for first tri
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // Store second tri indices
G_TRI1_handler:
    li      $ra, tris_end                 // After done with this tri, exit tri processing
    sw      cmd_w0, 4(rdpCmdBufPtr)      // Store first tri indices
tri_main:
    lpv     $v27[0], 0(rdpCmdBufPtr) // To vector unit
    lbu     $1, 5(rdpCmdBufPtr)
    lbu     $2, 6(rdpCmdBufPtr)
    lbu     $3, 7(rdpCmdBufPtr)
    vclr    vZero
    lhu     $1, (vertexTable)($1)
    vmudn   $v29, vOne, v30_VB    // Address of vertex buffer
    lhu     $2, (vertexTable)($2)
    vmadl   $v27, $v27, v30_VS    // Plus vtx indices times length
    lhu     $3, (vertexTable)($3)
    vmadl   $v4, $v31, $v31[2]    // 0; vtx 2 addr in $v4 elem 6
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 0x4000  // Increment number of tris requested
    move    $4, $1                // Save original vertex 1 addr (pre-shuffle) for flat shading
.endif
tri_noinit: // ra is next cmd, second tri in TRI2, or middle of clipping
    vnxor   tHAtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    llv     $v6[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vnxor   tMAtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vmov    $v6[6], $v27[5]         // elem 6 of v6 = vertex 1 addr
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vnxor   tLAtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    lhu     $5, VTX_CLIP($1)
    vmov    $v8[6], $v27[7]         // elem 6 of v8 = vertex 3 addr
    lhu     $7, VTX_CLIP($2)
    // vnop
    lhu     $8, VTX_CLIP($3)
    vmudh   $v2, vOne, $v6[1] // v2 all elems = y-coord of vertex 1
    andi    $11, $5, CLIP_SCRN_NPXY | CLIP_CAMPLANE // All three verts on wrong side of same plane
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    and     $11, $11, $7
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    and     $11, $11, $8
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    bnez    $11, return_and_end_mat // Then the whole tri is offscreen, cull
     // 22 cycles
     vmrg   tHPos, $v6, $v4   // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    vmudh   $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    lhu     $24, activeClipPlanes
    vmadh   $v26, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    lw      $6, geometryModeLabel // Load full geometry mode word
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    or      $10, $5, $7
    vmrg    tLPos, $v6, $v4   // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    or      $10, $10, $8      // $10 = all clip bits which are true for any verts
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    and     $10, $10, $24     // If clipping is enabled, check clip flags
    vmrg    $v4, tHPos, $v8   // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    mfc2    $9, $v26[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    tHPos, $v8, tHPos // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    bnez    $10, ovl234_clipping_entrypoint // Facing info and occlusion may be garbage if need to clip
     // 30 cycles
     sll    $20, $6, 21       // Bit 10 in the sign bit, for facing cull
    vlt     $v29, $v6, $v2    // VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    srl     $11, $9, 31       // = 0 if x prod positive (back facing), 1 if x prod negative (front facing)
    vmudh   $v3, vOne, $v31[5] // 0x4000; some rounding factor
    sllv    $11, $20, $11     // Sign bit = bit 10 of geom mode if back facing, bit 9 if front facing
    vmrg    tMPos, $v4, tLPos // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    bltz    $11, return_and_end_mat // Cull if bit is set (culled based on facing)
     // 34 cycles
     vmrg   tLPos, tLPos, $v4 // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
tSubPxHF equ $v4
tSubPxHI equ $v26
    vmudn   tSubPxHF, tHPos, $v31[5] // 0x4000
    beqz    $9, return_and_end_mat  // If cross product is 0, tri is degenerate (zero area), cull.
     // 36 cycles
     mfc2   $1, tHPos[12]     // tHPos = lowest Y value = highest on screen (x, y, addr)
tPosCatI equ $v15 // 0 X L-M; 1 Y L-M; 2 X M-H; 3 X L-H; 4-7 garbage
tPosCatF equ $v25
    vsub    tPosMmH, tMPos, tHPos
    mfc2    $2, tMPos[12]     // tMPos = mid vertex (x, y, addr)
    vsub    tPosLmH, tLPos, tHPos
.if !ENABLE_PROFILING
    sll     $11, $6, 10       // Moves the value of G_SHADING_SMOOTH into the sign bit
.endif
    vsub    tPosHmM, tHPos, tMPos
    andi    $6, $6, (G_SHADE | G_ZBUFFER)
    vsub    tPosCatI, tLPos, tMPos
    mfc2    $3, tLPos[12]     // tLPos = highest Y value = lowest on screen (x, y, addr)
    vmov    tPosCatI[2], tPosMmH[0]
.if !CFG_NO_OCCLUSION_PLANE
    and     $5, $5, $7
    and     $5, $5, $8
    andi    $5, $5, CLIP_OCCLUDED
.endif
tXPF equ $v16 // Triangle cross product
tXPI equ $v17
tXPRcpF equ $v23 // Reciprocal of cross product (becomes that * 4)
tXPRcpI equ $v24
t1WI equ $v13 // elems 0, 4, 6
t1WF equ $v14
    vmudh   $v29, tPosMmH, tPosLmH[0]
.if !CFG_NO_OCCLUSION_PLANE
    bnez    $5, tri_culled_by_occlusion_plane // Cull if all verts occluded
.endif
    llv     t1WI[0], VTX_INV_W_VEC($1)
    vmadh   $v29, tPosLmH, tPosHmM[0]
    lpv     tHAtI[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
    vreadacc tXPI, ACC_UPPER
    lpv     tMAtI[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vreadacc tXPF, ACC_MIDDLE
    lpv     tLAtI[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vrcp    $v20[0], tPosCatI[1]
.if !ENABLE_PROFILING
    lpv     $v25[0], VTX_COLOR_VEC($4)  // Load RGB from vertex 4 (flat shading vtx)
.endif
    vmov    tPosCatI[3], tPosLmH[0]
    llv     t1WI[8], VTX_INV_W_VEC($2)
    vrcph   $v22[0], tXPI[1]
    llv     t1WI[12], VTX_INV_W_VEC($3)
    vrcpl   tXPRcpF[1], tXPF[1]
.if !ENABLE_PROFILING
    bltz    $11, tri_skip_flat_shading  // Branch if G_SHADING_SMOOTH is set
.endif
     vrcph  tXPRcpI[1], $v31[2]            // 0
.if !ENABLE_PROFILING
    vlt     $v29, $v31, $v31[3]         // Set vcc to 11100000
    vmrg    tHAtI, $v25, tHAtI        // RGB from $4, alpha from $1
    vmrg    tMAtI, $v25, tMAtI        // RGB from $4, alpha from $2
    vmrg    tLAtI, $v25, tLAtI        // RGB from $4, alpha from $3
tri_skip_flat_shading:
.endif
    // 52 cycles
    vrcp    $v20[2], tPosMmH[1]
    lb      $20, (alphaCompareCullMode)($zero)
    vrcph   $v22[2], tPosMmH[1]
    lw      $5, VTX_INV_W_VEC($1) // $5, $7, $8 = 1/W for H, M, L
    vrcp    $v20[3], tPosLmH[1]
    lw      $7, VTX_INV_W_VEC($2)
    vrcph   $v22[3], tPosLmH[1]
    lw      $8, VTX_INV_W_VEC($3)
    vmudl   tHAtI, tHAtI, v30_0100 // vertex color 1 >>= 8
    lbu     $9, textureSettings1 + 3
    vmudl   tMAtI, tMAtI, v30_0100 // vertex color 2 >>= 8
    sub     $11, $5, $7  // Four instr: $5 = max($5, $7)
    vmudl   tLAtI, tLAtI, v30_0100 // vertex color 3 >>= 8
    sra     $10, $11, 31
    vmudl   $v29, $v20, v30_0020
    // no nop if tri_skip_flip_facing was unaligned
    vmadm   $v22, $v22, v30_0020
    beqz    $20, tri_skip_alpha_compare_cull
     vmadn  $v20, $v31, $v31[2] // 0
    // Alpha compare culling
    vge     $v26, tHAtI, tMAtI
    lbu     $19, alphaCompareCullThresh
    vlt     $v27, tHAtI, tMAtI
    bgtz    $20, @@skip1
     vge    $v26, $v26, tLAtI // If alphaCompareCullMode > 0, $v26 = max of 3 verts
    vlt     $v26, $v27, tLAtI // else if < 0, $v26 = min of 3 verts
@@skip1: // $v26 elem 3 has max or min alpha value
    mfc2    $24, $v26[6]
    sub     $24, $24, $19 // sign bit set if (max/min) < thresh
    xor     $24, $24, $20 // invert sign bit if other cond. Sign bit set -> cull
    bltz    $24, return_and_end_mat // if max < thresh or if min >= thresh.
tri_skip_alpha_compare_cull:
    // 63 cycles
    vmudm   tPosCatF, tPosCatI, v30_1000
    // no nop if tri_skip_alpha_compare_cull was unaligned
    vmadn   tPosCatI, $v31, $v31[2] // 0
    and     $11, $11, $10
    vsubc   tSubPxHF, vZero, tSubPxHF
    sub     $5, $5, $11
    vsub    tSubPxHI, vZero, vZero
    sub     $11, $5, $8  // Four instr: $5 = max($5, $8)
    vmudm   $v29, tPosCatF, $v20
    sra     $10, $11, 31
    vmadl   $v29, tPosCatI, $v20
    and     $11, $11, $10
    vmadn   $v20, tPosCatI, $v22
    sub     $5, $5, $11
    vmadh   tPosCatI, tPosCatF, $v22
    sw      $5, 0x0010(rdpCmdBufPtr) // Store max of three verts' 1/W to temp mem
    vmudl   $v29, tXPRcpF, tXPF
tMx1W equ $v27
    llv     tMx1W[0], 0x0010(rdpCmdBufPtr) // Load max of three verts' 1/W
    vmadm   $v29, tXPRcpI, tXPF
    mfc2    $5, tXPI[1]
    vmadn   tXPF, tXPRcpF, tXPI
    lbu     $7, textureSettings1 + 2
    vmadh   tXPI, tXPRcpI, tXPI
    lsv     tMAtI[14], VTX_SCR_Z($2)
    vand    $v22, $v20, v30_FFF8
    lsv     tLAtI[14], VTX_SCR_Z($3)
    vcr     tPosCatI, tPosCatI, v30_0100
    lsv     tMAtF[14], VTX_SCR_Z_FRAC($2)
    vmudh   $v29, vOne, $v31[4] // 4
    lsv     tLAtF[14], VTX_SCR_Z_FRAC($3)
    vmadn   tXPF, tXPF, $v31[0] // -4
    ori     $11, $6, G_TRI_FILL // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadh   tXPI, tXPI, $v31[0] // -4
    or      $11, $11, $9 // Incorporate whether textures are enabled into the triangle command id
    vmudn   $v29, $v3, tHPos[0]
    sb      $11, 0x0000(rdpCmdBufPtr) // Store the triangle command id
    vmadl   $v29, $v22, tSubPxHF[1]
    ssv     tLPos[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
    vmadm   $v29, tPosCatI, tSubPxHF[1]
    ssv     tMPos[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadn   $v2, $v22, tSubPxHI[1]
    ssv     tHPos[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
    vmadh   $v3, tPosCatI, tSubPxHI[1]
    lw      $20, otherMode1
tMnWI equ $v27
tMnWF equ $v10
    vrcph   $v29[0], tMx1W[0] // Reciprocal of max 1/W = min W
    andi    $10, $5, 0x0080 // Extract the left major flag from $5
    vrcpl   tMnWF[0], tMx1W[1]
    or      $10, $10, $7 // Combine the left major flag with the level and tile from the texture settings
    vmudh   t1WF, vOne, t1WI[1q]
    sb      $10, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vrcph   tMnWI[0], $v31[2]     // 0
    sb      $zero, materialCullMode // This covers tri write out
tSTWHMI equ $v22 // H = elems 0-2, M = elems 4-6; init W = 7FFF
tSTWHMF equ $v25
    vmudh   tSTWHMI, vOne, $v31[7]  // 0x7FFF
    ssv     tPosMmH[2], 0x0030(rdpCmdBufPtr) // MmHY -> first short (temp mem)
    vmudm   $v29, t1WI, tMnWF[0] // 1/W each vtx * min W = 1 for one of the verts, < 1 for others
    llv     tSTWHMI[0], VTX_TC_VEC($1)
    vmadl   $v29, t1WF, tMnWF[0]
    ssv     tPosLmH[0], 0x0032(rdpCmdBufPtr) // LmHX -> second short (temp mem)
    vmadn   t1WF, t1WF, tMnWI[0]
    llv     tSTWHMI[8], VTX_TC_VEC($2)
    vmadh   t1WI, t1WI, tMnWI[0]
    ssv     tPosHmM[0], 0x0034(rdpCmdBufPtr) // HmMX -> third short (temp mem)
tSTWLI equ $v10 // L = elems 4-6; init W = 7FFF
tSTWLF equ $v13
    vmudh   tSTWLI, vOne, $v31[7]  // 0x7FFF
    andi    $20, ZMODE_DEC
    set_vcc_11110001                // select RGBA___Z or ____STW_
    llv     tSTWLI[8], VTX_TC_VEC($3)
    vmudm   $v29, tSTWHMI, t1WF[0h] // (S, T, 7FFF) * (1 or <1) for H and M
    addi    $20, $20, -ZMODE_DEC
    vmadh   tSTWHMI, tSTWHMI, t1WI[0h]
    ldv     tPosLmH[8], 0x0030(rdpCmdBufPtr) // MmHY -> e4, LmHX -> e5, HmMX -> e6
    vmadn   tSTWHMF, $v31, $v31[2]  // 0
    vmudm   $v29, tSTWLI, t1WF[6]  // (S, T, 7FFF) * (1 or <1) for L
    vmadh   tSTWLI, tSTWLI, t1WI[6]
    vmadn   tSTWLF, $v31, $v31[2]  // 0
    sdv     tSTWHMI[0], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int to temp mem
    vmrg    tMAtI, tMAtI, tSTWHMI // Merge S, T, W Mid into elems 4-6
    sdv     tSTWHMF[0], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac to temp mem
    vmrg    tMAtF, tMAtF, tSTWHMF // Merge S, T, W Mid into elems 4-6
    ldv     tHAtI[8], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int from temp mem
    vmrg    tLAtI, tLAtI, tSTWLI // Merge S, T, W Low into elems 4-6
    ldv     tHAtF[8], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac from temp mem
    vmrg    tLAtF, tLAtF, tSTWLF // Merge S, T, W Low into elems 4-6
.if !ENABLE_PROFILING
    addi    perfCounterA, perfCounterA, 1 // Increment number of tris sent to RDP
.endif
    // 106 cycles
    vmudl   $v29, tXPF, tXPRcpF
    lsv     tHAtF[14], VTX_SCR_Z_FRAC($1)
    vmadm   $v29, tXPI, tXPRcpF
    lsv     tHAtI[14], VTX_SCR_Z($1) // contains R, G, B, A, S, T, W, Z
    vmadn   tXPRcpF, tXPF, tXPRcpI
    lh      $1, VTX_SCR_VEC($2)
    vmadh   tXPRcpI, tXPI, tXPRcpI
    addi    $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
    vmudh   tPosLmH, tPosLmH, $v31[0h] // e1 LmHY * -4 = 4*HmLY; e456 MmHY,LmHX,HmMX *= 4
tAtLmHF equ $v10
tAtLmHI equ $v9
tAtMmHF equ $v13
tAtMmHI equ $v7
    vsubc   tAtLmHF, tLAtF, tHAtF
    andi    $3, $6, G_SHADE
    vsub    tAtLmHI, tLAtI, tHAtI
    sll     $1, $1, 14
    vsubc   tAtMmHF, tMAtF, tHAtF
    sw      $1, 0x0008(rdpCmdBufPtr)         // Store XL edge coefficient
    vsub    tAtMmHI, tMAtI, tHAtI
    ssv     $v3[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
// DaDx = (v3 - v1) * factor + (v2 - v1) * factor
tDaDxF equ $v2
tDaDxI equ $v3
    vmudn   $v29, tAtLmHF, tPosLmH[4] // MmHY * 4
    ssv     $v2[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[4] // MmHY * 4
    ssv     $v3[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vmadn   $v29, tAtMmHF, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     $v2[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     tPosCatI[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vreadacc tDaDxF, ACC_MIDDLE
    ssv     $v20[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vreadacc tDaDxI, ACC_UPPER
    ssv     tPosCatI[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
// DaDy = (v2 - v1) * factor + (v3 - v1) * factor
tDaDyF equ $v6
tDaDyI equ $v7
    vmudn   $v29, tAtMmHF, tPosLmH[5] // LmHX * 4
    ssv     $v20[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[5] // LmHX * 4
    ssv     tPosCatI[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vmadn   $v29, tAtLmHF, tPosLmH[6] // HmMX * 4
    ssv     $v20[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[6] // HmMX * 4
    sll     $11, $3, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vreadacc tDaDyF, ACC_MIDDLE
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vreadacc tDaDyI, ACC_UPPER
    sll     $11, $9, 5              // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
// DaDx, DaDy *= more factors
    vmudl   $v29, tDaDxF, tXPRcpF[1]
    add     rdpCmdBufPtr, $1, $11   // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, tDaDxI, tXPRcpF[1]
    andi    $6, $6, G_ZBUFFER       // Get the value of G_ZBUFFER from the current geometry mode
    vmadn   tDaDxF, tDaDxF, tXPRcpI[1]
    sll     $11, $6, 4              // Shift (geometry mode & G_ZBUFFER) by 4 to get 0x10 if G_ZBUFFER is set
    vmadh   tDaDxI, tDaDxI, tXPRcpI[1]
    move    $10, rdpCmdBufPtr       // Write Z here
    vmudl   $v29, tDaDyF, tXPRcpF[1]
    add     rdpCmdBufPtr, rdpCmdBufPtr, $11  // Increment the triangle pointer by 0x10 bytes (depth coefficients) if G_ZBUFFER is set
    vmadm   $v29, tDaDyI, tXPRcpF[1]
    sub     $8, rdpCmdBufPtr, rdpCmdBufEndP1 // Check if we need to write out to RDP
    vmadn   tDaDyF, tDaDyF, tXPRcpI[1]
    sdv     tDaDxF[0], 0x0018($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   tDaDyI, tDaDyI, tXPRcpI[1]
    sdv     tDaDxI[0], 0x0008($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
// DaDe = DaDx * factor
tDaDeF equ $v8
tDaDeI equ $v9
    // 135 cycles
    vmadl   $v29, tDaDxF, $v20[3]
    sdv     tDaDxF[8], 0x0018($1)   // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadm   $v29, tDaDxI, $v20[3]
    sdv     tDaDxI[8], 0x0008($1)   // Store DsDx, DtDx, DwDx texture coefficients (integer)
    vmadn   tDaDeF, tDaDxF, tPosCatI[3]
    sdv     tDaDyF[0], 0x0038($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   tDaDeI, tDaDxI, tPosCatI[3]
    sdv     tDaDyI[0], 0x0028($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
// Base value += DaDe * factor
    vmudn   $v29, tHAtF, vOne[0]
    sdv     tDaDyF[8], 0x0038($1)   // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadh   $v29, tHAtI, vOne[0]
    sdv     tDaDyI[8], 0x0028($1)   // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadl   $v29, tDaDeF, tSubPxHF[1]
    sdv     tDaDeF[0], 0x0030($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadm   $v29, tDaDeI, tSubPxHF[1]
    sdv     tDaDeI[0], 0x0020($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    vmadn   tHAtF, tDaDeF, tSubPxHI[1]
    sdv     tDaDeF[8], 0x0030($1)   // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    vmadh   tHAtI, tDaDeI, tSubPxHI[1]
    sdv     tDaDeI[8], 0x0020($1)   // Store DsDe, DtDe, DwDe texture coefficients (integer)
    // All values start in element 7. "a", attribute, is Z. Need
    // tHAtI, tHAtF, tDaDxI, tDaDxF, tDaDeI, tDaDeF, tDaDyI, tDaDyF
    // VCC is still 11110001
    // 145 cycles
    vmrg    tDaDyI, tDaDyF, tDaDyI[7] // Elems 6-7: DzDyI:F
    beqz    $20, tri_decal_fix_z
     vmrg   tDaDxI, tDaDxF, tDaDxI[7] // Elems 6-7: DzDxI:F
tri_return_from_decal_fix_z:
    vmrg    tDaDeI, tDaDeF, tDaDeI[7] // Elems 6-7: DzDeI:F
    sdv     tHAtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    vmrg    $v10, tHAtF, tHAtI[7]  // Elems 6-7: ZI:F
    sdv     tHAtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    sdv     tHAtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    sdv     tHAtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)
    slv     tDaDyI[12], 0x0C($10)  // DzDyI:F
    slv     tDaDxI[12], 0x04($10)  // DzDxI:F
    slv     tDaDeI[12], 0x08($10)  // DzDeI:F
    bltz    $8, return_and_end_mat      // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
     slv    $v10[12], 0x00($10)   // ZI:F
     // 156 cycles
flush_rdp_buffer: // $8 = rdpCmdBufPtr - rdpCmdBufEndP1
    mfc0    $10, SP_DMA_BUSY                 // Check if any DMA is in flight
    lw      cmd_w1_dram, rdpFifoPos          // FIFO pointer = end of RDP read, start of RSP write
    addi    dmaLen, $8, RDP_CMD_BUFSIZE + 8  // dmaLen = size of DMEM buffer to copy
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

tri_decal_fix_z:
    // Valid range of tHAtI = 0 to 7FFF, but most of the scene is large values
    vmudh   $v29, vOne, v30_DO  // accum all elems = -DM/2
    vmadm   $v25, tHAtI, v30_DM // elem 7 = (0 to DM/2-1) - DM/2 = -DM/2 to -1
    vcr     tDaDyI, tDaDyI, $v25[7] // Clamp DzDyI (6) to <= -val or >= val; clobbers DzDyF (7)
    j       tri_return_from_decal_fix_z
     set_vcc_11110001 // Clobbered by vcr

tri_culled_by_occlusion_plane:
.if CFG_PROFILING_B
    addi    perfCounterB, perfCounterB, 0x4000
.endif
return_and_end_mat:
    jr      $ra
     sb     $zero, materialCullMode // This covers all tri early exits except clipping

tri_fan_store:
    lb      $11, (inputBufferEnd - 7)(inputBufferPos) // Load vtx 1
    j       tri_main
     sb     $11, 5(rdpCmdBufPtr)         // Store vtx 1

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

.if !CFG_LEGACY_VTX_PIPE
// Jump here for all overlay 4 features. If overlay 3 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ovl4_entrypoint_ovl3ver:            // same IMEM address as ovl234_ovl4_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4
.endif //!CFG_LEGACY_VTX_PIPE

// Jump here to do clipping. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl234_clipping_entrypoint:
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterB, perfCounterB, 1  // Increment clipped (input) tris count
.endif
    sb      $zero, materialCullMode        // In case only/all tri(s) clip then offscreen
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
    li      outVtxBase, clipTempVertsEnd
clip_find_unused_loop:
    lhu     $11, (VTX_CLIP - vtxSize)(outVtxBase)
    addi    $10, outVtxBase, -clipTempVerts  // This is within the loop rather than before b/c delay after lhu
    blez    $10, clip_done                 // If can't find one (should never happen), give up
     andi   $11, $11, CLIP_VTX_USED
    bnez    $11, clip_find_unused_loop
     addi   outVtxBase, outVtxBase, -vtxSize
    beqz    clipFlags, clip_skipswap23     // V2 flag is clear / on screen, therefore V3 is set / off screen
     move   $19, $2                            // 
    move    $19, $3                            // Otherwise swap V2 and V3; note we are overwriting $3 but not $2
    move    $3, $2                             // 
clip_skipswap23: // After possible swap, $19 = vtx not meeting clip cond / on screen, $3 = vtx meeting clip cond / off screen
    // Interpolate between these two vertices; create a new vertex which is on the
    // clipping boundary (e.g. at the screen edge)
vClBaseF equ $v20
vClBaseI equ $v21
vClDiffF equ $v16
vClDiffI equ $v17
vClFade1 equ $v16 // = vClDiffF
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
    sub     $11, clipPolyWrite, clipPolySelect // Make sure we are not overflowing
    vrcph   $v3[3], vClDiffI[3]
    addi    $11, $11, 6 - ((MAX_CLIP_POLY_VERTS) * 2) // Write ptr to last zero slot
    vrcpl   $v2[3], vClDiffF[3]           // frac: 1 / (x+y+z+w), vtx on screen - vtx off screen
    bgez    $11, clip_done                // If so, give up
     vrcph  $v3[3], $v31[2]               // 0; get int result of reciprocal
    vabs    $v29, $v29, $v31[3]           // 2; v29 = +/- 2 based on sum positive (incl. zero) or negative
    lhu     $5, geometryModeLabel + 1     // Load middle 2 bytes of geom mode, incl fog setting
    vmudn   $v2, $v2, $v29[3]             // multiply reciprocal by +/- 2
    sh      outVtxBase, (clipPoly)(clipPolyWrite) // Write pointer to generated vertex to polygon
    vmadh   $v3, $v3, $v29[3]
    lhu     $11, VTX_CLIP($3)             // Load clip flags for off screen vert
    veq     $v3, $v3, $v31[2]             // 0; if reciprocal high is 0
    andi    $7, $5, G_FOG >> 8            // Nonzero if fog enabled
    vmrg    $v2, $v2, $v31[1]             // keep reciprocal low, otherwise set to -1
    addi    clipPolyWrite, clipPolyWrite, 2  // Increment write ptr
    vmudl   $v29, vClDiffF, $v2[3]        // sum frac * reciprocal, discard
    andi    $11, $11, ~CLIP_VTX_USED      // Clear used flag from off screen vert
    vmadm   vClDiffI, vClDiffI, $v2[3]    // sum int * reciprocal, frac out
    li      $1, -1                        // $1 < 0 triggers last vtx loop iter
    vmadn   vClDiffF, $v31, $v31[2]       // 0; get int out
    sh      $11, VTX_CLIP($3)             // Store modified clip flags for off screen vert
    vrcph   $v24[3], vClDiffI[3]          // reciprocal again (discard result)
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    addi    outVtxBase, outVtxBase, -vtxSize // Inc'd by 2, must point to second vtx
.endif
    vrcpl   $v23[3], vClDiffF[3]          // frac part
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    srl     $7, $7, 5                     // 8 if G_FOG is set, 0 otherwise
.endif
    vrcph   $v24[3], $v31[2]              // 0; int part
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    li      $ra, clip_after_vtx_store + 0x8000
.endif
    vmudl   $v29, $v23, vClDiffF          // self * own reciprocal? frac*frac discard
    vmadm   $v29, $v24, vClDiffF          // self * own reciprocal? int*frac discard
    vmadn   vClDiffF, $v23, vClDiffI      // self * own reciprocal? frac out
    vmadh   vClDiffI, $v24, vClDiffI      // self * own reciprocal? int out
    vmudh   $v29, vOne, $v31[4]           // 4 (int part), Newton-Raphson algorithm
    vmadn   vClDiffF, vClDiffF, $v31[0]   // - 4 * prev result frac part
    vmadh   vClDiffI, vClDiffI, $v31[0]   // - 4 * prev result frac part
    vmudl   $v29, $v23, vClDiffF          // * own reciprocal again? frac*frac discard
    vmadm   $v29, $v24, vClDiffF          // * own reciprocal again? int*frac discard
    vmadn   $v23, $v23, vClDiffI          // * own reciprocal again? frac out
    vmadh   $v24, $v24, vClDiffI          // * own reciprocal again? int out
    vmudl   $v29, vClBaseF, $v23
    ldv     $v6[0], VTX_FRAC_VEC($3)      // Vtx off screen, frac pos
    vmadm   $v29, vClBaseI, $v23
    ldv     $v7[0], VTX_INT_VEC ($3)      // Vtx off screen, int pos
    vmadn   vClDiffF, vClBaseF, $v24
    luv     $v23[0], VTX_COLOR_VEC($3)    // Vtx off screen, RGBA
    vmadh   vClDiffI, vClBaseI, $v24      // 11:10 = vtx on screen sum * prev calculated value
    luv     vPairRGBA[0], VTX_COLOR_VEC($19) // Vtx on screen, RGBA
    vmudl   $v29, vClDiffF, $v2[3]
    llv     $v24[0], VTX_TC_VEC   ($3)    // Vtx off screen, ST
    vmadm   vClDiffI, vClDiffI, $v2[3]
    llv     vPairST[0], VTX_TC_VEC($19)   // Vtx on screen, ST
    vmadn   vClDiffF, $v31, $v31[2]       // End of computing vClDiff = vClBase / vClDiff
    vlt     vClDiffI, vClDiffI, vOne[0]   // If integer part of factor less than 1,
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    addi    $19, rdpCmdBufEndP1, vtxSize  // Fog writes up to one vtx behind
.endif
    vmrg    vClDiffF, vClDiffF, $v31[1]   // keep frac part of factor, else set to 0xFFFF (max val)
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    move    outVtx2, $19             // Old last vtx regs = temp mem
.endif
    vsubc   $v29, vClDiffF, vOne[0]       // frac part - 1 for carry
    vge     vClDiffI, vClDiffI, $v31[2]   // 0; If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    vmrg    vClFade1, vClDiffF, vOne[0]   // keep frac part of factor, else set to 1 (min val)
    vmudn   vClFade2, vClFade1, $v31[1]   // signed x * -1 = 0xFFFF - unsigned x! v2[3] is fade factor for on screen vert
    // Fade between attributes for on screen and off screen vert
    // Colors are now in $v23 and vPairRGBA, ST now in $v24 and vPairST.
    vmudm   $v29, $v23, vClFade1[3]       //   Fade factor for off screen vert * off screen vert color and TC
    vmadm   vPairRGBA, vPairRGBA, vClFade2[3]  // + Fade factor for on  screen vert * on  screen vert color
    vmudm   $v29, $v24, vClFade1[3]       //   Fade factor for off screen vert * off screen vert TC
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    vmadm   sSTS, vPairST, vClFade2[3]    // Put output ST in sSTS; don't want to scale twice in clipping
.else
    vmadm   vPairST, vPairST, vClFade2[3] // + Fade factor for on  screen vert * on  screen vert TC
.endif
    vmudl   $v29, $v6, vClFade1[3]        //   Fade factor for off screen vert * off screen vert pos frac
    vmadm   $v29, $v7, vClFade1[3]        // + Fade factor for off screen vert * off screen vert pos int
    vmadl   $v29, $v4, vClFade2[3]        // + Fade factor for on screen vert * on screen vert pos frac
    vmadm   vPairTPosI, $v5, vClFade2[3]  // + Fade factor for on screen vert * on screen vert pos int
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    j       vtx_store_for_clip
.else
    jal     vtx_store_for_clip
.endif
     vmadn  vPairTPosF, $v31, $v31[2]     // 0; load resulting frac pos
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
clip_after_vtx_store:
    ori     $10, $10, CLIP_VTX_USED       // Mark generated vtx as used
    slv     sSTS[0], (VTX_TC_VEC   )($19) // Store not-twice-scaled ST
    sh      $10,     (VTX_CLIP     )($19) // Store generated vertex flags
.endif
clip_nextedge:
    bnez    clipFlags, clip_edgelooptop   // Discard V2 if it was off screen (whether inserted vtx or not)
     move   $3, $2                        // Move what was the end of the edge to be the new start of the edge
    sub     $11, clipPolyWrite, clipPolySelect // Make sure we are not overflowing
    addi    $11, $11, 6 - ((MAX_CLIP_POLY_VERTS) * 2) // Write ptr to last zero slot
    bgez    $11, clip_done                // If so, give up
     sh     $3, (clipPoly)(clipPolyWrite) // Former V2 was on screen, so add it to the output polygon
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
    vclr    vZero // TODO may not need this
    sh      $zero, activeClipPlanes
    lqv     $v30, (v30Value)($zero)
// Current polygon starts 6 (3 verts) below clipPolySelect, ends 2 (1 vert) below clipPolyWrite
// Draws verts in pattern like 0-1-4, 1-2-4, 2-3-4
clip_draw_tris_loop:
    lhu     $1, (clipPoly - 6)(clipPolySelect)
    lhu     $2, (clipPoly - 4)(clipPolySelect)
    lhu     $3, (clipPoly - 2)(clipPolyWrite)
    mtc2    $1, $v27[10]              // Addresses go in vector regs too
    mtc2    $2, $v4[12]
    jal     tri_noinit
     mtc2   $3, $v27[14]
    bne     clipPolyWrite, clipPolySelect, clip_draw_tris_loop
     addi   clipPolySelect, clipPolySelect, 2
clip_done:
    li      $11, CLIP_SCAL_NPXY | CLIP_CAMPLANE
    sh      $11, activeClipPlanes
    lqv     $v30, (v30Value)($zero) // Need this repeated here in case we exited early
    lh      $ra, tempTriRA

fill_vertex_table:
    // Create bytes 00-07
    li      $1, 7
@@loop1:
    sb      $1, (vertexTable)($1)
    bgtz    $1, @@loop1
     addi   $1, $1, -1
    // Load to vu and multiply by 2 to get vertex indexes. It would be more cycles
    // to change the loop above to count by 2s than the stalls here.
    li      $2, vertexTable
    lpv     $v3[0], (0)($2)
    li      $3, vertexTable + ((G_MAX_VERTS + 8) * 2) // Need 0-56 inclusive, so do 0-63
    vmudh   $v3, $v3, $v31[3] // 2; now 0x0000, 0x0200, ..., 0x0E00
@@loop2:
    vmudn   $v29, vOne, v30_VB  // Address of vertex buffer
    vmadl   $v4, $v3, v30_VS    // Plus vtx indices times length
    vadd    $v3, $v3, v30_1000  // increment by 8 verts = 16
    addi    $2, $2, 0x10
    bne     $2, $3, @@loop2
     sqv    $v4[0], (-0x10)($2)
    jr      $ra
     nop

ovl3_end:
.align 8
ovl3_padded_end:

.orga max(max(ovl2_padded_end - ovl2_start, ovl4_padded_end - ovl4_start) + orga(ovl3_start), orga())
ovl234_end:

/*

Vertex load:

Prepare and trigger DMA
Post DMA register setup

-> Clipping
Set up constants
Clipping ->

Check and recompute MVP

If not lighting goto setup_vtx_store

Check lighting mode, jump to one lighting overlay or the other entrypoint

Lighting setup (e.g. transform directions)

Call while_wait_dma_busy

Lighting only on all verts

lw v2.rgba
lw v1.st
sw v2.rgba -> v1.st
lpv, lpv, lpv

end:
suv v1.rgba
lw fake v1.st
sw real v1.st
sw v2.rgba

setup_vtx_store:
Load MVP
Call while_wait_dma_busy (possibly again if did lighting)
Preload first vertex info

-> Clipping
Vertex write loop
Clipping ->

Epilogue

*/

vtx_after_dma:
    andi    inVtx, dmemAddr, 0xFFF8      // Round down input start addr to DMA word
    lhu     $5, geometryModeLabel + 1          // Load middle 2 bytes of geom mode
    srl     $2, cmd_w0, 11                     // n << 1
    sub     $2, cmd_w0, $2                     // = v0 << 1
    lhu     outVtxBase, (vertexTable)($2)    // Address of output start
.if COUNTER_A_UPPER_VERTEX_COUNT
    sll     $11, $1, 12                        // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
.endif
vtx_setup_constants:

.if CFG_LEGACY_VTX_PIPE

    // Computes modified viewport scale and offset including fog info, and stores
    // these to temp memory in the RDP buffer. This is only used during vertex write
    // and the first half of clipping, so that memory is not used then.
    llv     $v23[0], (fogFactor)($zero)           // Load fog multiplier 0 and offset 1
.if CFG_NO_OCCLUSION_PLANE
    veq     $v29, $v31, $v31[3h] // VCC = 00010001
.else
    vge     $v29, $v31, $v31[2h] // VCC = 00110011
.endif
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
.if CFG_NO_OCCLUSION_PLANE
// sFGM is $v12 // FoG Mask
    vmrg    sFGM, vOne, $v31[2] // sFGM is 0,0,0,1,0,0,0,1
.else
    vmrg    sOPMs, vOne, $v31[1] // Signs of sOPMs are --++--++
.endif
    ldv     sVPO[8], (viewport + 8)($zero)
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    llv     sSTS[0], (textureSettings2)($zero)    // Texture ST scale in 0, 1
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    ldv     sVPS[8], (viewport)($zero)
.if !CFG_NO_OCCLUSION_PLANE
    vmudh   sOPMs, sOPMs, $v31[5] // sOPMs is 0xC000, 0xC000, 0x4000, 0x4000, repeat
.endif
    llv     $v30[0], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 0, 1
    vmrg    sVPO, sVPO, $v23[1]                   // Put fog offset in elements 3,7 of vtrans
    llv     $v30[8], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 4, 5
    vmov    sSTS[4], sSTS[0]
    andi    $11, $5, G_ATTROFFSET_ST_ENABLE >> 8
    vmrg    sVPS, sVPS, $v23[0]                   // Put fog multiplier in elements 3,7 of vscale
    bnez    $11, @@skipoffset
     lbu    $7, mITValid
    vclr    $v30
@@skipoffset:
.if !CFG_NO_OCCLUSION_PLANE
    sqv     sOPMs, (tempOccPlusMinus)(rdpCmdBufEndP1) // Store occlusion plane -/+4000 constants
    sqv     sVPO, (tempViewportOffset)(rdpCmdBufEndP1) // Store viewport offset
    sqv     sVPS, (tempViewportScale)(rdpCmdBufEndP1) // Store viewport scale
.endif
    vmov    sSTS[5], sSTS[1]
    bgtz    $ra, clip_after_constants             // Return to clipping if from there
     lsv    $v30[6], (perspNorm - altBase)(altBaseReg) // Perspective norm

.else

    // Computes modified viewport scale and offset including fog info, and stores
    // these to temp memory in the RDP buffer. This is only used during vertex write
    // and the first half of clipping, so that memory is not used then.
    llv     $v23[0], (fogFactor)($zero)           // Load fog multiplier 0 and offset 1
.if !CFG_NO_OCCLUSION_PLANE
    vge     $v29, $v31, $v31[2h] // VCC = 00110011
.endif
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
.if !CFG_NO_OCCLUSION_PLANE
    vmrg    sOPMs, vOne, $v31[1] // Signs of sOPMs are --++--++
.endif
    ldv     sVPO[8], (viewport + 8)($zero)
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    ldv     sVPS[8], (viewport)($zero)
    lqv     $v30, (fxParams - altBase)(altBaseReg) // Parameters for vtx and lighting
.if !CFG_NO_OCCLUSION_PLANE
    vmudh   sOPMs, sOPMs, $v31[5] // sOPMs is 0xC000, 0xC000, 0x4000, 0x4000, repeat
.endif
    lw      $10, (geometryModeLabel)($zero)
    vmrg    sVPO, sVPO, $v23[1]                   // Put fog offset in elements 3,7 of vtrans
.if !CFG_NO_OCCLUSION_PLANE
    sqv     sOPMs, (tempOccPlusMinus)(rdpCmdBufEndP1) // Store occlusion plane -/+4000 constants
.endif
    andi    $11, $10, G_AMBOCCLUSION
    vmrg    sVPS, sVPS, $v23[0]                   // Put fog multiplier in elements 3,7 of vscale
    bnez    $11, @@skipzeroao                     // Continue if AO disabled
     sqv    sVPO, (tempViewportOffset)(rdpCmdBufEndP1) // Store viewport offset
    vge     $v29, $v31, $v31[3]                   // VCC = 00011111
    vmrg    $v30, $v30, $v31[2]                   // 0; zero AO values
@@skipzeroao:
    bgtz    $ra, clip_after_constants             // Return to clipping if from there
     sqv    sVPS, (tempViewportScale)(rdpCmdBufEndP1) // Store viewport scale

.endif

vtx_after_setup_constants:
    andi    $8, $5, G_LIGHTING >> 8        // Temp to be reused below, is outVtx2
    beqz    $8, @@skip_lighting
     li     $16, vtx_loop_no_lighting      // This is clipFlags, but not modified
    li      $16, lt_vtx_pair               // during vtx_store
@@skip_lighting:

.if CFG_LEGACY_VTX_PIPE

    bnez    $7, skip_vtx_mvp
     li     $2, vpMatrix
    li      $3, mMatrix
    j       mtx_multiply
     li     $6, mITMatrix
vtx_after_mtx_multiply:
    sqv     $v5[0], (fourthQWMVP +    0)($zero)
    sb      $10, mITValid  // $10 is nonzero from mtx_multiply, in fact 0x18
skip_vtx_mvp:
    bnez    $8, ovl234_lighting_entrypoint      // Lighting setup, incl. transform
     sb     $zero, materialCullMode             // Vtx ends material
vtx_after_lt_setup:
    lqv     vM0I,     (mITMatrix + 0x00)($zero)  // Load MVP matrix
    lqv     vM2I,     (mITMatrix + 0x10)($zero)
    lqv     vM0F,     (mITMatrix + 0x20)($zero)
    lqv     vM2F,     (fourthQWMVP +  0)($zero)
.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    addi    outVtxBase, outVtxBase, -vtxSize // Will inc by 2, but need point to 2nd
.else
    addi    outVtxBase, outVtxBase, -2*vtxSize // Going to increment this by 2 verts in loop
.endif
    vcopy   vM1I,  vM0I
    vcopy   vM3I,  vM2I
    ldv     vM1I[0],  (mITMatrix + 0x08)($zero)
    vcopy   vM1F,  vM0F
    ldv     vM3I[0],  (mITMatrix + 0x18)($zero)
    vcopy   vM3F,  vM2F
    ldv     vM1F[0],  (mITMatrix + 0x28)($zero)
    ldv     vM3F[0],  (fourthQWMVP +  8)($zero)
    ldv     vM0I[8],  (mITMatrix + 0x00)($zero)
    ldv     vM2I[8],  (mITMatrix + 0x10)($zero)
    ldv     vM0F[8],  (mITMatrix + 0x20)($zero)
    ldv     vM2F[8],  (fourthQWMVP +  0)($zero)
.else
    sb      $zero, materialCullMode            // Vtx ends material
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
    addi    outVtxBase, outVtxBase, -2*vtxSize // Going to increment this by 2 verts in loop
    vcopy   vVP1I, vVP0I
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
.endif
    andi    $7, $5, G_FOG >> 8    // Nonzero if fog enabled
.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    srl     $7, $7, 5  // 8 if G_FOG is set, 0 otherwise
    addi    outVtx1, rdpCmdBufEndP1, vtxSize  // Temp mem; fog writes up to vtxSize before
    jal     while_wait_dma_busy   // Wait for vertex load to finish
     move   outVtx2, outVtx1     // for first pre-loop, same for outVtx2
    ldv     vPairPosI[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // 1st vec pos
    ldv     vPairPosI[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // 2nd vec pos
    llv     sTCL[8],      (VTX_IN_CN + 0 * inputVtxSize)(inVtx) // RGBA in 4:5
    llv     sTCL[12],     (VTX_IN_CN + 1 * inputVtxSize)(inVtx) // RGBA in 6:7
    llv     vPairST[0],   (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1
    j       vtx_store_loop_entry
     llv    vPairST[8],   (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5
.else
    jal     while_wait_dma_busy   // Wait for vertex load to finish
     addi   outVtx1, rdpCmdBufEndP1, tempPrevVtxGarbage  // Temp mem we can freely overwrite replaces outVtxBase
    j       vtx_store_loop_entry
     move   outVtx2, outVtx1     // for first pre-loop, same for outVtx2
.endif

.if CFG_LEGACY_VTX_PIPE && CFG_NO_OCCLUSION_PLANE // New LVP_NOC

// $v0:$v7 = MVP, $v8:$v10 = sVPS/sVPO/sSTS, $v11 = available, $v12 = sFGM,
// $v13 = first light dir, $v14:$v16 = Y/Z/vPairNrml/temp, $v17 = vPairLt/temp,
// $v18:$v19 = available, $v20:$v21 = vPairPosI/F/temp,
// $v22 = vPairST, $v23:$v24 = vPairTPosF/I/temp, $v25:$v26 = temps, $v27 = vPairRGBA,
// $v28 = vOne, $v29 = garbage, $v30 = params, $v31 = constants
// $1: 0x10 vtx count, $2: need for clipping, $3: temp, $4: vtx1/perf,
// $5: geom mode mid, $6: need for clipping, $7: fog flag, $8: outVtx2,
// $9: clipping / curLight, $10:$11: temp, $12: perf, $13: altBaseReg, $14: inVtx,
// $15: outVtxBase, $16: clipping / lt jump addr, $17:$18: clipping, $19: outVtx1,
// $20: temp, $21: clipping / first light, $22:$23: cmd buf, $24: temp, $25: cmd_w0 global,
// $26: taskDataPtr, $27: inputBufferPos, $28:$30: perf, $ra return addr

.align 8

.if CFG_NO_OCCLUSION_PLANE

vtx_loop_no_lighting:
    vmadh   $v29, vM1I, vPairPosI[1h]
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vPairTPosF, vM2F, vPairPosI[2h]
    or      $10, $10, $11          // Combine results for first vertex
    vmadh   vPairTPosI, vM2I, vPairPosI[2h]
    sh      $10,              (VTX_CLIP      )(outVtx1) // Store first vertex flags
// sKPI is $v11 // vtx_store Keep Int (keep across pipelining)
// sKPG is vBBB = $v21 // vtx_store Keep Fog
    vge     sKPG, sKPI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    luv     vPairRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// sCLZ is $v19
    vge     sCLZ, sKPI, $v31[2]              // 0; clamp Z to >= 0
    addi    $1, $1, -2*inputVtxSize         // Decrement vertex count by 2
vtx_return_from_lighting:
vtx_store_for_clip:
    vmudl   $v29, vPairTPosF, $v30[3]       // Persp norm
    sub     $20, outVtx2, $7           // Points 8 before outVtx2 if fog, else 0
// s1WI is $v16 // vtx_store 1/W Int
    vmadm   s1WI, vPairTPosI, $v30[3]       // Persp norm
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
// s1WF is $v17 // vtx_store 1/W Frac
    vmadn   s1WF, $v31, $v31[2]             // 0
    sbv     sKPG[15], (VTX_COLOR_A + 8)($20) // In VTX_SCR_Y if fog disabled...
// sKPF is $v18 // vtx_store Keep Frac
    vmov    sKPF[1], sCLZ[2]
    sbv     sKPG[7],  (VTX_COLOR_A + 8 - vtxSize)($20) // ...which gets overwritten below
// sSCF is $v20 // vtx_store Scaled Clipping Frac
    vmudn   sSCF, vPairTPosF, $v31[3]        // W * clip ratio for scaled clipping
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
// sSCI is $v21 // vtx_store Scaled Clipping Int
    vmadh   sSCI, vPairTPosI, $v31[3]        // W * clip ratio for scaled clipping
    slv     sKPI[8],  (VTX_SCR_VEC    )(outVtx2)
    vrcph   $v29[0], s1WI[3]
    slv     sKPI[0],  (VTX_SCR_VEC    )(outVtx1)
// sRTF is $v25 // vtx_store Reciprocal Temp Frac
    vrcpl   sRTF[2], s1WF[3]
    ssv     sKPF[12], (VTX_SCR_Z_FRAC )(outVtx2)
// sRTI is $v26 // vtx_store Reciprocal Temp Int
    vrcph   sRTI[3], s1WI[7]
    slv     sKPF[2],  (VTX_SCR_Z      )(outVtx1)
    vrcpl   sRTF[6], s1WF[7]
    sra     $24, $1, 31        // All 1s if on last iter
    vrcph   sRTI[7], $v31[2] // 0
    andi    $24, $24, vtxSize  // vtxSize if on last iter, else normally 0
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    sub     outVtx2, outVtxBase, $24 // First output vtx on last iter, else second
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    $10, $vcc                   // Screen clip results
    vmadm   $v29, s1WI, sRTF[2h]
    sdv     vPairTPosF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadn   s1WF, s1WF, sRTI[3h]
// sTCL is $v19 // vtx_store Temp CoLor
    ldv     sTCL[0],   (VTX_IN_TC + 2 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vPairTPosF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vch     $v29, vPairTPosI, sSCI[3h] // Clip scaled high
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmudh   $v29, vOne, $v31[4]  // 4
    sdv     vPairTPosI[8],  (VTX_INT_VEC   )(outVtx2)
    vmadn   s1WF, s1WF, $v31[0]  // -4
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, $v31[0]  // -4
    sdv     vPairTPosI[0],  (VTX_INT_VEC   )(outVtx1)
    vmudm   $v29, vPairST, sSTS       // Scale ST
    ldv     sTCL[8],   (VTX_IN_TC + 3 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
// sST2 equ $v11 // vtx_store ST coordinates copy 2
    vmadh   sST2, vOne, $v30          // + 1 * ST offset; elems 0, 1, 4, 5
    suv     vPairRGBA[4],   (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vPairTPosI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    suv     vPairRGBA[0],   (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmadn   s1WF, s1WF, sRTI[3h]
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     $24, $10, 4            // Shift second vertex screen clipping to first slots
    vcl     $v29, vPairTPosF, sSCF[3h] // Clip scaled low
    andi    $24, $24, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcopy   vPairST, sTCL
    cfc2    $20, $vcc                   // Scaled clip results
    vmudl   $v29, vPairTPosF, s1WF[3h] // Pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vPairTPosI, s1WF[3h] // Pos times inv W
// vPairPosI is $v20
    ldv     vPairPosI[0], (VTX_IN_OB + 2 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmadn   vPairTPosF, vPairTPosF, s1WI[3h]
    ldv     vPairPosI[8], (VTX_IN_OB + 3 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadh   vPairTPosI, vPairTPosI, s1WI[3h] // vPairTPosI:vPairTPosF = pos times inv W
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmov    sTCL[4], vPairST[2] // First vtx RG to elem 4
    andi    $10, $10, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmov    sTCL[5], vPairST[3] // First vtx BA to elem 5
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmadm   vPairTPosI, vPairTPosI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vPairTPosF, $v31, $v31[2] // 0; Now vPairTPosI:vPairTPosF = projected position
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    // vnop
    slv     sST2[8],           (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudh   $v29, sVPO, vOne // offset * 1
    slv     sST2[0],           (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    vmadh   $v29, sFGM, $v31[6] // + (0,0,0,1,0,0,0,1) * 0x7F00
    andi    $20, $20, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   sKPF, vPairTPosF, sVPS   // + pos frac * scale
    or      $24, $24, $20            // Combine results for second vertex
    vmadh   sKPI, vPairTPosI, sVPS   // int part, sKPI:sKPF is now screen space pos
    sh      $24,               (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
vtx_store_loop_entry:
    vmudn   $v29, vM3F, vOne
    blez    $1, vtx_epilogue
     vmadh  $v29, vM3I, vOne
    vmadn   $v29, vM0F, vPairPosI[0h]
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmadh   $v29, vM0I, vPairPosI[0h]
    jr      $16                    // lt_vtx_pair or vtx_loop_no_lighting
     vmadn  $v29, vM1F, vPairPosI[1h]
    
vtx_epilogue:
    vge     sKPG, sKPI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vge     sCLZ, sKPI, $v31[2]              // 0; clamp Z to >= 0
    or      $10, $10, $11          // Combine results for first vertex
    beqz    $7, @@skip_fog
     slv    sKPI[8],  (VTX_SCR_VEC    )(outVtx2)
    sbv     sKPG[15], (VTX_COLOR_A    )(outVtx2)
    sbv     sKPG[7],  (VTX_COLOR_A    )(outVtx1)
@@skip_fog:
    vmov    sKPF[1], sCLZ[2]
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
    slv     sKPI[0],  (VTX_SCR_VEC    )(outVtx1)
    ssv     sKPF[12], (VTX_SCR_Z_FRAC )(outVtx2)
    bltz    $ra, clip_after_vtx_store  // $ra - from clipping or + from while_wait_dma_busy
     slv    sKPF[2],  (VTX_SCR_Z      )(outVtx1)
    sh      $10,      (VTX_CLIP       )(outVtx1) // Store first vertex flags
    j       vertex_end
     lqv    $v30, (v30Value)($zero)    // Restore value overwritten in vtx_store


.else // not CFG_NO_OCCLUSION_PLANE

// sKPI is $v11 // vtx_store Keep Int (keep across pipelining)
// sKPG is vBBB = $v21 // vtx_store Keep Fog
// sCLZ is $v19
// s1WI is $v16 // vtx_store 1/W Int
// s1WF is $v17 // vtx_store 1/W Frac
// sKPF is $v18 // vtx_store Keep Frac
// sSCF is $v20 // vtx_store Scaled Clipping Frac
// sSCI is $v21 // vtx_store Scaled Clipping Int
// sRTF is $v25 // vtx_store Reciprocal Temp Frac
// sRTI is $v26 // vtx_store Reciprocal Temp Int
// sTCL is $v19 // vtx_store Temp CoLor
// sST2 equ $v11 // vtx_store ST coordinates copy 2
// vPairPosI is $v20

    

vtx_return_from_lighting:
    TODO
    
vtx_store_for_clip:
    TODO
    bltz    $ra, clip_after_vtx_store


    // $3 available

    // Permanent:
    // $v0:$v7 = MVP, $v10 = sSTS, $v13 = first light dir, 
    // $v28 = vOne, $v29 = garbage, $v30 = params/sSTO, $v31 = constants
    // Uses but otherwise temp:
    // $v20 = vPairPosI, $v22 = vPairST, $v23:$v24 = vPairTPosF/I = vAAA/vBBB, $v27 = vPairRGBA
    // Need during lighting, otherwise temp:
    // $v14:$v16 = Y/Z/vPairNrml/temp, $v17 = vPairLt/temp, $v25:$v26 = vCCC/vDDD
    // Always available:
    // $v8:$v9, $v11:$v12, $v18:$v19, $v21
    
    // Kept across lighting: sKPI, sKPF, sOC2, sO47
    
    // 71 cycles, 17 more than NOC
    // 6 vu cycles for plane, 8 vu cycles for edges, 1 more vnop than NOC,
    // 1 branch delay slot with SU instr, 1 land-after-branch.
vtx_loop_no_lighting:
    veq     $v29, $v31, $v31[0q]  // Set VCC to 10101010
    sub     $20, outVtx1, $7      // Points 8 before outVtx1 if fog, else 0
// sOC3 is $v27 = vPairRGBA
    vmrg    sOC2, sOC2, sOC3      // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
// sFOG is $v24 = vBBB
    sbv     sFOG[7],  (VTX_COLOR_A + 8)($20) // ...which gets overwritten below
// sCLZ is $v23 = vAAA
    vmrg    sKPF, sKPF, sCLZ[2h]  // Z int elem 2, 6 to elem 1, 5; Z frac in elem 2, 6
    luv     vPairRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
    vmudm   $v29, vPairST, sSTS   // Scale ST
    slv     sKPI[8],  (VTX_SCR_VEC    )(outVtx2)
    vmadh   vPairST, vOne, $v30   // + 1 * ST offset; elems 0, 1, 4, 5
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
    vge     $v29, sOC2, sO47      // Each compare to coeffs 4-7
    slv     sKPI[0],  (VTX_SCR_VEC    )(outVtx1)
    vmudn   $v29, vM3F, vOne
    cfc2    $20, $vcc
    vmadh   $v29, vM3I, vOne
    slv     sKPF[10], (VTX_SCR_Z      )(outVtx2)
    vmadn   $v29, vM0F, vPairPosI[0h]
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadh   $v29, vM0I, vPairPosI[0h]
    slv     sKPF[2],  (VTX_SCR_Z      )(outVtx1)
    vmadn   $v29, vM1F, vPairPosI[1h]
    or      $20, $20, $11    // Combine occlusion results. Any set in 0-3, 4-7 = not occluded
    vmadh   $v29, vM1I, vPairPosI[1h]
    slv     vPairST[8], (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmadn   vPairTPosF, vM2F, vPairPosI[2h]
    andi    $11, $20, 0x000F // Bits 0-3 for vtx 1
    vmadh   vPairTPosI, vM2I, vPairPosI[2h]
    bnez    $11, @@skipv1    // If nonzero, at least one equation false, don't set occluded flag
     slv    vPairST[0], (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    ori     $10, $10, CLIP_OCCLUDED // All equations true, set vtx 1 occluded flag
@@skipv1:
    // 16 cycles
    vmudl   $v29, vPairTPosF, $v30[3]       // Persp norm
    addi    $20, $20, -(0x0010) // If not occluded, atl 1 of 4-7 set, so $20 >= 0x10. Else $20 < 0x10.
s1WI equ $v20 // = vPairPosI
    vmadm   s1WI, vPairTPosI, $v30[3]       // Persp norm
    andi    $20, $20, CLIP_OCCLUDED // This is bit 11, = sign bit b/c |$20| <= 0xFF
s1WF equ $v22 // = vPairST
    vmadn   s1WF, $v31, $v31[2]             // 0
    or      $24, $24, $20 // occluded = $20 negative = sign bit set = $20 is flag, else 0
    vmudn   $v29, vPairTPosF, sOCM          // X * kx, Y * ky, Z * kz
    sh      $24,            (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
    vmadh   $v29, vPairTPosI, sOCM          // Int * int
    sh      $10,            (VTX_CLIP      )(outVtx1) // Store first vertex flags
    vrcph   $v29[0], s1WI[3]
    blez    $1, vertex_end  TODO
     vrcpl  sRTF[2], s1WF[3]
    vrcph   sRTI[3], s1WI[7]
    addi    $1, $1, -2*inputVtxSize         // Decrement vertex count by 2
    vrcpl   sRTF[6], s1WF[7]
    sra     $24, $1, 31        // All 1s if on last iter
    vrcph   sRTI[7], $v31[2] // 0
    andi    $24, $24, vtxSize  // vtxSize if on last iter, else normally 0
    vreadacc sOC1, ACC_UPPER                // Load int * int portion
    ldv     sTCL[0],   (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    sub     outVtx2, outVtxBase, $24 // First output vtx on last iter, else second
    vmudl   $v29, s1WF, sRTF[2h]
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vmadm   $v29, s1WI, sRTF[2h]
    suv     vPairRGBA[4],   (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vmadn   s1WF, s1WF, sRTI[3h]
    suv     vPairRGBA[0],   (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vPairTPosI[8],  (VTX_INT_VEC   )(outVtx2)
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    sdv     vPairTPosI[0],  (VTX_INT_VEC   )(outVtx1)
    vmudh   $v29, vOne, $v31[4]  // 4
    cfc2    $10, $vcc                   // Screen clip results
    vmadn   s1WF, s1WF, $v31[0]  // -4
    sdv     vPairTPosF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadh   s1WI, s1WI, $v31[0]  // -4
    ldv     sTCL[8],   (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
sSCF equ $v27 // = vPairRGBA
    vmudn   sSCF, vPairTPosF, $v31[3]       // W * clip ratio for scaled clipping
    sdv     vPairTPosF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vmadh   sSCI, vPairTPosI, $v31[3]       // W * clip ratio for scaled clipping
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    // vnop
    lsv     vPairTPosI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outVtx1) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, sRTI[3h]
    srl     $24, $10, 4            // Shift second vertex screen clipping to first slots
    vmadh   s1WI, s1WI, sRTI[3h]
    lqv     sVPO, (tempViewportOffset)(rdpCmdBufEndP1) // Load viewport offset
    vch     $v29, vPairTPosI, sSCI[3h] // Clip scaled high
    andi    $24, $24, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcl     $v29, vPairTPosF, sSCF[3h] // Clip scaled low
    andi    $10, $10, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmudl   $v29, vPairTPosF, s1WF[3h] // Pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vPairTPosI, s1WF[3h] // Pos times inv W
    cfc2    $20, $vcc                   // Scaled clip results
    vmadn   vPairTPosF, vPairTPosF, s1WI[3h]
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmadh   vPairTPosI, vPairTPosI, s1WI[3h] // vPairTPosI:vPairTPosF = pos times inv W
sVPS equ $v27 // = sSCF, = vPairRGBA
    lqv     sVPS, (tempViewportScale)(rdpCmdBufEndP1) // Load viewport scale
    vcopy   vPairST, sTCL
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vadd    sOC4, sOC1, sOC1[1h] // Add Y to X
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    vmadm   vPairTPosI, vPairTPosI, $v30[3] // Persp norm
    andi    $20, $20, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vPairTPosF, $v31, $v31[2] // 0; Now vPairTPosI:vPairTPosF = projected position
    or      $24, $24, $20            // Combine results for second vertex
    vadd    sOC1, sOC4, sOC1[2h] // Add Z to X
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmov    sTCL[4], vPairST[2] // First vtx RG to elem 4
    ldv     vPairPosI[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmudh   $v29, sVPO, vOne // offset * 1
    ldv     vPairPosI[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadn   sKPF, vPairTPosF, sVPS   // + pos frac * scale
    ldv     sO03[0], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // Load coeffs 0-3
    vmadh   sKPI, vPairTPosI, sVPS   // int part, sKPI:sKPF is now screen space pos
    ldv     sO03[8], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // and for vtx 2
sFOG equ $v24 // = vPairTPosI = vBBB
    vmadh   sFOG, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
    or      $10, $10, $11         // Combine results for first vertex
    vlt     $v29, sOC1, sOCM[3h] // Occlusion plane X+Y+Z<C in elems 0, 4
sOPM equ $v23 // = vPairTPosF = vAAA
    lqv     sOPM, (tempOccPlusMinus)(rdpCmdBufEndP1) // Load occlusion plane -/+4000 constants
    vmov    sTCL[5], vPairST[3] // First vtx BA to elem 5
    cfc2    $11, $vcc // Load occlusion plane mid results to bits 3 and 7
sOSC equ $v27 // = vPairRGBA = sVPS
    vmudh   sOSC, sKPI, $v31[4]   // 4; scale up x and y
    ldv     sO47[0], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // Load coeffs 4-7
    vge     sFOG, sFOG, $v31[6]   // 0x7F00; clamp fog to >= 0 (want low byte only)   
    ldv     sO47[8], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // and for vtx 2
    // vnop
    andi    $11, $11, (1 << 0) | (1 << 4) // Only bits 0, 4 from occlusion
    vmulf   $v29, sOPM, sKPI[1h]  // -0x4000*Y1, --, +0x4000*Y1, --, repeat vtx 2
    sub     $20, outVtx2, $7      // Points 8 before outVtx2 if fog, else 0
    vmacf   sOC2, sO03, sOSC[0h]  //    4*X1*c0, --,    4*X1*c2, --, repeat vtx 2
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmulf   $v29, sOPM, sKPI[0h]  // --, -0x4000*X1, --, +0x4000*X1, repeat vtx 2
    sbv     sFOG[15], (VTX_COLOR_A + 8)($20) // In VTX_SCR_Y if fog disabled...
sOC3 equ $v27 // = vPairRGBA = sOSC
    vmacf   sOC3, sO03, sOSC[1h]  // --,    4*Y1*c1, --,    4*Y1*c3, repeat vtx 2
    jr      $ra                   // lt_vtx_pair or vtx_loop_no_lighting
sCLZ equ $v23 // = vPairTPosF = vAAA = sOPM
     vge    sCLZ, sKPI, $v31[2]   // 0; clamp Z to >= 0
     // vnop in land slot
     
    
    
    

vertex_end:
    j      run_next_DL_command
     lqv   $v30, (v30Value)($zero)           // Restore value overwritten in vtx_store


.endif

.else // end of new LVP_NOC

.if CFG_LEGACY_VTX_PIPE
vtx_early_return_from_lighting:
    vmrg    vPairRGBA, vPairLt, vPairRGBA  // RGB = light, A = vtx alpha
.endif
vtx_loop_no_lighting:
vtx_return_from_lighting:
    li      $ra, vertex_end
.if CFG_LEGACY_VTX_PIPE
    vmudm   vPairST, vPairST, sSTS      // Scale ST; must be after texgen
@@skipsecond:
.else
    vclr    sSTO
    andi    $11, $5, G_ATTROFFSET_ST_ENABLE >> 8
    vmudn   $v29, vVP3F, vOne
    beqz    $11, @@skipoffset
     vmadh  $v29, vVP3I, vOne
    llv     sSTO[0], (attrOffsetST - altBase)(altBaseReg) // elems 0, 1 = S, T offset
    llv     sSTO[8], (attrOffsetST - altBase)(altBaseReg) // elems 4, 5 = S, T offset
@@skipoffset:
    vmadl   $v29, vVP0F, vPairPosF[0h]
    llv     sSTS[0], (textureSettings2)($zero)  // Texture ST scale in 0, 1
    vmadm   $v29, vVP0I, vPairPosF[0h]
    llv     sSTS[8], (textureSettings2)($zero)  // Texture ST scale in 4, 5
    vmadn   $v29, vVP0F, vPairPosI[0h]
    vmadh   $v29, vVP0I, vPairPosI[0h]
    vmadl   $v29, vVP1F, vPairPosF[1h]
    vmadm   $v29, vVP1I, vPairPosF[1h]
    vmadn   $v29, vVP1F, vPairPosI[1h]
    vmadh   $v29, vVP1I, vPairPosI[1h]
    vmadl   $v29, vVP2F, vPairPosF[2h]
    vmadm   $v29, vVP2I, vPairPosF[2h]
    vmadn   vPairTPosF, vVP2F, vPairPosI[2h]
    vmadh   vPairTPosI, vVP2I, vPairPosI[2h]
    vmudm   $v29, vPairST, sSTS         // Scale ST; must be after texgen
    vmadh   vPairST, sSTO, vOne         // + 1 * (ST offset or zero)
.endif
    addi    outVtxBase, outVtxBase, 2*vtxSize
vtx_store_for_clip:
    // Inputs: vPairTPosI, vPairTPosF, vPairST, vPairRGBA
    // Locals: $v20, $v21, $v25, $v26, $v16, $v17 ($v29 is temp). Also vPairST and
    // vPairRGBA can be used as temps once stored ($v22, $v27).
    // Scalar regs: outVtx2, outVtxBase; set to the same thing if only write 1 vtx
    // temps $10, $11, $20, $24
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
    move    outVtx2, outVtxBase          // Second and output vertices write to same mem...
    vmadm   s1WI, vPairTPosI, $v30[3] // Persp norm
    bltz    $1, @@skipsecond                    // ...if < 0 verts remain, ...
     vmadn  s1WF, $v31, $v31[2] // 0
    addi    outVtx2, outVtxBase, vtxSize // ...otherwise, second vtx is next vtx
@@skipsecond:
    vch     $v29, vPairTPosI, vPairTPosI[3h] // Clip screen high
    suv     vPairRGBA[4],     (VTX_COLOR_VEC )(outVtx2)
    vcl     $v29, vPairTPosF, vPairTPosF[3h] // Clip screen low
    suv     vPairRGBA[0],     (VTX_COLOR_VEC )(outVtxBase)
    vrcph   $v29[0], s1WI[3]
    cfc2    $10, $vcc // Load screen clipping results
    vrcpl   sRTF[2], s1WF[3]
    sdv     vPairTPosF[8],    (VTX_FRAC_VEC  )(outVtx2)
    vrcph   sRTI[3], s1WI[7]
    move    outVtx1, outVtxBase  // Else outVtx1 is initialized to temp memory on first pre-loop
    vrcpl   sRTF[6], s1WF[7]
    sdv     vPairTPosF[0],    (VTX_FRAC_VEC  )(outVtxBase)
    vrcph   sRTI[7], $v31[2] // 0
    sdv     vPairTPosI[8],    (VTX_INT_VEC   )(outVtx2)
    vmudn   sSCF, vPairTPosF, $v31[3] // W * clip ratio for scaled clipping
    sdv     vPairTPosI[0],    (VTX_INT_VEC   )(outVtxBase)
    vmadh   sSCI, vPairTPosI, $v31[3] // W * clip ratio for scaled clipping
    slv     vPairST[8],       (VTX_TC_VEC    )(outVtx2)
    vmudl   $v29, s1WF, sRTF[2h]
    slv     vPairST[0],       (VTX_TC_VEC    )(outVtxBase)
    vmadm   $v29, s1WI, sRTF[2h]

.if CFG_NO_OCCLUSION_PLANE
    vmadn   s1WF, s1WF, sRTI[3h]
    addi    inVtx, inVtx, 2*inputVtxSize
    vmadh   s1WI, s1WI, sRTI[3h]
vtx_store_loop_entry:
// vPairST is $v22
    ldv     vPairST[0],   (VTX_IN_TC + inputVtxSize * 0)(inVtx) // ST in 0:1, RGBA in 2:3
    vch     $v29, vPairTPosI, sSCI[3h] // Clip scaled high
    ldv     vPairST[8],   (VTX_IN_TC + inputVtxSize * 1)(inVtx) // ST in 4:5, RGBA in 6:7
    vmudh   $v29, vOne, $v31[4] // 4 * 1 in elems 3, 7
    lsv     vPairTPosI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, $v31[0] // -4
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, $v31[0] // -4
    srl     $24, $10, 4            // Shift second vertex screen clipping to first slots
    vcl     $v29, vPairTPosF, sSCF[3h] // Clip scaled low
    andi    $24, $24, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
// sTCL is $v21
    vcopy   sTCL, vPairST
    cfc2    $20, $vcc // Load scaled clipping results
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, sRTI[3h]
// vPairPosI is $v20
    ldv     vPairPosI[0], (VTX_IN_OB + inputVtxSize * 0)(inVtx)
    vmadh   s1WI, s1WI, sRTI[3h] // s1WI:s1WF is 1/W
    ldv     vPairPosI[8], (VTX_IN_OB + inputVtxSize * 1)(inVtx)
    vmov    sTCL[4], vPairST[2]
    andi    $10, $10, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmov    sTCL[5], vPairST[3]
    ori     $10, $10, CLIP_VTX_USED // Write for all first verts, only matters for generated verts
    vmudl   $v29, vPairTPosF, s1WF[3h]
    ssv     s1WF[14],         (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vPairTPosI, s1WF[3h]
    ssv     s1WF[6],          (VTX_INV_W_FRAC)(outVtx1)
    vmadn   vPairTPosF, vPairTPosF, s1WI[3h]
    ssv     s1WI[14],         (VTX_INV_W_INT )(outVtx2)
    vmadh   vPairTPosI, vPairTPosI, s1WI[3h] // pos * 1/W
    ssv     s1WI[6],          (VTX_INV_W_INT )(outVtx1)
    // vnop
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA
    // vnop
.if CFG_LEGACY_VTX_PIPE
    lpv     $v14[7],      (tempVpRGBA - 8)(rdpCmdBufEndP1) // Y to elem 0, 4
.else
// sVPO is $v17 // vtx_store ViewPort Offset
    lqv     sVPO, (tempViewportOffset)(rdpCmdBufEndP1) // Load viewport offset
.endif
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
.if CFG_LEGACY_VTX_PIPE
    lpv     $v15[6],      (tempVpRGBA - 8)(rdpCmdBufEndP1) // Z to elem 0, 4
.else
// sVPS is $v26 // vtx_store ViewPort Scale
    lqv     sVPS, (tempViewportScale)(rdpCmdBufEndP1) // Load viewport scale
.endif
    vmadm   vPairTPosI, vPairTPosI, $v30[3] // Persp norm
// vPairRGBA is $v27
    luv     vPairRGBA[0], (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
    vmadn   vPairTPosF, $v31, $v31[2] // 0
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
.if !CFG_LEGACY_VTX_PIPE
// sTPN is $v16
    vmov    sTPN[2], vPairPosI[7]  // Move vtx 1 packed normals to elem 2
.endif
    andi    $20, $20, CLIP_SCAL_NPXY // Mask to only bits we care about
.if !CFG_LEGACY_VTX_PIPE
    vmov    sTPN[0], vPairPosI[3]  // Move vtx 0 packed normals to elem 0
.endif
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmudh   $v29, sVPO, vOne // offset * 1
    or      $24, $24, $20          // Combine results for second vertex
    vmadn   vPairTPosF, vPairTPosF, sVPS // + XYZ * scale
    or      $10, $10, $11          // Combine results for first vertex
    vmadh   vPairTPosI, vPairTPosI, sVPS
    sh      $24,              (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
// sFOG is $v25
    vmadh   sFOG, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
.if !CFG_LEGACY_VTX_PIPE
    sdv     sTPN[0],          (tempVpPkNorm)(rdpCmdBufEndP1) // Vtx 0 and 1 packed normals
.endif
    // vnop
    sh      $10,              (VTX_CLIP      )(outVtx1)          // Store first vertex results
// vPairNrml is $v16
    vmudn   vPairNrml, vPairRGBA, $v31[3] // 2; left shift RGBA without clamp; vtx pair normals
    ssv     vPairTPosF[12],   (VTX_SCR_Z_FRAC)(outVtx2)
// sCLZ is $v21 // vtx_store CLamped Z
    vge     sCLZ, vPairTPosI, $v31[2] // 0; clamp Z to >= 0
    ssv     vPairTPosF[4],    (VTX_SCR_Z_FRAC)(outVtx1)
    vge     sFOG, sFOG, $v31[6] // 0x7F00; clamp fog to >= 0 (want low byte only)
    slv     vPairTPosI[8],    (VTX_SCR_VEC   )(outVtx2)
    vmudn   $v29, vM3F, vOne
    slv     vPairTPosI[0],    (VTX_SCR_VEC   )(outVtx1)
    vmadh   $v29, vM3I, vOne
    blez    $1, skip_return_to_lt_or_loop  // $ra left as vertex_end or clipping
     vmadn  $v29, vM0F, vPairPosI[0h]
    move    $ra, $16                    // Normally $ra = loop or lighting
skip_return_to_lt_or_loop:
    vmadh   $v29, vM0I, vPairPosI[0h]
    addi    $1, $1, -2*inputVtxSize     // Counter of remaining verts * inputVtxSize
    vmadn   $v29, vM1F, vPairPosI[1h]
    ssv     sCLZ[12],         (VTX_SCR_Z     )(outVtx2)
    vmadh   $v29, vM1I, vPairPosI[1h]
    ssv     sCLZ[4],          (VTX_SCR_Z     )(outVtx1)
// sOUTF = vPairPosF is $v21, or vPairTPosF is $v23
    vmadn   sOUTF, vM2F, vPairPosI[2h] // vPairPosI/F = vertices world coords
    beqz    $7, return_and_end_mat // fog disabled
// sOUTI = vPairPosI is $v20, or vPairTPosI is $v24
     vmadh  sOUTI, vM2I, vPairPosI[2h] // or vPairTPosI/F = vertices clip coords
    sbv     sFOG[15],         (VTX_COLOR_A   )(outVtx2)
    jr      $ra
     sbv    sFOG[7],          (VTX_COLOR_A   )(outVtx1)
    
.else // CFG_NO_OCCLUSION_PLANE
    
// sOCM is $v22 // vtx_store OCclusion Mid, $v22 = vPairST
    ldv     sOCM[0], (occlusionPlaneMidCoeffs - altBase)(altBaseReg)
    vmadn   s1WF, s1WF, sRTI[3h]
    ldv     sOCM[8], (occlusionPlaneMidCoeffs - altBase)(altBaseReg)
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     $24, $10, 4            // Shift second vertex screen clipping to first slots
    vch     $v29, vPairTPosI, sSCI[3h] // Clip scaled high
    andi    $10, $10, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcl     $v29, vPairTPosF, sSCF[3h] // Clip scaled low
    andi    $24, $24, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmudh   $v29, vOne, $v31[4] // 4 * 1 in elems 3, 7
    cfc2    $20, $vcc // Load scaled clipping results
    vmadn   s1WF, s1WF, $v31[0] // -4
    ori     $10, $10, CLIP_VTX_USED // Write for all first verts, only matters for generated verts
    vmadh   s1WI, s1WI, $v31[0] // -4
    addi    inVtx, inVtx, 2*inputVtxSize
    vmudn   $v29, vPairTPosF, sOCM // X * kx, Y * ky, Z * kz
    vmadh   $v29, vPairTPosI, sOCM // Int * int
    lsv     vPairTPosF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
// sOC1 is $v21 // vtx_store OCclusion temp 1
    vreadacc sOC1, ACC_UPPER // Load int * int portion
    lsv     vPairTPosF[6],  (VTX_Z_FRAC    )(outVtxBase) // load Z into W slot, will be for fog below
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vPairTPosI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    lsv     vPairTPosI[6],  (VTX_Z_INT     )(outVtxBase) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, sRTI[3h]
    sll     $11, $20, 4            // Shift first vertex scaled clipping to second slots
    vmadh   s1WI, s1WI, sRTI[3h] // s1WI:s1WF is 1/W
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    veq     $v29, $v31, $v31[3h] // Set VCC to 00010001
    blez    $1, skip_return_to_lt_or_loop  // $ra left as vertex_end or clipping
     vmrg   sOC1, sOCM, sOC1  // Put constant factor in elems 3, 7
vtx_store_loop_entry:
    move    $ra, $16                    // Normally $ra = loop or lighting
skip_return_to_lt_or_loop:
    vmudl   $v29, vPairTPosF, s1WF[3h]  // W must be overwritten with Z before here
    ssv     s1WF[14],         (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vPairTPosI, s1WF[3h]
    ssv     s1WF[6],          (VTX_INV_W_FRAC)(outVtx1)
    vmadn   vPairTPosF, vPairTPosF, s1WI[3h]
    ssv     s1WI[14],         (VTX_INV_W_INT )(outVtx2)
    vmadh   vPairTPosI, vPairTPosI, s1WI[3h] // pos * 1/W
    ssv     s1WI[6],          (VTX_INV_W_INT )(outVtx1)
    vadd    sOC1, sOC1, sOC1[0q] // Add pairs upwards
.if !CFG_LEGACY_VTX_PIPE
// sVPO is $v17 // vtx_store ViewPort Offset
    lqv     sVPO, (tempViewportOffset)(rdpCmdBufEndP1) // Load viewport offset
.endif
    // vnop
.if CFG_LEGACY_VTX_PIPE
    addi    $1, $1, -2*inputVtxSize     // Counter of remaining verts * inputVtxSize
.else
// sVPS is $v16 // vtx_store ViewPort Scale
    lqv     sVPS, (tempViewportScale)(rdpCmdBufEndP1) // Load viewport scale
.endif
    vmudl   $v29, vPairTPosF, $v30[3] // Persp norm
// vPairST is $v22
    ldv     vPairST[0],   (VTX_IN_TC + inputVtxSize * 0)(inVtx) // ST in 0:1, RGBA in 2:3
    vmadm   vPairTPosI, vPairTPosI, $v30[3] // Persp norm
    ldv     vPairST[8],   (VTX_IN_TC + inputVtxSize * 1)(inVtx) // ST in 4:5, RGBA in 6:7
    vmadn   vPairTPosF, $v31, $v31[2] // 0
// vPairPosI is $v20
    ldv     vPairPosI[0],      (VTX_IN_OB + inputVtxSize * 0)(inVtx)
    vadd    sOC1, sOC1, sOC1[1h] // Add elems 1, 5 to 3, 7
    ldv     vPairPosI[8],      (VTX_IN_OB + inputVtxSize * 1)(inVtx)
    // vnop
// sO03 is $v26 // vtx_store Occlusion coeffs 0-3
    ldv     sO03[0], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // Load coeffs 0-3
    vmudh   $v29, sVPO, vOne // offset * 1
    ldv     sO03[8], (occlusionPlaneEdgeCoeffs - altBase)(altBaseReg) // and for vtx 2
    vmadn   vPairTPosF, vPairTPosF, sVPS // + XYZ * scale
.if !CFG_LEGACY_VTX_PIPE
// sOPM is $v17 // vtx_store Occlusion Plus Minus constants
    lqv     sOPM, (tempOccPlusMinus)(rdpCmdBufEndP1) // Load occlusion plane -/+4000 constants
.endif
    vmadh   vPairTPosI, vPairTPosI, sVPS
    andi    $20, $20, CLIP_SCAL_NPXY // Mask to only bits we care about
// sFOG is $v16
    vmadh   sFOG, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
    or      $10, $10, $11          // Combine results for first vertex
    vlt     $v29, sOC1, $v31[2] // Occlusion plane equation < 0 in elems 3, 7
    slv     vPairST[4],   (tempVpRGBA + 0)(rdpCmdBufEndP1) // Store vtx 0 RGBA to temp mem
.if !CFG_LEGACY_VTX_PIPE
// sTPN is $v18
    vmov    sTPN[2], vPairPosI[7]  // Move vtx 1 packed normals to elem 2
.endif
    slv     vPairST[12],  (tempVpRGBA + 4)(rdpCmdBufEndP1) // Store vtx 1 RGBA to temp mem
.if !CFG_LEGACY_VTX_PIPE
    vmov    sTPN[0], vPairPosI[3]  // Move vtx 0 packed normals to elem 0
.endif
    cfc2    $11, $vcc // Load occlusion plane mid results to bits 3 and 7
// sOSC is $v21 // vtx_store Occlusion SCaled up
    vmudh   sOSC, vPairTPosI, $v31[4] // 4; scale up x and y
    ssv     vPairTPosF[12],   (VTX_SCR_Z_FRAC)(outVtx2)
    vge     sFOG, sFOG, $v31[6] // 0x7F00; clamp fog to >= 0 (want low byte only)
    or      $24, $24, $20          // Combine results for second vertex
// sCLZ is $v25 // vtx_store CLamped Z
    vge     sCLZ, vPairTPosI, $v31[2] // 0; clamp Z to >= 0
    ssv     vPairTPosF[4],    (VTX_SCR_Z_FRAC)(outVtx1)
    vmulf   $v29, sOPM, vPairTPosI[1h] // -0x4000*Y1, --, +0x4000*Y1, --, repeat vtx 2
// sO47 is $v23 // vtx_store Occlusion coeffs 0-3; $v23 = vPairTPosF
    ldv     sO47[0], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // Load coeffs 4-7
// sOC2 is $v27 // vtx_store OCclusion temp 2; $v27 = vPairRGBA
    vmacf   sOC2, sO03, sOSC[0h]       //    4*X1*c0, --,    4*X1*c2, --, repeat vtx 2
    ldv     sO47[8], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // and for vtx 2
    vmulf   $v29, sOPM, vPairTPosI[0h] // --, -0x4000*X1, --, +0x4000*X1, repeat vtx 2
    beqz    $7, @@skipfog // fog disabled
// sOC3 is $v21 // vtx_store OCclusion temp 3
     vmacf  sOC3, sO03, sOSC[1h]       // --,    4*Y1*c1, --,    4*Y1*c3, repeat vtx 2
    sbv     sFOG[15],         (VTX_COLOR_A   )(outVtx2)
    sbv     sFOG[7],          (VTX_COLOR_A   )(outVtx1)
@@skipfog:
    slv     vPairTPosI[8],    (VTX_SCR_VEC   )(outVtx2)
    veq     $v29, $v31, $v31[0q]       // Set VCC to 10101010
    slv     vPairTPosI[0],    (VTX_SCR_VEC   )(outVtx1)
    vmrg    sOC2, sOC2, sOC3           // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
.if CFG_LEGACY_VTX_PIPE
    lpv     $v14[7],          (tempVpRGBA - 8)(rdpCmdBufEndP1) // Y to elem 0, 4
.else
    sdv     sTPN[0],          (tempVpPkNorm)(rdpCmdBufEndP1) // Vtx 0 and 1 packed normals
.endif
    // vnop
    ssv     sCLZ[12],         (VTX_SCR_Z     )(outVtx2)
    // vnop
.if CFG_LEGACY_VTX_PIPE
    lpv     $v15[6],          (tempVpRGBA - 8)(rdpCmdBufEndP1) // Z to elem 0, 4
.else
    addi    $1, $1, -2*inputVtxSize     // Counter of remaining verts * inputVtxSize
.endif
    // vnop
    ssv     sCLZ[4],          (VTX_SCR_Z     )(outVtx1)
    vge     $v29, sOC2, sO47           // Each compare to coeffs 4-7
// vPairNrml is $v16
    lpv     vPairNrml[0],     (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair normals
    vmudn   $v29, vM3F, vOne
    cfc2    $20, $vcc
    vmadh   $v29, vM3I, vOne
// vPairRGBA is $v27
    luv     vPairRGBA[0],     (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair colors
    vmadn   $v29, vM0F, vPairPosI[0h]
    andi    $11, $11, (1 << 7) | (1 << 3) // Only bits 3, 7 from occlusion
    vmadh   $v29, vM0I, vPairPosI[0h]
    or      $20, $20, $11    // Combine occlusion results. Any set in 0-3, 4-7 = not occluded
    vmadn   $v29, vM1F, vPairPosI[1h]
    andi    $11, $20, 0x00F0 // Bits 4-7 for vtx 2
    vmadh   $v29, vM1I, vPairPosI[1h]
    bnez    $11, @@skipv2    // If nonzero, at least one equation false, don't set occluded flag
     andi   $20, $20, 0x000F // Bits 0-3 for vtx 1
    ori     $24, $24, CLIP_OCCLUDED // All equations true, set vtx 2 occluded flag
@@skipv2:
// sOUTF = vPairPosF is $v21, or vPairTPosF is $v23
    vmadn   sOUTF, vM2F, vPairPosI[2h] // vPairPosI/F = vertices world coords
    bnez    $20, @@skipv1    // If nonzero, at least one equation false, don't set occluded flag
     sh     $24,              (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
    ori     $10, $10, CLIP_OCCLUDED // All equations true, set vtx 1 occluded flag
@@skipv1:    
// sOUTI = vPairPosI is $v20, or vPairTPosI is $v24
    vmadh   sOUTI, vM2I, vPairPosI[2h] // or vPairTPosI/F = vertices clip coords
    jr      $ra
     sh     $10,              (VTX_CLIP      )(outVtx1)          // Store first vertex results

.endif // CFG_NO_OCCLUSION_PLANE

.endif // New LVP_NOC

.if !CFG_PROFILING_A && (!CFG_NO_OCCLUSION_PLANE || !CFG_LEGACY_VTX_PIPE)
vertex_end:
    j      run_next_DL_command
     lqv   $v30, (v30Value)($zero)           // Restore value overwritten in vtx_store
.endif

.if CFG_PROFILING_A
vertex_end:
    li      $ra, 0                           // Flag for coming from vtx
.if !CFG_NO_OCCLUSION_PLANE || !CFG_LEGACY_VTX_PIPE
    lqv     $v30, (v30Value)($zero)          // Restore value overwritten in vtx_store
.endif
tris_end:
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

.if CFG_LEGACY_VTX_PIPE || CFG_NO_OCCLUSION_PLANE
G_MTX_end:
    instantiate_mtx_end_begin
mtx_multiply:
    instantiate_mtx_multiply
.endif


.if CFG_PROFILING_B
loadOverlayInstrs equ 13
.elseif CFG_PROFILING_C
loadOverlayInstrs equ 24
.else
loadOverlayInstrs equ 12
.endif
endFreeImemAddr equ (0x1FC8 - (4 * loadOverlayInstrs))
startFreeImem:
.if . > endFreeImemAddr
    .error "Out of IMEM space"
.endif
.org endFreeImemAddr
endFreeImem:

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
    jal     shared_dma_read_write  // If CFG_PROFILING_C, use the one without perfCounterD
     add    cmd_w1_dram, cmd_w1_dram, $11
    move    $ra, postOvlRA
    // Fall through to while_wait_dma_busy
.if CFG_PROFILING_C
// ...except if profiling DMA time. According to Tharo's testing, and in contradiction
// to the manual, almost no instructions are issued while an IMEM DMA is happening.
// So we have to time it using counters.
    mfc0    $11, SP_DMA_BUSY
@@while_dma_busy:
    bnez    $11, @@while_dma_busy
     mfc0   $11, SP_DMA_BUSY
    mfc0    $11, DPC_CLOCK
    sub     $11, $11, $9
    jr      $ra
     add    perfCounterD, perfCounterD, $11

// Also, normal dma_read_write below can't be changed to insert perfCounterD due to
// S2DEX constraints. So we have to duplicate that part of it.
dma_read_write:
    mfc0    $11, SP_DMA_FULL
    bnez    $11, dma_read_write
     addi   perfCounterD, perfCounterD, 6  // 3 instr + 2 after mfc + 1 taken branch
    j       dma_read_write_not_full
     // $11 load in delay slot is harmless.
.endif

.if . != 0x1FC8
    // This has to be at this address for boot and S2DEX compatibility
    .error "Error in organization of end of IMEM"
.endif

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
old_return_routine:
    jr      $ra
     // Has mfc0 in branch delay slot, causes a stall if first instr after ret is load

.if !CFG_PROFILING_C
dma_read_write:
.endif
shared_dma_read_write:
     mfc0   $11, SP_DMA_FULL          // load the DMA_FULL value
@@while_dma_full:
    bnez    $11, @@while_dma_full     // Loop until DMA_FULL is cleared
     mfc0   $11, SP_DMA_FULL          // Update DMA_FULL value
dma_read_write_not_full:
    mtc0    dmemAddr, SP_MEM_ADDR     // Set the DMEM address to DMA from/to
    bltz    dmemAddr, dma_write       // If the DMEM address is negative, this is a DMA write, if not read
     mtc0   cmd_w1_dram, SP_DRAM_ADDR // Set the DRAM address to DMA from/to
    jr      $ra
     mtc0   dmaLen, SP_RD_LEN         // Initiate a DMA read with a length of dmaLen
dma_write:
    jr      $ra
     mtc0   dmaLen, SP_WR_LEN         // Initiate a DMA write with a length of dmaLen

.if . != 0x00002000
    .error "Code at end of IMEM shared with other ucodes has been corrupted"
.endif

.headersize 0x00001000 - orga()

// Overlay 0 handles three cases of stopping the current microcode.
// The action here is controlled by $1. If yielding, $1 > 0. If this was
// G_LOAD_UCODE, $1 == 0. If we got to the end of the parent DL, $1 < 0.
ovl0_start:
    sub     $8, rdpCmdBufPtr, rdpCmdBufEndP1
    addi    $10, $8, (RDP_CMD_BUFSIZE + 8) - 1 // Does the current buffer contain anything?
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
    sw      $zero, OSTask + OSTask_flags    // So next ucode knows it didn't come from yield
    li      dmemAddr, start         // Beginning of overwritable part of IMEM
    sw      taskDataPtr, OSTask + OSTask_data_ptr // Store where we are in the DL
    sw      cmd_w1_dram, OSTask + OSTask_ucode // Store pointer to new ucode about to execute
    // Store counters in mITMatrix; first 0x180 of DMEM will be preserved in ucode swap AND
    // if other ucode yields
    sw      perfCounterA, mITMatrix + YDF_OFFSET_PERFCOUNTERA
    sw      perfCounterB, mITMatrix + YDF_OFFSET_PERFCOUNTERB
    sw      perfCounterC, mITMatrix + YDF_OFFSET_PERFCOUNTERC
    sw      perfCounterD, mITMatrix + YDF_OFFSET_PERFCOUNTERD
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
    lhu     $10, (vertexTable)(cmd_w0)      // Start vtx addr
    lhu     $3, (vertexTable)(cmd_w1_dram)  // End vertex
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
.if !CFG_LEGACY_VTX_PIPE
lt_vtx_pair:
.endif
.if CFG_PROFILING_B
.if CFG_LEGACY_VTX_PIPE
    nop
.else
    addi    perfCounterA, perfCounterA, 2    // Increment lit vertex count by 2
.endif
.endif
    j       lt_continue_setup
.if CFG_LEGACY_VTX_PIPE
     lbu    $21, numLightsxSize
.else
     andi   $11, $5, G_PACKED_NORMALS >> 8
.endif

.if !CFG_LEGACY_VTX_PIPE
// Jump here for all overlay 4 features. If overlay 2 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ovl4_entrypoint_ovl2ver:            // same IMEM address as ovl234_ovl4_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4
.endif //!CFG_LEGACY_VTX_PIPE

// Jump here to do clipping. If overlay 2 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipping_entrypoint_ovl2ver:        // same IMEM address as ovl234_clipping_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

lt_continue_setup:
.if CFG_LEGACY_VTX_PIPE
//
// LVP lighting setup
//
    llv     $v30[12], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 6, 7
    lb      $11, dirLightsXfrmValid
    li      $10, -1                   // To mark lights valid
    addi    $21, $21, altBase         // Point to ambient light; stored through vtx proc
    andi    $17, $5, G_TEXTURE_GEN >> 8 // This is clipPolyRead, but not touched in vtx_store
    and     $11, $11, $7              // Zero if either matrix or lights invalid
    bnez    $11, lt_setup_after_xfrm
     sb     $10, dirLightsXfrmValid
xfrm_dir_lights:
    // Transform directional lights' direction by M transpose.
    // First, load M transpose. Can use any regs except $v8-$v12, $v28-$v31.
    // This algorithm clobbers all of $v0-$v7 and $v16-$v23 with the transposes;
    // it's mainly just an excuse to use the rare ltv and swv instructions.
    // The F3DEX2 implementation takes 18 instructions and 11 cycles.
    // This implementation is 23 instructions and 17 cycles, but this version
    // loads M transpose to both halves of each vector so we can process two
    // lights at a time, which matters because there's always at least 3 lights
    // (technically 2 for EX3)--the lookat directions. Plus, those 17 cycles
    // also include a few instructions starting the loop.
    // Memory at mMatrix contains, in shorts within qwords, for the elements we care about:
    // A B C - D E F - (X int, Y int)
    // G H I - - - - - (Z int, W int)
    // M N O - P Q R - (X frac, Y frac)
    // S T U - - - - - (Z frac, W frac)
    // First, make $v0-$v7 contain this, and same for $v16-$v23 frac parts.
    // $v0 A - G - A - G -   $v16 M - S - M - S -
    // $v1 - B - H - B - H   $v17 - N - T - N - T
    // $v2 I - C - I - C -   $v18 U - O - U - O -
    // $v3 - - - - - - - -   $v19 - - - - - - - -
    // $v4 D - - - D - - -   $v20 P - - - P - - -
    // $v5 - E - - - E - -   $v21 - Q - - - Q - -
    // $v6 - - F - - - F -   $v22 - - R - - - R -
    // $v7 - - - - - - - -   $v23 - - - - - - - -
    ltv     $v0[0],   (mMatrix + 0x00)($zero) // A to $v0[0] etc.
    ltv     $v0[12],  (mMatrix + 0x10)($zero) // G to $v0[2] etc.
    ltv     $v0[8],   (mMatrix + 0x00)($zero) // A to $v0[4] etc.
    ltv     $v0[4],   (mMatrix + 0x10)($zero) // G to $v0[6] etc.
    ltv     $v16[0],  (mMatrix + 0x20)($zero)
    ltv     $v16[12], (mMatrix + 0x30)($zero)
    ltv     $v16[8],  (mMatrix + 0x20)($zero)
    ltv     $v16[4],  (mMatrix + 0x30)($zero)
    veq     $v29, $v31, $v31[0q] // Set VCC to 10101010
    vmudh   $v1, vOne, $v1[1q]                // B - H - B - H -
    lsv     $v18[6],  (mMatrix + 0x2C)($zero) // U - O(R)U - O -
    vmrg    $v0, $v0, $v4[0q]                 // A D G - A D G -
    lsv     $v18[14], (mMatrix + 0x2C)($zero) // U - O R U - O(R)
    vmrg    $v2, $v2, $v6[0q]                 // I - C F I - C F
    lpv     $v3[0], (lightBufferLookat - altBase)(altBaseReg) // Lookat 0 and 1
    vmudh   $v17, vOne, $v17[1q]              // N - T - N - T -
    li      curLight, altBase - 4 * lightSize // + ltBufOfs = light -4; write pointer
    vmrg    $v1, $v1, $v5                     // B E H - B E H -
    // nop
    // Interleave the start of transforming pairs of dir lights, including lookat.
    vmrg    $v16, $v16, $v20[0q]              // M P S - M P S -
    swv     $v18[4], (tempXfrmSingle)(rdpCmdBufEndP1) // Stores O R U - O R U -
    vmudh   $v29, $v0,  $v3[0h]
    lqv     $v18,    (tempXfrmSingle)(rdpCmdBufEndP1)
    vmrg    $v17, $v17, $v21                  // N Q T - N Q T -
    swv     $v2[4],  (tempXfrmSingle)(rdpCmdBufEndP1) // Stores C F I - C F I -
    vmadh   $v29, $v1,  $v3[1h]
    lqv     $v2,     (tempXfrmSingle)(rdpCmdBufEndP1)
    vmadn   $v29, $v16, $v3[0h]
    // 18 cycles
xfrm_light_loop_1:
    vmadn   $v29, $v18, $v3[2h]
xfrm_light_loop_2:
    vmadn   $v29, $v17, $v3[1h]
    vmadh   $v4,  $v2,  $v3[2h]  // $v4[0:2] and [4:6] = two lights dir in model space
    vrsqh   $v29[0], $v20[0]
    vrsql   $v23[0], $v21[0]
    vrsqh   $v22[0], $v20[4]
    addi    curLight, curLight, 2 * lightSize // Iters: -2, 0, 2, ...
    vrsql   $v23[4], $v21[4]
    lw      $20, (ltBufOfs + 8 + 2 * lightSize)(curLight) // First iter = light 0
    vrsqh   $v22[4], $v31[2]     // 0
    lw      $24, (ltBufOfs + 8 + 3 * lightSize)(curLight) // First iter = light 1
    vmudh   $v29, $v4, $v4       // Squared
    sub     $10, curLight, altBaseReg // Is curLight (write ptr) <= 0?
    vreadacc $v7, ACC_MIDDLE     // Read not-clamped value
    sub     $11, curLight, $21   // Is curLight (write ptr) <, =, or > ambient light?
    vreadacc $v6, ACC_UPPER
    sw      $20,    (tempXfrmSingle)(rdpCmdBufEndP1) // Store light 0
    vmudm   $v29, $v19, $v23[0h] // Vec int * frac scaling
    sw      $24,    (tempXfrmSingle + 4)(rdpCmdBufEndP1) // Store light 1
    vmadh   $v5,  $v19, $v22[0h] // Vec int * int scaling
    lpv     $v3[0], (tempXfrmSingle)(rdpCmdBufEndP1) // Load dirs 0-2, 4-6
    vmudm   $v29, vOne, $v7[2h]  // Sum of squared components
    vmadh   $v29, vOne, $v6[2h]
    vmadm   $v29, vOne, $v7[1h]
    vmadh   $v29, vOne, $v6[1h]
    spv     $v5[0], (tempXfrmSingle)(rdpCmdBufEndP1) // Store elem 0-2, 4-6 as bytes to temp memory
    vmadn   $v21, $v7,  vOne     // elem 0, 4; swapped so we can do vmadn and get result
    lw      $20,    (tempXfrmSingle)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vmadh   $v20, $v6,  vOne
    lw      $24,    (tempXfrmSingle + 4)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vcopy   $v19, $v4
    blez    $10, xfrm_light_store_lookat // curLight = -2 or 0
     vmudh  $v29, $v0,  $v3[0h]
     // 20 cycles from xfrm_light_loop_2 not counting land
    vmadh   $v29, $v1,  $v3[1h]
    bgtz    $11, lt_setup_after_xfrm // curLight > ambient; only one light valid
     sw     $20, (ltBufOfs + 0xC - 2 * lightSize)(curLight) // Write light relative -2
    vmadn   $v29, $v16, $v3[0h]
    bltz    $11, xfrm_light_loop_1   // curLight < ambient; more lights to compute
     sw     $24, (ltBufOfs + 0xC - 1 * lightSize)(curLight) // Write light relative -1
lt_setup_after_xfrm:
    // Load first light direction to $v13, which is not used throughout vtx processing.
    j       vtx_after_lt_setup
     lpv    $v13[0], (ltBufOfs + 8 - lightSize)($21) // Xfrmed dir in elems 4-6
    
xfrm_light_store_lookat:
    vmadh   $v29, $v1,  $v3[1h]
    spv     $v5[0], (xfrmLookatDirs)($zero) // First time is garbage; second actual
    vmadn   $v29, $v16, $v3[0h]
    j       xfrm_light_loop_2
     vmadn  $v29, $v18, $v3[2h]


.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
.align 8
.endif
lt_vtx_pair:
//
// LVP main lighting
//
.if CFG_PROFILING_B
    addi    perfCounterA, perfCounterA, 2    // Increment lit vertex count by 2
.endif
.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    vmadh   $v29, vM1I, vPairPosI[1h]
    lpv     vPairNrml[0],     (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair normals
    vmadn   vPairTPosF, vM2F, vPairPosI[2h]
    lpv     $v14[7],      (tempVpRGBA - 8)(rdpCmdBufEndP1) // Y to elem 0, 4
    vmadh   vPairTPosI, vM2I, vPairPosI[2h]
    lpv     $v15[6],      (tempVpRGBA - 8)(rdpCmdBufEndP1) // Z to elem 0, 4
    // vnop
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
.endif
    vmulf   $v29, vPairNrml, $v13[4] // Normals X elems 0, 4 * first light dir
    luv     vPairLt,     (ltBufOfs + 0)($21)  // Total light level, init to ambient
    vmacf   $v29, $v14, $v13[5] // Normals Y elems 0, 4 * first light dir
    lpv     vDDD[0],     (ltBufOfs + 8 - 2*lightSize)($21) // Xfrmed dir in elems 4-6
    vmacf   vAAA, $v15, $v13[6] // Normals Z elems 0, 4 * first light dir
.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    or      $10, $10, $11          // Combine results for first vertex
    vmulf   vPairRGBA, vPairNrml, $v31[5] // 0x4000; right shift vtx alpha from lpv
.else
    // nop
    // vnop
.endif
    beq     $21, altBaseReg, lt_post
.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
     addi   $1, $1, -2*inputVtxSize         // Decrement vertex count by 2
.else
     lpv    ltLookAt[0], (xfrmLookatDirs + 0)($zero) // Lookat 0 in 0-2, 1 in 4-6; = vNrmOut
.endif
    // vnop
    move    curLight, $21                   // Point to ambient light
lt_loop:
    vge     vCCC, vAAA, $v31[2] // 0; clamp dot product to >= 0
    vmulf   $v29, vPairNrml, vDDD[4] // Normals X elems 0, 4
    luv     vBBB,        (ltBufOfs + 0 - 1*lightSize)(curLight) // Light color
    vmacf   $v29, $v14, vDDD[5] // Normals Y elems 0, 4
    addi    curLight, curLight, -lightSize
    vmacf   vAAA, $v15, vDDD[6] // Normals Z elems 0, 4
    lpv     vDDD[0],     (ltBufOfs + 8 - 2*lightSize)(curLight) // Xfrmed dir in elems 4-6
    vmudh   $v29, vOne, vPairLt // Load accum mid with current light level
    bne     curLight, altBaseReg, lt_loop
     vmacf  vPairLt, vBBB, vCCC[0h] // + light color * dot product
lt_post:
.if CFG_NO_OCCLUSION_PLANE // New LVP_NOC
    vge     sKPG, sKPI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    lpv     ltLookAt[0], (xfrmLookatDirs + 0)($zero) // Lookat 0 in 0-2, 1 in 4-6; = vNrmOut
    vge     sCLZ, sKPI, $v31[2]              // 0; clamp Z to >= 0
    sh      $10, (VTX_CLIP      )(outVtx1) // Store first vertex flags
    vne     $v29, $v31, $v31[3h]           // Set VCC to 11101110
    beqz    $17, vtx_return_from_lighting
     vmrg   vPairRGBA, vPairLt, vPairRGBA  // RGB = light, A = vtx alpha
.else
    beqz    $17, vtx_early_return_from_lighting
     vne    $v29, $v31, $v31[3h]           // Set VCC to 11101110
    vmrg    vPairRGBA, vPairLt, vPairRGBA  // RGB = light, A = vtx alpha
.endif
// Texgen uses vLookat0:1 = vPairLt and VAAA, vCCC:vDDD, and of course vPairST.
    vmulf   $v29, vPairNrml, ltLookAt[0] // Normals X elems 0, 4 * lookat 0 X
    vmacf   $v29, $v14, ltLookAt[1]      // Normals Y elems 0, 4 * lookat 0 Y
    vmacf   vLookat0, $v15, ltLookAt[2]  // Normals Z elems 0, 4 * lookat 0 Z
    vmulf   $v29, vPairNrml, ltLookAt[4] // Normals X elems 0, 4 * lookat 1 X
    vmacf   $v29, $v14, ltLookAt[5]      // Normals Y elems 0, 4 * lookat 1 Y
    vmacf   vLookat1, $v15, ltLookAt[6]  // Normals Z elems 0, 4 * lookat 1 Z
    // Continue to rest of texgen shared by both versions.

.endif // CFG_LEGACY_VTX_PIPE
    
    
.if !CFG_LEGACY_VTX_PIPE
//
// F3DEX3 native lighting
//
    // Inputs: vPairPosI/F vertices pos world int:frac, vPairRGBA, vPairST, vPairNrml
    // Outputs: leave alone vPairPosI/F; update vPairRGBA, vPairST 
    // Locals: vAAA and vBBB after merge and normals selection, vCCC, vDDD, vPairLt, vNrmOut
    // New available locals: $6 (existing: $11, $10, $20, $24)
    beqz    $11, lt_skip_packed_normals
     lpv    vAAA[0],      (tempVpPkNorm)(rdpCmdBufEndP1) // V0 PN in 0,1; V1 PN in 4,5
    // Packed normals algorithm. This produces a vector (one for each input vertex)
    // in vPairNrml such that |X| + |Y| + |Z| = 0x7F00 (called L1 norm), in the
    // same direction as the standard normal vector. The length is not "correct"
    // compared to the standard normal, but it's is normalized anyway after the M
    // matrix transform.
.endif
vPackPXY equ $v25 // = vCCC; positive X and Y in packed normals
vPackZ   equ $v26 // = vDDD; Z in packed normals
.if !CFG_LEGACY_VTX_PIPE
    vand    vPackPXY, vAAA, $v31[6]          // 0x7F00; positive X, Y
    vmudh   $v29, vOne, $v31[1]              // -1; set all elems of $v29 to -1
    // vnop; vnop
    vaddc   vBBB, vPackPXY, vPackPXY[1q]     // elems 0, 4: +X + +Y, no clamping; VCO always 0
    vxor    vPairNrml, vPackPXY, $v31[6]     // 0x7F00 - x, 0x7F00 - y
    // vnop; vnop
    vxor    vPackZ, vBBB, $v31[6]            // 0x7F00 - +X - +Y in elems 0, 4
    vge     $v29, $v29, vBBB[0h]             // set 0-3, 4-7 vcc if -1 >= (+X + +Y), = negative
    vmrg    vPairNrml, vPairNrml, vPackPXY   // If so, use 0x7F00 - +X, else +X (same for Y)
    vne     $v29, $v31, $v31[2h]             // Set VCC to 11011101
    // vnop; vnop
    vabs    vPairNrml, vAAA, vPairNrml       // Apply sign of original X and Y to new X and Y
    // vnop; vnop; vnop
    vmrg    vPairNrml, vPairNrml, vPackZ[0h] // Move Z to elements 2, 6
    // vnop; vnop
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
.endif
vLtMIT0I   equ $v26 // = vDDD
vLtMIT1I   equ $v25 // = vCCC
vLtMIT2I   equ $v23 // = vAAA; last in multiply
vLtMIT0F   equ $v29 // = temp; first
vLtMIT1F   equ $v17 // = vPairLt
vLtMIT2F   equ $v24 // = vBBB; second to last
.if !CFG_LEGACY_VTX_PIPE
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
CFG_DEBUG_NORMALS equ 0 // Can manually enable here
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
     // nop
     vmrg   vAAA, vAAA, vCCC                            // vAAA = light direction
    bnez    $11, lt_point
     luv    vDDD,    (ltBufOfs + 0 - lightSize)(curLight) // Light color
    vcopy   vBBB, vOne // Directional light dot scaling = 0001.0001, approx == 1.0
    vmulf   vAAA, vAAA, vPairNrml // Light dir * normalized normals
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   vCCC, vPairRGBA, $v30[1] // + (alpha - 1) * aoDir factor; elems 3, 7
    // vnop
    vmudh   $v29, vOne, vAAA[0h]
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
    // vnop (assuming not specular)
    vge     vAAA, vAAA, $v31[2] // 0; clamp dot product to >= 0
    // vnop; vnop; vnop
    vmudm   $v29, vAAA, vBBB[2h] // Dot product int * scale frac
    vmadh   vAAA, vAAA, vBBB[3h] // Dot product int * scale int, clamp to 0x7FFF
    addi    curLight, curLight, -lightSize
    // vnop; vnop
    vmudh   $v29, vOne, vPairLt // Load accum mid with current light level
    j       lt_loop
     vmacf  vPairLt, vDDD, vAAA[0h] // + light color * dot product
    
lt_post:
    // Valid: vPairPosI/F, vPairST, modified vPairRGBA ([3h] = alpha - 1),
    // vPairNrml normal [0h:2h] fresnel [3h], vPairLt [0h:2h], vAAA lookat 0 dir
.endif
vLtRGBOut  equ $v25 // = vCCC: light / effects RGB output
vLtAOut    equ $v26 // = vDDD: light / effects alpha output
.if !CFG_LEGACY_VTX_PIPE
    vadd    vPairRGBA, vPairRGBA, $v31[7]  // 0x7FFF; undo change for ambient occlusion
    andi    $11, $5, G_LIGHTTOALPHA >> 8
    // vnop
    andi    $20, $5, G_PACKED_NORMALS >> 8
    // vnop
    andi    $10, $5, G_TEXTURE_GEN >> 8
    // vnop
    // nop
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
    vmadh   vLookat1, vOne, vLookat1[2h]
.endif
    // Rest of texgen shared by F3DEX3 native and LVP
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
    
.if !CFG_LEGACY_VTX_PIPE
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
    // vnop; vnop
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
    // vnop; vnop; vnop
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
    // vnop; vnop; vnop
    vmudn   vBBB, vBBB, $v29[0h] // Vec frac * int scaling, discard result
    srl     $20, $20, 16
    vmadm   vBBB, vAAA, $v29[1h] // Vec int * frac scaling, discard result
    jr      $ra
     vmadh  vNrmOut, vAAA, $v29[0h] // Vec int * int scaling
.endif

ovl2_end:
.align 8
ovl2_padded_end:

.headersize ovl234_start - orga()

ovl4_start:

.if !CFG_LEGACY_VTX_PIPE

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
.if !CFG_NO_OCCLUSION_PLANE
G_MTX_end:
.endif
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       ovl4_select_instr
     lw     cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Overwritten by overlay load

// Jump here to do clipping. If overlay 4 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipping_entrypoint_ovl4ver:        // same IMEM address as ovl234_clipping_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

ovl4_select_instr:
.if !CFG_NO_OCCLUSION_PLANE
    li      $2, (0xFF00 | G_MTX)
    beq     $2, $7, g_mtx_end_ovl4
.endif
     li     $3, G_BRANCH_WZ
    beq     $3, $7, g_branch_wz_ovl4
     li     $2, (0xFF00 | G_DMA_IO)
    beq     $2, $7, g_dma_io_ovl4
     li     $3, (0xFF00 | G_MEMSET)
    beq     $3, $7, g_memset_ovl4
     // Otherwise calc_mit. Delay slot is harmless.

calc_mit:
    /*
    Compute M inverse transpose. All regs available except vM0I::vM3F, $v30 (fxParams),
    and $v31 constants.
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

.if !CFG_NO_OCCLUSION_PLANE
g_mtx_end_ovl4:
    instantiate_mtx_end_begin
    instantiate_mtx_multiply
.endif

g_branch_wz_ovl4:
    instantiate_branch_wz

g_dma_io_ovl4:
    instantiate_dma_io
    
g_memset_ovl4:
    instantiate_memset

.endif // !CFG_LEGACY_VTX_PIPE

ovl4_end:
.align 8
ovl4_padded_end:

.close // CODE_FILE
