.rsp

.include "rsp/rsp_defs.inc"
.include "rsp/gbi.inc"

// This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

// Not-application-specific global registers
vZero equ $v0
vOne equ $v1

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
.macro vcopy, dst, src
    vadd dst, src, vZero[0]
.endmacro

.macro vclr, dst
    vxor dst, dst, dst
.endmacro

ACC_UPPER equ 0
ACC_MIDDLE equ 1
ACC_LOWER equ 2
.macro vreadacc, dst, N
    vsar dst, dst, dst[N]
.endmacro

// There are two different memory spaces for the overlays: (a) IMEM and (b) the
// microcode file (which, plus an offset, is also the location in DRAM).
// 
// A label marks both an IMEM addresses and a file address, but evaluating the
// label in an integer context (e.g. in a branch) gives the IMEM address.
// `orga(your_label)` gets the file address of the label.
// The IMEM address can be set with `.headersize desired_imem_addr - orga()`.
// The file address can be set with `.org`.
// 
// In IMEM, the whole microcode is organized as (each row is the same address):
// 
// start               Overlay 0          Overlay 1
// (initialization)    (End task)         (More cmd handlers)
// 
// Many command
// handlers
// 
// Overlay 2           Overlay 3
// (Lighting)          (Clipping)
// 
// Vertex and
// tri handlers
// 
// DMA code
//
// In the file, the microcode is organized as:
// start
// Many command handlers
// Overlay 3
// Vertex and tri handlers
// DMA code
// Overlay 0
// Overlay 1
// Overlay 2

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
    
// Not global names, but used multiple times with the same meaning.
// Matrix row X integer/fractional
mxr0i equ $v8
mxr1i equ $v9
mxr2i equ $v10
mxr3i equ $v11
mxr0f equ $v12
mxr1f equ $v13
mxr2f equ $v14
mxr3f equ $v15

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
.if (UCODE_IS_F3DEX2_204H) // F3DEX2 2.04H puts an extra 0x0A before the name
    .db 0x0A
.endif
    .ascii NAME, 0x0A

.align 16

// Base address for RSP effects DMEM region (see discussion in lighting below).
// Could pick a better name, basically a global fixed DMEM pointer used with
// fixed offsets to things in this region. Perhaps had to do with DMEM overlays
// at some point in development.
spFxBase:
spFxBaseReg equ $13

// 0x0180-0x1B0: clipping values
clipRatio:
    .dw 0x00010000
G_MWO_CLIP_RNX:
    .dw 0x00000002
    .dw 0x00000001
G_MWO_CLIP_RNY:
    .dw 0x00000002
    .dw 0x00010000
G_MWO_CLIP_RPX:
    .dw 0x0000FFFE
    .dw 0x00000001
G_MWO_CLIP_RPY:
    .dw 0x0000FFFE
    .dw 0x00000000
    .dw 0x0001FFFF
    .dw 0x00000000
.if NoN == 1
    .dw 0x00000001 // No Nearclipping
.else
    .dw 0x00010001 // Nearclipping
.endif

// 0x1B0: constants for register $v31
.align 0x10 // loaded with lqv
v31Value:
    .dh 0xFFFF // 65535
    .dh 0x0004 // 4
    .dh 0x0008 // 8
    .dh 0x7F00 // 32512
    .dh 0xFFFC // 65532
    .dh 0x4000 // 16384
    .dh 0x0420 // 1056
    .dh 0x7FFF // 32767

// 0x1C0: constants for register $v30
.align 0x10 // loaded with lqv
v30Value:
    .dh 0x7FFC
    .dh 0x1400
.if (UCODE_IS_206_OR_OLDER)
    .dh 0x01CC
    .dh 0x0200
    .dh 0xFFF0
    .dh 0x0010
    .dh 0x0020
    .dh 0x0100
.else
    .dh 0x1000
    .dh 0x0100
    .dh 0xFFF0
    .dh 0xFFF8
    .dh 0x0010
    .dh 0x0020
.endif

.align 0x10 // loaded with lqv
linearGenerateCoefficients:
    .dh 0xC000
    .dh 0x44D3
    .dh 0x6CB3
    .dh 0x0002

// 0x01D8
    .db 0x00 // Padding to allow mvpValid to be written to as a 32-bit word
mvpValid:
    .db 0x01

// 0x01DA
    .dh 0x0000 // Shared padding to allow mvpValid (probably lightsValid?) and
               // numLightsx18 to both be written to as 32-bit words for moveword

// 0x01DC
lightsValid:   // Gets overwritten with 0 when numLights is written with moveword.
    .db 1
numLightsx18:
    .db 0

    .db 11
    .db 7 * 0x18

// 0x01E0
fogFactor:
    .dw 0x00000000

// 0x01E4
textureSettings1:
    .dw 0x00000000 // first word, has command byte, bowtie val, level, tile, and on

// 0x01E8
textureSettings2:
    .dw 0x00000000 // second word, has s and t scale

// 0x01EC
geometryModeLabel:
    .dw G_CLIPPING

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
// (does not affect the result). Once there is one point light, the rest (until
// ambient) are also assumed to be point lights.
lightBufferMain:
    .fill (8 * lightSize)
// Code uses pointers relative to spFxBase, with immediate offsets, so that
// another register isn't needed to store the start or end address of the array.
curLight    equ $9 // With ltBufOfs immediate added, points to current light
                   // (current max in list, counting down).
tmpCurLight equ $6 // Same meaning, another register.
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

// 0x02F0-0x02FE: Movemem table
movememTable:
    .dh tempMatrix        // G_MTX multiply temp matrix (model)
    .dh mvMatrix          // G_MV_MMTX
    .dh tempMatrix        // G_MTX multiply temp matrix (projection)
    .dh pMatrix           // G_MV_PMTX
    .dh viewport          // G_MV_VIEWPORT
    .dh lightBufferLookat // G_MV_LIGHT
    .dh vertexBuffer      // G_MV_POINT
// Further entries in the movemem table come from the moveword table

// 0x02FE-0x030E: moveword table
movewordTable:
    .dh mvpMatrix        // G_MW_MATRIX
    .dh numLightsx18 - 3 // G_MW_NUMLIGHT
    .dh clipRatio        // G_MW_CLIP
    .dh segmentTable     // G_MW_SEGMENT
    .dh fogFactor        // G_MW_FOG
    .dh lightBufferMain  // G_MW_LIGHTCOL
    .dh mvpValid - 1     // G_MW_FORCEMTX
    .dh perspNorm - 2    // G_MW_PERSPNORM

// 0x030E-0x0314: G_POPMTX, G_MTX, G_MOVEMEM Command Jump Table
movememHandlerTable:
jumpTableEntry G_POPMTX_end   // G_POPMTX
jumpTableEntry G_MTX_end      // G_MTX (multiply)
jumpTableEntry G_MOVEMEM_end  // G_MOVEMEM, G_MTX (load)

// 0x0314-0x0370: RDP/Immediate Command Jump Table
jumpTableEntry G_SPECIAL_3_handler
jumpTableEntry G_SPECIAL_2_handler
jumpTableEntry G_SPECIAL_1_handler
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
jumpTableEntry G_SYNC_handler    // G_RDPLOADSYNC
jumpTableEntry G_SYNC_handler    // G_RDPPIPESYNC
jumpTableEntry G_SYNC_handler    // G_RDPTILESYNC
jumpTableEntry G_SYNC_handler    // G_RDPFULLSYNC
jumpTableEntry G_RDP_handler     // G_SETKEYGB
jumpTableEntry G_RDP_handler     // G_SETKEYR
jumpTableEntry G_RDP_handler     // G_SETCONVERT
jumpTableEntry G_SETSCISSOR_handler
jumpTableEntry G_RDP_handler     // G_SETPRIMDEPTH
jumpTableEntry G_RDPSETOTHERMODE_handler
jumpTableEntry G_RDP_handler     // G_LOADTLUT
jumpTableEntry G_RDPHALF_2_handler
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

// 0x0370-0x0380: DMA Command Jump Table
jumpTableEntry G_VTX_handler
jumpTableEntry G_MODIFYVTX_handler
jumpTableEntry G_CULLDL_handler
jumpTableEntry G_BRANCH_WZ_handler // different for F3DZEX
jumpTableEntry G_TRI1_handler
jumpTableEntry G_TRI2_handler
jumpTableEntry G_QUAD_handler
jumpTableEntry G_LINE3D_handler

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
cullFaceValues:
    .dh 0xFFFF
    .dh 0x8000
    .dh 0x0000
    .dh 0x0000
    .dh 0x8000

nearclipValue:
.if NoN == 1
    .dw 0x30304080 // No Nearclipping
.else
    .dw 0x30304040 // Nearclipping
.endif

lbl_03D0:
    .dw 0x00000000
    .dw 0x00000000
    .dw 0x00000000
    .dw 0x00000000

    .dw 0x00000000
    .dw 0x00000000
    .dw 0x00000000
    .dw 0x00000000

    .dw 0x00000000
    .dw 0x00000000

lbl_03F8:
    .dw 0x00100000
    .dw 0x00200000
    .dw 0x10000000
    .dw 0x20000000
    .dw 0x00004000

// 40c
.if NoN == 1
.dw 0x00000080 // No Nearclipping
.else
.dw 0x00000040 // Nearclipping
.endif

// 0x0410-0x0420: Overlay 2/3 table
overlayInfo2:
    OverlayEntry orga(ovl2_start), orga(ovl2_end), ovl2_start
overlayInfo3:
    OverlayEntry orga(ovl3_start), orga(ovl3_end), ovl3_start

// 0x0420-0x0920: Vertex buffer
vertexBuffer:
    .skip (vtxSize * 32) // 32 vertices

// 0x0920-0x09C8: Input buffer
inputBuffer:
inputBufferLength equ 0xA8
    .skip inputBufferLength
inputBufferEnd:

// 0x09C8-0x09D0: ??
    .skip 8

// 0x09D0 - 0x0A10: Temp matrix for G_MTX multiplication mode
tempMatrix:
    .skip 0x40

// 0xA50-0xBA8: ??
.skip 0x198

RDP_CMD_BUFSIZE equ 0x158
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

// Global registers
cmd_w1 equ $24
cmd_w0 equ $25
taskDataPtr equ $26
inputBufferPos equ $27
rdpCmdBufPtr equ $23
rdpCmdBufEnd equ $22

// Initialization routines
// Everything up until displaylist_dma will get overwritten by ovl0 and/or ovl1
start:
.if UCODE_TYPE == TYPE_F3DZEX && UCODE_ID < 2
    vor     vZero, $v16, $v16 // Sets vZero to $v16
.else
    vclr    vZero             // Clear vZero
.endif
    lqv     $v31[0], (v31Value)($zero)
    lqv     $v30[0], (v30Value)($zero)
    li      rdpCmdBufPtr, rdpCmdBuffer1
.if !(UCODE_IS_207_OR_OLDER)
    vadd    vOne, vZero, vZero   // vZero is all 0s, vOne also becomes all 0s
.endif
    li      rdpCmdBufEnd, rdpCmdBuffer1End
    vsub    vOne, vZero, $v31[0]   // Vector of 1s
.if UCODE_METHOD == METHOD_FIFO
    lw      $11, rdpFifoPos
    lw      $12, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // task done and yielded signals
    beqz    $11, task_init
     mtc0   $1, SP_STATUS
    andi    $12, $12, OS_TASK_YIELDED
    beqz    $12, calculate_overlay_addrs    // skip overlay address calculations if resumed from yield?
     sw     $zero, OSTask + OSTask_flags
    j       load_overlay1_init              // Skip the initialization and go straight to loading overlay 1
     lw     taskDataPtr, OS_YIELD_DATA_SIZE - 8
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
.else // UCODE_METHOD == METHOD_XBUS
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
     lw taskDataPtr, OS_YIELD_DATA_SIZE_TOTAL - 8
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
    li      $11, overlayInfo1   // set up loading of overlay 1

.align 8

    jal     load_overlay_and_enter  // load overlay 1 and enter
     move   $12, $ra                // set up the return address, since load_overlay_and_enter returns to $12
    // This return should be such that it coincides with displaylist_dma so no code from overlay 1 is ran, ensure that
    // ovl01_end remains aligned to 8 bytes
ovl01_end:
// Overlays 0 and 1 overwrite everything up to this point (2.08 versions overwrite up to the previous .align 8)

displaylist_dma: // loads inputBufferLength bytes worth of displaylist data via DMA into inputBuffer
    li      $19, inputBufferLength - 1  // set the DMA length
    move    $24, taskDataPtr            // set up the DRAM address to read from
    jal     dma_read_write              // initiate the DMA read
     la     $20, inputBuffer            // set the address to DMA read to
    addiu   taskDataPtr, taskDataPtr, inputBufferLength // increment the DRAM address to read from next time
    li      inputBufferPos, -inputBufferLength          // reset the DL word index
wait_for_dma_and_run_next_command:
G_POPMTX_end:
G_MOVEMEM_end:
    jal     while_wait_dma_busy // wait for the DMA read to finish
G_LINE3D_handler:
G_SPNOOP_handler:
.if !(UCODE_IS_F3DEX2_204H) // F3DEX2 2.04H has this located elsewhere
G_SPECIAL_1_handler:
.endif
G_SPECIAL_2_handler:
G_SPECIAL_3_handler:
run_next_DL_command:
     mfc0   $1, SP_STATUS                               // load the status word into register $1
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // load the command word into cmd_w0
    beqz    inputBufferPos, displaylist_dma             // load more DL commands if none are left
     andi   $1, $1, SP_STATUS_SIG0                      // check if the task should yield
    sra     $12, cmd_w0, 24                             // extract DL command byte from command word
    sll     $11, $12, 1                                 // multiply command byte by 2 to get jump table offset
    lhu     $11, (commandJumpTable)($11)                // get command subroutine address from command jump table
    bnez    $1, load_overlay_0_and_enter                // load and execute overlay 0 if yielding
     lw     cmd_w1, (inputBufferEnd + 4)(inputBufferPos) // load the next DL word into cmd_w1
    jr      $11                                         // jump to the loaded command handler
     addiu  inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words

.if (UCODE_IS_F3DEX2_204H) // Microcodes besides F3DEX2 2.04H have this as a noop
G_SPECIAL_1_handler:    // Seems to be a manual trigger for mvp recalculation
    li      $ra, run_next_DL_command
    li      $21, pMatrix
    li      $20, mvMatrix
    li      $19, mvpMatrix
    j       mtx_multiply
     sb     cmd_w0, mvpValid
.endif

G_DMA_IO_handler:
    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1) to a virtual one
     lh     $20, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    $19, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    // At this point, $20's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra     $20, $20, 2
    j       dma_read_write  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of $20)
     li     $ra, wait_for_dma_and_run_next_command  // Setup the return address for running the next DL command

geometryMode equ $11
G_GEOMETRYMODE_handler:
    lw      geometryMode, geometryModeLabel     // load the geometry mode value
    and     geometryMode, geometryMode, cmd_w0  // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      geometryMode, geometryMode, cmd_w1  // sets the flags in cmd_w1 (set in g*SPSetGeometryMode)
    j       run_next_DL_command                 // run the next DL command
     sw     geometryMode, geometryModeLabel     // update the geometry mode value

dlStackIdx equ $1
G_ENDDL_handler:
    lbu     dlStackIdx, displayListStackLength      // Load the DL stack index
    beqz    dlStackIdx, load_overlay_0_and_enter    // Load overlay 0 if there is no DL return address, to end the graphics task processing
     addi   dlStackIdx, dlStackIdx, -4              // Decrement the DL stack index
    j       f3dzex_ovl1_00001020                    // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)(dlStackIdx) // Load the address of the DL to return to into the taskDataPtr (the current DL address)

G_RDPHALF_2_handler:
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val                 // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
    sdv     $v29[0], (0x400 - 8)(rdpCmdBufPtr)   // move textrectWord1 to lbl_03F8
G_RDP_handler:
    sw      cmd_w1, 4(rdpCmdBufPtr)         // Add the second word of the command to the RDP command buffer
G_SYNC_handler:
G_NOOP_handler:
    sw      cmd_w0, 0(rdpCmdBufPtr)         // Add the command word to the RDP command buffer
    j       check_rdp_buffer_full_and_run_next_cmd
     addi   rdpCmdBufPtr, rdpCmdBufPtr, 8   // Increment the next RDP command pointer by 2 words

G_SETxIMG_handler:
    li      $ra, G_RDP_handler          // Load the RDP command handler into the return address, then fall through to convert the address to virtual
// Converts the segmented address in $24 (also cmd_w1) to the corresponding physical address
segmented_to_physical:
    srl     $11, $24, 22                // Copy (segment index << 2) into $11
    andi    $11, $11, 0x3C              // Clear the bottom 2 bits that remained during the shift
    lw      $11, (segmentTable)($11)    // Get the current address of the segment
    sll     $24, $24, 8                 // Shift the address to the left so that the top 8 bits are shifted out
    srl     $24, $24, 8                 // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr      $ra
     add    $24, $24, $11               // Add the segment's address to the masked input address, resulting in the virtual address

G_RDPSETOTHERMODE_handler:
    sw      cmd_w0, otherMode0  // Record the local otherMode0 copy
    j       G_RDP_handler       // Send the command to the RDP
     sw     cmd_w1, otherMode1  // Record the local otherMode1 copy

G_SETSCISSOR_handler:
    sw      cmd_w0, scissorUpLeft       // Record the local scissorUpleft copy
    j       G_RDP_handler               // Send the command to the RDP
     sw     cmd_w1, scissorBottomRight  // Record the local scissorBottomRight copy

check_rdp_buffer_full_and_run_next_cmd:
    li      $ra, run_next_DL_command    // Set up running the next DL command as the return address

.if UCODE_METHOD == METHOD_FIFO
check_rdp_buffer_full:
     sub    $11, rdpCmdBufPtr, rdpCmdBufEnd
    blez    $11, return_routine         // Return if rdpCmdBufEnd >= rdpCmdBufPtr
flush_rdp_buffer:
     mfc0   $12, SP_DMA_BUSY
    lw      $24, rdpFifoPos
    addiu   $19, $11, RDP_CMD_BUFSIZE
    bnez    $12, flush_rdp_buffer
     lw     $12, OSTask + OSTask_output_buff_size
    mtc0    $24, DPC_END
    add     $11, $24, $19
    sub     $12, $12, $11
    bgez    $12, f3dzex_000012A8
@@await_start_valid:
     mfc0   $11, DPC_STATUS
    andi    $11, $11, DPC_STATUS_START_VALID
    bnez    $11, @@await_start_valid
     lw     $24, OSTask + OSTask_output_buff
f3dzex_00001298:
    mfc0    $11, DPC_CURRENT
    beq     $11, $24, f3dzex_00001298
     nop
    mtc0    $24, DPC_START
f3dzex_000012A8:
    mfc0    $11, DPC_CURRENT
    sub     $11, $11, $24
    blez    $11, f3dzex_000012BC
     sub    $11, $11, $19
    blez    $11, f3dzex_000012A8
f3dzex_000012BC:
     add    $11, $24, $19
    sw      $11, rdpFifoPos
    // Set up the DMA from DMEM to the RDP fifo in RDRAM
    addi    $19, $19, -1                                    // subtract 1 from the length
    addi    $20, rdpCmdBufEnd, -(0x2000 | RDP_CMD_BUFSIZE)  // The 0x2000 is meaningless, negative means write
    xori    rdpCmdBufEnd, rdpCmdBufEnd, rdpCmdBuffer1End ^ rdpCmdBuffer2End // Swap between the two RDP command buffers
    j       dma_read_write
     addi   rdpCmdBufPtr, rdpCmdBufEnd, -RDP_CMD_BUFSIZE
.else // UCODE_METHOD == METHOD_XBUS
check_rdp_buffer_full:
    addi $11, rdpCmdBufPtr, -0xF10
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
     addi $11, $11, -0xB0
    blez $11, ovl0_04001284
     nop
ovl0_0400129C:
    jr $ra
     nop
.endif

.align 8
ovl23_start:

ovl3_start:

// Overlay 3 registers
savedRA equ $30
savedNearclip equ $29

vPairMVPPosI equ $v24
vPairMVPPosF equ $v23
vPairST equ $v22
vPairRGBATemp equ $v7

// Jump here to do lighting. If overlay 3 is loaded (this code), loads and jumps
// to overlay 2 (same address as right here).
ovl23_lighting_entrypoint:
    li      $11, overlayInfo2       // set up a load for overlay 2
    j       load_overlay_and_enter  // load overlay 2
     li     $12, ovl23_lighting_entrypoint  // set the return address

// Jump here to do clipping. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl23_clipping_entrypoint:
    move    savedRA, $ra
ovl3_clipping_nosavera:
    la      $5, 0x0014
    la      $18, 6
    la      $15, inputBufferEnd
    sh      $1, (lbl_03D0 - 6)($18)
    sh      $2, (lbl_03D0 - 6 + 2)($18)
    sh      $3, (lbl_03D0 - 6 + 4)($18)
    sh      $zero, (lbl_03D0)($18)
    lw      savedNearclip, nearclipValue
f3dzex_00001308:
    lw      $9, (lbl_03F8)($5)
    lw      $16, 0x0024($3)
    and     $16, $16, $9
    addi    $17, $18, -6
    xori    $18, $18, 0x1C
    addi    $21, $18, -6
f3dzex_00001320:
    lhu     $2, (lbl_03D0)($17)
    addi    $17, $17, 0x0002
    beqz    $2, f3dzex_000014A8
     lw     $11, 0x0024($2)
    and     $11, $11, $9
    beq     $11, $16, f3dzex_00001494
     move   $16, $11
    beqz    $16, f3dzex_0000134C
     move   $19, $2
    move    $19, $3
    move    $3, $2
f3dzex_0000134C:
    sll     $11, $5, 1
    ldv     $v2[0], 0x0180($11)
    ldv     $v4[0], 0x0008($19)
    ldv     $v5[0], 0x0000($19)
    ldv     $v6[0], 0x0008($3)
    ldv     $v7[0], 0x0000($3)
    vmudh   $v3, $v2, $v31[0]
    vmudn   $v8, $v4, $v2
    vmadh   $v9, $v5, $v2
    vmadn   $v10, $v6, $v3
    vmadh   $v11, $v7, $v3
    vaddc   $v8, $v8, $v8[0q]
    lqv     $v25[0], (linearGenerateCoefficients)($zero)
    vadd    $v9, $v9, $v9[0q]
    vaddc   $v10, $v10, $v10[0q]
    vadd    $v11, $v11, $v11[0q]
    vaddc   $v8, $v8, $v8[1h]
    vadd    $v9, $v9, $v9[1h]
    vaddc   $v10, $v10, $v10[1h]
    vadd    $v11, $v11, $v11[1h]
.if (UCODE_IS_F3DEX2_204H) // Only in F3DEX2 2.04H
    vrcph   $v29[0], $v11[3]
.else
    vor     $v29, $v11, vOne[0]
    vrcph   $v3[3], $v11[3]
.endif
    vrcpl   $v2[3], $v10[3]
    vrcph   $v3[3], vZero[0]
.if (UCODE_IS_F3DEX2_204H) // Only in F3DEX2 2.04H
    vabs    $v29, $v11, $v25[3]
.else
    vabs    $v29, $v29, $v25[3]
.endif
    vmudn   $v2, $v2, $v29[3]
    vmadh   $v3, $v3, $v29[3]
    veq     $v3, $v3, vZero[0]
    vmrg    $v2, $v2, $v31[0]
    vmudl   $v29, $v10, $v2[3]
    vmadm   $v11, $v11, $v2[3]
    vmadn   $v10, vZero, vZero[0]
    vrcph   $v13[3], $v11[3]
    vrcpl   $v12[3], $v10[3]
    vrcph   $v13[3], vZero[0]
    vmudl   $v29, $v12, $v10
    vmadm   $v29, $v13, $v10
    vmadn   $v10, $v12, $v11
    vmadh   $v11, $v13, $v11
    vmudh   $v29, vOne, $v31[1]
    vmadn   $v10, $v10, $v31[4]
    vmadh   $v11, $v11, $v31[4]
    vmudl   $v29, $v12, $v10
    vmadm   $v29, $v13, $v10
    vmadn   $v12, $v12, $v11
    vmadh   $v13, $v13, $v11
    vmudl   $v29, $v8, $v12
    luv     $v26[0], 0x0010($3)
    vmadm   $v29, $v9, $v12
    llv     $v26[8], 0x0014($3)
    vmadn   $v10, $v8, $v13
    luv     $v25[0], 0x0010($19)
    vmadh   $v11, $v9, $v13
    llv     $v25[8], 0x0014($19)
    vmudl   $v29, $v10, $v2[3]
    vmadm   $v11, $v11, $v2[3]
    vmadn   $v10, $v10, vZero[0]
    vlt     $v11, $v11, vOne[0]
    vmrg    $v10, $v10, $v31[0]
    vsubc   $v29, $v10, vOne[0]
    vge     $v11, $v11, vZero[0]
    vmrg    $v10, $v10, vOne[0]
    vmudn   $v2, $v10, $v31[0]
    vmudl   $v29, $v6, $v10[3]
    vmadm   $v29, $v7, $v10[3]
    vmadl   $v29, $v4, $v2[3]
    vmadm   vPairMVPPosI, $v5, $v2[3]
    vmadn   vPairMVPPosF, vZero, vZero[0]
    vmudm   $v29, $v26, $v10[3]
    vmadm   vPairST, $v25, $v2[3]
    li      $7, 0x0000
    li      $1, 0x0002
    sh      $15, (lbl_03D0)($21)
    j       load_spfx_global_values // Goes to load_spfx_global_values, then to vertices_store, then
     li   $ra, vertices_store + 0x8000 // comes back here, via bltz $ra, f3dzex_00001478

outputVtxPos equ $15
f3dzex_00001478:
.if (UCODE_IS_F3DEX2_204H)
    sdv     $v25[0], 0x03C8(outputVtxPos)
.else
    slv     $v25[0], 0x01C8(outputVtxPos)
.endif
    ssv     $v26[4], 0x00CE(outputVtxPos)
    suv     vPairST[0], 0x03C0(outputVtxPos)
    slv     vPairST[8], 0x01C4(outputVtxPos)
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    ssv     $v3[4], 0x00CC(outputVtxPos)
.endif
    addi    outputVtxPos, outputVtxPos, -vtxSize
    addi    $21, $21, 0x0002
f3dzex_00001494:
    bnez    $16, f3dzex_00001320
     move   $3, $2
    sh      $3, (lbl_03D0)($21)
    j       f3dzex_00001320
     addi   $21, $21, 0x0002

f3dzex_000014A8:
    sub     $11, $21, $18
    bltz    $11, f3dzex_000014EC
     sh     $zero, (lbl_03D0)($21)
    lhu     $3, 0x03CE($21)
    bnez    $5, f3dzex_00001308
     addi   $5, $5, -0x0004
    sw      $zero, nearclipValue
f3dzex_000014C4:
.if (UCODE_IS_F3DEX2_204H) // In F3DEX2, $21 counts down instead of $18 counting up
    reg1 equ $21
    val1 equ -0x0002
.else
    reg1 equ $18
    val1 equ 0x0002
.endif
    lhu     $1, 0x03CA($18)
    lhu     $2, 0x03CC(reg1)
    lhu     $3, 0x03CE($21)
    mtc2    $1, $v2[10]
    vor     $v3, vZero, $v31[5]
    mtc2    $2, $v4[12]
    jal     f3dzex_00001A7C
     mtc2   $3, $v2[14]
    bne     $21, $18, f3dzex_000014C4
     addi   reg1, reg1, val1
f3dzex_000014EC:
    jr      savedRA
     sw     savedNearclip, nearclipValue

.align 8

// Leave room for loading overlay 2 if it is larger than overlay 3 (true for f3dzex)
.orga max(ovl2_end - ovl2_start + orga(ovl3_start), orga())
ovl3_end:

ovl23_end:

inputVtxPos equ $14
tempCmdBuf50 equ $8
// See load_spfx_global_values for detailed contents
vFxScaleFMin equ $v16
vFxTransFMax equ $v17
vFxMisc      equ $v18
vFxMask      equ $v19
vFxNegScale  equ $v21

G_VTX_handler:
    lhu     $20, (vertexTable)(cmd_w0)      // Load the address of the provided vertex array
    jal     segmented_to_physical           // Convert the vertex array's segmented address (in $24) to a virtual one
     lhu    $1, (inputBufferEnd - 0x07)(inputBufferPos) // Load the size of the vertex array to copy into reg $1
    sub     $20, $20, $1                    // Calculate the address to DMA the provided vertices into
    jal     dma_read_write                  // DMA read the vertices from DRAM
     addi   $19, $1, -1                     // Set up the DMA length
    lhu     $5, geometryModeLabel           // Load the geometry mode into $5
    srl     $1, $1, 3
    sub     outputVtxPos, cmd_w0, $1
    lhu     outputVtxPos, (vertexTable)(outputVtxPos)
    move    inputVtxPos, $20
    lbu     $8, mvpValid
    andi    tmpCurLight, $5, G_LIGHTING_H  // If no lighting, tmpCurLight is 0, skips transforming light dirs and setting this up as a pointer
    bnez    tmpCurLight, ovl23_lighting_entrypoint // Run overlay 2 for lighting, either directly or via overlay 3 loading overlay 2
     andi   $7, $5, G_FOG_H
after_light_dir_xfrm:
    bnez    $8, vertex_skip_recalc_mvp  // Skip recalculating the mvp matrix if it's already up-to-date
     sll    $7, $7, 3                 // $7 is 8 if G_FOG is set, 0 otherwise
    sb      cmd_w0, mvpValid          // Set mvpValid
    li      $21, pMatrix              // Arguments to mtx_multiply
    li      $20, mvMatrix
    // Calculate the MVP matrix
    jal     mtx_multiply
     li     $19, mvpMatrix

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
    ldv     $v20[0], (inputVtxSize * 0)(inputVtxPos) // load the position of the 1st vertex into v20's lower 8 bytes
    vmov    vFxScaleFMin[5], vFxNegScale[1]          // Finish building vFxScaleFMin
    ldv     $v20[8], (inputVtxSize * 1)(inputVtxPos) // load the position of the 2nd vertex into v20's upper 8 bytes

vertices_process_pair:
    // Two verts pos in v20; multiply by MVP
    vmudn   $v29, mxr3f, vOne[0]
    lw      $11, (inputVtxSize + 0xC)(inputVtxPos) // load the color/normal of the 2nd vertex into $11
    vmadh   $v29, mxr3i, vOne[0]
    llv     vPairST[12], 8(inputVtxPos)            // load the texture coords of the 1st vertex into v22[12-15]
    vmadn   $v29, mxr0f, $v20[0h]
    move    curLight, tmpCurLight
    vmadh   $v29, mxr0i, $v20[0h]
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight)    // First instruction of lights_dircoloraccum2 loop; load light transformed dir
    vmadn   $v29, mxr1f, $v20[1h]
    sw      $11, 8(inputVtxPos)                    // Move the first vertex's colors/normals into the word before the second vertex's
    vmadh   $v29, mxr1i, $v20[1h]
    lpv     vPairRGBATemp[0], 8(inputVtxPos)       // Load both vertex's colors/normals into v7's elements RGBARGBA or XYZAXYZA
    vmadn   vPairMVPPosF, mxr2f, $v20[2h]          // vPairMVPPosF = MVP * vpos result frac
    bnez    tmpCurLight, light_vtx                 // Zero if lighting disabled, pointer if enabled
     vmadh  vPairMVPPosI, mxr2i, $v20[2h]          // vPairMVPPosI = MVP * vpos result int
    // These two instructions are repeated at the end of all the lighting codepaths,
    // since they're skipped here if lighting is being performed
    // This is the original location of INSTR 1 and INSTR 2
    vge     $v27, $v25, $v31[3]                     // INSTR 1: Finishing prev vtx store loop, some sort of clamp Z?
    llv     vPairST[4], (inputVtxSize + 8)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]

vertices_store:
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    vge     $v3, $v25, vZero[0]
.endif
    addi    $1, $1, -4
    vmudl   $v29, vPairMVPPosF, vFxMisc[4] // Persp norm
    sub     $11, tempCmdBuf50, $7
    vmadm   $v2, vPairMVPPosI, vFxMisc[4] // Persp norm
    sbv     $v27[15], -0x0D($11)
    vmadn   $v21, vZero, vZero[0]
    sbv     $v27[7], -0x35($11)
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    vmov    $v26[1], $v3[2]
    ssv     $v3[12], 0x00F4(tempCmdBuf50)
.endif
    vmudn   $v7, vPairMVPPosF, vFxMisc[5] // 0x0002
.if (UCODE_IS_F3DEX2_204H)
    sdv     $v25[8], 0x03F0(tempCmdBuf50)
.else
    slv     $v25[8], 0x01F0(tempCmdBuf50)
.endif
    vmadh   $v6, vPairMVPPosI, vFxMisc[5] // 0x0002
    sdv     $v25[0], 0x03C8(tempCmdBuf50)
    vrcph   $v29[0], $v2[3]
    ssv     $v26[12], 0x0F6(tempCmdBuf50)
    vrcpl   $v5[3], $v21[3]
.if (UCODE_IS_F3DEX2_204H)
    ssv     $v26[4], 0x00CE(tempCmdBuf50)
.else
    slv     $v26[2], 0x01CC(tempCmdBuf50)
.endif
    vrcph   $v4[3], $v2[7]
    ldv     $v3[0], 0x0008(inputVtxPos)  // Load RGBARGBA for two vectors (was stored this way above)
    vrcpl   $v5[7], $v21[7]
    sra     $11, $1, 31
    vrcph   $v4[7], vZero[0]
    andi    $11, $11, 0x0028
    vch     $v29, vPairMVPPosI, vPairMVPPosI[3h]
    addi    outputVtxPos, outputVtxPos, (2 * vtxSize) // Advance two positions forward in the output vertices
    vcl     $v29, vPairMVPPosF, vPairMVPPosF[3h]
    sub     $8, outputVtxPos, $11
    vmudl   $v29, $v21, $v5
    cfc2    $10, $vcc
    vmadm   $v29, $v2, $v5
    sdv     vPairMVPPosF[8], 0x03E0($8)
    vmadn   $v21, $v21, $v4
    ldv     $v20[0], (2 * inputVtxSize)(inputVtxPos) // Load pos of 1st vector on next iteration
    vmadh   $v2, $v2, $v4
    sdv     vPairMVPPosF[0], 0x03B8(outputVtxPos)
    vge     $v29, vPairMVPPosI, vZero[0]
    lsv     vPairMVPPosF[14], 0x00E4($8)
    vmudh   $v29, vOne, $v31[1]
    sdv     vPairMVPPosI[8], 0x03D8($8)
    vmadn   $v26, $v21, $v31[4]
    lsv     vPairMVPPosF[6], 0x00BC(outputVtxPos)
    vmadh   $v25, $v2, $v31[4]
    sdv     vPairMVPPosI[0], 0x03B0(outputVtxPos)
    vmrg    $v2, vZero, $v31[7]
    ldv     $v20[8], (3 * inputVtxSize)(inputVtxPos) // Load pos of 2nd vector on next iteration
    vch     $v29, vPairMVPPosI, $v6[3h]
    slv     $v3[0], 0x01E8($8) // Store RGBA for first vector
    vmudl   $v29, $v26, $v5
    lsv     vPairMVPPosI[14], 0x00DC($8)
    vmadm   $v29, $v25, $v5
    slv     $v3[4], 0x01C0(outputVtxPos) // Store RGBA for second vector
    vmadn   $v5, $v26, $v4
    lsv     vPairMVPPosI[6], 0x00B4(outputVtxPos)
    vmadh   $v4, $v25, $v4
    sh      $10, -0x0002($8)
    vmadh   $v2, $v2, $v31[7]
    sll     $11, $10, 4
    vcl     $v29, vPairMVPPosF, $v7[3h]
    cfc2    $10, $vcc
    vmudl   $v29, vPairMVPPosF, $v5[3h]
    ssv     $v5[14], 0x00FA($8)
    vmadm   $v29, vPairMVPPosI, $v5[3h]
    addi    inputVtxPos, inputVtxPos, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadn   $v26, vPairMVPPosF, $v2[3h]
    sh      $10, -0x0004($8)
    vmadh   $v25, vPairMVPPosI, $v2[3h]
    sll     $10, $10, 4
    vmudm   $v3, vPairST, vFxMisc // Scale ST for two verts, using TexSScl and TexTScl in elems 2, 3, 6, 7
    sh      $11, (0x26 - 2 * vtxSize)(outputVtxPos)
    sh      $10, (0x24 - 2 * vtxSize)(outputVtxPos)
    vmudl   $v29, $v26, vFxMisc[4] // Persp norm
    ssv     $v5[6], 0x00D2(outputVtxPos)
    vmadm   $v25, $v25, vFxMisc[4] // Persp norm
    ssv     $v4[14], 0x00F8($8)
    vmadn   $v26, vZero, vZero[0]
    ssv     $v4[6], 0x00D0(outputVtxPos)
    slv     $v3[4], 0x01EC($8) // Store scaled S, T vertex 1
    vmudh   $v29, vFxTransFMax, vOne[0]
    slv     $v3[12], 0x01C4(outputVtxPos) // Store scaled S, T vertex 2
    vmadh   $v29, vFxMask, $v31[3]
    vmadn   $v26, $v26, vFxScaleFMin
    bgtz    $1, vertices_process_pair
     vmadh  $v25, $v25, vFxScaleFMin
    bltz    $ra, f3dzex_00001478    // has a different version in ovl2
.if !(UCODE_IS_F3DEX2_204H) // Handled differently by F3DEX2 2.04H
     vge    $v3, $v25, vZero[0]
    slv     $v25[8], 0x01F0($8)
    vge     $v27, $v25, $v31[3] // INSTR 1: Finishing prev vtx store loop, some sort of clamp Z?
    slv     $v25[0], 0x01C8(outputVtxPos)
    ssv     $v26[12], 0x00F6($8)
    ssv     $v26[4], 0x00CE(outputVtxPos)
    ssv     $v3[12], 0x00F4($8)
    beqz    $7, run_next_DL_command
     ssv    $v3[4], 0x00CC(outputVtxPos)
.else // This is the F3DEX2 2.04H version
     vge    $v27, $v25, $v31[3]
    sdv     $v25[8], 0x03F0($8)
    sdv     $v25[0], 0x03C8(outputVtxPos)
    ssv     $v26[12], 0x00F6($8)
    beqz    $7, run_next_DL_command
     ssv    $v26[4], 0x00CE(outputVtxPos)
.endif
    sbv     $v27[15], 0x006B($8)
    j       run_next_DL_command
     sbv    $v27[7], 0x0043(outputVtxPos)

load_spfx_global_values:
    /*
    vscale = viewport shorts 0:3, vtrans = viewport shorts 4:7
    v16 = vFxScaleFMin = [vscale[0], -vscale[1], fogMin, vscale[3], (repeat)]
                         (element 5 written just before vertices_process_pair)
    v17 = vFxTransFMax = [vtrans[0], fogMax,     fogMax, vtrans[0], (repeat)]
    v18 = vFxMisc = [???, ???, TexSScl, TexTScl, perspNorm, 0x0002, TexSScl, TexTScl]
    v19 = vFxMask = [0x0000, 0x0001, 0x0001, 0x0000, 0x0000, 0x0001, 0x0001, 0x0000]
    v21 = vFxNegScale = -[vscale[0:3], vscale[0:3]]
    */
    li      spFxBaseReg, spFxBase
    ldv     vFxScaleFMin[0], (viewport)($zero)     // vFxScaleFMin = [vscale[0], vscale[1], vscale[2], vscale[3], 0, 0, 0, 0]
    ldv     vFxScaleFMin[8], (viewport)($zero)     // vFxScaleFMin = [vscale[0], vscale[1], vscale[2], vscale[3], vscale[0], vscale[1], vscale[2], vscale[3]]
    llv     $v29[0], (fogFactor - spFxBase)(spFxBaseReg) // Load fog settings
    ldv     vFxTransFMax[0], (viewport + 8)($zero) // vtrans
    ldv     vFxTransFMax[8], (viewport + 8)($zero) // vtrans
    vlt     vFxMask, $v31, $v31[3]                 // VCC = [0, 1, 1, 0, 0, 1, 1, 0]
    vsub    vFxNegScale, vZero, vFxScaleFMin       // 0 - vscale
    llv     vFxMisc[4], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
    vmrg    vFxScaleFMin, vFxScaleFMin, $v29[0]    // Put fog min in elements 01100110 of vscale
    llv     vFxMisc[12], (textureSettings2 - spFxBase)(spFxBaseReg) // Texture ST scale
    vmrg    vFxMask, vZero, vOne[0]                // Put 0 or 1 in v19 01100110
    llv     vFxMisc[8], (perspNorm)($zero)         // Perspective normalization long (actually short)
    vmrg    vFxTransFMax, vFxTransFMax, $v29[1]    // Put fog max in elements 01100110 of vtrans
    lsv     vFxMisc[10], (G_MWO_CLIP_RNX + 2 - spFxBase)(spFxBaseReg) // Value 0x0002
    vmov    vFxScaleFMin[1], vFxNegScale[1]        // -vscale[1]
    jr      $ra
     addi   tempCmdBuf50, rdpCmdBufPtr, 0x50

G_TRI2_handler:
G_QUAD_handler:
    jal     f3dzex_00001A4C
     sw     cmd_w1, 4(rdpCmdBufPtr)
G_TRI1_handler:
    li      $ra, run_next_DL_command
    sw      cmd_w0, 4(rdpCmdBufPtr) // store the command word (cmd_w0) into address rdpCmdBufPtr + 4
f3dzex_00001A4C:
    lpv     $v2[0], 0(rdpCmdBufPtr)
    // read the three vertex indices from the stored command word
    lbu     $1, 0x0005(rdpCmdBufPtr)     // $1 = vertex 1 index
    lbu     $2, 0x0006(rdpCmdBufPtr)     // $2 = vertex 2 index
    lbu     $3, 0x0007(rdpCmdBufPtr)     // $3 = vertex 3 index
    vor     $v3, vZero, $v31[5]
    lhu     $1, (vertexTable)($1) // convert vertex 1's index to its address
    vmudn   $v4, vOne, $v31[6]
    lhu     $2, (vertexTable)($2) // convert vertex 2's index to its address
    vmadl   $v2, $v2, $v30[1]
    lhu     $3, (vertexTable)($3) // convert vertex 3's index to its address
    vmadn   $v4, vZero, vZero[0]
    move    $4, $1
f3dzex_00001A7C:
    vnxor   $v5, vZero, $v31[7]
    llv     $v6[0], 0x0018($1) // Load pixel coords of vertex 1 into v6
    vnxor   $v7, vZero, $v31[7]
    llv     $v4[0], 0x0018($2) // Load pixel coords of vertex 2 into v4
    vmov    $v6[6], $v2[5]
    llv     $v8[0], 0x0018($3) // Load pixel coords of vertex 3 into v8
    vnxor   $v9, vZero, $v31[7]
    lw      $5, 0x0024($1)
    vmov    $v8[6], $v2[7]
    lw      $6, 0x0024($2)
    vadd    $v2, vZero, $v6[1] // v2 = y-coord of vertex 1
    lw      $7, 0x0024($3)
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2
.if NoN == 1
    andi    $11, $5, 0x70B0   // No Nearclipping
.else
    andi    $11, $5, 0x7070   // Nearclipping
.endif
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1
    and     $11, $6, $11
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3
    and     $11, $7, $11
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    vmrg    $v14, $v6, $v4    // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    bnez    $11, return_routine
     lbu    $11, geometryModeLabel + 2  // Loads the geometry mode byte that contains face culling settings
    vmudh   $v29, $v10, $v12[1]
    lw      $12, nearclipValue
    vmadh   $v29, $v12, $v11[1]
    or      $5, $5, $6
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    or      $5, $5, $7
    vmrg    $v10, $v6, $v4    // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    lw      $11, (cullFaceValues)($11)
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    mfc2    $6, $v29[0]
    vmrg    $v4, $v14, $v8    // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    and     $5, $5, $12
    vmrg    $v14, $v8, $v14   // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    bnez    $5, ovl23_clipping_entrypoint // Run overlay 3 for clipping, either directly or via overlay 2 loading overlay 3
     add     $11, $6, $11
    vlt     $v6, $v6, $v2     // v6 (thrown out), VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    bgez    $11, return_routine
     vmrg    $v2, $v4, $v10   // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    vmrg    $v10, $v10, $v4   // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    mfc2    $1, $v14[12]
    vmudn   $v4, $v14, $v31[5]
    beqz    $6, return_routine
     vsub    $v6, $v2, $v14
    mfc2    $2, $v2[12]
    vsub    $v8, $v10, $v14
    mfc2    $3, $v10[12]
    vsub    $v11, $v14, $v2
    lw      $6, geometryModeLabel
    vsub    $v12, $v14, $v10
    llv     $v13[0], 0x0020($1)
    vsub    $v15, $v10, $v2
    llv     $v13[8], 0x0020($2)
    vmudh   $v16, $v6, $v8[0]
    llv     $v13[12], 0x0020($3)
    vmadh   $v16, $v8, $v11[0]
    sll     $11, $6, 10             // Moves the value of G_SHADING_SMOOTH into the sign bit
    vreadacc $v17, ACC_UPPER
    bgez    $11, no_smooth_shading  // Branch if G_SHADING_SMOOTH isn't set
     vreadacc $v16, ACC_MIDDLE
    lpv     $v18[0], 0x0010($1) // Load vert color of vertex 1
    vmov    $v15[2], $v6[0]
    lpv     $v19[0], 0x0010($2) // Load vert color of vertex 2
    vrcp    $v20[0], $v15[1]
    lpv     $v21[0], 0x0010($3) // Load vert color of vertex 3
    vrcph   vPairST[0], $v17[1]
    vrcpl   vPairMVPPosF[1], $v16[1]
    j       shading_done
     vrcph   vPairMVPPosI[1], vZero[0]
no_smooth_shading:
    lpv     $v18[0], 0x0010($4)
    vrcp    $v20[0], $v15[1]
    lbv     $v18[6], 0x0013($1)
    vrcph   vPairST[0], $v17[1]
    lpv     $v19[0], 0x0010($4)
    vrcpl   vPairMVPPosF[1], $v16[1]
    lbv     $v19[6], 0x0013($2)
    vrcph   vPairMVPPosI[1], vZero[0]
    lpv     $v21[0], 0x0010($4)
    vmov    $v15[2], $v6[0]
    lbv     $v21[6], 0x0013($3)
shading_done:
.if (UCODE_IS_206_OR_OLDER)
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
    vrcph   vPairST[2], $v6[1]
    lw      $5, 0x0020($1)
    vrcp    $v20[3], $v8[1]
    lw      $7, 0x0020($2)
    vrcph   vPairST[3], $v8[1]
    lw      $8, 0x0020($3)
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
    vmadm   vPairST, vPairST, $vec1[i2]
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
    vmadn   $v20, $v15, vPairST
    lsv     $v19[14], 0x001C($2)
    vmadh   $v15, $v25, vPairST
    lsv     $v21[14], 0x001C($3)
    vmudl   $v29, vPairMVPPosF, $v16
    lsv     $v7[14], 0x001E($2)
    vmadm   $v29, vPairMVPPosI, $v16
    lsv     $v9[14], 0x001E($3)
    vmadn   $v16, vPairMVPPosF, $v17
    ori     $11, $6, 0x00C8 // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadh   $v17, vPairMVPPosI, $v17
    or      $11, $11, $9 // Incorporate whether textures are enabled into the triangle command id
.if !(UCODE_IS_206_OR_OLDER)
    vand    vPairST, $v20, $v30[5]
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
    beqz    $9, f3dzex_00001D2C // If textures are not enabled, skip texture coefficient calculation
    vmadh   $v3, $v15, $v26[1]
    vrcph   $v29[0], $v27[0]
    vrcpl   $v10[0], $v27[1]
    vadd    $v14, vZero, $v13[1q]
    vrcph   $v27[0], vZero[0]
    vor     vPairST, vZero, $v31[7]
    vmudm   $v29, $v13, $v10[0]
    vmadl   $v29, $v14, $v10[0]
    llv     vPairST[0], 0x0014($1)
    vmadn   $v14, $v14, $v27[0]
    llv     vPairST[8], 0x0014($2)
    vmadh   $v13, $v13, $v27[0]
    vor     $v10, vZero, $v31[7]
    vge     $v29, $v30, $v30[7]
    llv     $v10[8], 0x0014($3)
    vmudm   $v29, vPairST, $v14[0h]
    vmadh   vPairST, vPairST, $v13[0h]
    vmadn   $v25, vZero, vZero[0]
    vmudm   $v29, $v10, $v14[6]     // acc = (v10 * v14[6]); v29 = mid(clamp(acc))
    vmadh   $v10, $v10, $v13[6]     // acc += (v10 * v13[6]) << 16; v10 = mid(clamp(acc))
    vmadn   $v13, vZero, vZero[0]   // v13 = lo(clamp(acc))
    sdv     vPairST[0], 0x0020(rdpCmdBufPtr)
    vmrg    $v19, $v19, vPairST
    sdv     $v25[0], 0x0028(rdpCmdBufPtr) // 8
    vmrg    $v7, $v7, $v25
    ldv     $v18[8], 0x0020(rdpCmdBufPtr) // 8
    vmrg    $v21, $v21, $v10
    ldv     $v5[8], 0x0028(rdpCmdBufPtr) // 8
    vmrg    $v9, $v9, $v13
f3dzex_00001D2C:
    vmudl   $v29, $v16, vPairMVPPosF
    lsv     $v5[14], 0x001E($1)
    vmadm   $v29, $v17, vPairMVPPosF
    lsv     $v18[14], 0x001C($1)
    vmadn   vPairMVPPosF, $v16, vPairMVPPosI
    lh      $1, 0x0018($2)
    vmadh   vPairMVPPosI, $v17, vPairMVPPosI
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
    vmudl   $v29, $v2, vPairMVPPosF[1]
    add     rdpCmdBufPtr, $1, $11            // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, $v3, vPairMVPPosF[1]
    andi    $6, $6, G_ZBUFFER       // Get the value of G_ZBUFFER from the current geometry mode
    vmadn   $v2, $v2, vPairMVPPosI[1]
    sll     $11, $6, 4              // Shift (geometry mode & G_ZBUFFER) by 4 to get 0x10 if G_ZBUFFER is set
    vmadh   $v3, $v3, vPairMVPPosI[1]
    add     rdpCmdBufPtr, rdpCmdBufPtr, $11           // Increment the triangle pointer by 0x10 bytes (depth coefficients) if G_ZBUFFER is set
    vmudl   $v29, $v6, vPairMVPPosF[1]
    vmadm   $v29, $v7, vPairMVPPosF[1]
    vmadn   $v6, $v6, vPairMVPPosI[1]
    sdv     $v2[0], 0x0018($2)      // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   $v7, $v7, vPairMVPPosI[1]
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
    sdv     $v6[8], 0x0038($1)      // Store DsDy, DtDy, DwDy texture coefficeints (fractional)
    vmadh   $v29, $v18, vOne[0]
    sdv     $v7[8], 0x0028($1)      // Store DsDy, DtDy, DwDy texture coefficeints (integer)
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
    ssv     $v8[14], 0x00FA(rdpCmdBufPtr)
    vmudl   $v29, $v10, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v9[14], 0x00F8(rdpCmdBufPtr)
    vmadn   $v5, $v5, $v30[i6]      // v30[i6] is 0x0020
    ssv     $v2[14], 0x00F6(rdpCmdBufPtr)
    vmadh   $v18, $v18, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v3[14], 0x00F4(rdpCmdBufPtr)
    ssv     $v6[14], 0x00FE(rdpCmdBufPtr)
    ssv     $v7[14], 0x00FC(rdpCmdBufPtr)
    ssv     $v5[14], 0x00F2(rdpCmdBufPtr)
    j       check_rdp_buffer_full
    ssv     $v18[14], 0x00F0(rdpCmdBufPtr)

no_z_buffer:
    sdv     $v5[0], 0x0010($2)      // Store RGBA shade color (fractional)
    sdv     $v18[0], 0x0000($2)     // Store RGBA shade color (integer)
    sdv     $v5[8], 0x0010($1)      // Store S, T, W texture coefficients (fractional)
    j       check_rdp_buffer_full
     sdv    $v18[8], 0x0000($1)     // Store S, T, W texture coefficients (integer)

vtxPtr equ $25
endVtxPtr equ $24
G_CULLDL_handler:
    lhu     vtxPtr, (vertexTable)(cmd_w0) // load start vertex address
    lhu     endVtxPtr, (vertexTable)(cmd_w1) // load end vertex address
.if NoN == 1
    addiu   $1, $zero, 0x70B0       // todo what is this value (No Nearclipping)
.else
    addiu   $1, $zero, 0x7070       // todo what is this value (Nearclipping)
.endif
    lw      $11, 0x0024(vtxPtr)     // todo what is this reading from the vertex?
culldl_loop:
    and     $1, $1, $11
    beqz    $1, run_next_DL_command
     lw     $11, 0x004C(vtxPtr)
    bne     vtxPtr, endVtxPtr, culldl_loop  // loop until reaching the last vertex
     addiu  vtxPtr, vtxPtr, vtxSize         // advance to the next vertex
    j       G_ENDDL_handler                 // otherwise skip the rest of the displaylist
G_BRANCH_WZ_handler:
     lhu    vtxPtr, (vertexTable)(cmd_w0)   // get the address of the vertex being tested
.if UCODE_TYPE == TYPE_F3DZEX // BRANCH_W/BRANCH_Z difference
    lh      vtxPtr, 0x0006(vtxPtr)          // read the w coordinate of the vertex (f3dzex)
.else
    lw      vtxPtr, 0x001C(vtxPtr)          // read the z coordinate of the vertex (f3dex2)
.endif
    sub     $2, vtxPtr, endVtxPtr       // subtract the w/z value being tested
    bgez    $2, run_next_DL_command     // if vtx.w/z > w/z, continue running this DL
     lw     $24, rdpHalf1Val            // load the RDPHALF1 value
    j       f3dzex_ovl1_00001008
G_MODIFYVTX_handler:
     lbu    $1, (inputBufferEnd - 0x07)(inputBufferPos)
    j       do_moveword
     lhu    vtxPtr, (vertexTable)(cmd_w0)

     
.if . > 0x00001FAC
    .error "Not enough room in IMEM"
.endif
.org 0x1FAC

// This subroutine sets up the values to load overlay 0 and then falls through
// to load_overlay_and_enter to execute the load.
load_overlay_0_and_enter:
G_LOAD_UCODE_handler:
    li      $12, ovl0_start    // Sets up return address
    li      $11, overlayInfo0       // Sets up ovl0 table address
// This subroutine accepts the address of an overlay table entry and loads that overlay.
// It then jumps to that overlay's address after DMA of the overlay is complete.
// $11 is used to provide the overlay table entry
// $12 is used to pass in a value to return to
ovlTableEntry equ $11
returnAddr equ $12
load_overlay_and_enter:
    lw      $24, overlay_load(ovlTableEntry)    // Set up overlay dram address
    lhu     $19, overlay_len(ovlTableEntry)     // Set up overlay length
    jal     dma_read_write                      // DMA the overlay
     lhu    $20, overlay_imem(ovlTableEntry)    // Set up overlay load address
    move    $ra, returnAddr     // Set the return address to the passed in value
while_wait_dma_busy:
    mfc0    $11, SP_DMA_BUSY    // Load the DMA_BUSY value into $11
while_dma_busy:
    bnez    $11, while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   $11, SP_DMA_BUSY    // Update $11's DMA_BUSY value
// This routine is used to return via conditional branch
return_routine:
    jr      $ra

dmemAddr equ $20
dramAddr equ $24
dmaLen equ $19
dmaFull equ $11
dma_read_write:
     mfc0   dmaFull, SP_DMA_FULL    // load the DMA_FULL value
while_dma_full:
    bnez    dmaFull, while_dma_full // Loop until DMA_FULL is cleared
     mfc0   dmaFull, SP_DMA_FULL    // Update DMA_FULL value
    mtc0    dmemAddr, SP_MEM_ADDR   // Set the DMEM address to DMA from/to
    bltz    dmemAddr, dma_write     // If the DMEM address is negative, this is a DMA write, if not read
     mtc0   dramAddr, SP_DRAM_ADDR  // Set the DRAM address to DMA from/to
    jr $ra
     mtc0   dmaLen, SP_RD_LEN       // Initiate a DMA read with a length of dmaLen
dma_write:
    jr $ra
     mtc0   dmaLen, SP_WR_LEN       // Initiate a DMA write with a length of dmaLen

.if . > 0x00002000
    .error "Not enough room in IMEM"
.endif

// first overlay table at 0x02E0
// overlay 0 (0x98 bytes loaded into 0x1000)

.headersize 0x00001000 - orga()

// Overlay 0 controls the RDP and also stops the RSP when work is done
ovl0_start:
.if UCODE_METHOD == METHOD_FIFO
    sub     $11, rdpCmdBufPtr, rdpCmdBufEnd
    addiu   $12, $11, RDP_CMD_BUFSIZE - 1
    bgezal  $12, flush_rdp_buffer
     nop
    jal     while_wait_dma_busy
     lw     $24, rdpFifoPos
    bltz    $1, taskdone_and_break
     mtc0   $24, DPC_END            // Set the end pointer of the RDP so that it starts the task
.else // UCODE_METHOD == METHOD_XBUS
    bltz    $1, taskdone_and_break
     nop
.endif
    bnez    $1, task_yield
     add    taskDataPtr, taskDataPtr, inputBufferPos
    lw      $24, 0x09C4(inputBufferPos) // Should this be (inputBufferEnd - 0x04)?
    sw      taskDataPtr, OSTask + OSTask_data_ptr
    sw      $24, OSTask + OSTask_ucode
    la      $20, start              // DMA address
    jal     dma_read_write          // initiate DMA read
     li     $19, 0x0F48 - 1
.if UCODE_METHOD == METHOD_XBUS
ovl0_xbus_wait_for_rdp:
    mfc0 $11, DPC_STATUS
    andi $11, $11, DPC_STATUS_DMA_BUSY
    bnez $11, ovl0_xbus_wait_for_rdp // Keep looping while RDP is busy.
.endif
    lw      $24, rdpHalf1Val
    la      $20, 0x0180             // DMA address; equal to but probably not actually spFxBase or clipRatio
    andi    $19, cmd_w0, 0x0FFF
    add     $24, $24, $20
    jal     dma_read_write          // initate DMA read
     sub    $19, $19, $20
    j       while_wait_dma_busy
.if (UCODE_IS_F3DEX2_204H || UCODE_METHOD == METHOD_XBUS /* ??? */)
     li     $ra, taskdone_and_break_204H
.else
     li     $ra, taskdone_and_break
.endif

ucode equ $11
status equ $12
task_yield:
    lw      ucode, OSTask + OSTask_ucode
.if UCODE_METHOD == METHOD_FIFO
    sw      taskDataPtr, OS_YIELD_DATA_SIZE - 8
    sw      ucode, OS_YIELD_DATA_SIZE - 4
    li      status, SP_SET_SIG1 | SP_SET_SIG2   // yielded and task done signals
    lw      $24, OSTask + OSTask_yield_data_ptr
    li      $20, 0x8000
    li      $19, OS_YIELD_DATA_SIZE - 1
.else // UCODE_METHOD == METHOD_XBUS
    sw      taskDataPtr, OS_YIELD_DATA_SIZE
    sw      ucode, OS_YIELD_DATA_SIZE + 4
    lw      $24, OSTask + OSTask_yield_data_ptr
    li      $20, 0x8000
    jal     dma_read_write
     li     $19, OS_YIELD_DATA_SIZE - 1
    li      status, SP_SET_SIG1 | SP_SET_SIG2 // yielded and task done signals
    addiu   $24, $24, OS_YIELD_DATA_SIZE_TOTAL - 8
    li      $20, -0x76E0 // ???
    li      $19, 7
.endif
    j       dma_read_write
taskdone_and_break_204H: // Only used in f3dex2 2.04H
     li     $ra, break
taskdone_and_break:
    li      status, SP_SET_SIG2   // task done signal
break:
.if UCODE_METHOD == METHOD_XBUS
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
    .error "Overlay 0 too large"
.endif

// overlay 1 (0x170 bytes loaded into 0x1000)
.headersize 0x00001000 - orga()

ovl1_start:

G_DL_handler:
    lbu     $1, displayListStackLength  // Get the DL stack length
    sll     $2, cmd_w0, 15              // Shifts the push/nopush value to the highest bit in $2
f3dzex_ovl1_00001008:
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos
    bltz    $2, displaylist_dma         // If the operation is nopush (branch) then simply DMA the new displaylist
     move   taskDataPtr, cmd_w1         // Set the task data pointer to the target display list
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
     sw     cmd_w1, (texrectWord2 - G_TEXRECTFLIP_handler)($11)

G_MOVEWORD_handler:
    srl     $2, cmd_w0, 16                              // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $1, (movewordTable - (G_MOVEWORD << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    add     $1, $1, cmd_w0          // adds the offset in the command word to the address from the table (the upper 4 bytes are effectively ignored)
    j       run_next_DL_command     // process the next command
     sw     cmd_w1, ($1)            // moves the specified value (in cmd_w1) into the word (offset + moveword_table[index])

G_POPMTX_handler:
    lw      $11, matrixStackPtr             // Get the current matrix stack pointer
    lw      $2, OSTask + OSTask_dram_stack  // Read the location of the dram stack
    sub     $24, $11, cmd_w1                // Decrease the matrix stack pointer by the amount passed in the second command word
    sub     $1, $24, $2                     // Subtraction to check if the new pointer is greater than or equal to $2
    bgez    $1, do_popmtx                   // If the new matrix stack pointer is greater than or equal to $2, then use the new pointer as is
     nop
    move    $24, $2                         // If the new matrix stack pointer is less than $2, then use $2 as the pointer instead
do_popmtx:
    beq     $24, $11, run_next_DL_command   // If no bytes were popped, then we don't need to make the mvp matrix as being out of date and can run the next command
     sw     $24, matrixStackPtr             // Update the matrix stack pointer with the new value
    j       do_movemem
     sw     $zero, mvpValid                 // Mark the MVP matrix and light directions as being out of date (the word being written to contains both)

G_MTX_end: // Multiplies the loaded model matrix into the model stack
    lhu     $19, (movememTable + G_MV_MMTX)($1) // Set the output matrix to the model or projection matrix based on the command
    jal     while_wait_dma_busy
     lhu    $21, (movememTable + G_MV_MMTX)($1) // Set the first input matrix to the model or projection matrix based on the command
    li      $ra, run_next_DL_command
    // The second input matrix will correspond to the address that memory was moved into, which will be tempMtx for G_MTX

input_mtx_0 equ $21
input_mtx_1 equ $20
output_mtx equ $19
mtx_multiply:
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

matrixStackAddr equ $24
G_MTX_handler:
    // The lower 3 bits of G_MTX are, from LSb to MSb (0 value/1 value),
    //  matrix type (modelview/projection)
    //  load type (multiply/load)
    //  push type (nopush/push)
    // In F3DEX2 (and by extension F3DZEX), G_MTX_PUSH is inverted, so 1 is nopush and 0 is push
    andi    $11, cmd_w0, G_MTX_P_MV | G_MTX_NOPUSH_PUSH // Read the matrix type and push type flags into $11
    bnez    $11, load_mtx                               // If the matrix type is projection or this is not a push, skip pushing the matrix
     andi   $2, cmd_w0, G_MTX_MUL_LOAD                  // Read the matrix load type into $2 (0 is multiply, 2 is load)
    lw      matrixStackAddr, matrixStackPtr             // Set up the DMA from dmem to rdram at the matrix stack pointer
    li      $20, -0x2000                                //
    jal     dma_read_write                              // DMA the current matrix from dmem to rdram
     li     $19, 0x0040 - 1                             // Set the DMA length to the size of a matrix (minus 1 because DMA is inclusive)
    addi    matrixStackAddr, matrixStackAddr, 0x40      // Increase the matrix stack pointer by the size of one matrix
    sw      matrixStackAddr, matrixStackPtr             // Update the matrix stack pointer
    lw      cmd_w1, (inputBufferEnd - 4)(inputBufferPos)
load_mtx:
    add     $12, $12, $2        // Add the load type to the command byte, selects the return address based on whether the matrix needs multiplying or just loading
    sw      $zero, mvpValid     // Mark the MVP matrix and light directions as being out of date (the word being written to contains both)
G_MOVEMEM_handler:
    jal     segmented_to_physical   // convert the memory address cmd_w1 to a virtual one
do_movemem:
     andi   $1, cmd_w0, 0x00FE                           // Move the movemem table index into $1 (bits 1-7 of the first command word)
    lbu     $19, (inputBufferEnd - 0x07)(inputBufferPos) // Move the second byte of the first command word into $19
    lhu     $20, (movememTable)($1)                      // Load the address of the memory location for the given movemem index
    srl     $2, cmd_w0, 5                                // Left shifts the index by 5 (which is then added to the value read from the movemem table)
    lhu     $ra, (movememHandlerTable - (G_POPMTX | 0xFF00))($12)  // Loads the return address from movememHandlerTable based on command byte
    j       dma_read_write
G_SETOTHERMODE_H_handler: // These handler labels must be 4 bytes apart for the code below to work
     add    $20, $20, $2
G_SETOTHERMODE_L_handler:
    lw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($11) // resolves to othermode0 or othermode1 based on which handler was jumped to
    lui     $2, 0x8000
    srav    $2, $2, cmd_w0
    srl     $1, cmd_w0, 8
    srlv    $2, $2, $1
    nor     $2, $2, $zero
    and     $3, $3, $2
    or      $3, $3, cmd_w1
    sw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($11)
    lw      cmd_w0, otherMode0
    j       G_RDP_handler
     lw     cmd_w1, otherMode1

.align 8
ovl1_end:

.if ovl1_end > ovl01_end
    .error "Overlay 1 too large"
.endif

.headersize ovl23_start - orga()

ovl2_start:
ovl23_lighting_entrypoint_copy:         // same IMEM address as ovl23_lighting_entrypoint
    lbu     $11, lightsValid
    j       continue_light_dir_xfrm
     lbu    tmpCurLight, numLightsx18

ovl23_clipping_entrypoint_copy:         // same IMEM address as ovl23_clipping_entrypoint
    move    savedRA, $ra
    li      $11, overlayInfo3           // set up a load of overlay 3
    j       load_overlay_and_enter      // load overlay 3
     li     $12, ovl3_clipping_nosavera // set up the return address in ovl3
     
continue_light_dir_xfrm:
    // Transform light directions from camera space to model space, by
    // multiplying by modelview transpose, then normalize and store the results
    // (not overwriting original dirs). This is applied starting from the two
    // lookat lights and through all directional and point lights, but not
    // ambient. For point lights, the data is garbage but doesn't harm anything.
    bnez    $11, after_light_dir_xfrm // Skip calculating lights if they're not out of date
     addi   tmpCurLight, tmpCurLight, spFxBase - lightSize // With ltBufOfs, points at top/max light.
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
    xfrmLtPtr equ $20
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
    beq     xfrmLtPtr, tmpCurLight, after_light_dir_xfrm    // exit if equal
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
.if (UCODE_IS_206_OR_OLDER)
    i7 equ 7
.else
    i7 equ 3
.endif
    vmudn   $v11, $v11, $v30[i7]        // Scale results to become bytes
    j       @@loop
     vmadh  $v15, $v15, $v30[i7]        // Scale results to become bytes

curMatrix equ $12
ltColor equ $v29
vPairRGBA equ $v27
vPairAlpha37 equ $v28 // Same as mvTc1f, but alpha values are left in elems 3, 7
vPairNX equ $v7 // also named vPairRGBATemp; with name vPairNX, uses X components = elems 0, 4
vPairNY equ $v6
vPairNZ equ $v5

// For point lighting, but armips does not like these defined in an .if
mvTc0i equ $v4
mvTc1i equ $v21
mvTc2i equ $v30
mvTc0f equ $v3
mvTc1f equ $v28
mvTc2f equ $v31

light_vtx:
    vadd    vPairNY, vZero, vPairRGBATemp[1h] // Move vertex normals Y to separate reg
.if UCODE_HAS_POINT_LIGHTING
    luv     ltColor[0], (ltBufOfs + lightSize + 0)(curLight) // Load next light color (ambient)
.else
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load next below transformed light direction as XYZ_XYZ_ for lights_dircoloraccum2
.endif
    vadd    vPairNZ, vZero, vPairRGBATemp[2h] // Move vertex normals Z to separate reg
    luv     vPairRGBA[0], 8(inputVtxPos)      // Load both verts' XYZAXYZA as unsigned
    vne     $v4, $v31, $v31[3h]               // Set VCC to 11101110
.if UCODE_HAS_POINT_LIGHTING
    andi    $11, $5, G_LIGHTING_POSITIONAL_H  // check if point lighting is enabled in the geometry mode
    beqz    $11, directional_lighting         // If not enabled, use directional algorithm for everything
     li     curMatrix, mvpMatrix + 0x8000     // Set flag in negative to indicate cur mtx is MVP
    vaddc   vPairAlpha37, vPairRGBA, vZero[0] // Copy vertex alpha
    suv     ltColor[0], 8(inputVtxPos)        // Store ambient light color to two verts' RGBARGBA
    ori     $11, $zero, 0x0004
    vmov    $v30[7], $v30[6]                  // v30[7] = 0x0010 because v30[0:2,4:6] will get clobbered
    mtc2    $11, $v31[6]                      // v31[6] = 0x0004 (was previously 0x0420)
next_light_dirorpoint:
    lbu     $11, (ltBufOfs + 0x3)(curLight)   // Load light type / constant attenuation value at light structure + 3
    bnez    $11, light_point                  // If not zero, this is a point light
     lpv    $v2[0], (ltBufOfs + 0x10)(curLight) // Load light transformed direction
    luv     ltColor[0], 8(inputVtxPos)        // Load current light color of two verts RGBARGBA
    vmulu   $v20, vPairNX, $v2[0h]            // Vertex normals X * light transformed dir X
    vmacu   $v20, vPairNY, $v2[1h]            // + Vtx Y * light Y
    vmacu   $v20, vPairNZ, $v2[2h]            // + Vtx Z * light Z; only elements 0, 4 matter
    luv     $v2[0], (ltBufOfs + 0)(curLight)  // Load light RGB
    vmrg    ltColor, ltColor, vPairAlpha37    // Select original alpha
    vand    $v20, $v20, $v31[7]               // 0x7FFF; not sure why AND rather than clamp
    vmrg    $v2, $v2, vZero[0]                // Set elements 3 and 7 of light RGB to 0
    vmulf   ltColor, ltColor, $v31[7]         // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v2, $v20[0h]            // + light color * dot product
    suv     ltColor[0], 8(inputVtxPos)        // Store new light color of two verts RGBARGBA
    bne     curLight, spFxBaseReg, next_light_dirorpoint // If at start of lights, done
     addi   curLight, curLight, -lightSize
after_dirorpoint_loop:
    lqv     $v31[0], (v31Value)($zero)        // Fix clobbered v31
    lqv     $v30[0], (v30Value)($zero)        // Fix clobbered v30
    llv     vPairST[4], (inputVtxSize + 0x8)(inputVtxPos) // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
    bgezal  curMatrix, lights_loadmtxdouble   // Branch if current matrix is MV matrix
     li     curMatrix, mvpMatrix + 0x8000     // Load MVP matrix and set flag for is MVP
    andi    $11, $5, G_TEXTURE_GEN_H
    vmrg    $v3, vZero, $v31[5]               // INSTR 3: Setup for texgen: 0x4000 in elems 3, 7
    beqz    $11, vertices_store               // Done if no texgen
     vge    $v27, $v25, $v31[3]               // INSTR 1: Finishing prev vtx store loop, some sort of clamp Z?
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight) // Load lookat 1 transformed dir for texgen (curLight was decremented)
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load lookat 0 transformed dir for texgen
    j       lights_texgenmain
     vmulf  $v21, vPairNX, $v2[0h]            // First instruction of texgen, vertex normal X * last transformed dir

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
    mtc2    $11, $v27[0]                 // 0x3 << 4 -> v27 elems 0, 1
    vmadh   $v2, mvTc1i, $v20[1h]
    vmadn   $v2, mvTc2f, $v20[2h]
    vmadh   $v20, mvTc2i, $v20[2h]       // v20 = int result of vert-to-light in model space
    vmudm   $v2, $v20, $v29[3h]          // v2l_model * length normalization frac
    vmadh   $v20, $v20, $v29[2h]         // v2l_model * length normalization int
    vmudn   $v2, $v2, $v31[3]            // this is 0x7F00; v31 is mvTc2f but elements 3 and 7 weren't overwritten
    vmadh   $v20, $v20, $v31[3]          // scale to byte, only keep int part
    vmulu   $v2, vPairNX, $v20[0h]       // Normal X * normalized vert-to-light X
    mtc2    $11, $v27[8]                 // 0x3 << 4 -> v27 elems 4, 5
    vmacu   $v2, vPairNY, $v20[1h]       // Y * Y
    lbu     $11, (ltBufOfs + 0x7)(curLight) // Linear attenuation factor byte from point light props
    vmacu   $v2, vPairNZ, $v20[2h]       // Z * Z
    sll     $24, $24, 5
    vand    $v20, $v2, $v31[7]           // 0x7FFF; not sure why AND rather than clamp
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
    vmadn   $v29, $v27, $v30[3]          // + (byte 0x3 << 4) * 0xFFF0
    vreadacc $v2, ACC_MIDDLE
    vrcph   $v2[0], $v2[0]               // v2 int, v29 frac: function of distance to light
    vrcpl   $v2[0], $v29[0]              // Reciprocal = inversely proportional
    vrcph   $v2[4], $v2[4]
    vrcpl   $v2[4], $v29[4]
    luv     ltColor[0], 0x0008(inputVtxPos) // Get current RGBARGBA for two verts
    vand    $v2, $v2, $v31[7]            // 0x7FFF; not sure why AND rather than clamp
    vmulf   $v2, $v2, $v20               // Inverse dist factor * dot product (elems 0, 4)
    luv     $v20[0], (ltBufOfs + 0)(curLight) // Light color RGB_RGB_
    vmrg    ltColor, ltColor, vPairAlpha37 // Select orig alpha; vPairAlpha37 = v28 = mvTc1f, but alphas were not overwritten
    vand    $v2, $v2, $v31[7]            // 0x7FFF; not sure why AND rather than clamp
    vmrg    $v20, $v20, vZero[0]         // Zero elements 3 and 7 of light color
    vmulf   ltColor, ltColor, $v31[7]    // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v20, $v2[0h]       // + light color * light amount
    suv     ltColor[0], 0x0008(inputVtxPos) // Store new RGBARGBA for two verts
    bne     curLight, spFxBaseReg, next_light_dirorpoint
     addi   curLight, curLight, -lightSize
    j       after_dirorpoint_loop
directional_lighting:
     lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Load next light transformed dir; this value is overwritten with the same thing
.else // No point lighting
    luv     ltColor[0], (ltBufOfs + lightSize + 0)(curLight) // Init to ambient light color
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
    vmrg    ltColor, ltColor, vPairRGBA  // select orig alpha
    mtc2    $zero, $v4[6]                // light 2n+1 color comp 3 = 0 (to not interfere with alpha)
    vmrg    $v3, $v3, vZero[0]           // light 2n color components 3,7 = 0
    mtc2    $zero, $v4[14]               // light 2n+1 color comp 7 = 0 (to not interfere with alpha)
    vand    $v21, $v21, $v31[7]          // 0x7FFF; not sure why AND rather than clamp
    lpv     $v2[0], (ltBufOfs + 0x10)(curLight) // Normal for light or lookat next slot down, 2n+1
    vand    $v28, $v28, $v31[7]          // 0x7FFF; not sure why AND rather than clamp
    lpv     $v20[0], (ltBufOfs - lightSize + 0x10)(curLight) // Normal two slots down, 2n
    vmulf   ltColor, ltColor, $v31[7]    // Load light color to accumulator (0x7FFF = 0.5 b/c unsigned?)
    vmacf   ltColor, $v4, $v21[0h]       // + color 2n+1 * dot product
    bne     $11, spFxBaseReg, lights_dircoloraccum2 // Pointer 1 behind, minus 1 light, if at base then done
     vmacf  ltColor, $v3, $v28[0h]       // + color 2n * dot product
// End of loop for even number of lights
    vmrg    $v3, vZero, $v31[5]          // INSTR 3: Setup for texgen: 0x4000 in elems 3, 7
    llv     vPairST[4], (inputVtxSize + 8)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
    
lights_texgenpre:
// Texgen beginning
    vge     $v27, $v25, $v31[3]         // INSTR 1: Finishing prev vtx store loop, some sort of clamp Z?
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
.if (UCODE_IS_F3DEX2_204H)
    vmudh   vPairST, vOne, $v31[5]      // Bug? Reinit S, T init to 0x4000 each
.else
    vmudh   $v21, vOne, $v31[5]         // Initialize accumulator with 0x4000 each (v21 discarded)
.endif
    vmacf   vPairST, vPairST, $v2[1]    // + ST * coefficient 0x44D3
    j       vertices_store
     vmacf  vPairST, $v4, $v3           // + ST squared * (ST + ST * coeff)

lights_finishone:
    vmrg    ltColor, ltColor, vPairRGBA // select orig alpha
    vmrg    $v4, $v4, vZero[0]          // clear alpha component of color
    vand    $v21, $v21, $v31[7]         // 0x7FFF; not sure why AND rather than clamp
    veq     $v3, $v31, $v31[3h]         // set VCC to 00010001, opposite of 2 light case
    lpv     $v2[0], (ltBufOfs - 2 * lightSize + 0x10)(curLight) // Load second dir down, lookat 0, for texgen
    vmrg    $v3, vZero, $v31[5]         // INSTR 3 OPPOSITE: Setup for texgen: 0x4000 in 0,1,2,4,5,6
    llv     vPairST[4], (inputVtxSize + 8)(inputVtxPos)  // INSTR 2: load the texture coords of the 2nd vertex into v22[4-7]
    vmulf   ltColor, ltColor, $v31[7]   // Move cur color to accumulator
    j       lights_texgenpre
     vmacf  ltColor, $v4, $v21[0h]      // + light color * dot product

.align 8
ovl2_end:

.close // CODE_FILE
