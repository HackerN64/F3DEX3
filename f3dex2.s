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
.macro vcopy, dst, src
    vadd dst, src, $v0[0]
.endmacro

.macro vclr, dst
    vxor dst, dst, dst
.endmacro

ACC_LOWER equ 0
ACC_MIDDLE equ 1
ACC_UPPER equ 2
.macro vreadacc, dst, N
    vsar dst, dst, dst[N]
.endmacro

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

// 0x0000-0x003F: modelview matrix
mvMatrix:
    .fill 64

// 0x0040-0x007F: projection matrix
pMatrix:
    .fill 64

// 0x0080-0x00C0: modelviewprojection matrix
mvpMatrix:
    .fill 64

// 0x00C0-0x00C7: scissor (four 12-bit values)
scissorUpLeft: // the command byte is included since the command word is copied verbatim
    .dw (G_SETSCISSOR << 24) | ((  0 * 4) << 12) | ((  0 * 4) << 0)
scissorBottomRight:
    .dw ((320 * 4) << 12) | ((240 * 4) << 0)

// 0x00C8-0x00CF: othermode
otherMode0: // command byte included, same as above
    .dw (G_RDPSETOTHERMODE << 24) | (0x080CFF)
otherMode1:
    .dw 0x00000000

// 0x00D0-0x00D9: ??
texrectWord1:
    .fill 4 // first word, has command byte, xh and yh
texrectWord2:
    .fill 4 // second word, has tile, xl, yl
rdpHalf1Val:
    .dh 0x0000

// 0x00DA-0x00DD: perspective norm
perspNorm:
    .dw 0x0000FFFF

// 0x00DE: displaylist stack length
displayListStackLength:
    .db 0x00 // starts at 0, increments by 4 for each "return address" pushed onto the stack

    .db 0x48 // this seems to be the max displaylist length

// 0x00E0-0x00EF: viewport
viewport:
    .fill 16

// 0x00F0-0x00F3: ?
lbl_00F0:
    .fill 4

// 0x00F4-0x00F7:
matrixStackPtr:
    .dw 0x00000000

.orga 0x00F8

// 0x00F8-0x0137: segment table
segmentTable:
    .fill (4 * 16) // 16 DRAM pointers

// 0x0138-0x017F: displaylist stack
displayListStack:

// 0x0138-0x017F: ucode text (shared with DL stack)
.if (UCODE_IS_F3DEX2_204H) // F3DEX2 2.04H puts an extra 0x0A before the name
    .db 0x0A
.endif
    .ascii NAME, 0x0A

.align 16

// 0x0180-0x2DF: ???
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

v31Value:
    .dh 0xFFFF
    .dh 0x0004
    .dh 0x0008
    .dh 0x7F00
    .dh 0xFFFC
    .dh 0x4000
    .dh 0x0420
    .dh 0x7FFF

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

linearGenerateCoefficients:
    .dh 0xC000
    .dh 0x44D3
    .dh 0x6CB3
    .dh 0x0002

forceMatrix:
    .db 0x00

mvpValid:
    .db 0x01

// 0x01DA
numLights:
    .dh 0000
// 0x01DC
    .db 0x01
    .db 0x00

    .dh 0x0BA8

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

// 0x01F0-0x021F: Light data
lightBuffer:
    .fill (8 * 6)

// 0x0220-0x023F: Light colors
lightColors:
    .fill (8 * 4)

// 0x0240-0x02DF: ??
.orga 0x02E0

// 0x02E0-0x02EF: Overlay 0/1 Table
overlayInfo0:
    OverlayEntry orga(Overlay0Address), orga(Overlay0End), Overlay0Address
overlayInfo1:
    OverlayEntry orga(Overlay1Address), orga(Overlay1End), Overlay1Address

// 0x02F0-0x02FD: Movemem table
movememTable:
    .dh 0x09D0
    .dh mvMatrix     // G_MV_MMTX
    .dh 0x09D0
    .dh pMatrix      // G_MV_PMTX
    .dh viewport     // G_MV_VIEWPORT
    .dh lightBuffer  // G_MV_LIGHT
    .dh vertexBuffer // G_MV_POINT
// Further entries in the movemem table come from the moveword table

// 0x02FE-0x030D: moveword table
movewordTable:
    .dh mvpMatrix     // G_MW_MATRIX
    .dh numLights     // G_MW_NUMLIGHT
    .dh clipRatio     // G_MW_CLIP
    .dh segmentTable  // G_MW_SEGMENT
    .dh fogFactor     // G_MW_FOG
    .dh lightColors   // G_MW_LIGHTCOL
    .dh forceMatrix   // G_MW_FORCEMTX
    .dh perspNorm     // G_MW_PERSPNORM

// 0x030E-0x036F: RDP/Immediate Command Jump Table
jumpTableEntry G_D0_D2_handler
jumpTableEntry G_D1_handler
jumpTableEntry G_D0_D2_handler
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

// 0x0370-0x037F: DMA Command Jump Table
jumpTableEntry G_VTX_handler
jumpTableEntry G_MODIFYVTX_handler
jumpTableEntry G_CULLDL_handler
jumpTableEntry G_BRANCH_WZ_handler // different for F3DZEX
jumpTableEntry G_TRI1_handler
jumpTableEntry G_TRI2_handler
jumpTableEntry G_QUAD_handler
jumpTableEntry G_LINE3D_handler

// 0x0380-0x03C3: vertex pointers
vertexTable:

// The vertex table is a list of pointers to the location of each vertex in the buffer
// After the last vertex pointer, there is a pointer to the address after the last vertex
// This means there are really 33 entries in the table

.macro vertexTableEntry, i
    .dh vertexBuffer + (i * 0x28)
.endmacro

.macro vertexTableEntries, i
    .if i > 0
        vertexTableEntries (i - 1)
    .endif
    vertexTableEntry i
.endmacro

    vertexTableEntries 32

// 0x03C2-0x040F: ??
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

// 0x0410-0x041F: Overlay 2/3 table
overlayInfo2:
    OverlayEntry orga(Overlay2Address), orga(Overlay2End), Overlay2Address
overlayInfo3:
    OverlayEntry orga(Overlay3Address), orga(Overlay3End), Overlay3Address

// 0x0420-0x0919: Vertex buffer
vertexBuffer:
    .skip (40 * 32) // 40 bytes per vertex, 32 vertices

// 0x0920-0x09C7: Input buffer
inputBuffer:
inputBufferLength equ 0xA8
    .skip inputBufferLength
inputBufferEnd:

.orga 0xBA8

// 0x0BA8-??: RDP Command Buffer?
lbl_0BA8:

.orga 0x0BF8

// 0x0BF8-0x0C00: ??
lbl_0BF8:
    .skip 4
lbl_0BFC: // old ucode?
    .skip 4

.orga 0x0D00

// 0x0D00-??: RDP Command Buffer?
lbl_0D00:

.orga 0x0FC0

// 0x0FC0-0x0FFF: OSTask
OSTask:
    .skip 0x40

.if . > 0x00001000
    .error "Not enough room in DMEM"
.endif

.close // DATA_FILE

// RSP IMEM
.create CODE_FILE, 0x00001080

// Global registers
curClipRatio equ $13
cmd_w1 equ $24
cmd_w0 equ $25
taskDataPtr equ $26
inputBufferPos equ $27

// Initialization routines
// Everything up until displaylist_dma will get overwritten by ovl1
start:
.if UCODE_TYPE == TYPE_F3DZEX && UCODE_ID < 2
    vor     $v0, $v16, $v16 // Sets $v0 to $v16
.else
    vclr    $v0             // Clear $v0
.endif
    lqv     $v31[0], (v31Value)($zero)
    lqv     $v30[0], (v30Value)($zero)
    li      $23, lbl_0BA8
.if !(UCODE_IS_207_OR_OLDER)
    vadd    $v1, $v0, $v0
.endif
    li      $22, lbl_0D00
    vsub    $v1, $v0, $v31[0]
    lw      $11, lbl_00F0
    lw      $12, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // task done and yielded signals
    beqz    $11, task_init
     mtc0   $1, SP_STATUS
    andi    $12, $12, OS_TASK_YIELDED
    beqz    $12, calculate_overlay_addrs    // skip overlay address calculations if resumed from yield?
     sw     $zero, OSTask + OSTask_flags
    j       load_overlay1_init              // Skip the initialization and go straight to loading overlay 1
     lw     taskDataPtr, lbl_0BF8

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
    sw      $2, lbl_00F0
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
displaylist_dma: // loads inputBufferLength bytes worth of displaylist data via DMA into inputBuffer
    li      $19, inputBufferLength - 1  // set the DMA length
    move    $24, taskDataPtr            // set up the DRAM address to read from
    jal     dma_read_write              // initiate the DMA read
     la     $20, inputBuffer            // set the address to DMA read to
    addiu   taskDataPtr, taskDataPtr, inputBufferLength // increment the DRAM address to read from next time
    li      inputBufferPos, -inputBufferLength          // reset the DL word index
wait_for_dma_and_run_next_command:
G_D0_D2_handler: // unknown D0/D2 commands?
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
    j       calculate_mvp_matrix
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

rdpCmdBufPtr equ $23
G_RDPHALF_2_handler:
    ldv     $v29[0], (texrectWord1)($zero)
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    $23, $23, 8
    sdv     $v29[0], (lbl_03F8)($23)        // move textrectWord1 to lbl_03F8
G_RDP_handler:
    sw      cmd_w1, 4(rdpCmdBufPtr)         // Add the second word of the command to the RDP command buffer
G_SYNC_handler:
G_NOOP_handler:
    sw      cmd_w0, 0(rdpCmdBufPtr)         // Add the command word to the RDP command buffer
    j       f3dzex_00001258
     addi   rdpCmdBufPtr, rdpCmdBufPtr, 0x0008 // Increment the next RDP command pointer by 2 words

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

f3dzex_00001258:
    li      $ra, run_next_DL_command    // Set up running the next DL command as the return address
f3dzex_0000125C:
     sub    $11, $23, $22               // todo what are $22 and $23?
    blez    $11, return_routine         // Return if $22 >= $23
f3dzex_00001264:
     mfc0   $12, SP_DMA_BUSY
    lw      $24, lbl_00F0
    addiu   $19, $11, 0x0158
    bnez    $12, f3dzex_00001264
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
    sw      $11, lbl_00F0
    addi    $19, $19, -1        // subtract 1 from the length
    addi    $20, $22, -0x2158
    xori    $22, $22, 0x0208
    j       dma_read_write
     addi   $23, $22, -0x0158

Overlay23LoadAddress:

// Overlay 3 registers
savedRA equ $30
savedNearclip equ $29

Overlay3Address:
    li      $11, overlayInfo2       // set up a load for overlay 2
    j       load_overlay_and_enter  // load overlay 2
     li     $12, Overlay2Address    // set the return address to overlay 2's start

f3dzex_ov3_000012E4:
    move    savedRA, $ra
f3dzex_ov3_000012E8:
    la      $5, 0x0014
    la      $18, 6
    addiu   $15, $zero, (inputBufferEnd)
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
    vor     $v29, $v11, $v1[0]
    vrcph   $v3[3], $v11[3]
.endif
    vrcpl   $v2[3], $v10[3]
    vrcph   $v3[3], $v0[0]
.if (UCODE_IS_F3DEX2_204H) // Only in F3DEX2 2.04H
    vabs    $v29, $v11, $v25[3]
.else
    vabs    $v29, $v29, $v25[3]
.endif
    vmudn   $v2, $v2, $v29[3]
    vmadh   $v3, $v3, $v29[3]
    veq     $v3, $v3, $v0[0]
    vmrg    $v2, $v2, $v31[0]
    vmudl   $v29, $v10, $v2[3]
    vmadm   $v11, $v11, $v2[3]
    vmadn   $v10, $v0, $v0[0]
    vrcph   $v13[3], $v11[3]
    vrcpl   $v12[3], $v10[3]
    vrcph   $v13[3], $v0[0]
    vmudl   $v29, $v12, $v10
    vmadm   $v29, $v13, $v10
    vmadn   $v10, $v12, $v11
    vmadh   $v11, $v13, $v11
    vmudh   $v29, $v1, $v31[1]
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
    vmadn   $v10, $v10, $v0[0]
    vlt     $v11, $v11, $v1[0]
    vmrg    $v10, $v10, $v31[0]
    vsubc   $v29, $v10, $v1[0]
    vge     $v11, $v11, $v0[0]
    vmrg    $v10, $v10, $v1[0]
    vmudn   $v2, $v10, $v31[0]
    vmudl   $v29, $v6, $v10[3]
    vmadm   $v29, $v7, $v10[3]
    vmadl   $v29, $v4, $v2[3]
    vmadm   $v24, $v5, $v2[3]
    vmadn   $v23, $v0, $v0[0]
    vmudm   $v29, $v26, $v10[3]
    vmadm   $v22, $v25, $v2[3]
    li      $7, 0x0000
    li      $1, 0x0002
    sh      $15, (lbl_03D0)($21)
    j       f3dzex_000019F4
     addi   $ra, $zero, f3dzex_00001870 + 0x8000 // Why?

f3dzex_00001478:
.if (UCODE_IS_F3DEX2_204H)
    sdv     $v25[0], 0x03C8($15)
.else
    slv     $v25[0], 0x01C8($15)
.endif
    ssv     $v26[4], 0x00CE($15)
    suv     $v22[0], 0x03C0($15)
    slv     $v22[8], 0x01C4($15)
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    ssv     $v3[4], 0x00CC($15)
.endif
    addi    $15, $15, -0x0028
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
    vor     $v3, $v0, $v31[5]
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
.orga max(Overlay2End - Overlay2Address + orga(Overlay3Address), orga())
Overlay3End:

do_lighting equ $6
G_VTX_handler:
    lhu     $20, (vertexTable)(cmd_w0)      // Load the address of the provided vertex array
    jal     segmented_to_physical           // Convert the vertex array's segmented address (in $24) to a virtual one
     lhu    $1, (inputBufferEnd - 0x07)(inputBufferPos) // Load the size of the vertex array to copy into reg $1
    sub     $20, $20, $1                    // Calculate the address to DMA the provided vertices into
    jal     dma_read_write                  // DMA read the vertices from DRAM
     addi   $19, $1, -1                     // Set up the DMA length
    lhu     $5, geometryModeLabel           // Load the geometry mode into $5
    srl     $1, $1, 3
    sub     $15, cmd_w0, $1
    lhu     $15, (vertexTable)($15)
    move    $14, $20
    lbu     $8, mvpValid
    andi    $6, $5, G_LIGHTING_H
    bnez    $6, Overlay23LoadAddress    // This will always end up in overlay 2, as the start of overlay 3 loads and enters overlay 2
     andi   $7, $5, G_FOG_H
f3dzex_000017BC:
    bnez    $8, g_vtx_load_mvp  // Skip recalculating the mvp matrix if it's already up-to-date
     sll    $7, $7, 3
    sb      cmd_w0, mvpValid
    li      $21, pMatrix
    li      $20, mvMatrix
    // Calculate the MVP matrix
    jal     calculate_mvp_matrix
     li     $19, mvpMatrix

g_vtx_load_mvp:
    lqv     $v8,  (mvpMatrix +  0)($zero)  // load bytes  0-15 of the mvp matrix into v8
    lqv     $v10, (mvpMatrix + 16)($zero)  // load bytes 16-31 of the mvp matrix into v10
    lqv     $v12, (mvpMatrix + 32)($zero)  // load bytes 32-47 of the mvp matrix into v12
    lqv     $v14, (mvpMatrix + 48)($zero)  // load bytes 48-63 of the mvp matrix into v14

    vcopy   $v9, $v8                        // copy v8 into v9
    ldv     $v9, (mvpMatrix +  8)($zero)    // load bytes  8-15 of the mvp matrix into the lower half of v9
    vcopy   $v11, $v10                      // copy v10 into v11
    ldv     $v11, (mvpMatrix + 24)($zero)   // load bytes 24-31 of the mvp matrix into the lower half of v11
    vcopy   $v13, $v12                      // copy v10 into v11
    ldv     $v13, (mvpMatrix + 40)($zero)   // load bytes 40-47 of the mvp matrix into the lower half of v13
    vcopy   $v15, $v14                      // copy v10 into v11
    ldv     $v15, (mvpMatrix + 56)($zero)   // load bytes 56-63 of the mvp matrix into the lower half of v13

    ldv     $v8[8],  (mvpMatrix +  0)($zero)    // load bytes  0- 8 of the mvp matrix into the upper half of v8
    ldv     $v10[8], (mvpMatrix + 16)($zero)    // load bytes 16-23 of the mvp matrix into the upper half of v10
    jal     f3dzex_000019F4
     ldv    $v12[8], (mvpMatrix + 32)($zero)    // load bytes 32-39 of the mvp matrix into the upper half of v12
    jal     while_wait_dma_busy
     ldv    $v14[8], (mvpMatrix + 48)($zero)    // load bytes 48-55 of the mvp matrix into the upper half of v14
    ldv     $v20[0], (vtxSize * 0)($14)         // load the position of the 1st vertex into v20's lower 8 bytes
    vmov    $v16[5], $v21[1]                    // moves v21[1-2] into v16[5-6]
    ldv     $v20[8], (vtxSize * 1)($14)         // load the position of the 2nd vertex into v20's upper 8 bytes

f3dzex_0000182C:
    vmudn   $v29, $v15, $v1[0]
    lw      $11, 0x001C($14)        // load the color/normal of the 2nd vertex into $11
    vmadh   $v29, $v11, $v1[0]
    llv     $v22[12], 0x0008($14)   // load the texture coords of the 1st vertex into v22[12-15]
    vmadn   $v29, $v12, $v20[0h]
    move    $9, $6
    vmadh   $v29, $v8, $v20[0h]
    lpv     $v2[0], 0x00B0($9)
    vmadn   $v29, $v13, $v20[1h]
    sw      $11, 0x0008($14)
    vmadh   $v29, $v9, $v20[1h]
    lpv     $v7[0], 0x0008($14)
    vmadn   $v23, $v14, $v20[2h]
    bnez    $6, light_vtx           // If G_LIGHTING is on, then process vertices accordingly
     vmadh  $v24, $v10, $v20[2h]
    vge     $v27, $v25, $v31[3]
    llv     $v22[4], 0x0018($14)    // load the texture coords of the 2nd vertex into v22[4-7]
f3dzex_00001870:
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    vge     $v3, $v25, $v0[0]
.endif
    addi    $1, $1, -0x0004
    vmudl   $v29, $v23, $v18[4]
    sub     $11, $8, $7
    vmadm   $v2, $v24, $v18[4]
    sbv     $v27[15], 0x0073($11)
    vmadn   $v21, $v0, $v0[0]
    sbv     $v27[7], 0x004B($11)
.if !(UCODE_IS_F3DEX2_204H) // Not in F3DEX2 2.04H
    vmov    $v26[1], $v3[2]
    ssv     $v3[12], 0x00F4($8)
.endif
    vmudn   $v7, $v23, $v18[5]
.if (UCODE_IS_F3DEX2_204H)
    sdv     $v25[8], 0x03F0($8)
.else
    slv     $v25[8], 0x01F0($8)
.endif
    vmadh   $v6, $v24, $v18[5]
    sdv     $v25[0], 0x03C8($8)
    vrcph   $v29[0], $v2[3]
    ssv     $v26[12], 0x0F6($8)
    vrcpl   $v5[3], $v21[3]
.if (UCODE_IS_F3DEX2_204H)
    ssv     $v26[4], 0x00CE($8)
.else
    slv     $v26[2], 0x01CC($8)
.endif
    vrcph   $v4[3], $v2[7]
    ldv     $v3[0], 0x0008($14)
    vrcpl   $v5[7], $v21[7]
    sra     $11, $1, 31
    vrcph   $v4[7], $v0[0]
    andi    $11, $11, 0x0028
    vch     $v29, $v24, $v24[3h]
    addi    $15, $15, 0x0050
    vcl     $v29, $v23, $v23[3h]
    sub     $8, $15, $11
    vmudl   $v29, $v21, $v5
    cfc2    $10, $vcc
    vmadm   $v29, $v2, $v5
    sdv     $v23[8], 0x03E0($8)
    vmadn   $v21, $v21, $v4
    ldv     $v20[0], 0x0020($14)
    vmadh   $v2, $v2, $v4
    sdv     $v23[0], 0x03B8($15)
    vge     $v29, $v24, $v0[0]
    lsv     $v23[14], 0x00E4($8)
    vmudh   $v29, $v1, $v31[1]
    sdv     $v24[8], 0x03D8($8)
    vmadn   $v26, $v21, $v31[4]
    lsv     $v23[6], 0x00BC($15)
    vmadh   $v25, $v2, $v31[4]
    sdv     $v24[0], 0x03B0($15)
    vmrg    $v2, $v0, $v31[7]
    ldv     $v20[8], 0x0030($14)
    vch     $v29, $v24, $v6[3h]
    slv     $v3[0], 0x01E8($8)
    vmudl   $v29, $v26, $v5
    lsv     $v24[14], 0x00DC($8)
    vmadm   $v29, $v25, $v5
    slv     $v3[4], 0x01C0($15)
    vmadn   $v5, $v26, $v4
    lsv     $v24[6], 0x00B4($15)
    vmadh   $v4, $v25, $v4
    sh      $10, -0x0002($8)
    vmadh   $v2, $v2, $v31[7]
    sll     $11, $10, 4
    vcl     $v29, $v23, $v7[3h]
    cfc2    $10, $vcc
    vmudl   $v29, $v23, $v5[3h]
    ssv     $v5[14], 0x00FA($8)
    vmadm   $v29, $v24, $v5[3h]
    addi    $14, $14, 0x0020
    vmadn   $v26, $v23, $v2[3h]
    sh      $10, -0x0004($8)
    vmadh   $v25, $v24, $v2[3h]
    sll     $10, $10, 4
    vmudm   $v3, $v22, $v18
    sh      $11, -0x002A($15)
    sh      $10, -0x002C($15)
    vmudl   $v29, $v26, $v18[4]
    ssv     $v5[6], 0x00D2($15)
    vmadm   $v25, $v25, $v18[4]
    ssv     $v4[14], 0x00F8($8)
    vmadn   $v26, $v0, $v0[0]
    ssv     $v4[6], 0x00D0($15)
    slv     $v3[4], 0x01EC($8)
    vmudh   $v29, $v17, $v1[0]
    slv     $v3[12], 0x01C4($15)
    vmadh   $v29, $v19, $v31[3]
    vmadn   $v26, $v26, $v16
    bgtz    $1, f3dzex_0000182C
     vmadh  $v25, $v25, $v16
    bltz    $ra, f3dzex_00001478    // has a different version in ovl2
.if !(UCODE_IS_F3DEX2_204H) // Handled differently by F3DEX2 2.04H
     vge    $v3, $v25, $v0[0]
    slv     $v25[8], 0x01F0($8)
    vge     $v27, $v25, $v31[3]
    slv     $v25[0], 0x01C8($15)
    ssv     $v26[12], 0x00F6($8)
    ssv     $v26[4], 0x00CE($15)
    ssv     $v3[12], 0x00F4($8)
    beqz    $7, run_next_DL_command
     ssv    $v3[4], 0x00CC($15)
.else // This is the F3DEX2 2.04H version
     vge    $v27, $v25, $v31[3]
    sdv     $v25[8], 0x03F0($8)
    sdv     $v25[0], 0x03C8($15)
    ssv     $v26[12], 0x00F6($8)
    beqz    $7, run_next_DL_command
     ssv    $v26[4], 0x00CE($15)
.endif
    sbv     $v27[15], 0x006B($8)
    j       run_next_DL_command
     sbv    $v27[7], 0x0043($15)

f3dzex_000019F4: // handle clipping?
    li      curClipRatio, clipRatio
    ldv     $v16[0], (viewport)($zero)
    ldv     $v16[8], (viewport)($zero)
    llv     $v29[0], 0x0060(curClipRatio)
    ldv     $v17[0], (viewport + 8)($zero)
    ldv     $v17[8], (viewport + 8)($zero)
    vlt     $v19, $v31, $v31[3]
    vsub    $v21, $v0, $v16
    llv     $v18[4], 0x0068(curClipRatio)
    vmrg    $v16, $v16, $v29[0]
    llv     $v18[12], 0x0068(curClipRatio)
    vmrg    $v19, $v0, $v1[0]
    llv     $v18[8], (perspNorm + 2)($zero)
    vmrg    $v17, $v17, $v29[1]
    lsv     $v18[10], 0x0006(curClipRatio)
    vmov    $v16[1], $v21[1]
    jr      $ra
     addi   $8, $23, 0x0050

G_TRI2_handler:
G_QUAD_handler:
    jal     f3dzex_00001A4C
     sw     cmd_w1, 0x0004($23)
G_TRI1_handler:
    li      $ra, run_next_DL_command
    sw      cmd_w0, 0x0004($23) // store the command word (cmd_w0) into address $23 + 4
f3dzex_00001A4C:
    lpv     $v2[0], 0x0000($23)
    // read the three vertex indices from the stored command word
    lbu     $1, 0x0005($23)     // $1 = vertex 1 index
    lbu     $2, 0x0006($23)     // $2 = vertex 2 index
    lbu     $3, 0x0007($23)     // $3 = vertex 3 index
    vor     $v3, $v0, $v31[5]
    lhu     $1, (vertexTable)($1) // convert vertex 1's index to its address
    vmudn   $v4, $v1, $v31[6]
    lhu     $2, (vertexTable)($2) // convert vertex 2's index to its address
    vmadl   $v2, $v2, $v30[1]
    lhu     $3, (vertexTable)($3) // convert vertex 3's index to its address
    vmadn   $v4, $v0, $v0[0]
    move    $4, $1
f3dzex_00001A7C:
    vnxor   $v5, $v0, $v31[7]
    llv     $v6[0], 0x0018($1)
    vnxor   $v7, $v0, $v31[7]
    llv     $v4[0], 0x0018($2)
    vmov    $v6[6], $v2[5]
    llv     $v8[0], 0x0018($3)
    vnxor   $v9, $v0, $v31[7]
    lw      $5, 0x0024($1)
    vmov    $v8[6], $v2[7]
    lw      $6, 0x0024($2)
    vadd    $v2, $v0, $v6[1]
    lw      $7, 0x0024($3)
    vsub    $v10, $v6, $v4
.if NoN == 1
    andi    $11, $5, 0x70B0 // No Nearclipping
.else
    andi    $11, $5, 0x7070 // Nearclipping
.endif
    vsub    $v11, $v4, $v6
    and     $11, $6, $11
    vsub    $v12, $v6, $v8
    and     $11, $7, $11
    vlt     $v13, $v2, $v4[1]
    vmrg    $v14, $v6, $v4
    bnez    $11, return_routine
     lbu    $11, geometryModeLabel + 2  // Loads the geometry mode byte that contains face culling settings
    vmudh   $v29, $v10, $v12[1]
    lw      $12, nearclipValue
    vmadh   $v29, $v12, $v11[1]
    or      $5, $5, $6
    vge     $v2, $v2, $v4[1]
    or      $5, $5, $7
    vmrg    $v10, $v6, $v4
    lw      $11, (cullFaceValues)($11)
    vge     $v6, $v13, $v8[1]
    mfc2    $6, $v29[0]
    vmrg    $v4, $v14, $v8
    and     $5, $5, $12
    vmrg    $v14, $v8, $v14
    bnez    $5, f3dzex_ov2_000012E4 // has a different version in ovl3
     add     $11, $6, $11
    vlt     $v6, $v6, $v2
    bgez    $11, return_routine
     vmrg    $v2, $v4, $v10
    vmrg    $v10, $v10, $v4
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
    vreadacc $v17, ACC_LOWER
    bgez    $11, no_smooth_shading  // Branch if G_SHADING_SMOOTH isn't set
     vreadacc $v16, ACC_MIDDLE
    lpv     $v18[0], 0x0010($1)
    vmov    $v15[2], $v6[0]
    lpv     $v19[0], 0x0010($2)
    vrcp    $v20[0], $v15[1]
    lpv     $v21[0], 0x0010($3)
    vrcph   $v22[0], $v17[1]
    vrcpl   $v23[1], $v16[1]
    j       shading_done
     vrcph   $v24[1], $v0[0]
no_smooth_shading:
    lpv     $v18[0], 0x0010($4)
    vrcp    $v20[0], $v15[1]
    lbv     $v18[6], 0x0013($1)
    vrcph   $v22[0], $v17[1]
    lpv     $v19[0], 0x0010($4)
    vrcpl   $v23[1], $v16[1]
    lbv     $v19[6], 0x0013($2)
    vrcph   $v24[1], $v0[0]
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
    vrcph   $v22[2], $v6[1]
    lw      $5, 0x0020($1)
    vrcp    $v20[3], $v8[1]
    lw      $7, 0x0020($2)
    vrcph   $v22[3], $v8[1]
    lw      $8, 0x0020($3)
    vmudl   $v18, $v18, $v30[i1]    // v30[i1] is 0x0100
    lbu     $9, textureSettings1 + 3
    vmudl   $v19, $v19, $v30[i1]    // v30[i1] is 0x0100
    sub     $11, $5, $7
    vmudl   $v21, $v21, $v30[i1]    // v30[i1] is 0x0100
    sra     $12, $11, 31
    vmov    $v15[3], $v8[0]
    and     $11, $11, $12
    vmudl   $v29, $v20, $vec1[i2]
    sub     $5, $5, $11
    vmadm   $v22, $v22, $vec1[i2]
    sub     $11, $5, $8
    vmadn   $v20, $v0, $v0[0]
    sra     $12, $11, 31
    vmudm   $v25, $v15, $vec1[i3]
    and     $11, $11, $12
    vmadn   $v15, $v0, $v0[0]
    sub     $5, $5, $11
    vsubc   $v4, $v0, $v4
    sw      $5, 0x0010($23)
    vsub    $v26, $v0, $v0
    llv     $v27[0], 0x0010($23)
    vmudm   $v29, $v25, $v20
    mfc2    $5, $v17[1]
    vmadl   $v29, $v15, $v20
    lbu     $7, textureSettings1 + 2
    vmadn   $v20, $v15, $v22
    lsv     $v19[14], 0x001C($2)
    vmadh   $v15, $v25, $v22
    lsv     $v21[14], 0x001C($3)
    vmudl   $v29, $v23, $v16
    lsv     $v7[14], 0x001E($2)
    vmadm   $v29, $v24, $v16
    lsv     $v9[14], 0x001E($3)
    vmadn   $v16, $v23, $v17
    ori     $11, $6, 0x00C8
    vmadh   $v17, $v24, $v17
    or      $11, $11, $9
.if !(UCODE_IS_206_OR_OLDER)
    vand    $v22, $v20, $v30[5]
.endif
    vcr     $v15, $v15, $v30[i4]
    sb      $11, 0x0000($23)
    vmudh   $v29, $v1, $v30[i5]
    ssv     $v10[2], 0x0002($23)
    vmadn   $v16, $v16, $v30[4]     // v30[4] is 0xFFF0
    ssv     $v2[2], 0x0004($23)
    vmadh   $v17, $v17, $v30[4]     // v30[4] is 0xFFF0
    ssv     $v14[2], 0x0006($23)
    vmudn   $v29, $v3, $v14[0]
    andi    $12, $5, 0x0080
    vmadl   $v29, $vec2, $v4[1]
    or      $12, $12, $7
    vmadm   $v29, $v15, $v4[1]
    sb      $12, 0x0001($23)
    vmadn   $v2, $vec2, $v26[1]
    beqz    $9, f3dzex_00001D2C
    vmadh   $v3, $v15, $v26[1]
    vrcph   $v29[0], $v27[0]
    vrcpl   $v10[0], $v27[1]
    vadd    $v14, $v0, $v13[1q]
    vrcph   $v27[0], $v0[0]
    vor     $v22, $v0, $v31[7]
    vmudm   $v29, $v13, $v10[0]
    vmadl   $v29, $v14, $v10[0]
    llv     $v22[0], 0x0014($1)
    vmadn   $v14, $v14, $v27[0]
    llv     $v22[8], 0x0014($2)
    vmadh   $v13, $v13, $v27[0]
    vor     $v10, $v0, $v31[7]
    vge     $v29, $v30, $v30[7]
    llv     $v10[8], 0x0014($3)
    vmudm   $v29, $v22, $v14[0h]
    vmadh   $v22, $v22, $v13[0h]
    vmadn   $v25, $v0, $v0[0]
    vmudm   $v29, $v10, $v14[6]
    vmadh   $v10, $v10, $v13[6]
    vmadn   $v13, $v0, $v0[0]
    sdv     $v22[0], 0x0020($23)
    vmrg    $v19, $v19, $v22
    sdv     $v25[0], 0x0028($23) // 8
    vmrg    $v7, $v7, $v25
    ldv     $v18[8], 0x0020($23) // 8
    vmrg    $v21, $v21, $v10
    ldv     $v5[8], 0x0028($23) // 8
    vmrg    $v9, $v9, $v13
f3dzex_00001D2C:
    vmudl   $v29, $v16, $v23
    lsv     $v5[14], 0x001E($1)
    vmadm   $v29, $v17, $v23
    lsv     $v18[14], 0x001C($1)
    vmadn   $v23, $v16, $v24
    lh      $1, 0x0018($2)
    vmadh   $v24, $v17, $v24
    addiu   $2, $23, 0x0020
    vsubc   $v10, $v9, $v5
    andi    $3, $6, 0x0004
    vsub    $v9, $v21, $v18
    sll     $1, $1, 14
    vsubc   $v13, $v7, $v5
    sw      $1, 0x0008($23)
    vsub    $v7, $v19, $v18
    ssv     $v3[6], 0x0010($23)
    vmudn   $v29, $v10, $v6[1]
    ssv     $v2[6], 0x0012($23)
    vmadh   $v29, $v9, $v6[1]
    ssv     $v3[4], 0x0018($23)
    vmadn   $v29, $v13, $v12[1]
    ssv     $v2[4], 0x001A($23)
    vmadh   $v29, $v7, $v12[1]
    ssv     $v15[0], 0x000C($23)
    vreadacc $v2, ACC_MIDDLE
    ssv     $v20[0], 0x000E($23)
    vreadacc $v3, ACC_LOWER
    ssv     $v15[6], 0x0014($23)
    vmudn   $v29, $v13, $v8[0]
    ssv     $v20[6], 0x0016($23)
    vmadh   $v29, $v7, $v8[0]
    ssv     $v15[4], 0x001C($23)
    vmadn   $v29, $v10, $v11[0]
    ssv     $v20[4], 0x001E($23)
    vmadh   $v29, $v9, $v11[0]
    sll     $11, $3, 4
    vreadacc $v6, ACC_MIDDLE
    add     $1, $2, $11
    vreadacc $v7, ACC_LOWER
    sll     $11, $9, 5
    vmudl   $v29, $v2, $v23[1]
    add     $23, $1, $11
    vmadm   $v29, $v3, $v23[1]
    andi    $6, $6, 0x0001
    vmadn   $v2, $v2, $v24[1]
    sll     $11, $6, 4
    vmadh   $v3, $v3, $v24[1]
    add     $23, $23, $11
    vmudl   $v29, $v6, $v23[1]
    vmadm   $v29, $v7, $v23[1]
    vmadn   $v6, $v6, $v24[1]
    sdv     $v2[0], 0x0018($2)
    vmadh   $v7, $v7, $v24[1]
    sdv     $v3[0], 0x0008($2)
    vmadl   $v29, $v2, $v20[3]
    sdv     $v2[8], 0x0018($1)
    vmadm   $v29, $v3, $v20[3]
    sdv     $v3[8], 0x0008($1)
    vmadn   $v8, $v2, $v15[3]
    sdv     $v6[0], 0x0038($2)
    vmadh   $v9, $v3, $v15[3]
    sdv     $v7[0], 0x0028($2)
    vmudn   $v29, $v5, $v1[0]
    sdv     $v6[8], 0x0038($1)
    vmadh   $v29, $v18, $v1[0]
    sdv     $v7[8], 0x0028($1)
    vmadl   $v29, $v8, $v4[1]
    sdv     $v8[0], 0x0030($2)
    vmadm   $v29, $v9, $v4[1]
    sdv     $v9[0], 0x0020($2)
    vmadn   $v5, $v8, $v26[1]
    sdv     $v8[8], 0x0030($1)
    vmadh   $v18, $v9, $v26[1]
    sdv     $v9[8], 0x0020($1)
    vmudn   $v10, $v8, $v4[1]
    beqz    $6, f3dzex_00001EB4
     vmudn  $v8, $v8, $v30[i6]      // v30[i6] is 0x0020
    vmadh   $v9, $v9, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v5[0], 0x0010($2)
    vmudn   $v2, $v2, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v18[0], 0x0000($2)
    vmadh   $v3, $v3, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v5[8], 0x0010($1)
    vmudn   $v6, $v6, $v30[i6]      // v30[i6] is 0x0020
    sdv     $v18[8], 0x0000($1)
    vmadh   $v7, $v7, $v30[i6]      // v30[i6] is 0x0020
    ssv     $v8[14], 0x00FA($23)
    vmudl   $v29, $v10, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v9[14], 0x00F8($23)
    vmadn   $v5, $v5, $v30[i6]      // v30[i6] is 0x0020
    ssv     $v2[14], 0x00F6($23)
    vmadh   $v18, $v18, $v30[i6]    // v30[i6] is 0x0020
    ssv     $v3[14], 0x00F4($23)
    ssv     $v6[14], 0x00FE($23)
    ssv     $v7[14], 0x00FC($23)
    ssv     $v5[14], 0x00F2($23)
    j       f3dzex_0000125C
    ssv     $v18[14], 0x00F0($23)

f3dzex_00001EB4:
    sdv     $v5[0], 0x0010($2)
    sdv     $v18[0], 0x0000($2)
    sdv     $v5[8], 0x0010($1)
    j       f3dzex_0000125C
     sdv    $v18[8], 0x0000($1)

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
     addiu  vtxPtr, vtxPtr, 0x0028          // advance to the next vertex
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

.orga 0xF2C

// This subroutine sets up the values to load overlay 0 and then falls through
// to load_overlay_and_enter to execute the load.
load_overlay_0_and_enter:
G_LOAD_UCODE_handler:
    li      $12, Overlay0Address    // Sets up return address
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
Overlay0Address:
    sub     $11, $23, $22
    addiu   $12, $11, 0x0157
    bgezal  $12, f3dzex_00001264
     nop
    jal     while_wait_dma_busy
     lw     $24, lbl_00F0
    bltz    $1, taskdone_and_break
     mtc0   $24, DPC_END            // Set the end pointer of the RDP so that it starts the task
    bnez    $1, task_yield
     add    taskDataPtr, taskDataPtr, inputBufferPos
    lw      $24, 0x09C4(inputBufferPos) // Should this be (inputBufferEnd - 0x04)?
    sw      taskDataPtr, OSTask + OSTask_data_ptr
    sw      $24, OSTask + OSTask_ucode
    la      $20, start              // DMA address
    jal     dma_read_write          // initiate DMA read
     li     $19, 0x0F48 - 1
    lw      $24, rdpHalf1Val
    la      $20, clipRatio          // DMA address
    andi    $19, cmd_w0, 0x0FFF
    add     $24, $24, $20
    jal     dma_read_write          // initate DMA read
     sub    $19, $19, $20
    j       while_wait_dma_busy
.if (UCODE_IS_F3DEX2_204H)
     li     $ra, taskdone_and_break_204H
.else
     li     $ra, taskdone_and_break
.endif

ucode equ $11
status equ $12
task_yield:
    lw      ucode, OSTask + OSTask_ucode
    sw      taskDataPtr, lbl_0BF8
    sw      ucode, lbl_0BFC
    li      status, SP_SET_SIG1 | SP_SET_SIG2   // yielded and task done signals
    lw      $24, OSTask + OSTask_yield_data_ptr
    li      $20, -0x8000
    li      $19, OS_YIELD_DATA_SIZE - 1
    j       dma_read_write
taskdone_and_break_204H: // Only used in f3dex2 2.04H
     li     $ra, break
taskdone_and_break:
    li      status, SP_SET_SIG2   // task done signal
break:
    mtc0    status, SP_STATUS
    break   0
    nop

.align 8
Overlay0End:

// overlay 1 (0x170 bytes loaded into 0x1000)
.headersize 0x00001000 - orga()

Overlay1Address:

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
     sw     $zero, mvpValid                 // Mark the MVP matrix as being out of date

G_D1_handler: // unknown D1 command?
    lhu     $19, 0x02F2($1)
    jal     while_wait_dma_busy
     lhu    $21, 0x02F2($1)
    li      $ra, run_next_DL_command

pMatrixPtr equ $21
mvMatrixPtr equ $20
mvpMatrixPtr equ $19
calculate_mvp_matrix:
    addi    $12, mvMatrixPtr, 0x0018
@@loop:
    vmadn   $v9, $v0, $v0[0]
    addi    $11, mvMatrixPtr, 0x0008
    vmadh   $v8, $v0, $v0[0]
    addi    pMatrixPtr, pMatrixPtr, -0x0020
    vmudh   $v29, $v0, $v0[0]
@@innerloop:
    ldv     $v5[0], 0x0040(pMatrixPtr)
    ldv     $v5[8], 0x0040(pMatrixPtr)
    lqv     $v3[0], 0x0020(mvMatrixPtr)
    ldv     $v4[0], 0x0020(pMatrixPtr)
    ldv     $v4[8], 0x0020(pMatrixPtr)
    lqv     $v2[0], 0x0000(mvMatrixPtr)
    vmadl   $v29, $v5, $v3[0h]
    addi    mvMatrixPtr, mvMatrixPtr, 0x0002
    vmadm   $v29, $v4, $v3[0h]
    addi    pMatrixPtr, pMatrixPtr, 0x0008
    vmadn   $v7, $v5, $v2[0h]
    bne     mvMatrixPtr, $11, @@innerloop
     vmadh  $v6, $v4, $v2[0h]
    bne     mvMatrixPtr, $12, @@loop
     addi   mvMatrixPtr, mvMatrixPtr, 0x0008
    // Store the results in the passed in matrix
    sqv     $v9[0], 0x0020(mvpMatrixPtr)
    sqv     $v8[0], 0x0000(mvpMatrixPtr)
    sqv     $v7[0], 0x0030(mvpMatrixPtr)
    jr      $ra
     sqv    $v6[0], 0x0010(mvpMatrixPtr)

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
    sw      $zero, mvpValid     // Mark the mvp matrix as out-of-date
G_MOVEMEM_handler:
    jal     segmented_to_physical   // convert the memory address cmd_w1 to a virtual one
do_movemem:
     andi   $1, cmd_w0, 0x00FE                           // Move the movemem table index into $1 (bits 1-7 of the first command word)
    lbu     $19, (inputBufferEnd - 0x07)(inputBufferPos) // Move the second byte of the first command word into $19
    lhu     $20, (movememTable)($1)                      // Load the address of the memory location for the given movemem index
    srl     $2, cmd_w0, 5                                // Left shifts the index by 5 (which is then added to the value read from the movemem table)
    lhu     $ra, (overlayInfo2 + 2 - G_MOVEMEM)($12)     // Loads the return address based on command byte?
    j       dma_read_write
G_SETOTHERMODE_H_handler:
     add    $20, $20, $2
G_SETOTHERMODE_L_handler:
    lw      $3, -0x1074($11)
    lui     $2, 0x8000
    srav    $2, $2, cmd_w0
    srl     $1, cmd_w0, 8
    srlv    $2, $2, $1
    nor     $2, $2, $zero
    and     $3, $3, $2
    or      $3, $3, cmd_w1
    sw      $3, -0x1074($11)
    lw      cmd_w0, otherMode0
    j       G_RDP_handler
     lw     cmd_w1, otherMode1

.align 8
Overlay1End:

.headersize Overlay23LoadAddress - orga()

Overlay2Address:
    lbu     $11, numLights + 2
    j       f3dzex_ov2_000012F4
     lbu    $6, numLights + 3

f3dzex_ov2_000012E4:
    move    savedRA, $ra
    li      $11, overlayInfo3           // set up a load of overlay 3
    j       load_overlay_and_enter      // load overlay 3
     li     $12, f3dzex_ov3_000012E8    // set up the return address in ovl3

f3dzex_ov2_000012F4:
    bnez    $11, f3dzex_000017BC // branch if number of lights non zero?
     addi   $6, $6, lightColors - 0x10 - (7 * 0x18)
    sb      cmd_w0, numLights + 2
    // mv[x][y] is row x, column y
    // Matrix integer portion vector registers
    col0int equ $v8     // used to hold rows 0-1 temporarily
    col1int equ $v9
    col2int equ $v10
    // Matrix fractional portion vector registers
    col0fra equ $v12    // used to hold rows 0-1 temporarily
    col1fra equ $v13
    col2fra equ $v14
    // Set up the column registers
    lqv     col0fra,    (mvMatrix + 0x20)($zero)    // load rows 0-1 of mv (fractional)
    lqv     col0int,    (mvMatrix + 0x00)($zero)    // load rows 0-1 of mv (integer)
    lsv     col1fra[2], (mvMatrix + 0x2A)($zero)    // load mv[1][1] into col1 element 1 (fractional)
    lsv     col1int[2], (mvMatrix + 0x0A)($zero)    // load mv[1][1] into col1 element 1 (integer)
    vmov    col1fra[0], col0fra[1]                  // load mv[0][1] into col1 element 0 (fractional)
    lsv     col2fra[4], (mvMatrix + 0x34)($zero)    // load mv[2][2] into col2 element 2 (fractional)
    vmov    col1int[0], col0int[1]                  // load mv[0][1] into col1 element 0 (integer)
    lsv     col2int[4], (mvMatrix + 0x14)($zero)    // load mv[2][2] into col2 element 2 (integer)
    vmov    col2fra[0], col0fra[2]                  // load mv[0][2] into col2 element 0 (fractional)
    li      $20, lightBuffer - (7 * 0x18) + 8       // set up pointer to light direction
    vmov    col2int[0], col0int[2]                  // load mv[0][2] into col2 element 0 (integer)
    lpv     $v7[0], (7 * 0x18)($20)                 // load light direction
    vmov    col2fra[1], col0fra[6]                  // load mv[1][2] into col2 element 1 (fractional)
    lsv     col1fra[4], (mvMatrix + 0x32)($zero)    // load mv[2][1] into col1 element 2 (fractional)
    vmov    col2int[1], col0int[6]                  // load mv[1][2] into col2 element 1 (integer)
    lsv     col1int[4], (mvMatrix + 0x12)($zero)    // load mv[2][1] into col1 element 2 (integer)
    vmov    col0fra[1], col0fra[4]                  // load mv[1][0] into col0 element 1 (fractional)
    lsv     col0fra[4], (mvMatrix + 0x30)($zero)    // load mv[2][0] into col0 element 2 (fractional)
    vmov    col0int[1], col0int[4]                  // load mv[1][0] into col0 element 1 (integer)
    lsv     col0int[4], (mvMatrix + 0x10)($zero)    // load mv[2][0] into col0 element 2 (integer)
@@loop:
    vmudn   $v29, col1fra, $v7[1]           // light y direction (fractional)
    vmadh   $v29, col1int, $v7[1]           // light y direction (integer)
    vmadn   $v29, col0fra, $v7[0]           // light x direction (fractional)
    spv     $v15[0], (7 * 0x18 + 8)($20)
    vmadh   $v29, col0int, $v7[0]           // light x direction (integer)
    lw      $12, (7 * 0x18 + 8)($20)
    vmadn   $v29, col2fra, $v7[2]           // light z direction (fractional)
    vmadh   $v29, col2int, $v7[2]           // light z direction (integer)
    vreadacc $v11, ACC_MIDDLE
    sw      $12, (7 * 0x18 + 0xC)($20)
    vreadacc $v15, ACC_LOWER
    beq     $20, $6, f3dzex_000017BC        // exit if equal
     vmudl  $v29, $v11, $v11
    vmadm   $v29, $v15, $v11
    vmadn   $v16, $v11, $v15
    beqz    $11, @@skip_incr    // skip increment if $11 is 0
     vmadh  $v17, $v15, $v15
    addi    $20, $20, 0x18      // increment light pointer?
@@skip_incr:
    vaddc   $v18, $v16, $v16[1]
    li      $11, 1
    vadd    $v29, $v17, $v17[1]
    vaddc   $v16, $v18, $v16[2]
    vadd    $v17, $v29, $v17[2]
    vrsqh   $v29[0], $v17[0]
    lpv     $v7[0], (7 * 0x18 + 0x18)($20)
    vrsql   $v16[0], $v16[0]
    vrsqh   $v17[0], $v0[0]
    vmudl   $v29, $v11, $v16[0]
    vmadm   $v29, $v15, $v16[0]
    vmadn   $v11, $v11, $v17[0]
    vmadh   $v15, $v15, $v17[0]
.if (UCODE_IS_206_OR_OLDER)
    i7 equ 7
.else
    i7 equ 3
.endif
    vmudn   $v11, $v11, $v30[i7]
    j       @@loop
     vmadh  $v15, $v15, $v30[i7]

light_vtx:
    vadd    $v6, $v0, $v7[1h]
.if UCODE_HAS_POINT_LIGHTING // Point lighting difference
    luv     $v29[0], 0x00B8($9) // load light position?
.else // No point lighting
    lpv     $v20[0], 0x0098($9) // load light direction?
.endif
    vadd    $v5, $v0, $v7[2h]
    luv     $v27[0], 0x0008($14)
    vne     $v4, $v31, $v31[3h]
.if UCODE_HAS_POINT_LIGHTING // point lighting
    andi    $11, $5, G_LIGHTING_POSITIONAL_H    // check if point lighting is enabled in the geometry mode
    beqz    $11, f3dzex_ovl2_0000168C           // if not enabled, skip ahead
     li     $12, -0x7F80
    vaddc   $v28, $v27, $v0[0]
    suv     $v29[0], 0x0008($14)
    ori     $11, $zero, 0x0004
    vmov    $v30[7], $v30[6]
    mtc2    $11, $v31[6]
f3dzex_ovl2_0000140C:
    lbu     $11, 0x00A3($9)             // load light type / constant attenuation value at light structure + 3 ?
    bnez    $11, f3dzex_ovl2_0000155C   // If not zero, use point lighting?
     lpv    $v2[0], 0x00B0($9)
    luv     $v29[0], 0x0008($14)
    vmulu   $v20, $v7, $v2[0h]
    vmacu   $v20, $v6, $v2[1h]
    vmacu   $v20, $v5, $v2[2h]
    luv     $v2[0], 0x00A0($9)
    vmrg    $v29, $v29, $v28
    vand    $v20, $v20, $v31[7]
    vmrg    $v2, $v2, $v0[0]
    vmulf   $v29, $v29, $v31[7]
    vmacf   $v29, $v2, $v20[0h]
    suv     $v29[0], 0x0008($14)
    bne     $9, curClipRatio, f3dzex_ovl2_0000140C
     addi   $9, $9, -0x18
f3dzex_ovl2_0000144C:
    lqv     $v31[0], (v31Value)($zero)
    lqv     $v30[0], (v30Value)($zero)
    llv     $v22[4], 0x0018($14)
    bgezal  $12, f3dzex_ovl2_00001480
     li     $12, -0x7F80
    andi    $11, $5, G_TEXTURE_GEN_H
    vmrg    $v3, $v0, $v31[5]
    beqz    $11, f3dzex_00001870
     vge    $v27, $v25, $v31[3]
    lpv     $v2[0], 0x00B0($9)
    lpv     $v20[0], 0x0098($9)
f3dzex_ovl2_00001478:
    j       f3dzex_ovl2_00001708
     vmulf  $v21, $v7, $v2[0h]

f3dzex_ovl2_00001480: // $12 is either 0 or -0x7F80
    lqv     $v8[0], 0x0000($12)
    lqv     $v10[0], 0x0010($12)
    lqv     $v12[0], 0x0020($12)
    lqv     $v14[0], 0x0030($12)
    vcopy   $v9, $v8
    ldv     $v9[0], 0x0008($12)
    vcopy   $v11, $v10
    ldv     $v11[0], 0x0018($12)
    vcopy   $v13, $v12
    ldv     $v13[0], 0x0028($12)
    vcopy   $v15, $v14
    ldv     $v15[0], 0x0038($12)
    ldv     $v8[8], 0x0000($12)
    ldv     $v10[8], 0x0010($12)
    ldv     $v12[8], 0x0020($12)
    jr      $ra
     ldv    $v14[8], 0x0030($12)

f3dzex_ovl2_000014C4:
    lsv     $v4[0], (mvMatrix)($zero)
    lsv     $v3[0], (mvMatrix + 0x20)($zero)
    lsv     $v21[0], (mvMatrix + 2)($zero)
    lsv     $v28[0], (mvMatrix + 0x22)($zero)
    lsv     $v30[0], (mvMatrix + 4)($zero)
    vmov    $v4[4], $v4[0]
    lsv     $v31[0], (mvMatrix + 0x24)($zero)
    vmov    $v3[4], $v3[0]
    lsv     $v4[2], (mvMatrix + 8)($zero)
    vmov    $v21[4], $v21[0]
    lsv     $v3[2], (mvMatrix + 0x28)($zero)
    vmov    $v28[4], $v28[0]
    lsv     $v21[2], (mvMatrix + 0xA)($zero)
    vmov    $v30[4], $v30[0]
    lsv     $v28[2], (mvMatrix + 0x2A)($zero)
    vmov    $v31[4], $v31[0]
    lsv     $v30[2], (mvMatrix + 0xC)($zero)
    vmov    $v4[5], $v4[1]
    lsv     $v31[2], (mvMatrix + 0x2C)($zero)
    vmov    $v3[5], $v3[1]
    lsv     $v4[4], (mvMatrix + 0x10)($zero)
    vmov    $v21[5], $v21[1]
    lsv     $v3[4], (mvMatrix + 0x30)($zero)
    vmov    $v28[5], $v28[1]
    lsv     $v21[4], (mvMatrix + 0x12)($zero)
    vmov    $v30[5], $v30[1]
    lsv     $v28[4], (mvMatrix + 0x32)($zero)
    vmov    $v31[5], $v31[1]    // v31[1] is 4
    lsv     $v30[4], (mvMatrix + 0x14)($zero)
    vmov    $v4[6], $v4[2]
    lsv     $v31[4], (mvMatrix + 0x34)($zero)
    vmov    $v3[6], $v3[2]
    or      $12, $zero, $zero
    vmov    $v21[6], $v21[2]
    vmov    $v28[6], $v28[2]
    vmov    $v30[6], $v30[2]
    j       f3dzex_ovl2_00001480
     vmov   $v31[6], $v31[2]    // v31[2] is 8

/*
v31Value:
.dh 0xFFFF // [0]
.dh 0x0004 // [1]
.dh 0x0008 // [2]
.dh 0x7F00 // [3]
.dh 0xFFFC // [4]
.dh 0x4000 // [5]
.dh 0x0420 // [6]
.dh 0x7FFF // [7]
*/
f3dzex_ovl2_0000155C:
    ldv     $v20[8], 0x0000($14)
    bltzal  $12, f3dzex_ovl2_000014C4
     ldv    $v20[0], 0x0010($14)
    vmudn   $v2, $v15, $v1[0]
    ldv     $v29[0], 0x00A8($9)
    vmadh   $v2, $v11, $v1[0]
    vmadn   $v2, $v12, $v20[0h]
    vmadh   $v2, $v8, $v20[0h]
    vmadn   $v2, $v13, $v20[1h]
    ldv     $v29[8], 0x00A8($9)
    vmadh   $v2, $v9, $v20[1h]
    vmadn   $v2, $v14, $v20[2h]
    vmadh   $v2, $v10, $v20[2h]
    vsub    $v20, $v29, $v2
    vmrg    $v29, $v20, $v0[0]
    vmudh   $v2, $v29, $v29
    vreadacc $v2, ACC_LOWER
    vreadacc $v29, ACC_MIDDLE
    vaddc   $v29, $v29, $v29[0q]
    vadd    $v2, $v2, $v2[0q]
    vaddc   $v29, $v29, $v29[2h]
    vadd    $v2, $v2, $v2[2h]
    vrsqh   $v29[3], $v2[1]
    vrsql   $v29[3], $v29[1]
    vrsqh   $v29[2], $v2[5]
    vrsql   $v29[7], $v29[5]
    vrsqh   $v29[6], $v0[0]
    vmudn   $v2, $v3, $v20[0h]
    sll     $11, $11, 4
    vmadh   $v2, $v4, $v20[0h]
    lbu     $24, 0x00AE($9)
    vmadn   $v2, $v28, $v20[1h]
    mtc2    $11, $v27[0]
    vmadh   $v2, $v21, $v20[1h]
    vmadn   $v2, $v31, $v20[2h]
    vmadh   $v20, $v30, $v20[2h]
    vmudm   $v2, $v20, $v29[3h]
    vmadh   $v20, $v20, $v29[2h]
    vmudn   $v2, $v2, $v31[3]
    vmadh   $v20, $v20, $v31[3]
    vmulu   $v2, $v7, $v20[0h]
    mtc2    $11, $v27[8]
    vmacu   $v2, $v6, $v20[1h]
    lbu     $11, 0x00A7($9)
    vmacu   $v2, $v5, $v20[2h]
    sll     $24, $24, 5
    vand    $v20, $v2, $v31[7]
    mtc2    $24, $v20[14]
    vrcph   $v29[0], $v29[2]
    vrcpl   $v29[0], $v29[3]
    vrcph   $v29[4], $v29[6]
    vrcpl   $v29[4], $v29[7]
    vmudh   $v2, $v29, $v30[7]
    mtc2    $11, $v20[6]
    vmudl   $v2, $v2, $v2[0h]
    vmulf   $v29, $v29, $v20[3]
    vmadm   $v29, $v2, $v20[7]
    vmadn   $v29, $v27, $v30[3]
    vreadacc $v2, ACC_MIDDLE
    vrcph   $v2[0], $v2[0]
    vrcpl   $v2[0], $v29[0]
    vrcph   $v2[4], $v2[4]
    vrcpl   $v2[4], $v29[4]
    luv     $v29[0], 0x0008($14)
    vand    $v2, $v2, $v31[7]
    vmulf   $v2, $v2, $v20
    luv     $v20[0], 0x00A0($9)
    vmrg    $v29, $v29, $v28
    vand    $v2, $v2, $v31[7]
    vmrg    $v20, $v20, $v0[0]
    vmulf   $v29, $v29, $v31[7]
    vmacf   $v29, $v20, $v2[0h]
    suv     $v29[0], 0x0008($14)
    bne     $9, curClipRatio, f3dzex_ovl2_0000140C
     addi   $9, $9, -0x18
    j       f3dzex_ovl2_0000144C
f3dzex_ovl2_0000168C:
     lpv     $v20[0], 0x0098($9)
.else // No point lighting
    luv     $v29[0], 0x00B8($9)
.endif
f3dzex_ovl2_00001690:
    vmulu   $v21, $v7, $v2[0h]
    luv     $v4[0], 0x00A0($9)
    vmacu   $v21, $v6, $v2[1h]
    beq     $9, curClipRatio, f3dzex_ovl2_00001758
     vmacu  $v21, $v5, $v2[2h]
    vmulu   $v28, $v7, $v20[0h]
    luv     $v3[0], 0x0088($9)
    vmacu   $v28, $v6, $v20[1h]
    addi    $11, $9, -0x18
    vmacu   $v28, $v5, $v20[2h]
    addi    $9, $9, -0x0030
    vmrg    $v29, $v29, $v27
    mtc2    $zero, $v4[6]
    vmrg    $v3, $v3, $v0[0]
    mtc2    $zero, $v4[14]
    vand    $v21, $v21, $v31[7]
    lpv     $v2[0], 0x00B0($9)
    vand    $v28, $v28, $v31[7]
    lpv     $v20[0], 0x0098($9)
    vmulf   $v29, $v29, $v31[7]
    vmacf   $v29, $v4, $v21[0h]
    bne     $11, curClipRatio, f3dzex_ovl2_00001690
     vmacf  $v29, $v3, $v28[0h]
    vmrg    $v3, $v0, $v31[5]
    llv     $v22[4], 0x0018($14)
f3dzex_ovl2_000016F4:
    vge     $v27, $v25, $v31[3] // v31[3] is 32512
    andi    $11, $5, G_TEXTURE_GEN_H
    vmulf   $v21, $v7, $v2[0h]
    beqz    $11, f3dzex_00001870
     suv    $v29[0], 0x0008($14)
f3dzex_ovl2_00001708:
    vmacf   $v21, $v6, $v2[1h]
    andi    $12, $5, G_TEXTURE_GEN_LINEAR_H
    vmacf   $v21, $v5, $v2[2h]
    vxor    $v4, $v3, $v31[5]   // v31[5] is 0x4000
    vmulf   $v28, $v7, $v20[0h]
    vmacf   $v28, $v6, $v20[1h]
    vmacf   $v28, $v5, $v20[2h]
    lqv     $v2[0], (linearGenerateCoefficients)($zero)
    vmudh   $v22, $v1, $v31[5]  // v31[5] is 16384
    vmacf   $v22, $v3, $v21[0h]
    beqz    $12, f3dzex_00001870
     vmacf  $v22, $v4, $v28[0h]
    vmadh   $v22, $v1, $v2[0]   // v2[0] is -0.5
    vmulf   $v4, $v22, $v22
    vmulf   $v3, $v22, $v31[7]  // v31[7] is 0.999969482421875
    vmacf   $v3, $v22, $v2[2]   // v2[2] is 0.849212646484375
.if (UCODE_IS_F3DEX2_204H)
    vec3 equ v22
.else
    vec3 equ v21
.endif
    vmudh   $vec3, $v1, $v31[5]
    vmacf   $v22, $v22, $v2[1]
    j       f3dzex_00001870
     vmacf  $v22, $v4, $v3

f3dzex_ovl2_00001758:
    vmrg    $v29, $v29, $v27
    vmrg    $v4, $v4, $v0[0]
    vand    $v21, $v21, $v31[7]
    veq     $v3, $v31, $v31[3h]
    lpv     $v2[0], 0x0080($9)
    vmrg    $v3, $v0, $v31[5]
    llv     $v22[4], 0x0018($14)
    vmulf   $v29, $v29, $v31[7]
    j       f3dzex_ovl2_000016F4
     vmacf  $v29, $v4, $v21[0h]

.align 8
Overlay2End:

.if . > 0x00002000
    .error "Not enough room in IMEM"
.endif

.close // CODE_FILE
