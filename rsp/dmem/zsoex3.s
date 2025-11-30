
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

// These two words are texrectState in S2DEX, so it can clobber them.
textureSettings1:
    .dw 0x00000000 // first word, has command byte, level, tile, and on
textureSettings2:
    .dw 0xFFFFFFFF // second word, has s and t scale
    
// This word is rdpHalf1Val in S2DEX, so it can clobber it.
fogFactor:
    .dw 0x00000000

yieldOrigV1Addr:
    .skip 2  // Needs to be saved over yield
    
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
    .dh 0x7F00 // used in fog
    .dh 0x7FFF // used often

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
See cpu/occlusionplane.c for more information.
Vertex is in occlusion region if all five equations below are true:
4 * screenX[s13.2] * c0[s0.15] - 0.5 * screenY[s13.2] < c4[s14.1]
4 * screenY[s13.2] * c1[s0.15] - 0.5 * screenX[s13.2] < c5[s14.1]
4 * screenX[s13.2] * c2[s0.15] + 0.5 * screenY[s13.2] < c6[s14.1]
4 * screenY[s13.2] * c3[s0.15] + 0.5 * screenX[s13.2] < c7[s14.1]
      clamp_to_0.s15(clipX[s15.16] * kx[s0.15])
    + clamp_to_0.s15(clipY[s15.16] * ky[s0.15])
    + clamp_to_0.s15(clipZ[s15.16] * kz[s0.15])
    >= kc[s0.15]
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
    .dh 0x7FFF // kc

// Alternate base address because vector load offsets can't reach all of DMEM.
// altBaseReg permanently points here.
.if (. & 15) != 0
    .error "Wrong alignment for altBase"
.endif
altBase:

// constants for register vTRC
.if (. & 15) != 0
    .error "Wrong alignment for vTRCValue"
.endif
vTRCValue:
decalFixMult equ 0x0400
decalFixOff equ (-(decalFixMult / 2))
    .dh vertexBuffer // around 0x300; for converting vertex index to address
    .dh vtxSize << 7 // 0x1300; it's not 0x2600 because vertex indices are *2
    .dh 0x7E00 // vertex index mask for snake
    .dh decalFixMult // defined above
    .dh decalFixOff  // negative
    .dh 0x0020 // used in tri write and vtx addr manip
    .dh 0x0100 // used several times in tri write
    .dh 0x1000 // some multiplier in tri write, vtx addr manip
.macro set_vcc_11110001
    vge    $v29, vTRC, vTRC[0]
.endmacro
.if (vertexBuffer <= 0x0100 || decalFixMult < vertexBuffer)
    .error "VCC pattern for vTRC corrupted"
.endif
vTRC_VB   equ vTRC[0] // Vertex Buffer
vTRC_VS   equ vTRC[1] // Vertex Size
vTRC_7E00 equ vTRC[2]
vTRC_DM   equ vTRC[3] // Decal Multiplier
vTRC_DO   equ vTRC[4] // Decal Offset
vTRC_0020 equ vTRC[5]
vTRC_0100 equ vTRC[6]
vTRC_1000 equ vTRC[7]
vTRC_0100_addr equ (vTRCValue + 2 * 6)

.if (. & 15) != 0
    .error "Wrong alignment for fxParams"
.endif
fxParams:
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

.if (. - fxParams) != 0x1A
    .error "Update fxParams MWO in GBI"
.endif

packedNormalsMaskConstant:
    .db 0xF8 // When read, materialCullMode has been zeroed, so read as 0xF800
materialCullMode:
    .db 0
    
geometryModeLabel:
    .dw 0x00000000

movewordTable:
    .dh fxParams           // G_MW_FX
    .dh numLightsxSize - 3 // G_MW_NUMLIGHT; writes numLightsxSize and pointLightFlag, zeroes dirLightsXfrmValid
packedNormalsConstants:
.if (. & 3) != 0
    .error "Alignment broken for packed normals constants in movewordTable"
.endif
    .dh 0x2008             // For packed normals; unused in movewordTable
.if (segmentTable & 0xFF00) != 0
    .error "Packed normals constants relies on first byte of segmentTable addr being 0"
.endif
    .dh segmentTable       // G_MW_SEGMENT
    .dh fogFactor          // G_MW_FOG
    .dh lightBufferMain    // G_MW_LIGHTCOL

// First half of RDP value for split commands. Also used as temp storage for
// tri vertices during tri commands.
rdpHalf1Val:
    .fill 4

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
miniTableEntry G_TEXRECT_handler // G_TEXRECT
miniTableEntry G_TEXRECT_handler // G_TEXRECTFLIP
miniTableEntry G_RDP_handler // G_RDPLOADSYNC
miniTableEntry G_RDP_handler // G_RDPPIPESYNC
miniTableEntry G_RDP_handler // G_RDPTILESYNC
miniTableEntry G_RDP_handler // G_RDPFULLSYNC
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
miniTableEntry G_RDP_handler // G_NOOP
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


VERTEX_BUFFER_SIZE_BYTES equ (G_MAX_VERTS * vtxSize)

RDP_CMD_BUFSIZE equ 0xB0
RDP_CMD_BUFSIZE_EXCESS equ 0xB0 // Maximum size of an RDP triangle command
RDP_CMD_BUFSIZE_TOTAL equ (RDP_CMD_BUFSIZE + RDP_CMD_BUFSIZE_EXCESS)

INPUT_BUFFER_CMDS equ 21
INPUT_BUFFER_SIZE_BYTES equ (INPUT_BUFFER_CMDS * 8)

OSTASK_ORIG_SIZE equ 0x40 // First CLIP_POLY_SIZE_BYTES (0x10) of this is clipPoly.

END_VARIABLE_LEN_DMEM equ (0x1000 - OSTASK_ORIG_SIZE - INPUT_BUFFER_SIZE_BYTES - (2 * RDP_CMD_BUFSIZE_TOTAL) - VERTEX_BUFFER_SIZE_BYTES)

startFreeDmem:
.org END_VARIABLE_LEN_DMEM
endFreeDmem:

// Main vertex buffer in RSP internal format
vertexBuffer:
    .skip VERTEX_BUFFER_SIZE_BYTES
    
// Round up to 0x8
.org ((clipTempVerts + 0x7) & 0xFF8)
   
texrectState:
    .skip 8  // Only needs to be saved over texrect, half1, half2; but yield can happen

// Round up to 0x10
.org ((texrectState + 0xF) & 0xFF0)

tempMatrix:
    .skip 0x40

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
inputBufferEndSgn equ (-(0x1000 - inputBufferEnd)) // Underflow DMEM address
// 0x0FC0-0x1000: OSTask; 0x0FC0-0x0FD0: clipPoly
OSTask:
// rest of OSTask
    .skip (OSTASK_ORIG_SIZE)

.if . != 0x1000
    .error "DMEM organization incorrect"
.endif

.close // DATA_FILE

// See rsp_defs.inc about why these are not used and we can reuse them.
startCounterTime equ (OSTask + OSTask_ucode_size)
xfrmLookatDirs equ -(0x1000 - (OSTask + OSTask_ucode_data)) // and OSTask_ucode_data_size
dumpDmemBuffer equ (OSTask + OSTask_yield_data_size) // CFG_PROFILING_B only
startFifoStallTime equ dumpDmemBuffer // CFG_PROFILING_A only

memsetBufferStart equ ((vertexBuffer + 0xF) & 0xFF0)
memsetBufferMaxEnd equ (rdpCmdBuffer1 & 0xFF0)
memsetBufferMaxSize equ (memsetBufferMaxEnd - memsetBufferStart)
memsetBufferSize equ (memsetBufferMaxSize > 0x800 ? 0x800 : memsetBufferMaxSize)
