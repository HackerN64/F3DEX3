.rsp

.include "rsp/rsp_defs.inc"
.include "rsp/gbi.inc"

// This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

// Sign-extends the immediate using addi. ori would zero-extend.
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

CFG_DEBUG_NORMALS equ 0 // Can manually enable here

// Only raise a warning in base modes; in profiling modes, addresses will be off
.macro warn_if_base, warntext
    .if !ENABLE_PROFILING
        .warning warntext
    .endif
.endmacro

.macro align_with_warning, alignment, warntext
    .if (. & (alignment - 1))
        warn_if_base warntext
    .endif
    .align alignment
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

Rest command handlers
Vertex start
All tri write cmds

Overlay 2           Overlay 3       Overlay 4
(Basic lighting)    (Clipping,      (Advanced
                    rare cmds)      lighting)

Main vertex write

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
    .fill 0x40

// 0x0040-0x0080: view * projection matrix
vpMatrix:
    .fill 0x40

// model * (view * projection) matrix
mvpMatrix:
    .fill 0x40
    
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

// TODO: This is unnecessary, the state only has to be saved between the two
// commands making up the texrect command. Could put this in the part of the
// clip buffer that's kept over yields.
// Saved texrect state for combining the multiple input commands into one RDP texrect command
texrectWord1:
    .fill 4 // first word, has command byte, xh and yh
texrectWord2:
    .fill 4 // second word, has tile, xl, yl

// First half of RDP value for split commands. Also used as temp storage for
// tri vertices during tri commands.
rdpHalf1Val:
    .fill 4
    
activeClipPlanes:
    .dh CLIP_SCAL_NPXY | CLIP_CAMPLANE  // Normal tri write, set to zero when clipping
    
// displaylist stack length
displayListStackLength:
    .db 0x00 // starts at 0, increments by 4 for each "return address" pushed onto the stack
    
unused1:
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
.if (. & 15) != 0
    .error "Wrong alignment for altBase"
.endif
altBase:

textureSettings1:
    .dw 0x00000000 // first word, has command byte, level, tile, and on
    
textureSettings2:
    .dw 0xFFFFFFFF // second word, has s and t scale
    
geometryModeLabel:
    .dw 0x00000000 // originally initialized to G_CLIPPING, but that does nothing
    
fogFactor:
    .dw 0x00000000

// constants for register vTRC
.if (. & 15) != 0
    .error "Wrong alignment for vTRCValue"
.endif
vTRCValue:
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
.macro set_vcc_11110001
    vge    $v29, vTRC, vTRC[7]
.endmacro
.if (vertexBuffer < 0x0100 || decalFixMult < 0x100)
    .error "VCC pattern for vTRC corrupted"
.endif
vTRC_VB   equ vTRC[0] // Vertex Buffer
vTRC_VS   equ vTRC[1] // Vertex Size
vTRC_1000 equ vTRC[2]
vTRC_DM   equ vTRC[3] // Decal Multiplier
vTRC_0020 equ vTRC[4]
vTRC_FFF8 equ vTRC[5]
vTRC_DO   equ vTRC[6] // Decal Offset
vTRC_0100 equ vTRC[7]
vTRC_0100_addr equ (vTRCValue + 2 * 7)

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
    
lastMatDLPhyAddr:
    .dw 0
    
packedNormalsMaskConstant:
    .db 0xF8 // When read, materialCullMode has been zeroed, so read as 0xF800
materialCullMode:
    .db 0
    
// moveword table
movewordTable:
    .dh fxParams           // G_MW_FX
    .dh numLightsxSize - 3 // G_MW_NUMLIGHT; writes numLightsxSize and pointLightFlag, zeroes dirLightsXfrmValid
packedNormalsConstants:
.if (. & 4) != 0
    .error "Alignment broken for packed normals constants in movewordTable"
.endif
    .dh 0x2008             // For packed normals; unused in movewordTable
.if (segmentTable & 0xFF00) != 0
    .error "Packed normals constants relies on first byte of segmentTable addr being 0"
.endif
    .dh segmentTable       // G_MW_SEGMENT
    .dh fogFactor          // G_MW_FOG
    .dh lightBufferMain    // G_MW_LIGHTCOL

// Movemem table
movememTable:
    .dh mMatrix         // G_MV_MMTX
    .dh tempMatrix      // G_MV_TEMPMTX0 multiply temp matrix (model)
    .dh vpMatrix        // G_MV_VPMTX
    .dh tempMatrix      // G_MV_TEMPMTX1 multiply temp matrix (view*projection)
    .dh viewport        // G_MV_VIEWPORT
    .dh cameraWorldPos  // G_MV_LIGHT

afterMovememRaTable:
    .dh run_next_DL_command
    .dh G_MTX_multiply_end

clipCondShifts:
    .db CLIP_SCAL_NY_SHIFT // Constants for clipping algorithm
    .db CLIP_SCAL_PY_SHIFT
    .db CLIP_SCAL_NX_SHIFT
    .db CLIP_SCAL_PX_SHIFT
    
mvpValid:
    .db 0   // Nonzero if the MVP matrix is valid, 0 if it needs to be recomputed.
dirLightsXfrmValid:
    .db 0   // Nonzero if transformed directional lights are valid.
unused2:
    .db 0
pointLightFlag:
    .db 0   // Sign bit set if there are point lights.
numLightsxSize:
    .db 0   // lightSize * number of lights

.macro miniTableEntry, addr
    .if addr < 0x1000 || addr >= 0x1400
        .error "Handler address out of range!"
    .endif
    .db (addr - 0x1000) >> 2
.endmacro

// RDP/Immediate Command Mini Table
// 1 byte per entry, after << 2 points to an addr in first 1/4 of IMEM
miniTableEntry G_FLUSH_handler
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
miniTableEntry G_TRISNAKE_handler
miniTableEntry G_SPNOOP_handler // no command mapped to 0x09
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
INPUT_BUFFER_CLOBBER_OSTASK_AMT equ 0x10 // Input buffer overwrites beginning of OSTask, see rsp_defs.inc
OSTASK_ORIG_SIZE equ 0x40
OSTASK_CLOBBERED_SIZE equ (OSTASK_ORIG_SIZE - INPUT_BUFFER_CLOBBER_OSTASK_AMT)

END_VARIABLE_LEN_DMEM equ (0x1000 - OSTASK_CLOBBERED_SIZE - INPUT_BUFFER_SIZE_BYTES - (2 * RDP_CMD_BUFSIZE_TOTAL) - (2 * CLIP_POLY_SIZE_BYTES) - CLIP_TEMP_VERTS_SIZE_BYTES - VERTEX_BUFFER_SIZE_BYTES)

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
.if (. & 15) != 0
    .error "tempMatrix not aligned"
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
    .skip INPUT_BUFFER_SIZE_BYTES - INPUT_BUFFER_CLOBBER_OSTASK_AMT
// 0x0FC0-0x1000: OSTask
OSTask:
    .skip INPUT_BUFFER_CLOBBER_OSTASK_AMT
inputBufferEnd:
inputBufferEndSgn equ -(0x1000 - inputBufferEnd) // Underflow DMEM address
// rest of OSTask
    .skip OSTASK_CLOBBERED_SIZE

.if . != 0x1000
    .error "DMEM organization incorrect"
.endif

.close // DATA_FILE

// See rsp_defs.inc about why these are not used and we can reuse them.
startCounterTime equ (OSTask + OSTask_ucode_size)
xfrmLookatDirs equ -(0x1000 - (OSTask + OSTask_ucode_data)) // and OSTask_ucode_data_size

memsetBufferStart equ ((vertexBuffer + 0xF) & 0xFF0)
memsetBufferMaxEnd equ (rdpCmdBuffer1 & 0xFF0)
memsetBufferMaxSize equ (memsetBufferMaxEnd - memsetBufferStart)
memsetBufferSize equ (memsetBufferMaxSize > 0x800 ? 0x800 : memsetBufferMaxSize)

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Naming ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/*
Scalar regs:
      Tri write   Clip VW       Vtx write   ltbasic    ltadv    V/L init  Cmd dispatch
$zero ---------------------- Hardwired zero ------------------------------------------
$1    v1 texptr   <------------- vtxLeft ------------------------------>  temp, init 0
$2    v2 shdptr   clipVNext -------> <----- lbPostAo   laPtr                  temp
$3    v3 shdflg   clipVLastOfsc  vLoopRet ---------> laVtxLeft                temp
$4    flat shading vtx or (perf) initial FIFO stall time -----------------------------
$5    <------------------------ vGeomMid ------------------------------>  
$6    geom mode   clipMaskIdx -----> <-- lbTexgenOrRet laSTKept
$7    v2flag tile <------------- fogFlag ---------->  laPacked  mtx valid   cmd byte
$8    v3flag      <------------- outVtx2 ---------->  laSpecular outVtx2
$9    xp texenab  clipMask --------> <----- curLight ---------> viLtFlag
$10   -------------------------- temp2 -----------------------------------------------
$11   --------------------------- temp -----------------------------------------------
$12   ----------------------- perfCounterD -------------------------------------------
$13   ------------------------ altBaseReg --------------------------------------------
$14               <-------------- inVtx ------------------------------->
$15               <------------ outVtxBase ---------------------------->
$16   v1flag lmaj clipFlags -------> <----- lbFakeAmb laSpecFres          ovlInitClock
$17               clipPolyRead ---->
$18   <---------- clipPolySelect -->
$19      temp     clipVOnsc      outVtx1 ---------->    laL2A   <---------   dmaLen
$20      temp     <------------- flagsV1 ---------->   laTexgen <---------  dmemAddr
$21   <---------- clipPolyWrite ---> <----- ambLight             ambLight
$22   ---------------------- rdpCmdBufEndP1 ------------------------------------------
$23   ----------------------- rdpCmdBufPtr -------------------------------------------
$24      temp     <------------- flagsV2 ---------->   fp temp  <--------- cmd_w1_dram
$25     cmd_w0 --------------------> <----- lbAfter             <---------   cmd_w0
$26   ------------------------ taskDataPtr -------------------------------------------
$27   ---------------------- inputBufferPos ------------------------------------------
$28   ----------------------- perfCounterA -------------------------------------------
$29   ----------------------- perfCounterB -------------------------------------------
$30   ----------------------- perfCounterC -------------------------------------------
$ra   return address, sometimes sign bit is flag -------------------------------------
*/

// Global scalar regs:
perfCounterD   equ $12   // Performance counter D (functions depend on config)
altBaseReg     equ $13   // Alternate base address register for vector loads
rdpCmdBufEndP1 equ $22   // Pointer to one command word past "end" (middle) of RDP command buf
rdpCmdBufPtr   equ $23   // RDP command buffer current DMEM pointer
taskDataPtr    equ $26   // Task data (display list) DRAM pointer
inputBufferPos equ $27   // DMEM position within display list input buffer, relative to end
perfCounterA   equ $28   // Performance counter A (functions depend on config)
perfCounterB   equ $29   // Performance counter B (functions depend on config)
perfCounterC   equ $30   // Performance counter C (functions depend on config)

// Vertex write:
vtxLeft        equ $1    // Number of vertices left to process * 0x10
vLoopRet       equ $3    // Return address at end of vtx loop = top of loop or misc lighting
vGeomMid       equ $5    // Middle two bytes of geometry mode
fogFlag        equ $7    // 8 if fog enabled, else 0
outVtx2        equ $8    // Pointer to second or dummy (= outVtx1) transformed vert
inVtx          equ $14   // Pointer to loaded vertex to transform; < 0 means from clipping.
outVtxBase     equ $15   // Pointer to vertex buffer to store transformed verts
outVtx1        equ $19   // Pointer to first transformed vert
flagsV1        equ $20   // Clip flags for vertex 1
flagsV2        equ $24   // Clip flags for vertex 2

// Lighting basic:
lbPostAo       equ $2    // Address to return to after AO
lbTexgenOrRet  equ $6    // ltbasic_texgen as negative if texgen, else vtx_return_from_lighting
curLight       equ $9    // Current light pointer with offset
lbFakeAmb      equ $16   // Pointer to ambient light or to 8 bytes of zeros if AO enabled
ambLight       equ $21   // Ambient (top) light pointer with offset
lbAfter        equ $25   // Address to return to after main lighting loop (vertex or extras)

// Lighting advanced:
laPtr          equ $2    // Pointer to current vertex pair being lit
laVtxLeft      equ $3    // Count of vertices left * 0x10
laSTKept       equ $6    // Texture coords of vertex 1 kept through processing
laPacked       equ $7    // Nonzero if packed normals enabled
laSpecular     equ $8    // Sign bit set if specular enabled
laSpecFres     equ $16   // Nonzero if doing ltadv_normal_to_vertex for specular or Fresnel
laL2A          equ $19   // Nonzero if light-to-alpha (cel shading) enabled
laTexgen       equ $20   // Nonzero if texgen enabled

// Clipping
clipVNext      equ $2    // Next vertex (vertex at forward end of current edge)
clipVLastOfsc  equ $3    // Last vertex / offscreen vertex
clipVOnsc      equ $19   // Onscreen vertex
clipMaskIdx    equ $6    // Clip mask index 4-0
clipMask       equ $9    // Current clip mask (one bit)
clipFlags      equ $16   // Current clipping flags being checked
clipPolyRead   equ $17   // Read pointer within current polygon being clipped
clipPolySelect equ $18   // Clip poly double buffer selection
clipPolyWrite  equ $21   // Write pointer within current polygon being clipped

// Vertex init
viLtFlag       equ $9    // Holds pointLightFlag or dirLightsXfrmValid

// Misc
nextRA         equ $10   // Address to return to after overlay load
ovlInitClock   equ $16   // Temp for profiling
dmaLen         equ $19   // DMA length in bytes minus 1
dmemAddr       equ $20   // DMA address in DMEM or IMEM. Also = rdpCmdBufPtr - rdpCmdBufEndP1 for flush_rdp_buffer
cmd_w1_dram    equ $24   // DL command word 1, which is also DMA DRAM addr
cmd_w0         equ $25   // DL command word 0, also holds next tris info

// Global vector regs:
vZero equ $v0  // All elements = 0; NOT global, only in tri write and clip. Mtx in vtx.
vTRC  equ $v1  // Triangle Constants; NOT global, only in tri write and clip. Mtx in vtx.
vOne  equ $v28 // All elements = 1; global
// $v29: permanent temp register, also write results here to discard
// $v30: vtx / lt = sSTO + persp norm + more lighting params
// $v31: Global constant vector register

// Vertex / lighting vector regs:
// Prefixes: v = vector register, vp = vertex pair, s = vertex store,
// l = basic lighting, a = advanced lighting
// Sadly, "vp" stands for vertex pair, view*projection matrix, and viewport

vMTX0I   equ $v0  // Matrix rows int/frac; MVP normally, or M in ltadv
vMTX1I   equ $v1
vMTX2I   equ $v2
vMTX3I   equ $v3
vMTX0F   equ $v4
vMTX1F   equ $v5
vMTX2F   equ $v6
vMTX3F   equ $v7
vTemp1   equ $v8  // Temporaries, used by lighting (along with some vp regs)
vTemp2   equ $v9
vKept1   equ $v10 // Kept across lighting
vKept2   equ $v11
vpMdl    equ $v12 // Vertex pair model space position
vpClpF   equ $v13 // Vertex pair clip space position frac
vpClpI   equ $v14 // Vertex pair clip space position int
vpScrF   equ $v15 // Vertex pair screen space position frac
vpScrI   equ $v16 // Vertex pair screen space position int
vpST     equ $v17 // Vertex pair ST texture coordinates
vpRGBA   equ $v18 // Vertex pair color
vpLtTot  equ $v19 // Vertex pair total light
vpNrmlX  equ $v20 // Vertex pair normal X (elems 3, 7)
vpNrmlY  equ $v21 // Vertex pair normal Y (elems 3, 7)
vpNrmlZ  equ $v22 // Vertex pair normal Z (elems 3, 7)
vLTC     equ $v23 // Lighting constants - first light dir, constants for packed normals
vPerm1   equ $v24 // Regs loaded in vtx_constants_for_clip and permanently kept through vtx/lt
vPerm2   equ $v25
vPerm3   equ $v26
vPerm4   equ $v27

// Lighting temporaries. Lighting also modifies vpNrmlX:Y:Z, vpLtTot, vpRGBA, and
// in texgen vpST. Only the two regs in the comments below and vKept1 are kept.
.if CFG_NO_OCCLUSION_PLANE
// vpClpI:F are kept, vpMdl is free to use as temp
lDOT equ vpMdl  // lighting DOT product
lCOL equ vKept2 // lighting total light COLor
.else
// vpMdl is kept, these are free to use as temps
lDOT equ vpClpF
lCOL equ vpClpI
.endif
lDTC equ vTemp1  // lighting DoT Clamped
lVCI equ vTemp2  // lighting Vertex Color In
lDIR equ vpRGBA  // lighting transformed light DIRection

// Kept
.if CFG_NO_OCCLUSION_PLANE
sCLZ equ vKept1 // vtx_store Clamped Z. Does have to be kept even though in instan_lt_vs_45 b/c need rest of lt temps at start of texgen (and advanced lighting).
sOCS equ $v29   // Does not exist
.else
sOCS equ vKept1 // vtx_store Occlusion State
sCLZ equ vpClpF // Not a kept in this config
.endif

// Common vertex temporaries
sRTF equ vTemp1  // vtx_store Reciprocal Temp Frac
sRTI equ vTemp2  // vtx_store Reciprocal Temp Int
sFOG equ lCOL // lCOL -> sFOG in lt epilogue with NOC, else sFOG -> lCOL in lt prologue

// Misc temps used by both
.if CFG_NO_OCCLUSION_PLANE
s1WI equ vpNrmlX // vtx_store 1/W Int
s1WF equ vpLtTot // vtx_store 1/W Frac
sSCI equ sFOG    // vtx_store Scaled Clipping Int
sSCF equ vpMdl   // vtx_store Scaled Clipping Frac
sTCL equ sCLZ    // vtx_store Temp CoLor
.else
s1WI equ vpMdl
s1WF equ vpNrmlX
sSCI equ vpScrI
sSCF equ vpScrF
sTCL equ vpLtTot
.endif

// Misc temps used by only one
.if CFG_NO_OCCLUSION_PLANE
sST2 equ vpScrI  // vtx_store ST coordinates copy 2
sOTM equ $v29    // Does not exist
.else
sST2 equ $v29    // Does not exist
sOTM equ vpRGBA  // vtx_store Occlusion Temporary
.endif

// Permanently kept through vertex/lighting
.if CFG_NO_OCCLUSION_PLANE
sVPS equ vPerm1 // vtx_store ViewPort Scale
sVPO equ vPerm2 // vtx_store ViewPort Offset
sFGM equ vPerm3 // vtx_store FoG Mask
sO03 equ $v29   // Does not exist
sO47 equ $v29
sOCM equ $v29
sOPM equ $v29
.else
// These are temps, not permanents, on this codepath
sVPS equ vpScrI // Temp, not permament, on this codepath
sVPO equ vpScrF // Temp, not permament, on this codepath
sFGM equ $v29   // Does not exist
sO03 equ vPerm1 // vtx_store Occlusion plane edge coefficients 0-3
sO47 equ vPerm2 // vtx_store Occlusion plane edge coefficients 4-7
sOCM equ vPerm3 // vtx_store Occlusion plane Mid coefficients
sOPM equ vKept2 // vtx_store Occlusion Plus Minus. Loaded in vtx_after_lt_setup not vtx_constants_for_clip b/c clobbered by lighting.
.endif
sSTS equ vPerm4

// ltadv:
aPNScl equ $v8  // ltadv Packed Normals Scales = (1<<0),(1<<5),(1<<11),XX, repeat
aNrmSc equ $v9  // ltadv Normals Scale = [0h:1h] scale to normalize all normals; elems 2,3,6,7 used for point light factors
aDOT   equ $v10 // ltadv Dot product = normals dot direction; also briefly light dir
aLen2I equ $v11 // ltadv Length 2quared Int part
// Uses vpMdl = $v12
vpWrlF equ $v13 // vertex pair World position Frac part
vpWrlI equ $v14 // vertex pair World position Int part
aDPosF equ $v15 // ltadv Delta Position Frac part
aDPosI equ $v16 // ltadv Delta Position Int part
aOAFrs equ $v17 // ltadv Offset Alpha (elem 3,7) and Fresnel (elem 0,4)
// Uses vpRGBA, vpLtTot, vpNrmlX, vpNrmlY, vpNrmlZ = $v18, $v19, $v20, $v21, $v22
aParam equ $v23 // ltadv Parameters = AO, texgen, and Fresnel params

aAOF2  equ aDOT   // Version of aAOF in init, can't be aDPosI/F or vpMdl there
aPLFcI equ aLen2I // ltadv Point Light Factor Int part
aLen2F equ vpMdl  // ltadv Length 2quared Frac part
aPLFcF equ vpMdl  // ltadv Point Light Factor Frac part
aLTC   equ vpMdl  // ltadv Light Color
aClOut equ vpWrlF // ltadv Color Out
aAlOut equ vpWrlI // ltadv Alpha Out
aDIR   equ aDPosF // ltadv Direction = normalize(light or cam - vertex)
aDotSc equ aDPosF // ltadv Dot product Scale factor
aLkDt0 equ aDPosF // ltadv Lookat Dot product 0 for texgen
aLenF  equ aDPosI // ltadv Length Frac part
aAOF   equ aDPosI // ltadv Ambient Occlusion Factor
aProj  equ aDPosI // ltadv Projection
aLkDt1 equ aDPosI // ltadv Lookat Dot product 1 for texgen
// vpST equ aOAFrs // ST used in texgen
vpWNrm equ vpNrmlX // vertex pair World space Normals
aRcpLn equ $v29 // ltadv Reciprocal of Length
aLenI  equ $v29 // ltadv Length Int part



// Temp storage after rdpCmdBufEndP1. There is 0xA8 of space here which will
// always be free during vtx load or clipping.
tempVpRGBA            equ 0x00        // Only used during loop
tempXfrmLt            equ tempVpRGBA  // ltbasic only used during init
tempVtx1ST            equ tempVpRGBA  // ltadv only during init
tempAmbient           equ 0x10        // ltbasic set during init, used during loop
tempPrevInvalVtxStart equ 0x20
tempPrevInvalVtx      equ (tempPrevInvalVtxStart + vtxSize) // 0x46; fog writes here
tempPrevInvalVtxEnd   equ (tempPrevInvalVtx + vtxSize)      // 0x6C; rest of vtx writes here
.if tempPrevInvalVtxEnd > (RDP_CMD_BUFSIZE_EXCESS - 8)
    .error "Too much temp storage used!"
.endif


////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// IMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// RSP IMEM
.create CODE_FILE, 0x00001080

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl1
start: // This is at IMEM 0x1080, not the start of IMEM
    vnop    // Return to here from S2DEX overlay 0 G_LOAD_UCODE jumps to start+4!
    lqv     $v31[0], (v31Value)($zero)      // Actual start is here
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    lqv     vTRC, (vTRCValue)($zero)        // Always as this value except vtx_store
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
    lw      perfCounterA, mvpMatrix + YDF_OFFSET_PERFCOUNTERA
    lw      perfCounterB, mvpMatrix + YDF_OFFSET_PERFCOUNTERB
    lw      perfCounterC, mvpMatrix + YDF_OFFSET_PERFCOUNTERC
    lw      perfCounterD, mvpMatrix + YDF_OFFSET_PERFCOUNTERD
    jal     fill_vertex_table
     lw     taskDataPtr, OSTask + OSTask_data_ptr
finish_setup:
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    sw      $11, startCounterTime
.endif
    sh      $zero, mvpValid  // and dirLightsXfrmValid
    li      inputBufferPos, 0
    li      cmd_w1_dram, orga(ovl1_start)
    j       load_overlays_0_1
     li     nextRA, displaylist_dma

start_end:
.align 8
start_padded_end:

.orga max(orga(), max(ovl0_padded_end - ovl0_start, ovl1_padded_end - ovl1_start) - 0x80)
ovl01_end:

G_CULLDL_handler: // 15
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

G_BRANCH_WZ_handler:
    lhu     $10, (vertexTable)(cmd_w0)  // Vertex addr from byte 3
.if CFG_G_BRANCH_W                      // G_BRANCH_W/G_BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      $10, VTX_W_INT($10)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      $10, VTX_SCR_Z($10)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, $10, cmd_w1_dram        // subtract the w/z value being tested
    bgez    $2, run_next_DL_command     // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val    // load the RDPHALF1 value as the location to branch to
    li      cmd_w0, 0x8000              // Bit 16 set (via negative) = nopush, bits 3-7 = 0 for hint
G_DL_handler:
    sll     $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
    lbu     $1, displayListStackLength      // Get the DL stack length
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
    bltz    $2, call_ret_common             // Nopush = branch = flag is set
     move   taskDataPtr, cmd_w1_dram        // Set the new DL to the target display list
    sw      $3, (displayListStack)($1)
    addi    $1, $1, 4                       // Increment the DL stack length
call_ret_common:
    sb      $zero, materialCullMode         // This covers call, branch, return, and cull and branchZ successes
    sb      $1, displayListStackLength
    andi    inputBufferPos, cmd_w0, 0x00F8             // Byte 3, how many cmds to drop from load (max 0xA0)
displaylist_dma:
    li      nextRA, run_next_DL_command
displaylist_dma_tri_snake:
    // Load INPUT_BUFFER_SIZE_BYTES - inputBufferPos cmds (inputBufferPos >= 0, mult of 8)
    addi    inputBufferPos, inputBufferPos, -INPUT_BUFFER_SIZE_BYTES // inputBufferPos = - num cmds
.if CFG_PROFILING_A
    sll     $11, inputBufferPos, 16 - 3                // Divide by 8 for num cmds to load, then move to upper 16
    sub     perfCounterB, perfCounterB, $11            // Negative so subtract
.endif
    nor     dmaLen, inputBufferPos, $zero              // DMA length = -inputBufferPos - 1 = ones compliment
    move    cmd_w1_dram, taskDataPtr                   // set up the DRAM address to read from
    sub     taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
    addi    dmemAddr, inputBufferPos, inputBufferEnd   // set the address to DMA read to
dma_and_wait_goto_next_ra:
    j       dma_read_write
     li     $ra, wait_goto_next_ra

G_POPMTX_handler:
G_DMA_IO_handler:
G_MEMSET_handler:
    j       ovl234_clipmisc_entrypoint       // Delay slot is harmless
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
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    bgezal  dmemAddr, flush_rdp_buffer
     // $1 on next instr survives flush_rdp_buffer
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
    // $7 must retain the command byte for load_mtx and overlay 3 stuff
    // $11 must contain the handler called for several handlers

G_SETxIMG_handler: // 10
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

.if !ENABLE_PROFILING
G_LIGHTTORDP_handler: // 9
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

G_LOAD_UCODE_handler: // 4
    j       load_overlay_0_and_enter         // Delay slot is harmless
G_MODIFYVTX_handler:
     lhu    $10, (vertexTable)(cmd_w0)       // Byte 3 = vtx being modified
    j       do_moveword  // Moveword adds cmd_w0 to $10 for final addr
     lbu    cmd_w0, (inputBufferEnd - 0x07)(inputBufferPos)  // offset in vtx, bit 15 clear

// Index = bits 1-6; direction flag = bit 0; end flag = bit 7
// CM 02 01 03 04 05 06 07
//               [bb^cc]   Indices b and c
//                  |
//                  cmd_w0 + inputBufferEnd
G_TRISNAKE_handler:
    sw      cmd_w0, rdpHalf1Val          // Store indices a, b, c
    addi    inputBufferPos, inputBufferPos, -5 // Point to byte 3, index c of 1st tri
tri_snake_loop:
    lh      $3, (inputBufferEnd - 1)(inputBufferPos) // Load indices b and c
tri_snake_loop_from_input_buffer:
    lb      $2, rdpHalf1Val + 1          // Old v1; == index b, except when bridging between old and new load
    li      $ra, tri_snake_loop          // For tri_main
    bltz    $3, tri_snake_end            // Upper bit of real index b set = done
     andi   $11, $3, 1                   // Get direction flag from index c
    beqz    inputBufferPos, tri_snake_over_input_buffer // == 0 at end of input buffer
     andi   $3, $3, 0x7E                 // Mask out flags from index c
    sb      $3, rdpHalf1Val + 1          // Store index c as vertex 1
    sb      $2, (rdpHalf1Val + 2)($11)   // Store old v1 as 2 if dir clear or 3 if set
    j       tri_main
     addi   inputBufferPos, inputBufferPos, 1  // Increment indices being read

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
     sw     cmd_w1_dram, rdpHalf1Val     // Store second tri indices
G_TRI1_handler:
    li      $ra, tris_end                // After done with this tri, exit tri processing
    sw      cmd_w0, rdpHalf1Val          // Store first tri indices
tri_main:
    lpv     $v27[4], (rdpHalf1Val)($zero) // To vector unit in elems 5-7
    lbu     $1, rdpHalf1Val + 1
    lbu     $2, rdpHalf1Val + 2
    lbu     $3, rdpHalf1Val + 3
    vclr    vZero
    lhu     $1, (vertexTable)($1)
    vmudn   $v29, vOne, vTRC_VB    // Address of vertex buffer
    lhu     $2, (vertexTable)($2)
    vmadl   $v27, $v27, vTRC_VS    // Plus vtx indices times length
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
    lhu     $16, VTX_CLIP($1)
    vmov    $v8[6], $v27[7]         // elem 6 of v8 = vertex 3 addr
    lhu     $7, VTX_CLIP($2)
    // vnop
    lhu     $8, VTX_CLIP($3)
    vmudh   $v2, vOne, $v6[1] // v2 all elems = y-coord of vertex 1
    andi    $11, $16, CLIP_SCRN_NPXY | CLIP_CAMPLANE // All three verts on wrong side of same plane
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    and     $11, $11, $7
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    and     $11, $11, $8
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    bnez    $11, return_and_end_mat // Then the whole tri is offscreen, cull
     // 22 cycles (for tri2 first tri; tri1/only subtract 1 from counts)
     vmrg   tHPos, $v6, $v4   // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    vmudh   $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    lhu     $24, activeClipPlanes
    vmadh   $v26, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    lw      $6, geometryModeLabel // Load full geometry mode word
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    or      $10, $16, $7
    vmrg    tLPos, $v6, $v4   // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    or      $10, $10, $8      // $10 = all clip bits which are true for any verts
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    and     $10, $10, $24     // If clipping is enabled, check clip flags
    vmrg    $v4, tHPos, $v8   // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    mfc2    $9, $v26[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    tHPos, $v8, tHPos // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    bnez    $10, ovl234_clipmisc_entrypoint // Facing info and occlusion may be garbage if need to clip
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
    and     $16, $16, $7
    and     $16, $16, $8
    andi    $16, $16, CLIP_OCCLUDED
.endif
tXPF equ $v16 // Triangle cross product
tXPI equ $v17
tXPRcpF equ $v23 // Reciprocal of cross product (becomes that * 4)
tXPRcpI equ $v24
t1WI equ $v13 // elems 0, 4, 6
t1WF equ $v14
    vmudh   $v29, tPosMmH, tPosLmH[0]
.if !CFG_NO_OCCLUSION_PLANE
    bnez    $16, tri_culled_by_occlusion_plane // Cull if all verts occluded
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
    lw      $16, VTX_INV_W_VEC($1) // $16, $7, $8 = 1/W for H, M, L
    vrcp    $v20[3], tPosLmH[1]
    lw      $7, VTX_INV_W_VEC($2)
    vrcph   $v22[3], tPosLmH[1]
    lw      $8, VTX_INV_W_VEC($3)
    vmudl   tHAtI, tHAtI, vTRC_0100 // vertex color 1 >>= 8
    lbu     $9, textureSettings1 + 3
    vmudl   tMAtI, tMAtI, vTRC_0100 // vertex color 2 >>= 8
    sub     $11, $16, $7  // Four instr: $16 = max($16, $7)
    vmudl   tLAtI, tLAtI, vTRC_0100 // vertex color 3 >>= 8
    sra     $10, $11, 31
    vmudl   $v29, $v20, vTRC_0020
    // no nop if tri_skip_flip_facing was unaligned
    vmadm   $v22, $v22, vTRC_0020
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
    vmudm   tPosCatF, tPosCatI, vTRC_1000
    // no nop if tri_skip_alpha_compare_cull was unaligned
    vmadn   tPosCatI, $v31, $v31[2] // 0
    and     $11, $11, $10
    vsubc   tSubPxHF, vZero, tSubPxHF
    sub     $16, $16, $11
    vsub    tSubPxHI, vZero, vZero
    sub     $11, $16, $8  // Four instr: $16 = max($16, $8)
    vmudm   $v29, tPosCatF, $v20
    sra     $10, $11, 31
    vmadl   $v29, tPosCatI, $v20
    and     $11, $11, $10
    vmadn   $v20, tPosCatI, $v22
    sub     $16, $16, $11
    vmadh   tPosCatI, tPosCatF, $v22
    sw      $16, 0x0010(rdpCmdBufPtr) // Store max of three verts' 1/W to temp mem
    vmudl   $v29, tXPRcpF, tXPF
tMx1W equ $v27
    llv     tMx1W[0], 0x0010(rdpCmdBufPtr) // Load max of three verts' 1/W
    vmadm   $v29, tXPRcpI, tXPF
    mfc2    $16, tXPI[1]
    vmadn   tXPF, tXPRcpF, tXPI
    lbu     $7, textureSettings1 + 2
    vmadh   tXPI, tXPRcpI, tXPI
    lsv     tMAtI[14], VTX_SCR_Z($2)
    vand    $v22, $v20, vTRC_FFF8
    lsv     tLAtI[14], VTX_SCR_Z($3)
    vcr     tPosCatI, tPosCatI, vTRC_0100
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
    lw      $19, otherMode1
tMnWI equ $v27
tMnWF equ $v10
    vrcph   $v29[0], tMx1W[0] // Reciprocal of max 1/W = min W
    andi    $10, $16, 0x0080 // Extract the left major flag from $16
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
    andi    $19, $19, ZMODE_DEC    // Mask to two Z mode bits
    set_vcc_11110001                // select RGBA___Z or ____STW_
    llv     tSTWLI[8], VTX_TC_VEC($3)
    vmudm   $v29, tSTWHMI, t1WF[0h] // (S, T, 7FFF) * (1 or <1) for H and M
    addi    $19, $19, -ZMODE_DEC  // Check if equal to decal mode
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
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Check if we need to write out to RDP
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
    beqz    $19, tri_decal_fix_z
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
    bltz    dmemAddr, return_and_end_mat     // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
     slv    $v10[12], 0x00($10)   // ZI:F
     // 156 cycles
flush_rdp_buffer: // Prereq: dmemAddr = rdpCmdBufPtr - rdpCmdBufEndP1, or dmemAddr = large neg num -> only wait and set DPC_END
    mfc0    $11, SP_DMA_BUSY                 // Check if any DMA is in flight
    lw      cmd_w1_dram, rdpFifoPos          // FIFO pointer = end of RDP read, start of RSP write
    lw      $10, OSTask + OSTask_output_buff_size // Load FIFO "size" (actually end addr)
.if CFG_PROFILING_C
    // This is a wait for DMA busy loop, but written inline to avoid overwriting ra.
    addi    perfCounterD, perfCounterD, 7    // 6 instr + 1 taken branch
.endif
    bnez    $11, flush_rdp_buffer            // Wait until no DMAs are active
     addi   dmaLen, dmemAddr, RDP_CMD_BUFSIZE + 8  // dmaLen = size of DMEM buffer to copy
    blez    dmaLen, old_return_routine       // Exit if nothing to copy, or if dmemAddr is large negative num from last flush DMA write
     mtc0   cmd_w1_dram, DPC_END             // Set RDP to execute until FIFO end (buf pushed last time)
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
    vmudh   $v29, vOne, vTRC_DO  // accum all elems = -DM/2
    vmadm   $v25, tHAtI, vTRC_DM // elem 7 = (0 to DM/2-1) - DM/2 = -DM/2 to -1
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

align_with_warning 8, "One instruction of padding before ovl234"

vtx_select_lighting:
.if CFG_PROFILING_B
    srl     $11, vtxLeft, 4                  // Vertex count
    add     perfCounterA, perfCounterA, $11  // Add to number of lit vertices
.endif
    bltz    viLtFlag, ovl234_ltadv_entrypoint  // Advanced lighting if have point lights
     andi   $10, vGeomMid, (G_LIGHTING_SPECULAR | G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    bnez    $10, ovl234_ltadv_entrypoint  // Advanced lighting if specular or Fresnel
     lb     viLtFlag, dirLightsXfrmValid
    // Fallthrough to ltbasic on whichever overlay is loaded

.if (. & 4)
    .error "vtx_select_lighting must be an even number of instructions"
.endif
ovl234_start:

ovl3_start:
// Clipping overlay.

// Jump here for basic lighting setup. If overlay 3 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_ltbasic_entrypoint_ovl3ver:         // same IMEM address as ovl234_ltbasic_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2

// Jump here for advanced lighting. If overlay 3 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ltadv_entrypoint_ovl3ver:           // same IMEM address as ovl234_ltadv_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here for clipping and rare commands. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl234_clipmisc_entrypoint:
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    bnez    $1, vtx_constants_for_clip     // In clipping, $1 is vtx 1 addr, never 0. Cmd dispatch, $1 = 0.
     li     inVtx, 0x8000                  // inVtx < 0 means from clipping. Inc'd each vtx write by 2 * inputVtxSize, but this is large enough it should stay negative.
    lw      cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Overwritten by overlay load
    li      $3, (0xFF00 | G_MTX)
    beq     $3, $7, g_mtx_push_ovl3
     li     $11, (0xFF00 | G_MEMSET)
    beq     $11, $7, g_memset_ovl3
     li     $3, (0xFF00 | G_DMA_IO)
    beq     $3, $7, g_dma_io_ovl3
g_popmtx_ovl3:  // otherwise
     lw     $11, matrixStackPtr             // Current matrix stack pointer
    lw      $2, OSTask + OSTask_dram_stack  // Top of the stack
    sub     cmd_w1_dram, $11, cmd_w1_dram   // Decrease pointer by amount in command
    sub     $3, cmd_w1_dram, $2             // Is it still valid / within the stack?
    bgez    $3, @@skip                      // If so, skip the failsafe
     sh     $zero, mvpValid                 // and dirLightsXfrmValid; mark both mtx and dir lts invalid
    move    cmd_w1_dram, $2                 // Use the top of the stack as the new pointer
@@skip:    
    j       do_movemem                      // Must keep $1 = 0
     sw     cmd_w1_dram, matrixStackPtr     // Update the matrix stack pointer

g_mtx_push_ovl3:
    lw      cmd_w1_dram, matrixStackPtr     // Set up the DMA from dmem to rdram at the matrix stack pointer
    li      dmemAddr, (mMatrix | 0x8000)    // mMatrix, negative = write
    jal     dma_read_write                  // DMA the current matrix from dmem to rdram
     li     dmaLen, 0x0040 - 1              // Set the DMA length to the size of a matrix (minus 1 because DMA is inclusive)
    addi    cmd_w1_dram, cmd_w1_dram, 0x40  // Increase the matrix stack pointer by the size of one matrix
    sw      cmd_w1_dram, matrixStackPtr     // Update the matrix stack pointer
    j       load_mtx
     lw     cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Load command word 1 again

g_dma_io_ovl3:
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    li      nextRA, run_next_DL_command
    j       dma_and_wait_goto_next_ra  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
     // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
     sra    dmemAddr, dmemAddr, 2

clip_after_constants:
.if CFG_PROFILING_B
    addi    perfCounterB, perfCounterB, 1  // Increment clipped (input) tris count
.endif
    // Clear all temp vertex slots used.
    li      $11, (MAX_CLIP_GEN_VERTS - 1) * vtxSize
clip_init_used_loop:
    sh      $zero, (VTX_CLIP + clipTempVerts)($11)
    bgtz    $11, clip_init_used_loop
     addi   $11, $11, -vtxSize
    li      clipMaskIdx, 4                     // 4=screen, 3=+x, 2=-x, 1=+y, 0=-y
    li      clipMask, CLIP_CAMPLANE            // Initial clip mask for screen clipping
    li      clipPolySelect, 6  // Everything being indexed from 6 saves one instruction at the end of the loop
    sh      $1, (clipPoly - 6 + 0)(clipPolySelect) // Write the current three verts
    sh      $2, (clipPoly - 6 + 2)(clipPolySelect) // as the initial polygon
    sh      $3, (clipPoly - 6 + 4)(clipPolySelect) // Initial state $3 = clipVLastOfsc
    sh      $zero, (clipPoly)(clipPolySelect)  // nullptr to mark end of polygon
    sb      $zero, materialCullMode            // In case only/all tri(s) clip then offscreen
// Available locals here: $11, $1, $7, $20, $24, $10
clip_condlooptop:
    lhu     clipFlags, VTX_CLIP(clipVLastOfsc) // Load flags for final vertex of the last polygon
    addi    clipPolyRead,   clipPolySelect, -6 // Start reading at the beginning of the old polygon
    xori    clipPolySelect, clipPolySelect, 6 ^ ((clipPoly2 - clipPoly) + 6) // Swap to the other polygon memory
    addi    clipPolyWrite,  clipPolySelect, -6 // Start writing at the beginning of the new polygon
    and     clipFlags, clipFlags, clipMask     // Mask last flags to current clip condition
clip_edgelooptop: // Loop over edges connecting verts, possibly subdivide the edge
    lhu     clipVNext, (clipPoly)(clipPolyRead) // Read next vertex (farther end of edge)
    addi    clipPolyRead, clipPolyRead, 0x0002 // Increment read pointer
    beqz    clipVNext, clip_nextcond           // If next vtx is nullptr, done with input polygon
     lhu    $11, VTX_CLIP(clipVNext)           // Load flags for next vtx
    and     $11, $11, clipMask                 // Mask next flags to current clip condition
    beq     $11, clipFlags, clip_nextedge      // Both set or both clear = both off screen or both on screen, no subdivision
     move   clipFlags, $11                     // clipFlags = masked next vtx's flags
    // Going to subdivide this edge. Find available temp vertex slot.
    li      outVtxBase, clipTempVertsEnd
clip_find_unused_loop:
    lhu     $11, (VTX_CLIP - vtxSize)(outVtxBase)
    addi    $10, outVtxBase, -clipTempVerts    // This is within the loop rather than before b/c delay after lhu
    blez    $10, clip_done                     // If can't find one (should never happen), give up
     andi   $11, $11, CLIP_VTX_USED
    bnez    $11, clip_find_unused_loop
     addi   outVtxBase, outVtxBase, -vtxSize
    beqz    clipFlags, clip_skipswap23         // Next vtx flag is clear / on screen,
     move   clipVOnsc, clipVNext               // therefore last vtx is set / off screen
    move    clipVOnsc, clipVLastOfsc           // Otherwise swap; note we are overwriting
    move    clipVLastOfsc, clipVNext           // clipVLastOfsc but not clipVNext
clip_skipswap23:
    // Interpolate between clipVLastOfsc and clipVOns; create a new vertex which is on the
    // clipping boundary (e.g. at the screen edge)
cPosOnOfF equ vpClpF
cPosOnOfI equ vpClpI
cPosOfF   equ vpScrF
cPosOfI   equ vpScrI
cRGBAOf   equ vpLtTot
cRGBAOn   equ vpRGBA
cSTOf     equ vpST
cSTOn     equ sSTS // Intentionally overwriting this kept reg. Vtx scales ST again, need to re-store unscaled value.
// Also uses sRTF, sRTI = vTemp1, vTemp2, and vtx_final_setup_for_clip sets sOPM = vKept2
cTemp     equ vpMdl
cBaseF    equ vpNrmlX
cBaseI    equ vpNrmlY
cDiffF    equ $v2
cDiffI    equ $v3
cRRF      equ $v4  // Range Reduction frac
cRRI      equ $v5  // Range Reduction int
cFadeOf   equ $v6
cFadeOn   equ $v7
    /*
    Five clip conditions (these are in a different order from vanilla):
           cBaseI/cBaseF[3]       cDiffI/cDiffF[3]
    4 W=0:           W1              W1  -         W2
    3 +X :    X1 - 2*W1      (X1 - 2*W1) - (X2 - 2*W2) <- the 2 is clip ratio
    2 -X :    X1 + 2*W1      (X1 + 2*W1) - (X2 + 2*W2)
    1 +Y :    Y1 - 2*W1      (Y1 - 2*W1) - (Y2 - 2*W2)
    0 -Y :    Y1 + 2*W1      (Y1 + 2*W1) - (Y2 + 2*W2)
    */
    xori    $11, clipMaskIdx, 1          // Invert sign of condition
    ldv     cPosOnOfF[0], VTX_FRAC_VEC(clipVOnsc)
    ctc2    $11, $vcc                    // Conditions 1 (+y) or 3 (+x) -> vcc[0] = 0
    ldv     cPosOnOfI[0], VTX_INT_VEC (clipVOnsc)
    vmrg    cTemp, vOne, $v31[1]         // elem 0 is 1 if W or neg cond, -1 if pos cond
    andi    $11, clipMaskIdx, 4          // W condition and screen clipping
    ldv     cPosOnOfF[8], VTX_FRAC_VEC(clipVLastOfsc) // Off screen to elems 4-7
    bnez    $11, clip_w                  // If so, use 1 or -1
     ldv    cPosOnOfI[8], VTX_INT_VEC (clipVLastOfsc)
    vmudh   cTemp, cTemp, $v31[3]        // elem 0 is (1 or -1) * 2 (clip ratio)
    andi    $11, clipMaskIdx, 2          // Conditions 2 (-x) or 3 (+x)
    vmudm   cBaseF, vOne, cPosOnOfF[0h]  // Set accumulator (care about 3, 7) to X
    bnez    $11, clip_skipy
     vmadh  cBaseI, vOne, cPosOnOfI[0h]
    vmudm   cBaseF, vOne, cPosOnOfF[1h]  // Discard that and set accumulator 3, 7 to Y
    vmadh   cBaseI, vOne, cPosOnOfI[1h]
clip_skipy:
    vmadn   cBaseF, cPosOnOfF, cTemp[0]  // + W * +/- 2
    vmadh   cBaseI, cPosOnOfI, cTemp[0]
clip_skipxy:
    vsubc   cDiffF, cBaseF, cBaseF[7]    // Vtx on screen - vtx off screen
    vsub    cDiffI, cBaseI, cBaseI[7]
    // This is computing cDiffI:F = cBaseI:F / cDiffI:F to high precision.
    // The first step is a range reduction, where cRRF becomes a scale factor
    // (roughly min(1.0f, abs(1.0f / cDiffI:F))) which scales down cDiffI:F (denominator)
    // Then the reciprocal of cDiffI:F is computed with a Newton-Raphson iteration
    // and multiplied by cBaseI:F. Finally scale down the result (numerator) by cRRF.
    vor     cTemp, cDiffI, vOne[0]  // Round up int sum to odd; this ensures the value is not 0, otherwise vabs result will be 0 instead of +/- 2
    sub     $11, clipPolyWrite, clipPolySelect // Make sure we are not overflowing
    vrcph   cRRI[3], cDiffI[3]
    addi    $11, $11, 6 - ((MAX_CLIP_POLY_VERTS) * 2) // Write ptr to last zero slot
    vrcpl   cRRF[3], cDiffF[3]              // 1 / (x+y+z+w), vtx on screen - vtx off screen
    bgez    $11, clip_done                  // If so, give up
     vrcph  cRRI[3], $v31[2]                // 0; get int result of reciprocal
    vabs    cTemp, cTemp, $v31[3]           // 2; cTemp = +/- 2 based on sum positive (incl. zero) or negative
    lhu     $11, VTX_CLIP(clipVLastOfsc)    // Load clip flags for off screen vert
    vmudn   cRRF, cRRF, cTemp[3]            // multiply reciprocal by +/- 2
    sh      outVtxBase, (clipPoly)(clipPolyWrite) // Write pointer to generated vertex to polygon
    vmadh   cRRI, cRRI, cTemp[3]
    addi    clipPolyWrite, clipPolyWrite, 2 // Increment write ptr
    veq     cRRI, cRRI, $v31[2]             // 0; if RR int part is 0
    andi    $11, $11, ~CLIP_VTX_USED        // Clear used flag from off screen vert
    vmrg    cRRF, cRRF, $v31[1]             // keep RR frac, otherwise set frac to 0xFFFF (max)
    sh      $11, VTX_CLIP(clipVLastOfsc)    // Store modified clip flags for off screen vert
    vmudl   $v29, cDiffF, cRRF[3]           // Multiply clDiffI:F by RR frac*frac
    ldv     cPosOfF[0], VTX_FRAC_VEC (clipVLastOfsc) // Off screen loaded above, but need
    vmadm   cDiffI, cDiffI, cRRF[3]         // int*frac, int out
    ldv     cPosOfI[0], VTX_INT_VEC  (clipVLastOfsc) // it in elems 0-3 for interp
    vmadn   cDiffF, $v31, $v31[2]           // 0; get frac out
    luv     cRGBAOf[0], VTX_COLOR_VEC(clipVLastOfsc)
    vrcph   sRTI[3], cDiffI[3]              // Reciprocal of new scaled cDiff (discard)
    luv     cRGBAOn[0], VTX_COLOR_VEC(clipVOnsc)
    vrcpl   sRTF[3], cDiffF[3]              // frac part
    llv     cSTOf[0],   VTX_TC_VEC   (clipVLastOfsc)
    vrcph   sRTI[3], $v31[2]                // 0; int part
    llv     cSTOn[0],   VTX_TC_VEC   (clipVOnsc) // Must be before vtx_final_setup_for_clip
    vmudl   $v29, sRTF, cDiffF              // D*R (see Newton-Raphson explanation)
.if CFG_NO_OCCLUSION_PLANE
    li      vtxLeft, -1                     // vtxLeft < 0 triggers vtx_epilogue
.else
    li      vtxLeft, inputVtxSize           // but trigger this on the second loop in this version
.endif
    vmadm   $v29, sRTI, cDiffF
.if CFG_NO_OCCLUSION_PLANE
    addi    outVtxBase, outVtxBase, -vtxSize // Inc'd by 2, must point to second vtx
.else
    addi    outVtxBase, outVtxBase, vtxSize // Not inc'd, must point to second vtx
.endif
    vmadn   cDiffF, sRTF, cDiffI
    li      vLoopRet, vtx_loop_no_lighting
    vmadh   cDiffI, sRTI, cDiffI
    vmudh   $v29, vOne, $v31[4]             // 4; 4 - 4 * (D*R)
    vmadn   cDiffF, cDiffF, $v31[0]         // -4
    vmadh   cDiffI, cDiffI, $v31[0]         // -4
    vmudl   $v29, sRTF, cDiffF              // 1/cDiff result = R * that
    vmadm   $v29, sRTI, cDiffF
    vmadn   sRTF, sRTF, cDiffI
    vmadh   sRTI, sRTI, cDiffI
    vmudl   $v29, cBaseF, sRTF              // cDiff regs = cBase / cDiff
    vmadm   $v29, cBaseI, sRTF
    vmadn   cDiffF, cBaseF, sRTI
    vmadh   cDiffI, cBaseI, sRTI 
    vmudl   $v29, cDiffF, cRRF[3]           // Scale by range reduction
    vmadm   cDiffI, cDiffI, cRRF[3]
    vmadn   cDiffF, $v31, $v31[2]           // Done cDiffI:F = cBaseI:F / cDiffI:F
    // Clamp to 0x0001 to 0xFFFF range and create inverse on-screen factor
    vlt     cDiffI, cDiffI, vOne[0]         // If integer part of factor less than 1,
    vmrg    cDiffF, cDiffF, $v31[1]         // keep frac part of factor, else set to 0xFFFF (max val)
    vsubc   $v29, cDiffF, vOne[0]           // frac part - 1 for carry
    vge     cDiffI, cDiffI, $v31[2]         // 0; If integer part of factor >= 0 (after carry, so overall value >= 0x0000.0001),
    j       vtx_final_setup_for_clip        // Clobbers vcc and accum in !NOC config.
     vmrg   cFadeOf, cDiffF, vOne[0]        // keep frac part of factor, else set to 1 (min val)
clip_after_final_setup: // This is here because otherwise 3 cycle stall here.
    vmudn   cFadeOn, cFadeOf, $v31[1]       // signed x * -1 = 0xFFFF - unsigned x! Fade factor for on screen vert
    // Fade between attributes for on screen and off screen vert
    vmudm   $v29,     cRGBAOf, cFadeOf[3]
    vmadm   vpRGBA,   cRGBAOn, cFadeOn[3]
    vmudm   $v29,       cSTOf, cFadeOf[3]
    vmadm   sSTS,       cSTOn, cFadeOn[3]
    vmudl   $v29,     cPosOfF, cFadeOf[3]
    vmadm   $v29,     cPosOfI, cFadeOf[3]
    vmadl   $v29,   cPosOnOfF, cFadeOn[3]
    vmadm   vpClpI, cPosOnOfI, cFadeOn[3]
    j       vtx_store_for_clip
     vmadn  vpClpF, $v31, $v31[2]           // 0; load resulting frac pos
clip_after_vtx_store:
    ori     flagsV1, flagsV1, CLIP_VTX_USED   // Mark generated vtx as used
    slv     sSTS[0], (VTX_TC_VEC   )(outVtx1) // Store not-twice-scaled ST
    sh      flagsV1, (VTX_CLIP     )(outVtx1) // Store generated vertex flags
clip_nextedge:
    bnez    clipFlags, clip_edgelooptop   // Discard V2 if it was off screen (whether inserted vtx or not)
     move   clipVLastOfsc, clipVNext      // Move what was the end of the edge to be the new start of the edge
    sub     $11, clipPolyWrite, clipPolySelect // Make sure we are not overflowing
    addi    $11, $11, 6 - ((MAX_CLIP_POLY_VERTS) * 2) // Write ptr to last zero slot
    bgez    $11, clip_done                // If so, give up
     sh     clipVLastOfsc, (clipPoly)(clipPolyWrite) // Former V2 was on screen,
    j       clip_edgelooptop              // so add it to the output polygon
     addi   clipPolyWrite, clipPolyWrite, 2

clip_w:
    vcopy   cBaseF, cPosOnOfF             // Result is just W
    j       clip_skipxy
     vcopy  cBaseI, cPosOnOfI

clip_nextcond:
    sub     $11, clipPolyWrite, clipPolySelect // Are there less than 3 verts in the output polygon?
    bltz    $11, clip_done                    // If so, degenerate result, quit
     sh     $zero, (clipPoly)(clipPolyWrite)  // Terminate the output polygon with a 0
    lhu     clipVLastOfsc, (clipPoly - 2)(clipPolyWrite) // Initialize edge start to the last vert
    beqz    clipMaskIdx, clip_draw_tris
     lbu    $11, (clipCondShifts - 1)(clipMaskIdx) // Load next clip condition shift amount
    li      clipMask, 1
    sllv    clipMask, clipMask, $11
    j       clip_condlooptop
     addi   clipMaskIdx, clipMaskIdx, -1
    
clip_draw_tris:
    sh      $zero, activeClipPlanes
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
    vmudn   $v29, vOne, vTRC_VB  // Address of vertex buffer
    vmadl   $v4, $v3, vTRC_VS    // Plus vtx indices times length
    vadd    $v3, $v3, vTRC_1000  // increment by 8 verts = 16
    addi    $2, $2, 0x10
    bne     $2, $3, @@loop2
     sqv    $v4[0], (-0x10)($2)
    jr      $ra
     // Delay slot harmless

g_memset_ovl3:
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
    j       while_wait_dma_busy
     li     $ra, run_next_DL_command
@@clamp_to_memset_buffer:
    addi    $11, cmd_w0, -memsetBufferSize // $2 = min(cmd_w0, memsetBufferSize)
    sra     $10, $11, 31
    and     $11, $11, $10
    jr      $ra
     addi   $2, $11, memsetBufferSize

ovl3_end:
.align 8
ovl3_padded_end:

.orga max(max(ovl2_padded_end - ovl2_start, ovl4_padded_end - ovl4_start) + orga(ovl3_start), orga())
ovl234_end:

vtx_after_dma:
    srl     $2, cmd_w0, 11                     // n << 1
    sub     $2, cmd_w0, $2                     // = v0 << 1
    lhu     outVtxBase, (vertexTable)($2)      // Address of output start
    andi    inVtx, dmemAddr, 0xFFF8            // Round down input start addr to DMA word
.if COUNTER_A_UPPER_VERTEX_COUNT
    sll     $11, vtxLeft, 12                   // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
.endif
vtx_constants_for_clip:
    // Sets up constants needed for vertex loop, including during clipping.
    // Results fill vPerm1:4. Uses misc temps.
    lhu     vGeomMid, geometryModeLabel + 1       // Load middle 2 bytes of geom mode
.if CFG_NO_OCCLUSION_PLANE
    llv     sFOG[0], (fogFactor - altBase)(altBaseReg) // Load fog multiplier 0 and offset 1
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
    veq     $v29, $v31, $v31[3h]                  // VCC = 00010001
    ldv     sVPO[8], (viewport + 8)($zero)
    llv     sSTS[0], (textureSettings2 - altBase)(altBaseReg) // Texture ST scale in 0, 1
    vmrg    sFGM, vOne, $v31[2]                   // sFGM is 0,0,0,1,0,0,0,1
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    vne     $v29, $v31, $v31[3h]                  // VCC = 11101110
    ldv     sVPS[8], (viewport)($zero)
    lb      $11, geometryModeLabel + 3            // G_ATTROFFSET_ST_ENABLE in sign bit
    vmrg    sVPO, sVPO, sFOG[1]                   // Put fog offset in elements 3,7 of vtrans
    llv     $v30[0], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 0, 1
    vmov    sSTS[4], sSTS[0]
    llv     $v30[8], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 4, 5
    vmrg    sVPS, sVPS, sFOG[0]                   // Put fog multiplier in elements 3,7 of vscale
    bltz    $11, @@keepoffset
     lbu    $7, mvpValid
    vclr    $v30
@@keepoffset:
.else
    lb      flagsV1, geometryModeLabel + 3    // G_ATTROFFSET_ST_ENABLE in sign bit
    lw      $11, (fogFactor)($zero)           // Load fog multiplier MSBs and offset LSBs
    llv     sSTS[0], (textureSettings2 - altBase)(altBaseReg) // Texture ST scale in 0, 1
    llv     $v30[0], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 0, 1
    llv     $v30[8], (attrOffsetST - altBase)(altBaseReg)  // Texture ST offset in 4, 5
    bltz    flagsV1, @@keepoffset
     srl    $10, $11, 16                      // Fog multiplier to lower bits
    vclr    $v30
@@keepoffset:
    sh      $11, (viewport + 0xE)($zero)      // Store fog offset over vtrans W
    vmov    sSTS[4], sSTS[0]
    sh      $10, (viewport + 0x6)($zero)      // Store fog multiplier over vscale W
    lbu     $7, mvpValid
    ldv     sO03[0], (occlusionPlaneEdgeCoeffs     - altBase)(altBaseReg) // Load coeffs 0-3
    ldv     sO03[8], (occlusionPlaneEdgeCoeffs     - altBase)(altBaseReg) // and for vtx 2
    ldv     sO47[0], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // Load coeffs 4-7
    ldv     sO47[8], (occlusionPlaneEdgeCoeffs + 8 - altBase)(altBaseReg) // and for vtx 2
    ldv     sOCM[0], (occlusionPlaneMidCoeffs      - altBase)(altBaseReg) // Load mid coeffs
    ldv     sOCM[8], (occlusionPlaneMidCoeffs      - altBase)(altBaseReg) // and for vtx 2
.endif
    vmov    sSTS[5], sSTS[1]
    bltz    inVtx, clip_after_constants             // inVtx < 0 means from clipping
     lsv    $v30[6], (perspNorm - altBase)(altBaseReg) // Perspective norm elem 3
vtx_after_setup_constants:
    bnez    $7, @@skip_recalc_mvp
     lb     viLtFlag, pointLightFlag
    li      $2, vpMatrix
    li      dmemAddr, mMatrix
    jal     mtx_multiply
     li     $3, mvpMatrix
    sb      $10, mvpValid  // $10 is nonzero from mtx_multiply, in fact 0x18
@@skip_recalc_mvp:
    andi    $11, vGeomMid, G_LIGHTING >> 8
    bnez    $11, vtx_select_lighting
     sb     $zero, materialCullMode  // Vtx ends material. Must be before lighting for clever packedNormalsMaskConstant reuse
vtx_setup_no_lighting:
    li      vLoopRet, vtx_loop_no_lighting
vtx_after_lt_setup:
    li      $11, mvpMatrix
vtx_load_mtx:
    lqv     vMTX0I,     (0x00)($11)  // Load MVP matrix
    lqv     vMTX2I,     (0x10)($11)
    lqv     vMTX0F,     (0x20)($11)
    lqv     vMTX2F,     (0x30)($11)
    // nop TODO
    vcopy   vMTX1I,  vMTX0I
    vcopy   vMTX3I,  vMTX2I
    ldv     vMTX1I[0],  (0x08)($11)
    vcopy   vMTX1F,  vMTX0F
    ldv     vMTX3I[0],  (0x18)($11)
    vcopy   vMTX3F,  vMTX2F
    ldv     vMTX1F[0],  (0x28)($11)
    ldv     vMTX3F[0],  (0x38)($11)
    ldv     vMTX0I[8],  (0x00)($11)
    ldv     vMTX2I[8],  (0x10)($11)
    ldv     vMTX0F[8],  (0x20)($11)
    beqz    $11, ltadv_after_mtx    // $11 = 0 = mMatrix if from ltadv
     ldv    vMTX2F[8],  (0x30)($11)
vtx_final_setup_for_clip:
.if !CFG_NO_OCCLUSION_PLANE
    vge     $v29, $v31, $v31[2h] // VCC = 00110011
.endif
    andi    fogFlag, vGeomMid, G_FOG >> 8  // Can't put before lt b/c fogFlag = mtx valid flag.
.if !CFG_NO_OCCLUSION_PLANE
    vmrg    sOPM, vOne, $v31[1] // Signs of sOPM are --++--++
.endif
    srl     fogFlag, fogFlag, 5            // 8 if G_FOG is set, 0 otherwise
    addi    outVtx1, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.if !CFG_NO_OCCLUSION_PLANE
    addi    outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.endif
    bltz    inVtx, clip_after_final_setup  // inVtx < 0 means from clipping
.if CFG_NO_OCCLUSION_PLANE
     addi   outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
.else
     vmudh  sOPM, sOPM, $v31[5] // sOPM is 0xC000, 0xC000, 0x4000, 0x4000, repeat
.endif
    jal     while_wait_dma_busy  // Wait for vertex load to finish
     addi   outVtxBase, outVtxBase, -vtxSize   // Will inc by 2, but need point to 2nd
.if CFG_NO_OCCLUSION_PLANE  // With occlusion plane, vpMdl loaded at vtx_store_loop_entry
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // 1st vec pos
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // 2nd vec pos
.endif
    llv     sTCL[8],  (VTX_IN_CN + 0 * inputVtxSize)(inVtx) // RGBA in 4:5
    llv     sTCL[12], (VTX_IN_CN + 1 * inputVtxSize)(inVtx) // RGBA in 6:7
    llv     vpST[0],  (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1
    j       vtx_store_loop_entry
     llv    vpST[8],  (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5
     
align_with_warning 8, "One instruction of padding before vertex loop"

.if CFG_NO_OCCLUSION_PLANE

vtx_loop_no_lighting:
// lCOL <- sSCI
// lDTC <- sRTF
// lVCI <- sRTI
// vpLtTot <- s1WF
// vpNrmlX <- s1WI
    vmadh   $v29, vMTX1I, vpMdl[1h]
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
    sh      flagsV1,        (VTX_CLIP      )(outVtx1) // Store first vertex flags
// lDOT <- vpMdl
// sFOG <- lCOL
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    luv     vpRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// sCLZ <- sTCL
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
vtx_return_from_lighting:
vtx_return_from_texgen:
vtx_store_for_clip:
    vmudl   $v29, vpClpF, $v30[3]       // Persp norm
    sub     $11, outVtx2, fogFlag       // Points 8 before outVtx2 if fog, else 0
// s1WI <- vpNrmlX
    vmadm   s1WI, vpClpI, $v30[3]       // Persp norm
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
// s1WF <- vpLtTot
    vmadn   s1WF, $v31, $v31[2]         // 0
    sbv     sFOG[15], (VTX_COLOR_A + 8)($11) // In VTX_SCR_Y if fog disabled...
    vmov    vpScrF[1], sCLZ[2]
    sbv     sFOG[7],  (VTX_COLOR_A + 8 - vtxSize)($11) // ...which gets overwritten below
// sSCF <- lDOT
    vmudn   sSCF, vpClpF, $v31[3]        // W * clip ratio for scaled clipping
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
// sSCI <- sFOG
    vmadh   sSCI, vpClpI, $v31[3]        // W * clip ratio for scaled clipping
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vrcph   $v29[0], s1WI[3]
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
// sRTF <- lDTC
    vrcpl   sRTF[2], s1WF[3]
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
// sRTI <- lVCI
    vrcph   sRTI[3], s1WI[7]
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    vrcpl   sRTF[6], s1WF[7]
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
    vrcph   sRTI[7], $v31[2] // 0
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadm   $v29, s1WI, sRTF[2h]
    sdv     vpClpF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadn   s1WF, s1WF, sRTI[3h]
// sTCL <- sCLZ
    ldv     sTCL[0],   (VTX_IN_TC + 2 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vpClpF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    lsv     vpClpF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmudh   $v29, vOne, $v31[4]  // 4
    sdv     vpClpI[8],  (VTX_INT_VEC   )(outVtx2)
    vmadn   s1WF, s1WF, $v31[0]  // -4
    lsv     vpClpF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, $v31[0]  // -4
    sdv     vpClpI[0],  (VTX_INT_VEC   )(outVtx1)
    vmudm   $v29, vpST, sSTS       // Scale ST
    ldv     sTCL[8],   (VTX_IN_TC + 3 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
// sST2 <- vpScrI
    vmadh   sST2, vOne, $v30          // + 1 * ST offset; elems 0, 1, 4, 5
    suv     vpRGBA[4],   (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vmudl   $v29, s1WF, sRTF[2h]
    lsv     vpClpI[14], (VTX_Z_INT     )(outVtx2) // load Z into W slot, will be for fog below
    vmadm   $v29, s1WI, sRTF[2h]
    suv     vpRGBA[0],   (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmadn   s1WF, s1WF, sRTI[3h]
    lsv     vpClpI[6],  (VTX_Z_INT     )(outVtx1) // load Z into W slot, will be for fog below
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcopy   vpST, sTCL
    cfc2    $11, $vcc                   // Scaled clip results
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
// vpMdl <- sSCF
    ldv     vpMdl[0], (VTX_IN_OB + 2 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmadn   vpClpF, vpClpF, s1WI[3h]
    ldv     vpMdl[8], (VTX_IN_OB + 3 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmov    sTCL[4], vpST[2] // First vtx RG to elem 4
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmov    sTCL[5], vpST[3] // First vtx BA to elem 5
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
    vmudl   $v29, vpClpF, $v30[3] // Persp norm
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmadm   vpClpI, vpClpI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    // vnop  // TODO maybe can rotate the loop so this is the jr land slot?
    slv     sST2[8],           (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudh   $v29, sVPO, vOne // offset * 1
    slv     sST2[0],           (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    vmadh   $v29, sFGM, $v31[6] // + (0,0,0,1,0,0,0,1) * 0x7F00
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpScrF, vpClpF, sVPS   // + pos frac * scale
    or      flagsV2, flagsV2, $11    // Combine results for second vertex
// vpScrI <- sST2
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI:vpScrF is now screen space pos
    sh      flagsV2,           (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
vtx_store_loop_entry:
    vmudn   $v29, vMTX3F, vOne
    blez    vtxLeft, vtx_epilogue
     vmadh  $v29, vMTX3I, vOne
    vmadn   $v29, vMTX0F, vpMdl[0h]
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmadh   $v29, vMTX0I, vpMdl[0h]
    jr      vLoopRet
     vmadn  $v29, vMTX1F, vpMdl[1h]
    
vtx_epilogue:
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    beqz    fogFlag, @@skip_fog
     slv    vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    sbv     sFOG[15], (VTX_COLOR_A    )(outVtx2)
    sbv     sFOG[7],  (VTX_COLOR_A    )(outVtx1)
@@skip_fog:
    vmov    vpScrF[1], sCLZ[2]
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
    bltz    inVtx, clip_after_vtx_store  // inVtx < 0 means from clipping
     slv    vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    sh      flagsV1,  (VTX_CLIP       )(outVtx1) // Store first vertex flags
    // Fallthrough (across the versions boundary) to vtx_end

.else // not CFG_NO_OCCLUSION_PLANE
    
    // 70 cycles, 16 more than NOC
    // 6 vu cycles for plane, 8 vu cycles for edges, 0 more vnops than NOC,
    // 1 branch delay slot with SU instr, 1 land-after-branch.
vtx_loop_no_lighting:
// lDTC <- sVPS
// lVCI <- sRTI
// vpLtTot <- sTCL
// vpNrmlX <- s1WF
// lDIR <- sOTM
    veq     $v29, $v31, $v31[0q]  // Set VCC to 10101010
    sub     $11, outVtx1, fogFlag      // Points 8 before outVtx1 if fog, else 0
    vmrg    sOCS, sOCS, sOTM      // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
    sbv     sFOG[7],  (VTX_COLOR_A + 8)($11) // ...which gets overwritten below
    vmrg    vpScrF, vpScrF, sCLZ[2h]  // Z int elem 2, 6 to elem 1, 5; Z frac in elem 2, 6
// vpRGBA <- lDIR
    luv     vpRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// lDOT <- sCLZ
// lCOL <- sFOG
vtx_return_from_texgen:
    vmudm   $v29, vpST, sSTS   // Scale ST
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vmadh   vpST, vOne, $v30   // + 1 * ST offset; elems 0, 1, 4, 5
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
vtx_return_from_lighting:
    vge     $v29, sOCS, sO47      // Each compare to coeffs 4-7
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
    vmudn   $v29, vMTX3F, vOne
    cfc2    $11, $vcc
    vmadh   $v29, vMTX3I, vOne
    slv     vpScrF[10], (VTX_SCR_Z      )(outVtx2)
    vmadn   $v29, vMTX0F, vpMdl[0h]
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadh   $v29, vMTX0I, vpMdl[0h]
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    vmadn   $v29, vMTX1F, vpMdl[1h]
    or      $11, $11, $10    // Combine occlusion results. Any set in 0-3, 4-7 = not occluded
    vmadh   $v29, vMTX1I, vpMdl[1h]
    andi    $10, $11, 0x000F // Bits 0-3 for vtx 1
// vpClpF <- lDOT
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
    addi    $11, $11, -(0x0010) // If not occluded, atl 1 of 4-7 set, so $11 >= 0x10. Else $11 < 0x10.
// vpClpI <- lCOL
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
    bnez    $10, @@skipv1    // If nonzero, at least one equation false, don't set occluded flag
     andi   $11, $11, CLIP_OCCLUDED // This is bit 11, = sign bit b/c |$11| <= 0xFF
    ori     flagsV1, flagsV1, CLIP_OCCLUDED // All equations true, set vtx 1 occluded flag
@@skipv1:
    // 16 cycles
vtx_store_for_clip:
    vmudl   $v29, vpClpF, $v30[3]       // Persp norm
    or      flagsV2, flagsV2, $11 // occluded = $11 negative = sign bit set = $11 is flag, else 0
// s1WI <- vpMdl
    vmadm   s1WI, vpClpI, $v30[3]       // Persp norm
    sh      flagsV2,            (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
// s1WF <- vpNrmlX
    vmadn   s1WF, $v31, $v31[2]         // 0
    blez    vtxLeft, vtx_epilogue
     vmudn  $v29, vpClpF, sOCM          // X * kx, Y * ky, Z * kz
    vmadh   $v29, vpClpI, sOCM          // Int * int
    sh      flagsV1,            (VTX_CLIP      )(outVtx1) // Store first vertex flags
    vrcph   $v29[0], s1WI[3]
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
// sRTF <- lDTC
    vrcpl   sRTF[2], s1WF[3]
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
// sRTI <- lVCI
    vrcph   sRTI[3], s1WI[7]
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
    vrcpl   sRTF[6], s1WF[7]
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
    vrcph   sRTI[7], $v31[2] // 0
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vreadacc sOCS, ACC_UPPER                // Load int * int portion
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmudl   $v29, s1WF, sRTF[2h]
    sdv     vpClpI[8],  (VTX_INT_VEC   )(outVtx2)
    vmadm   $v29, s1WI, sRTF[2h]
    sdv     vpClpI[0],  (VTX_INT_VEC   )(outVtx1)
    vmadn   s1WF, s1WF, sRTI[3h]
    sdv     vpClpF[8],  (VTX_FRAC_VEC  )(outVtx2)
    vmadh   s1WI, s1WI, sRTI[3h]
    sdv     vpClpF[0],  (VTX_FRAC_VEC  )(outVtx1)
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    sqv     vpClpI, (tempVpRGBA)(rdpCmdBufEndP1) // For Z to W manip. RGBA not currently stored here
    vmudh   $v29, vOne, $v31[4]  // 4
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadn   s1WF, s1WF, $v31[0]  // -4
    ssv     vpClpI[4],  (tempVpRGBA + 6)(rdpCmdBufEndP1)  // First Z to W
    vmadh   s1WI, s1WI, $v31[0]  // -4
// sTCL <- vpLtTot
    ldv     sTCL[0],   (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
// sSCF <- vpScrF
    vmudn   sSCF, vpClpF, $v31[3]       // W * clip ratio for scaled clipping
    ssv     vpClpI[12], (tempVpRGBA + 14)(rdpCmdBufEndP1) // Second Z to W
// sSCI <- vpScrI
    vmadh   sSCI, vpClpI, $v31[3]       // W * clip ratio for scaled clipping
    lsv     vpClpF[14], (VTX_Z_FRAC    )(outVtx2) // load Z into W slot, will be for fog below
    vmudl   $v29, s1WF, sRTF[2h]
    lqv     vpClpI, (tempVpRGBA)(rdpCmdBufEndP1) // Load int part with Z in W
    vmadm   $v29, s1WI, sRTF[2h]
    lsv     vpClpF[6],  (VTX_Z_FRAC    )(outVtx1) // load Z into W slot, will be for fog below
    vmadn   s1WF, s1WF, sRTI[3h]
    ldv     sTCL[8],   (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    slv     vpST[8], (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    cfc2    $11, $vcc                   // Scaled clip results
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
    slv     vpST[0], (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    vmadn   vpClpF, vpClpF, s1WI[3h]
// sVPO <- sSCF
    ldv     sVPO[0], (viewport + 8)($zero) // Load viewport offset incl. fog for first vertex
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
// sOTM <- vpRGBA
    vadd    sOTM, sOCS, sOCS[1h] // Add Y to X
    ldv     sVPO[8], (viewport + 8)($zero) // Load viewport offset incl. fog for second vertex
    vcopy   vpST, sTCL
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmudl   $v29, vpClpF, $v30[3] // Persp norm
// sVPS <- sSCI
    ldv     sVPS[0], (viewport)($zero) // Load viewport scale incl. fog for first vertex
    vmadm   vpClpI, vpClpI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    ldv     sVPS[8], (viewport)($zero) // Load viewport scale incl. fog for second vertex
    vadd    sOCS, sOTM, sOCS[2h] // Add Z to X
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    vmov    sTCL[4], vpST[2] // First vtx RG to elem 4
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmudh   $v29, sVPO, vOne // offset * 1
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
// vpScrF <- sVPO
    vmadn   vpScrF, vpClpF, sVPS   // + pos frac * scale
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
// vpScrI <- sVPS
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI:vpScrF is now screen space pos
    or      flagsV2, flagsV2, $11            // Combine results for second vertex
// sFOG <- vpClpI
    vmadh   sFOG, vOne, $v31[6] // + 0x7F00 in all elements, clamp to 0x7FFF for fog
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vlt     $v29, sOCS, sOCM[3h] // Occlusion plane X+Y+Z<C in elems 0, 4
    or      flagsV1, flagsV1, $10         // Combine results for first vertex
    vmov    sTCL[5], vpST[3] // First vtx BA to elem 5
    cfc2    $10, $vcc // Load occlusion plane mid results to bits 3 and 7
    vmudh   sOTM, vpScrI, $v31[4]   // 4; scale up x and y
// vpMdl <- s1WI
vtx_store_loop_entry:
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vge     sFOG, sFOG, $v31[6]   // 0x7F00; clamp fog to >= 0 (want low byte only)   
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    // vnop
    andi    $10, $10, (1 << 0) | (1 << 4) // Only bits 0, 4 from occlusion
    vmulf   $v29, sOPM, vpScrI[1h]  // -0x4000*Y1, --, +0x4000*Y1, --, repeat vtx 2
    sub     $11, outVtx2, fogFlag      // Points 8 before outVtx2 if fog, else 0
    vmacf   sOCS, sO03, sOTM[0h]  //    4*X1*c0, --,    4*X1*c2, --, repeat vtx 2
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmulf   $v29, sOPM, vpScrI[0h]  // --, -0x4000*X1, --, +0x4000*X1, repeat vtx 2
    sbv     sFOG[15], (VTX_COLOR_A + 8)($11) // In VTX_SCR_Y if fog disabled...
    vmacf   sOTM, sO03, sOTM[1h]  // --,    4*Y1*c1, --,    4*Y1*c3, repeat vtx 2
    jr      vLoopRet
// sCLZ <- vpClpF
     vge    sCLZ, vpScrI, $v31[2]   // 0; clamp Z to >= 0
     // vnop in land slot
     
vtx_epilogue:
    bltz    inVtx, clip_after_vtx_store  // inVtx < 0 means from clipping
     sh     flagsV1,            (VTX_CLIP      )(outVtx1) // Store first vertex flags
    // Fallthrough to vtx_end
     
.endif

vtx_end:
.if CFG_PROFILING_A
    li      $ra, 0                           // Flag for coming from vtx
    lqv     vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix
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
.else
    j       run_next_DL_command
     lqv    vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix
.endif

tri_snake_end:
    addi    inputBufferPos, inputBufferPos, 7 // Round up to whole input command
    addi    $11, $zero, 0xFFF8               // Sign-extend; andi is zero-extend!
    j       tris_end
     and    inputBufferPos, inputBufferPos, $11 // inputBufferPos has to be negative

tri_snake_over_input_buffer:
    j       displaylist_dma_tri_snake    // inputBufferPos is now 0; load whole buffer
     li     nextRA, tri_snake_ret_from_input_buffer
tri_snake_ret_from_input_buffer:
    j       tri_snake_loop_from_input_buffer // inputBufferPos pointing to first byte loaded
     lbu    $3, (inputBufferEnd)(inputBufferPos) // Load c; clear real index b sign bit -> don't exit

// Converts the segmented address in cmd_w1_dram to the corresponding physical address
segmented_to_physical: // 7
    srl     $11, cmd_w1_dram, 22          // Copy (segment index << 2) into $11
    andi    $11, $11, 0x3C                // Clear the bottom 2 bits that remained during the shift
    lw      $11, (segmentTable)($11)      // Get the current address of the segment
    sll     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address to the left so that the top 8 bits are shifted out
    srl     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr      $ra
     add    cmd_w1_dram, cmd_w1_dram, $11 // Add the segment's address to the masked input address, resulting in the virtual address

load_overlay_0_and_enter:
    li      nextRA, 0x1000                  // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)   // Sets up ovl0 table address
load_overlays_0_1:
    li      dmaLen, ovl01_end - 0x1000 - 1
    j       load_overlay_inner
     li     dmemAddr, 0x1000

load_overlays_2_3_4:
    addi    nextRA, $ra, -8  // Got here with jal, but want to return to addr of jal itself
    li      dmaLen, ovl234_end - ovl234_start - 1
    li      dmemAddr, ovl234_start
load_overlay_inner:  // dmaLen, dmemAddr, cmd_w1_dram, and nextRA must be set
    lw      $11, OSTask + OSTask_ucode
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 0x4000  // Increment overlay (all 0-4) load count
.endif
.if !CFG_PROFILING_C
    j       dma_and_wait_goto_next_ra
     add    cmd_w1_dram, cmd_w1_dram, $11
.else
    // According to Tharo's testing, and in contradiction to the manual, almost no
    // instructions are issued while an IMEM DMA is happening. So we have to time
    // it using counters.
    mfc0    ovlInitClock, DPC_CLOCK
    jal     shared_dma_read_write // The one without perfCounterD
     add    cmd_w1_dram, cmd_w1_dram, $11
    mfc0    $11, SP_DMA_BUSY
@@while_dma_busy:
    bnez    $11, @@while_dma_busy
     mfc0   $11, SP_DMA_BUSY
    mfc0    $11, DPC_CLOCK
    sub     $11, $11, ovlInitClock
    jr      nextRA
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

endFreeImemAddr equ 0x1FC4
startFreeImem:
.if . > endFreeImemAddr
    .error "Out of IMEM space"
.endif
.org endFreeImemAddr
endFreeImem:

wait_goto_next_ra:
    move    $ra, nextRA
    // Fallthrough to while_wait_dma_busy
    
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
    jal     flush_rdp_buffer   // See G_FLUSH_handler for docs on these 3 instructions.
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    jal     flush_rdp_buffer
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    lw      $10, startCounterTime
    sub     $11, $11, $10
    add     perfCounterA, perfCounterA, $11
.endif
    bnez    $1, task_done_or_yield  // Continue to load ucode if 0
load_ucode:
     lw     cmd_w1_dram, (inputBufferEnd - 0x04)(inputBufferPos) // word 1 = ucode code DRAM addr
    sw      $zero, OSTask + OSTask_flags    // So next ucode knows it didn't come from yield
    li      dmemAddr, start         // Beginning of overwritable part of IMEM
    sw      taskDataPtr, OSTask + OSTask_data_ptr // Store where we are in the DL
    sw      cmd_w1_dram, OSTask + OSTask_ucode // Store pointer to new ucode about to execute
    // Store counters in mvpMatrix; first 0x180 of DMEM will be preserved in ucode swap AND
    // if other ucode yields
    sw      perfCounterA, mvpMatrix + YDF_OFFSET_PERFCOUNTERA
    sw      perfCounterB, mvpMatrix + YDF_OFFSET_PERFCOUNTERB
    sw      perfCounterC, mvpMatrix + YDF_OFFSET_PERFCOUNTERC
    sw      perfCounterD, mvpMatrix + YDF_OFFSET_PERFCOUNTERD
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

// overlay 1
.headersize 0x00001000 - orga()

ovl1_start:

G_MTX_handler: // 12
.if CFG_PROFILING_C
    addi    perfCounterC, perfCounterC, 1  // Increment matrix count
.endif
    andi    $11, cmd_w0, G_MTX_VP_M | G_MTX_NOPUSH_PUSH
    beqz    $11, ovl234_clipmisc_entrypoint  // Model and push: go to overlay for push
     sh     $zero, mvpValid                  // and dirLightsXfrmValid
load_mtx:
    andi    $1, cmd_w0, G_MTX_MUL_LOAD       // Read the matrix load type into $1 (2 is multiply, 0 is load)
G_MOVEMEM_handler:  // Otherwise $1 is 0
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
do_movemem:
     // 0: load M, 2: mul M -> load temp, 4: load VP, 6: mul VP -> load temp
     andi   $3, cmd_w0, 0x00FE            // Movemem table index into $1 (bits 1-7 of the word 0)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Second byte of word 0
    lhu     dmemAddr, (movememTable)($3)  // $3 reused in G_MTX_multiply_end
    srl     $2, cmd_w0, 5                 // ((w0) >> 8) << 3; top 3 bits of idx must be 0; lower 1 bit of len byte must be 0
    add     dmemAddr, dmemAddr, $2
    j       dma_and_wait_goto_next_ra
     lh     nextRA, (afterMovememRaTable)($1) // $1 is 2 if mtx multiply, else 0

G_FLUSH_handler: // 32
    jal     flush_rdp_buffer        // Flush once to push partial DMEM buf to FIFO
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Prereq; offset buffer fullness
    // If the DMEM buffer was empty, dmemAddr will be unchanged and valid for this next
    // jump. Otherwise, running the DMA write will cause dmemAddr to get set to a large
    // negative number. Then for this second jump, the same codepath will be triggered as
    // if the buffer was empty. The result is it will wait for the DMA to finish, set
    // DPC_END, and return to $ra. This is why the dmemAddr register (as opposed to,
    // for example, dmaLen) is used as the DMEM buf fullness.
    j       flush_rdp_buffer
G_MTX_multiply_end:
     li     $ra, run_next_DL_command // Dual use for above and below
    lhu     $3, (movememTable - G_MV_TEMPMTX0)($3) // $3=2->0=M; $3=6->4=VP
    move    $2, $3 // Input 0 = output
mtx_multiply:
    // $2 and dmemAddr are input matrices; $3 is output matrix
    addi    $10, dmemAddr, 0x0018
@@loop:
    vmadn   $v7, $v31, $v31[2]  // 0
    addi    $11, dmemAddr, 0x0008
    vmadh   $v6, $v31, $v31[2]  // 0
    addi    $2, $2, -0x0020
    vmudh   $v29, $v31, $v31[2] // 0
@@innerloop:
    ldv     $v3[0], 0x0040($2)
    ldv     $v3[8], 0x0040($2)
    lqv     vTemp2[0], 0x0020(dmemAddr) // Input 1
    ldv     $v2[0], 0x0020($2)
    ldv     $v2[8], 0x0020($2)
    lqv     vTemp1[0], 0x0000(dmemAddr) // Input 1
    vmadl   $v29, $v3, vTemp2[0h]
    addi    dmemAddr, dmemAddr, 0x0002
    vmadm   $v29, $v2, vTemp2[0h]
    addi    $2, $2, 0x0008 // Increment input 0 pointer
    vmadn   $v5, $v3, vTemp1[0h]
    bne     dmemAddr, $11, @@innerloop
     vmadh  $v4, $v2, vTemp1[0h]
    bne     dmemAddr, $10, @@loop
     addi   dmemAddr, dmemAddr, 0x0008
    sqv     $v7[0], (0x0020)($3)
    sqv     $v6[0], (0x0000)($3)
    sqv     $v4[0], (0x0010)($3)
    jr      $ra
     sqv    $v5[0], (0x0030)($3)

G_VTX_handler: // 19
    lhu     dmemAddr, (vertexTable)(cmd_w0)    // (v0 + n) end address; up to 56 inclusive
    jal     segmented_to_physical              // Convert address in cmd_w1_dram to physical
     lhu    vtxLeft, (inputBufferEnd - 0x07)(inputBufferPos) // vtxLeft = size in bytes = vtx count * 0x10
    sub     dmemAddr, dmemAddr, vtxLeft        // Start addr = end addr - size. Rounded down to DMA word by H/W
    addi    dmaLen, vtxLeft, -1                // DMA length is always offset by -1
    j       dma_read_write
G_SETOTHERMODE_H_handler: // These handler labels must be 4 bytes apart for the code below to work
     li     $ra, vtx_after_dma  // Only for above, nop for below
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

G_RDPSETOTHERMODE_handler: // 4
    li      $1, 8      // Offset from scissor DMEM to othermode DMEM
G_SETSCISSOR_handler:  // $1 is 0 if jumped here
    sw      cmd_w0, (scissorUpLeft)($1) // otherMode0 = scissorUpLeft + 8
    j       G_RDP_handler                // Send the command to the RDP
     sw     cmd_w1_dram, (scissorBottomRight)($1) // otherMode1 = scissorBottomRight + 8

G_GEOMETRYMODE_handler: // 5; $7 = G_GEOMETRYMODE (as negative) if jumped here
    lw      $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7) // load the geometry mode value
    and     $11, $11, cmd_w0        // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      $11, $11, cmd_w1_dram   // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    j       run_next_DL_command     // run the next DL command
     sw     $11, (geometryModeLabel + (0x100 - G_GEOMETRYMODE))($7)  // update the geometry mode value

G_TEXTURE_handler: // 4
    li      $11, textureSettings1 - (texrectWord1 - G_TEXRECTFLIP_handler)  // Calculate the offset from texrectWord1 and $11 for saving to textureSettings
G_TEXRECT_handler: // $11 contains address of handler
G_TEXRECTFLIP_handler:
    // Stores first command word into textureSettings for gSPTexture, 0x00D0 for gSPTextureRectangle/Flip
    sw      cmd_w0, (texrectWord1 - G_TEXRECTFLIP_handler)($11)
G_RDPHALF_1_handler:
    j       run_next_DL_command
    // Stores second command word into textureSettings for gSPTexture, 0x00D4 for gSPTextureRectangle/Flip, 0x00D8 for G_RDPHALF_1
     sw     cmd_w1_dram, (texrectWord2 - G_TEXRECTFLIP_handler)($11)

G_RDPHALF_2_handler: // 7
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 1   // Increment number of tex/fill rects
.endif
    sb      $zero, materialCullMode         // This covers tex and fill rects
    j       G_RDP_handler
     sdv    $v29[0], -8(rdpCmdBufPtr)

/* This is a crazy optimization, and it was completely accidental!
When G_RELSEGMENT was implemented, we did not notice the G_MOVEWORD behavior of
subtracting (G_MOVEWORD << 8) from the movewordTable address in order to remove
the command byte. Since the command byte is G_RELSEGMENT, not G_MOVEWORD, the
final address is completely wrong. However, DMEM wraps at 4 KiB--only the lowest
4 bits of any address are significant. And, G_RELSEGMENT **happened** to end in
0xB, the same as G_MOVEWORD! So the wrong address aliases to the correct one!
I only noticed this when I tried to move G_RELSEGMENT to a different command
byte and got crashes. */
.if (G_RELSEGMENT & 0xF) != (G_MOVEWORD & 0xF)
.error "Crazy relsegment optimization broken, don't change command byte assignments"
.endif
G_RELSEGMENT_handler: // 9
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

ovl1_end:
align_with_warning 8, "One instruction of padding at end of ovl1"
ovl1_padded_end:

.if ovl1_padded_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif
// Currently want exactly 92 instructions (based on current size of start)
.if ovl1_padded_end > start_padded_end
    warn_if_base "ovl1 is larger than start, try to move something out"
.endif
.if ovl1_padded_end < start_padded_end
    warn_if_base "ovl1 is smaller than start, wasting space!"
.endif

.headersize ovl234_start - orga()

ovl2_start:
// Basic lighting overlay.

// Jump here for basic lighting setup. If overlay 2 is loaded (this code), jumps into the
// rest of the lighting code below.
ovl234_ltbasic_entrypoint:
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       ltbasic_continue_setup
     lbu    ambLight, numLightsxSize

// Jump here for advanced lighting. If overlay 2 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ltadv_entrypoint_ovl2ver:           // same IMEM address as ovl234_ltadv_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here for clipping and rare commands. If overlay 2 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipmisc_entrypoint_ovl2ver:        // same IMEM address as ovl234_clipmisc_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

ltbasic_continue_setup:
    bnez    viLtFlag, ltbasic_setup_after_xfrm  // Skip if lights were valid
     addi   ambLight, ambLight, altBase    // Point to ambient light; stored through vtx proc
xfrm_dir_lights:
lpWrld  equ $v11  // light pair world direction
lpMdl   equ $v12  // light pair model space direction (not yet normalized)
lpFinal equ $v13  // light pair normalized model space direction
lpSqrI  equ $v14  // Light pair direction squared int part
lpSqrF  equ $v15  // Light pair direction squared frac part
lpMdl2  equ $v19  // Copy of lpMdl for pipelining
lpSumI  equ $v20  // Light pair direction sum of squares int part
lpSumF  equ $v21  // Light pair direction sum of squares frac part
lpRsqI  equ $v22  // Light pair reciprocal square root int part
lpRsqF  equ $v23  // Light pair reciprocal square root frac part
    // Transform directional lights' direction by M transpose.
    // First, load M transpose. $v0-$v7 is the MVP matrix and $v24-$v31 is
    // permanent values, leaving $v8-$v15 and $v16-$v23 for the transposes.
    // This is mainly just an excuse to use the rare ltv and swv instructions.
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
    // First, load this pattern in $v8-$v15 (int) and $v16-$v23 (frac).
    // $v8  A - G - A - G -   $v16 M - S - M - S -
    // $v9  - B - H - B - H   $v17 - N - T - N - T
    // $v10 I - C - I - C -   $v18 U - O - U - O -
    // $v11 - - - - - - - -   $v19 - - - - - - - -
    // $v12 D - - - D - - -   $v20 P - - - P - - -
    // $v13 - E - - - E - -   $v21 - Q - - - Q - -
    // $v14 - - F - - - F -   $v22 - - R - - - R -
    // $v15 - - - - - - - -   $v23 - - - - - - - -
    ltv     $v8[0],   (mMatrix + 0x00)($zero) // A to $v8[0] etc.
    ltv     $v8[12],  (mMatrix + 0x10)($zero) // G to $v8[2] etc.
    ltv     $v8[8],   (mMatrix + 0x00)($zero) // A to $v8[4] etc.
    ltv     $v8[4],   (mMatrix + 0x10)($zero) // G to $v8[6] etc.
    ltv     $v16[0],  (mMatrix + 0x20)($zero)
    ltv     $v16[12], (mMatrix + 0x30)($zero)
    ltv     $v16[8],  (mMatrix + 0x20)($zero)
    ltv     $v16[4],  (mMatrix + 0x30)($zero)
    veq     $v29, $v31, $v31[0q] // Set VCC to 10101010
    vmudh   $v9, vOne, $v9[1q]                // B - H - B - H -
    lsv     $v18[6],  (mMatrix + 0x2C)($zero) // U - O(R)U - O -
    vmrg    $v8, $v8, $v12[0q]                // A D G - A D G -
    lsv     $v18[14], (mMatrix + 0x2C)($zero) // U - O R U - O(R)
    vmrg    $v10, $v10, $v14[0q]              // I - C F I - C F
    lpv     lpWrld[0], (lightBufferLookat - altBase)(altBaseReg) // Lookat 0 and 1
    vmudh   $v17, vOne, $v17[1q]              // N - T - N - T -
    li      curLight, altBase - 4 * lightSize // + ltBufOfs = light -4; write pointer
    vmrg    $v9, $v9, $v13                    // B E H - B E H -
    li      $11, 0x7F                         // Mark lights valid. Could use some other reg known to be zero, but need a nop here.
    vmrg    $v16, $v16, $v20[0q]              // M P S - M P S -
    swv     $v18[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores O R U - O R U -
    vmudh   $v29,  $v8,  lpWrld[0h]           // Start transforming lookat
    lqv     $v18,    (tempXfrmLt)(rdpCmdBufEndP1)
    // This is slightly wrong, vmrg writes accum lo. But only affects lookat and
    // we are only reading accum mid result. Basically rounding error.
    vmrg    $v17, $v17, $v21                  // N Q T - N Q T -
    swv     $v10[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores C F I - C F I -
    vmadh   $v29,  $v9,  lpWrld[1h]
    lqv     $v10,    (tempXfrmLt)(rdpCmdBufEndP1)
    vmadn   $v29,  $v16, lpWrld[0h]
    sb      $11, dirLightsXfrmValid
    // 18 cycles
xfrm_light_loop_1:
    vmadn   $v29,  $v18, lpWrld[2h]
xfrm_light_loop_2:
    vmadn   $v29,  $v17, lpWrld[1h]
    vmadh   lpMdl, $v10, lpWrld[2h]  // lpMdl[0:2] and [4:6] = two lights dir in model space
    vrsqh   $v29[0], lpSumI[0]
    vrsql   lpRsqF[0], lpSumF[0]
    vrsqh   lpRsqI[0], lpSumI[4]
    addi    curLight, curLight, 2 * lightSize // Iters: -2, 0, 2, ...
    vrsql   lpRsqF[4], lpSumF[4]
    lw      $20, (ltBufOfs + 8 + 2 * lightSize)(curLight) // First iter = light 0
    vrsqh   lpRsqI[4], $v31[2]       // 0
    lw      $24, (ltBufOfs + 8 + 3 * lightSize)(curLight) // First iter = light 1
    vmudh   $v29, lpMdl, lpMdl       // Squared
    sub     $10, curLight, altBaseReg // Is curLight (write ptr) <= 0?
    vreadacc lpSqrF, ACC_MIDDLE      // Read not-clamped value
    sub     $11, curLight, ambLight  // Is curLight (write ptr) <, =, or > ambient light?
    vreadacc lpSqrI, ACC_UPPER
    sw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Store light 0
    vmudm   $v29,    lpMdl2, lpRsqF[0h] // Vec int * frac scaling
    sw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Store light 1
    vmadh   lpFinal, lpMdl2, lpRsqI[0h] // Vec int * int scaling
    lpv     lpWrld[0], (tempXfrmLt)(rdpCmdBufEndP1) // Load dirs 0-2, 4-6
    vmudm   $v29, vOne, lpSqrF[2h]  // Sum of squared components
    vmadh   $v29, vOne, lpSqrI[2h]
    vmadm   $v29, vOne, lpSqrF[1h]
    vmadh   $v29, vOne, lpSqrI[1h]
    spv     lpFinal[0], (tempXfrmLt)(rdpCmdBufEndP1) // Store elem 0-2, 4-6 as bytes to temp memory
    vmadn   lpSumF, lpSqrF,  vOne     // elem 0, 4; swapped so we can do vmadn and get result
    lw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vmadh   lpSumI, lpSqrI,  vOne
    lw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vcopy   lpMdl2, lpMdl
    blez    $10, xfrm_light_store_lookat // curLight = -2 or 0
     vmudh  $v29, $v8,  lpWrld[0h]
     // 20 cycles from xfrm_light_loop_2 not counting land
    vmadh   $v29, $v9,  lpWrld[1h]
    bgtz    $11, ltbasic_setup_after_xfrm // curLight > ambient; only one light valid
     sw     $20, (ltBufOfs + 0xC - 2 * lightSize)(curLight) // Write light relative -2
    vmadn   $v29, $v16, lpWrld[0h]
    bltz    $11, xfrm_light_loop_1   // curLight < ambient; more lights to compute
     sw     $24, (ltBufOfs + 0xC - 1 * lightSize)(curLight) // Write light relative -1
ltbasic_setup_after_xfrm:
    // Constants registers:
    //       e0     e1     e2     e3     e4     e5     e6     e7
    // vLTC  0xF800 Lt1 Z  AOAmb  AODir  Lt1 X  Lt1 Y  AOAmb  AODir
    // $v30  SOffs  TOffs  0/AOa  Persp  SOffs  TOffs  0x0020 0x0800
    lpv     vLTC[0], (ltBufOfs + 8 - lightSize)(ambLight) // First lt xfrmed dir in elems 4-6
    addi    lbFakeAmb, ambLight, ltBufOfs  // Ptr to load amb light from; normally actual ambient light
    li      vLoopRet, ltbasic_start_standard
    andi    $11, vGeomMid, (G_AMBOCCLUSION | G_PACKED_NORMALS | G_LIGHTTOALPHA | G_TEXTURE_GEN) >> 8
    vmov    $v30[2], $v31[2] // 0 as AO alpha offset
    vmov    vLTC[1], vLTC[6] // Move first lt Z to elem 1; watch stall on vLTC load
    beqz    $11, vtx_after_lt_setup  // None of the above features enabled
     li     lbAfter, vtx_return_from_lighting
    andi    $11, vGeomMid, G_TEXTURE_GEN >> 8
    beqz    $11, @@skip_texgen
     andi   $10, vGeomMid, G_PACKED_NORMALS >> 8
    li      lbAfter, 0x8000 | ltbasic_texgen // Negative is used as flag
@@skip_texgen:
    beqz    $10, @@skip_packed
     move   lbTexgenOrRet, lbAfter
    // Packed normals setup
    sbv     $v31[15], (3)(lbFakeAmb)  // 0xFF; Set ambient "alpha" to FF / 7F80
    vmov    $v30[6], $v31[2] // 0; clear element 6, will overwrite second byte of it below
    sbv     $v31[15], (7)(lbFakeAmb)  // 0xFF; so vpLtTot alpha ~= 7FFF, so * vtx alpha
    li      lbAfter, ltbasic_packed
    li      vLoopRet, ltbasic_start_packed
    lsv     vLTC[0], (packedNormalsMaskConstant - altBase)(altBaseReg) // 0xF800; cull mode already zeroed
    llv     $v30[13], (packedNormalsConstants - altBase)(altBaseReg) // 00[20 0800 OB]; out of bounds truncates
@@skip_packed:
    andi    $11, vGeomMid, G_LIGHTTOALPHA >> 8
    beqz    $11, @@skip_l2a
     andi   $10, vGeomMid, G_AMBOCCLUSION >> 8
    li      lbAfter, ltbasic_l2a
@@skip_l2a:
    beqz    $10, vtx_after_lt_setup
     // AO setup
     move   lbPostAo, lbAfter // Harmless to be done even if not AO
    addi    lbFakeAmb, rdpCmdBufEndP1, tempAmbient  // Temp mem as ambient light
    vmov    $v30[2], $v31[7] // 7FFF as AO alpha offset
    spv     vOne[0], (0)(lbFakeAmb) // Store all zeros here (upper bytes of vOne are 0)
    llv     vLTC[4], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 2, 3
    llv     vLTC[12], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 6, 7
    j       vtx_after_lt_setup
     li     lbAfter, ltbasic_ao
    
.align 8
xfrm_light_store_lookat:
    vmadh   $v29, $v9,  lpWrld[1h]
    spv     lpFinal[0], (xfrmLookatDirs)($zero) // Store lookat. 1st time garbage, 2nd real
    vmadn   $v29, $v16, lpWrld[0h]
    j       xfrm_light_loop_2
     vmadn  $v29, $v18, lpWrld[2h]

// Lighting within vertex loop

.if CFG_NO_OCCLUSION_PLANE

.macro instan_lt_vec_1
    vmadh   $v29, vMTX1I, vpMdl[1h]
.endmacro
.macro instan_lt_vec_2
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
.endmacro
.macro instan_lt_vec_3
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
.endmacro
// lDOT <- vpMdl
.macro instan_lt_scl_1
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
.endmacro
.macro instan_lt_scl_2
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
.endmacro
// sFOG <- lCOL
.macro instan_lt_vs_45
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    sh      flagsV1, (VTX_CLIP      )(outVtx1) // Store first vertex flags
.endmacro

.else

.macro instan_lt_vec_1
    veq     $v29, $v31, $v31[0q]  // Set VCC to 10101010
.endmacro
.macro instan_lt_vec_2
    vmrg    sOCS, sOCS, sOTM      // Elems 0-3 are results for vtx 0, 4-7 for vtx 1
.endmacro
.macro instan_lt_vec_3
    vmrg    vpScrF, vpScrF, sCLZ[2h]  // Z int elem 2, 6 to elem 1, 5; Z frac in elem 2, 6
.endmacro
// lDOT <- sCLZ
// vpRGBA <- sOTM
.macro instan_lt_scl_1
    sub     $11, outVtx1, fogFlag      // Points 8 before outVtx1 if fog, else 0
.endmacro
.macro instan_lt_scl_2
    sbv     sFOG[7],  (VTX_COLOR_A + 8)($11)
.endmacro
// lCOL <- sFOG
.macro instan_lt_vs_45
    vmudm   $v29, vpST, sSTS   // Scale ST
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vmadh   vpST, vOne, $v30   // + 1 * ST offset; elems 0, 1, 4, 5
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
.endmacro

.endif

.align 8

// If lighting, vLoopRet = ltbasic_start_packed if packed, else ltbasic_start_standard

ltbasic_start_packed:
    instan_lt_vec_1
    instan_lt_vec_2
    instan_lt_vec_3
    vand    vpNrmlX, vpMdl, vLTC[0]  // 0xF800; mask X to only top 5 bits
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load RGBA
    vmudn   vpNrmlY, vpMdl, $v30[6]  // (1 << 5) = 0x0020; left shift normals Y
    j       ltbasic_after_start
     vmudn  vpNrmlZ, vpMdl, $v30[7]  // (1 << 11) = 0x0800; left shift normals Z

.align 8
ltbasic_start_standard:
    // Using elem 3, 7 for regular normals because packed normal results are there.
    instan_lt_vec_1
    lpv     vpNrmlX[3], (tempVpRGBA)(rdpCmdBufEndP1) // X to elem 3, 7
    instan_lt_vec_2
    lpv     vpNrmlY[2], (tempVpRGBA)(rdpCmdBufEndP1) // Y to elem 3, 7
    instan_lt_vec_3
    lpv     vpNrmlZ[1], (tempVpRGBA)(rdpCmdBufEndP1) // Z to elem 3, 7
    vnop
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load vertex color input
ltbasic_after_start:

.if CFG_DEBUG_NORMALS
.warning "Debug normals visualization is enabled"
    vmudh   vpNrmlX, vOne, vpNrmlX[3h] // Move X to all elements
    vne     $v29, $v31, $v31[1h] // Set VCC to 10111011
    vmrg    vpNrmlX, vpNrmlX, vpNrmlY[3h] // X in 0, 4; Y to 1, 5
    vne     $v29, $v31, $v31[2h] // Set VCC to 11011101
    vmrg    vpNrmlX, vpNrmlX, vpNrmlZ[3h] // Z to 2, 6
    vmudh   $v29, vOne, $v31[5] // 0x4000; middle gray
    j       vtx_return_from_lighting
     vmacf  vpRGBA, vpNrmlX, $v31[5] // 0x4000; + 0.5 * normal
.else // CFG_DEBUG_NORMALS

    vmulf   $v29,  vpNrmlX, vLTC[4] // Normals X elems 3, 7 * first light dir X
// lDIR <- (NOC: -, Occ: sOTM)
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(ambLight) // Xfrmed dir in elems 4-6; temp reg
    vmacf   $v29,  vpNrmlY, vLTC[5] // Normals Y elems 3, 7 * first light dir Y
    luv     vpLtTot,    (0)(lbFakeAmb)  // Total light level, init to ambient or zeros if AO
// lDOT <- (NOC: vpMdl, Occ: sCLZ)
    vmacf   lDOT, vpNrmlZ, vLTC[1] // Normals Z elems 3, 7 * first light dir Z
    instan_lt_scl_1  // $11 can be used as a temporary, except b/w instan_lt_scl_1...
    vsub    lVCI, lVCI, $v30[2] // Offset alpha for AO, or 0 normally
    instan_lt_scl_2 // ...and instan_lt_scl_2
// lCOL <- (Occ: sFOG here / NOC: sSCI earlier)
    // vnop
    beq     ambLight, altBaseReg, ltbasic_post
     move   curLight, ambLight                   // Point to ambient light
ltbasic_loop:
    vge     lDTC, lDOT, $v31[2] // 0; clamp dot product to >= 0
    vmulf   $v29,  vpNrmlX, lDIR[4] // Normals X elems 3, 7 * next light dir
    luv     lCOL,   (ltBufOfs + 0 - 1*lightSize)(curLight) // Light color
    vmacf   $v29,  vpNrmlY, lDIR[5] // Normals Y elems 3, 7 * next light dir
    addi    curLight, curLight, -lightSize
    vmacf   lDOT, vpNrmlZ, lDIR[6] // Normals Z elems 3, 7 * next light dir
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(curLight) // Xfrmed dir in elems 4-6; DOES dual-issue
    vmudh   $v29, vOne, vpLtTot // Load accum mid with current light level
    bne     curLight, altBaseReg, ltbasic_loop
     vmacf  vpLtTot, lCOL, lDTC[3h] // + light color * dot product
ltbasic_post:
// (NOC: sFOG here / Occ: vpClpI later) <- lCOL
    instan_lt_vs_45
    vne     $v29, $v31, $v31[3h]           // Set VCC to 11101110
    jr      lbAfter
// vpRGBA <- lDIR
     vmrg   vpRGBA, vpLtTot, lVCI  // RGB = light, A = vtx alpha

.endif // CFG_DEBUG_NORMALS

// lbAfter       = ltbasic_ao if AO else
// lbPostAo      = ltbasic_l2a if L2A else
//                 ltbasic_packed if packed else
// lbTexgenOrRet = ltbasic_texgen if texgen else
//                 vtx_return_from_lighting
     
ltbasic_ao:
    vmudn   $v29, vLTC, lVCI[3h]      // (aoAmb 2 6, aoDir 3 7) * (alpha - 1)
    luv     vpRGBA, (ltBufOfs + 0)(ambLight)  // Ambient light level
    vmadh   lDTC, vOne, $v31[7]       // + 0x7FFF (1 in s.15)
    vadd    lVCI, lVCI, $v31[7]       // 0x7FFF; undo offset alpha
    vmulf   $v29, vpLtTot, lDTC[3h]   // Sum of dir lights *= dir factor
    vmacf   vpLtTot, vpRGBA, lDTC[2h] // + ambient * amb factor
    jr      lbPostAo                  // Return, texgen, l2a, or packed
     vmacf  vpRGBA, $v31, $v31[2]     // 0; need it in vpRGBA if returning, else in vpLtTot
     
ltbasic_l2a:
    // Light-to-alpha (cel shading): alpha = max of light components, RGB = vertex color
    vge     vpLtTot, vpLtTot, vpLtTot[1h] // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    vge     vpLtTot, vpLtTot, vpLtTot[2h] // elem 0 = max(R0, G0, B0); equiv for elem 4
    vne     $v29, $v31, $v31[3h]          // Reset VCC to 11101110 (clobbered by vge)
    jr      lbTexgenOrRet
     vmrg   vpRGBA, lVCI, vpLtTot[0h]     // RGB is vcol (garbage if not packed); A is light
    
ltbasic_packed:
    bgez    lbTexgenOrRet, vtx_return_from_lighting // < 0 for texgen
     vmulf  vpRGBA, vpLtTot, lVCI      // (Light color, 7FFF alpha) * vertex RGBA.
ltbasic_texgen:
// Texgen: in vpNrmlX:Y:Z; temps vpLtTot, lDOT, lDTC; out vpST.
lLkDrs equ lDTC    // lighting Lookat Directions
lLkDt0 equ vpLtTot // lighting Lookat Dot product 0
lLkDt1 equ lDOT    // lighting Lookat Dot product 1
    lpv     lLkDrs[0], (xfrmLookatDirs + 0)($zero) // Lookat 0 in 0-2, 1 in 4-6
.macro texgen_dots, lookats, dot0, dot1
    vmulf   $v29, vpNrmlX, lookats[0]  // Normals X * lookat 0 X
    vmacf   $v29, vpNrmlY, lookats[1]  // Normals Y * lookat 0 Y
    vmacf   dot0, vpNrmlZ, lookats[2]  // Normals Z * lookat 0 Z
    vmulf   $v29, vpNrmlX, lookats[4]  // Normals X * lookat 1 X
    vmacf   $v29, vpNrmlY, lookats[5]  // Normals Y * lookat 1 Y
    vmacf   dot1, vpNrmlZ, lookats[6]  // Normals Z * lookat 1 Z
.endmacro
    texgen_dots lLkDrs, lLkDt0, lLkDt1
.if !CFG_NO_OCCLUSION_PLANE
    addi    outVtxBase, outVtxBase, -2*vtxSize // Undo doing this twice due to repeating ST scale
.endif
// In ltbasic, normals are in elems 3, 7; in ltadv, elems 0, 4
    vmudh   lLkDt0, vOne, lLkDt0[3h] // Move dot 0 from elems 3, 7 to 0, 4
.macro texgen_body, lookats, dot0, dot1, normalselem, branch_no_texgen_linear
// lookats now holds texgen linear coefficients elems 0, 1
    llv     lookats[0], (texgenLinearCoeffs - altBase)(altBaseReg)
    vne     $v29, $v31, $v31[1h]    // Set VCC to 10111011
    andi    $11, vGeomMid, G_TEXTURE_GEN_LINEAR >> 8
    vmrg    dot0, dot0, dot1[normalselem] // Dot products in elements 0, 1, 4, 5
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    beqz    $11, branch_no_texgen_linear
     vmacf  vpST, dot0, $v31[5]     // + dot products * 0x4000 ( / 2)
    // Texgen_Linear:
    vmulf   vpST, dot0, $v31[5]     // dot products * 0x4000 ( / 2)
// dot0 now holds lighting Lookat ST squared
    vmulf   dot0, vpST, vpST        // ST squared
    vmulf   $v29, vpST, $v31[7]     // Move ST to accumulator (0x7FFF = 1)
// dot1 now holds lighting Lookat Temp
    vmacf   dot1, vpST, lookats[1]  // + ST * 0x6CB3
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    vmacf   vpST, vpST, lookats[0]  // + ST * 0x44D3
.endmacro
    texgen_body lLkDrs, lLkDt0, lLkDt1, 3h, vtx_return_from_texgen
    j       vtx_return_from_texgen
.macro texgen_lastinstr, dot0, dot1
     vmacf  vpST, dot0, dot1        // + ST squared * (ST + ST * coeff)
.endmacro
     texgen_lastinstr lLkDt0, lLkDt1
    
ovl2_end:
.align 8
ovl2_padded_end:

.headersize ovl234_start - orga()

ovl4_start:
// Advanced lighting overlay.

// Jump here for basic lighting setup. If overlay 4 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_ltbasic_entrypoint_ovl4ver:         // same IMEM address as ovl234_ltbasic_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2
     
// Jump here for advanced lighting. If overlay 4 is loaded (this code), jumps
// to the instruction selection below.
ovl234_ltadv_entrypoint:
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       vtx_load_mtx
     li     $11, mMatrix

// Jump here for clipping and rare commands. If overlay 4 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipmisc_entrypoint_ovl4ver:        // same IMEM address as ovl234_clipmisc_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

ltadv_spec_fres_setup: // Odd instruction
    // Get aDIR = normalize(camera - vertex), aDOT = (vpWNrm dot aDIR)
    ldv     aDPosI[0], (cameraWorldPos - altBase)(altBaseReg) // Camera world pos
    j       ltadv_normal_to_vertex
     ldv    aDPosI[8], (cameraWorldPos - altBase)(altBaseReg)
     // nop; nop
ltadv_after_camera:
    // vnop; vnop
    vmov    aOAFrs[0], aDOT[0]       // Save Fresnel dot product in aOAFrs[0h]
    vmov    aOAFrs[4], aDOT[4]       // elems 0, 4
    bgez    laSpecular, ltadv_loop   // Sign bit clear = not specular
     li     laSpecFres, 0            // Clear flag for specular or fresnel
// aProj <- aLenF
    vmulf   aProj, vpWNrm, aDOT[0h]  // Projection of camera vec onto normal
    vmudh   $v29, aDIR, $v31[1]      // -camera vec
    j       ltadv_normals_to_regs    // For specular, replace vpWNrm with reflected vector
     // vnop; vnop
     vmadh  vpWNrm, aProj, $v31[3]   // + 2 * projection
     // vnop; vnop
     // aDPosI <- aProj
    
ltadv_xfrm: // Even instruction
    vmudn   $v29, vMTX0F, vpMdl[0h]
    lbu     curLight, numLightsxSize // Scalar instructions here must be OK to do twice
    vmadh   $v29, vMTX0I, vpMdl[0h]
    luv     vpRGBA,  (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2:1 RGBA
    vmadn   $v29, vMTX1F, vpMdl[1h]
    vmadh   $v29, vMTX1I, vpMdl[1h]
    addi    curLight, curLight, altBase // Point to ambient light
    vmadn   aDPosF, vMTX2F, vpMdl[2h]
    jr      $ra
     vmadh  aDPosI, vMTX2I, vpMdl[2h]
    
ltadv_after_mtx: // Even instruction
    move    laPtr, inVtx
    vcopy   aPNScl, vOne
    move    laVtxLeft, vtxLeft
    vmudn   aDPosF, vMTX1F, $v31[7] // 0x7FFF; transform a normal (0, 7FFF, 0)
    // 0001 00[20 0800 XX]01 = (1<<0),(1<<5),(1<<11),XX, repeat
    llv     aPNScl[3],  (packedNormalsConstants - altBase)(altBaseReg)
    vmadh   aDPosI, vMTX1I, $v31[7]
    j       ltadv_normalize
     llv    aPNScl[11], (packedNormalsConstants - altBase)(altBaseReg)
ltadv_continue_setup:
    lqv     aParam, (fxParams - altBase)(altBaseReg)
    vcopy   aNrmSc, aRcpLn // aRcpLn[0:1] is int:frac scale (1 / length)
    lsv     aPNScl[6], (packedNormalsMaskConstant - altBase)(altBaseReg) // F800
    vge     $v29, $v31, $v31[3] // Set VCC to 00011111
    andi    $11, vGeomMid, G_AMBOCCLUSION >> 8
    bnez    $11, @@skip_zero_ao
     andi   laL2A, vGeomMid, G_LIGHTTOALPHA >> 8
    vmrg    aParam, aParam, $v31[2] // 0
@@skip_zero_ao:
    jal     while_wait_dma_busy
     andi   laTexgen, vGeomMid, G_TEXTURE_GEN >> 8
    ldv     vpMdl[0], (VTX_IN_OB + 1 * inputVtxSize)(laPtr) // Vtx 2 Model pos + PN
    ldv     vpMdl[8], (VTX_IN_OB + 0 * inputVtxSize)(laPtr) // Vtx 1 Model pos + PN
align_with_warning 8, "One instruction of padding before ltadv_vtx_loop"
ltadv_vtx_loop: // Even instruction
    vmudm   $v29, aPNScl, vpMdl[3h] // Packed normals from elem 3,7 of model pos
    lw      $11,     (VTX_IN_CN + 1 * inputVtxSize)(laPtr) // Vtx 2 RGBA
    vmadn   vpNrmlY, $v31, $v31[2] // 0; load lower (vpMdl unsigned but must be T operand)
    lw      laSTKept,(VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 1 ST
    vand    vpNrmlX, vpMdl, aPNScl[3] // 0xF800; X component masked in elem 3, 7
    jal     ltadv_xfrm
     sw     $11,     (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2 RGBA -> Vtx 1 ST
    vmadn   vpWrlF, vMTX3F, vOne // Finish vertex pos transform
    vmadh   vpWrlI, vMTX3I, vOne
    andi    laPacked, vGeomMid, G_PACKED_NORMALS >> 8
// aOAFrs <- vpST
    vsub    aOAFrs, vpRGBA, $v31[7]  // 0x7FFF; offset alpha elems 3, 7
    luv     vpLtTot, (ltBufOfs + 0)(curLight) // Total light level, init to ambient
    vne     $v29, $v31, $v31[0h] // Set VCC to 01110111
    beqz    laPacked, @@skip_packed_normals
     lpv    vpMdl,  (VTX_IN_TC + 0 * inputVtxSize)(laPtr) // Vtx 2:1 regular normals
    vmrg    vpMdl, vpNrmlY, vpNrmlX[3h] // Masked X to 0, 4; multiplied Y, Z in 1, 2, 5, 6
@@skip_packed_normals:
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    jal     ltadv_xfrm
// aAOF2 <- aDOT
     vmadm  aAOF2, aOAFrs, aParam[0] // + (alpha - 1) * aoAmb factor; elems 3, 7
// aLTC <- vpMdl
    vmulf   vpLtTot, vpLtTot, aAOF2[3h] // light color *= ambient factor
// aDOT <- aAOF2
    vmudn   $v29, aDPosF, aNrmSc[0h] // Vec frac * int scaling, discard result
// aDIR <- aDPosF
    addi    laPtr, laPtr, 2 * inputVtxSize
    vmadm   $v29, aDPosI, aNrmSc[1h] // Vec int * frac scaling, discard result
    addi    laVtxLeft, laVtxLeft, -2 * inputVtxSize
// vpWNrm <- vpNrmlX
    vmadh   vpWNrm, aDPosI, aNrmSc[0h] // Vec int * int scaling
    sll     laSpecular, vGeomMid, (31 - 5) // G_LIGHTING_SPECULAR to sign bit
    vmudn   vpWrlF, vpWrlF, $v31[1] // -1; negate world pos so add light/cam pos to it
    andi    laSpecFres, vGeomMid, (G_LIGHTING_SPECULAR | G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vmadh   vpWrlI, vpWrlI, $v31[1] // -1

.if CFG_DEBUG_NORMALS
    vmudh   $v29, vOne, $v31[5] // 0x4000; middle gray
    li      laTexgen, 0
    vmacf   vpRGBA, vpWNrm, $v31[5] // 0x4000; + 0.5 * normal
ltadv_finish_light:
ltadv_loop:
ltadv_normals_to_regs:
ltadv_specular:
.else

ltadv_normals_to_regs:
    vmudh   vpNrmlY, vOne, vpWNrm[1h] // Move normals to separate registers
    bnez    laSpecFres, ltadv_spec_fres_setup
     vmudh  vpNrmlZ, vOne, vpWNrm[2h] // per component, in elems 0-3, 4-7
// vpNrmlX <- vpWNrm
// aAOF <- aDPosI
align_with_warning 8, "One instruction of padding before ltadv_loop"
ltadv_loop: // Even instruction
    vmudh   $v29, vOne, $v31[7] // Load accum mid with 0x7FFF (1 in s.15)
    lbu     $11,     (ltBufOfs + 3 - lightSize)(curLight) // Light type / constant attenuation
    vmadm   aAOF, aOAFrs, aParam[1] // + (alpha - 1) * aoDir factor; elems 3, 7
    beq     curLight, altBaseReg, ltadv_post
     lpv    aDOT[0], (ltBufOfs + 8 - lightSize)(curLight) // Light or lookat 0 dir in elems 0-2
    bnez    $11, ltadv_point
     luv    aLTC,    (ltBufOfs + 0 - lightSize)(curLight) // Light color
    // vnop
    vmulf   $v29, vpNrmlX, aDOT[0]
    vmacf   $v29, vpNrmlY, aDOT[1]
    bltzal  laSpecular, ltadv_specular
     vmacf  aDOT, vpNrmlZ, aDOT[2]
    // vnop; vnop
ltadv_finish_light:
    vmulf   aLTC, aLTC, aAOF[3h] // light color *= dir or point light factor
    vge     aDOT, aDOT, $v31[2] // 0; clamp dot product to >= 0
    addi    curLight, curLight, -lightSize
    vmudh   $v29, vOne, vpLtTot // Load accum mid with current light level
    j       ltadv_loop
     // vnop; vnop
     vmacf  vpLtTot, aLTC, aDOT[0h] // + light color * dot product

ltadv_specular: // aDOT in/out, uses vpLtTot[3] and $11 as temps
    lb      $11, (ltBufOfs + 0xF - lightSize)(curLight) // Light size factor
    // nop; nop
    mtc2    $11, vpLtTot[6]        // Light size factor in elem 3 as temp
    vxor    aDOT, aDOT, $v31[7]    // = 0x7FFF - dot product
    // vnop; vnop; vnop
    vmudh   aDOT, aDOT, vpLtTot[3] // * size factor
    jr      $ra
     // vnop; vnop; vnop
     vxor   aDOT, aDOT, $v31[7]    // = 0x7FFF - result
     // land then one vnop before vmulf; replaces two vnops if not specular

.align 8
ltadv_post:
// aClOut <- vpWrlF
// aAlOut <- vpWrlI
// vpMdl <- aLTC
    vge     aAOF, vpLtTot, vpLtTot[1h] // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    ldv     vpMdl[0], (VTX_IN_OB + 1 * inputVtxSize)(laPtr) // Vtx 2 Model pos + PN
    vmulf   aClOut, vpRGBA, vpLtTot    // RGB output is RGB * light
    beqz    laL2A, @@skip_cel
     vcopy  aAlOut, vpRGBA             // Alpha output = vertex alpha (only 3, 7 matter)
    // Cel: alpha = max of light components, RGB = vertex color
    vge     aAOF, aAOF, aAOF[2h]       // elem 0 = max(R0, G0, B0); equiv for elem 4
    vcopy   aClOut, vpRGBA             // RGB output is vertex color
    vmudh   aAlOut, vOne, aAOF[0h]     // move light level elem 0, 4 to 3, 7
@@skip_cel:
    vne     $v29, $v31, $v31[3h]       // Set VCC to 11101110
    bnez    laPacked, @@skip_novtxcolor
     andi   $11, vGeomMid, (G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    vcopy   aClOut, vpLtTot            // If no packed normals, base output is just light
@@skip_novtxcolor:
    vmrg    vpRGBA, aClOut, aAlOut     // Merge base output and alpha output
    beqz    $11, ltadv_skip_fresnel
     ldv    vpMdl[8], (VTX_IN_OB + 0 * inputVtxSize)(laPtr) // Vtx 1 Model pos + PN
    lsv     aAOF[0], (vTRC_0100_addr - altBase)(altBaseReg) // Load constant 0x0100 to temp
    vabs    aOAFrs, aOAFrs, aOAFrs     // Fresnel dot in aOAFrs[0h]; absolute value for underwater
    andi    $11, vGeomMid, G_FRESNEL_COLOR >> 8
    vmudh   $v29, vOne, aParam[7]      // Fresnel offset
    // vnop; vnop
    vmacf   aOAFrs, aOAFrs, aParam[6]  // + factor * scale
    beqz    $11, @@skip
     // vnop; vnop; vnop
     vmudh  aOAFrs, aOAFrs, aAOF[0]    // Result * 0x0100, clamped to 0x7FFF
    veq     $v29, $v31, $v31[3h]       // Set VCC to 00010001 if G_FRESNEL_COLOR
@@skip:
    // vnop; vnop
    vmrg    vpRGBA, vpRGBA, aOAFrs[0h] // Replace color or alpha with fresnel
    // vnop; vnop; vnop
    vge     vpRGBA, vpRGBA, $v31[2]    // Clamp to >= 0 for fresnel; doesn't affect others
    // vnop; vnop

.endif // CFG_DEBUG_NORMALS

ltadv_skip_fresnel:
    beqz    laTexgen, ltadv_after_texgen
     suv    vpRGBA,   (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Vtx 2:1 RGBA
// Texgen: aDOT still contains lookat 0 in elems 0-2, lookat 1 in elems 4-6
// vpST <- aOAFrs
    texgen_dots aDOT, aLkDt0, aLkDt1
    texgen_body aDOT, aLkDt0, aLkDt1, 0h, ltadv_texgen_end
    texgen_lastinstr aLkDt0, aLkDt1
ltadv_texgen_end:  // Vtx 2 ST in vpST elem 0, 1; vtx 1 ST in vpST elem 4, 5
    slv     vpST[8],  (tempVtx1ST)(rdpCmdBufEndP1) // Vtx 1 ST
    bltz    laVtxLeft, ltadv_after_texgen  // Only vtx 1 is valid, don't write vtx 2
     lw     laSTKept, (tempVtx1ST)(rdpCmdBufEndP1) // Overwrite stored Vtx 1 ST
    slv     vpST[0],  (VTX_IN_TC - 1 * inputVtxSize)(laPtr) // Vtx 2 ST
ltadv_after_texgen:
    lw      $11,      (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Vtx 2 RGBA from vtx 1 ST slot
    bltz    laVtxLeft, vtx_setup_no_lighting
     sw     laSTKept, (VTX_IN_TC - 2 * inputVtxSize)(laPtr) // Restore vtx 1 ST
ltadv_vtx_loop_end:
    bgtz    laVtxLeft, ltadv_vtx_loop
     sw     $11,      (VTX_IN_CN - 1 * inputVtxSize)(laPtr) // Real vtx 2 RGBA
    j       vtx_setup_no_lighting
     // Delay slot is OK
    
ltadv_point:
    /*
    Input vector 1 elem size 7FFF.0000 -> len^2 3FFF0001 -> 1/len 0001.0040 -> vec +801E.FFC0 -> clamped 7FFF
        len^2 * 1/len = 400E.FFC1 so about half actual length
    Input vector 1 elem size 0100.0000 -> len^2 00010000 -> 1/len 007F.FFC0 -> vec  7FFF.C000 -> clamped 7FFF
        len^2 * 1/len = 007F.FFC0 so about half actual length
    Input vector 1 elem size 0010.0000 -> len^2 00000100 -> 1/len 07FF.FC00 -> vec  7FFF.C000
    Input vector 1 elem size 0001.0000 -> len^2 00000001 -> 1/len 7FFF.C000 -> vec  7FFF.C000
    */
// aDPosI <- aAOF
    ldv     aDPosI[0], (ltBufOfs + 8 - lightSize)(curLight) // Light position int part 0-3
    ldv     aDPosI[8], (ltBufOfs + 8 - lightSize)(curLight) // 4-7
    lbu     $10,     (ltBufOfs + 7 - lightSize)(curLight) // PL: Linear factor
    // vnop; vnop
    lbu     $24,     (ltBufOfs + 0xE - lightSize)(curLight) // PL: Quadratic factor
ltadv_normal_to_vertex:
    vadd    aDPosI, aDPosI, vpWrlI     // Not using aDPosF; frac part is just vpWrlF
    // vnop; vnop; vnop
ltadv_normalize: // Normalize vector in aDPosI:vpWrlF i/f
    vmudm   $v29, aDPosI, vpWrlF       // Squared. Don't care about frac*frac term
    sll     $11, $11, 8                // Constant factor, 00000100 - 0000FF00
    vmadn   $v29, vpWrlF, aDPosI
    sll     $10, $10, 6                // Linear factor, 00000040 - 00003FC0
    vmadh   $v29, aDPosI, aDPosI
    mtc2    $11, aNrmSc[4]             // Constant frac part in elem 2
// aLen2F <- aLTC
    vreadacc aLen2F, ACC_MIDDLE
    mtc2    $10, aNrmSc[6]             // Linear frac part in elem 3
    vreadacc aLen2I, ACC_UPPER
    srl     $11, $24, 5                // Top 3 bits
    // vnop; vnop
    vmudm   $v29, vOne, aLen2F[2h]     // Sum of squared components
    andi    $10, $24, 0x1F             // Bottom 5 bits
    vmadh   $v29, vOne, aLen2I[2h]
    ori     $10, $10, 0x20             // Append leading 1 to mantissa
    vmadm   $v29, vOne, aLen2F[1h]
    sllv    $10, $10, $11              // Left shift to create floating point
    vmadh   $v29, vOne, aLen2I[1h]
    sll     $10, $10, 8 // Min range 00002000, 00002100... 00003F00, max 00100000...001F8000
    vmadn   aLen2F, aLen2F, vOne       // elem 0; swapped so we can do vmadn and get result
    bnez    $24, @@skip // If original value is zero, set to zero
     vmadh  aLen2I, aLen2I, vOne
    li      $10, 0
@@skip:
    // vnop; vnop
// aRcpLn <- $v29
    vrsqh   aRcpLn[2], aLen2I[0]       // High input, garbage output
    vrsql   aRcpLn[1], aLen2F[0]       // Low input, low output
    mtc2    $10, aNrmSc[12]            // Quadratic frac part in elem 6
    vrsqh   aRcpLn[0], aLen2I[4]       // High input, high output
    srl     $10, $10, 16
    vrsql   aRcpLn[5], aLen2F[4]       // Low input, low output
    beq     laPtr, inVtx, ltadv_continue_setup // Return aRcpLn; cond works only iter 0
     vrsqh  aRcpLn[4], $v31[2]         // 0 input, high output
    // vnop; vnop; vnop
    vmudn   aDIR, vpWrlF, aRcpLn[0h]   // Vec frac * int scaling, discard result
    mtc2    $10, aNrmSc[14]            // Quadratic int part in elem 7
    vmadm   aDIR, aDPosI, aRcpLn[1h]   // Vec int * frac scaling, discard result
    vmadh   aDIR, aDPosI, aRcpLn[0h]   // Vec int * int scaling
// aLenF <- aDPosI
    vmudm   aLenF, aLen2I, aRcpLn[1h]  // len^2 int * 1/len frac; ignoring frac*frac
    vmadn   aLenF, aLen2F, aRcpLn[0h]  // len^2 frac * 1/len int = len frac
// aLenI <- aRcpLn
    vmadh   aLenI, aLen2I, aRcpLn[0h]  // len^2 int * 1/len int = len int
    vmulf   aDOT, vpNrmlX, aDIR[0h]    // Normalized light dir * normalized normals
    vmacf   aDOT, vpNrmlY, aDIR[1h]
    bnez    laSpecFres, ltadv_after_camera  // Return if initial spec/fres; returns aDOT, aDIR
     vmacf  aDOT, vpNrmlZ, aDIR[2h]
// $v29 <- aLenI
    vmudm   $v29, aLenI,  aNrmSc[3]    //   len int * linear factor frac
    vmadl   $v29, aLenF,  aNrmSc[3]    // + len frac * linear factor frac
    vmadm   $v29, vOne,   aNrmSc[2]    // + 1 * constant factor frac
    vmadl   $v29, aLen2F, aNrmSc[6]    // + len^2 frac * quadratic factor frac
    vmadm   $v29, aLen2I, aNrmSc[6]    // + len^2 int * quadratic factor frac
// aPLFcF <- aLen2F
    vmadn   aPLFcF, aLen2F, aNrmSc[7]  // + len^2 frac * quadratic factor int = aPLFcF frac
    bltzal  laSpecular, ltadv_specular
// aPLFcI <- aLen2I
     vmadh  aPLFcI, aLen2I, aNrmSc[7]  // + len^2 int * quadratic factor int  = aLen2I int
// aAOF <- aLenF
    vmudh   aAOF, vOne, $v31[7]        // Load accum mid with 0x7FFF (1 in s.15)
    vmadm   aAOF, aOAFrs, aParam[2]    // + (alpha - 1) * aoPoint factor; elems 3, 7
    // vnop
// aDotSc <- aDIR
    vrcph   aDotSc[1], aPLFcI[0]       // 1/(2*light factor), input of 0000.8000 -> no change normals
    vrcpl   aDotSc[2], aPLFcF[0]       // Light factor 0001.0000 -> normals /= 2
    vrcph   aDotSc[3], aPLFcI[4]       // Light factor 0000.1000 -> normals *= 8 (with clamping)
// aLen2I <- aPLFcI
    vrcpl   aDotSc[6], aPLFcF[4]       // Light factor 0010.0000 -> normals /= 32
    vrcph   aDotSc[7], $v31[2]         // 0
// aLTC <- aPLFcF
    luv     aLTC,    (ltBufOfs + 0 - lightSize)(curLight) // aLTC = light color
    // vnop; vnop; vnop
    // This is a scale on the dot product, not the light, because the scale can
    // increase a small dot product (close to perpendicular), while it can't
    // increase a light beyond white.
    vmudm   $v29, aDOT, aDotSc[2h]     // Dot product int * scale frac
    j       ltadv_finish_light         // Returns aLTC, aAOF, aDOT
     vmadh  aDOT, aDOT, aDotSc[3h]     // Dot product int * scale int, clamp to 0x7FFF
     // vnop
     // aDIR <- aDotSc

/*
    ltadv per vertex pair up to light loop: 36
    ltadv per vertex pair last loop iter: 4
    ltadv per vertex pair after to next vtx pair, no packed normals: 23
total ltadv per vertex pair: 63
light loop directional: 18
    light loop point through jump: 6
    point: 64
    light loop point after return: 7
total point: 77
*/

ovl4_end:
.align 8
ovl4_padded_end:

.close // CODE_FILE
