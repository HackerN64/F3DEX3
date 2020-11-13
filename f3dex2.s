.rsp

.include "rsp/rsp_defs.inc"
.include "rsp/gbi.inc"

; This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

; Tweak the li and la macros so that the output matches
.macro li, reg, imm
    addi reg, r0, imm
.endmacro

.macro la, reg, imm
    addiu reg, r0, imm
.endmacro

; Load/store word/half/byte/vector immediate
.macro lwi, reg, imm
    lw reg, imm(r0)
.endmacro

.macro swi, reg, imm
    sw reg, imm(r0)
.endmacro

.macro lhui, reg, imm
    lhu reg, imm(r0)
.endmacro

.macro lbui, reg, imm
    lbu reg, imm(r0)
.endmacro

.macro sbi, reg, imm
    sb reg, imm(r0)
.endmacro

.macro move, dst, src
    ori dst, src, 0x0000
.endmacro

; Vector macros
.macro copyv, dst, src
    vadd $dst, $src, $v0[0]
.endmacro

; Overlay table data member offsets
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

; RSP DMEM
.create DATA_FILE, 0x0000

; 0x0000-0x003F: modelview matrix
mvMatrix:
.fill 64

; 0x0040-0x007F: projection matrix
pMatrix:
.fill 64

; 0x0080-0x00C0: modelviewprojection matrix
mvpMatrix:
.fill 64
mvpMatAddr equ lo(mvpMatrix)

; 0x00C0-0x00C7: scissor (four 12-bit values)
scissorUpLeft:
    .dw (G_SETSCISSOR << 24) | \ ; the command byte is included since the command word is copied verbatim
        ((  0 * 4) << 12) | ((  0 * 4) << 0)
scissorBottomRight:
    .dw ((320 * 4) << 12) | ((240 * 4) << 0)

; 0x00C8-0x00CF: othermode
otherMode0:
    .dw (G_RDPSETOTHERMODE << 24) | \ ; command byte included, same as above
        (0x080CFF)
otherMode1:
    .dw 0x00000000

; 0x00D0-0x00D9: ??
.dw 0x00000000
.dw 0x00000000
.dh 0x0000

; 0x00DA-0x00DD: perspective norm
perspNorm:
.dw 0x0000FFFF

; 0x00DE: displaylist stack length
displayListStackLength:
    .db 0x00 ; starts at 0, increments by 4 for each "return address" pushed onto the stack

.db 0x48 ; this seems to be the max displaylist length

; 0x00E0-0x00EF: viewport
viewport:
.fill 16

; 0x00F0-0x00F3: ?

; 0x00F4-0x00F7: 
.orga 0x00F4
matrixStackLength:
.dw 0x00000000

; 0x00F8-0x0137: segment table 
.orga 0x00F8
segmentTable:
.fill (4 * 16) ; 16 DRAM pointers

; 0x0138-0x017F: displaylist stack
displayListStack:

; 0x0138-0x017F: ucode text (shared with DL stack)
.if (UCODE_IS_F3DEX2_204H) ; F3DEX2 2.04H puts an extra 0x0A before the name
.db 0x0A
.endif

.ascii NAME, 0x0A

.align 16

; 0x0180-0x2DF: ???
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
.dw 0x00000001 ; No Nearclipping
.else
.dw 0x00010001 ; Nearclipping
.endif
.dw 0xFFFF0004
.dw 0x00087F00
.dw 0xFFFC4000
.dw 0x04207FFF
.dw 0x7FFC1400
.if (UCODE_IS_206_OR_OLDER)
.dw 0x01CC0200
.dw 0xFFF00010
.dw 0x00200100
.else
.dw 0x10000100
.dw 0xFFF0FFF8
.dw 0x00100020
.endif
.dw 0xC00044D3
.dw 0x6CB30002
forceMatrix:
.db 0x00
mvpValid:
.db 0x01
numLights:
.dh 0000
.dw 0x01000BA8
fogFactor:
.dw 0x00000000
.dw 0x00000000
.dw 0x00000000
geometryModeLabel:
.dw G_CLIPPING

; 0x01F0-0x021F: Light data
lightBuffer:
.fill (8 * 6)

; 0x0220-0x023F: Light colors
lightColors:
.fill (8 * 4)

; 0x0240-0x02DF: ??
.orga 0x02E0

; 0x02E0-0x02EF: Overlay 0/1 Table
overlayInfo0:
  OverlayEntry orga(Overlay0Address), orga(Overlay0End), Overlay0Address
overlayInfo1:
  OverlayEntry orga(Overlay1Address), orga(Overlay1End), Overlay1Address

; 0x02F0-0x02FD: Movemem table
movememTable:
.dh 0x09D0 
.dh mvMatrix     ; G_MV_MMTX
.dh 0x09D0 
.dh pMatrix      ; G_MV_PMTX
.dh viewport     ; G_MV_VIEWPORT
.dh lightBuffer  ; G_MV_LIGHT
.dh vertexBuffer ; G_MV_POINT
; Further entries in the movemem table come from the moveword table

; 0x02FE-0x030D: moveword table
movewordTable:
.dh mvpMatrix     ; G_MW_MATRIX
.dh numLights     ; G_MW_NUMLIGHT
.dh clipRatio     ; G_MW_CLIP
.dh segmentTable  ; G_MW_SEGMENT
.dh fogFactor     ; G_MW_FOG
.dh lightColors   ; G_MW_LIGHTCOL
.dh forceMatrix   ; G_MW_FORCEMTX
.dh perspNorm     ; G_MW_PERSPNORM

; 0x030E-0x036F: RDP/Immediate Command Jump Table
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
addr0336:
jumpTableEntry G_TEXRECT_handler
jumpTableEntry G_TEXRECTFLIP_handler
jumpTableEntry G_SYNC_handler    ; G_RDPLOADSYNC
jumpTableEntry G_SYNC_handler    ; G_RDPPIPESYNC
jumpTableEntry G_SYNC_handler    ; G_RDPTILESYNC
jumpTableEntry G_SYNC_handler    ; G_RDPFULLSYNC
jumpTableEntry G_RDP_handler     ; G_SETKEYGB
jumpTableEntry G_RDP_handler     ; G_SETKEYR
jumpTableEntry G_RDP_handler     ; G_SETCONVERT
jumpTableEntry G_SETSCISSOR_handler
jumpTableEntry G_RDP_handler     ; G_SETPRIMDEPTH
jumpTableEntry G_RDPSETOTHERMODE_handler
jumpTableEntry G_RDP_handler     ; G_LOADTLUT
jumpTableEntry G_RDPHALF_2_handler
jumpTableEntry G_RDP_handler     ; G_SETTILESIZE
jumpTableEntry G_RDP_handler     ; G_LOADBLOCK
jumpTableEntry G_RDP_handler     ; G_LOADTILE
jumpTableEntry G_RDP_handler     ; G_SETTILE
jumpTableEntry G_RDP_handler     ; G_FILLRECT
jumpTableEntry G_RDP_handler     ; G_SETFILLCOLOR
jumpTableEntry G_RDP_handler     ; G_SETFOGCOLOR
jumpTableEntry G_RDP_handler     ; G_SETBLENDCOLOR
jumpTableEntry G_RDP_handler     ; G_SETPRIMCOLOR
jumpTableEntry G_RDP_handler     ; G_SETENVCOLOR
jumpTableEntry G_RDP_handler     ; G_SETCOMBINE
jumpTableEntry G_SETxIMG_handler ; G_SETTIMG
jumpTableEntry G_SETxIMG_handler ; G_SETZIMG
jumpTableEntry G_SETxIMG_handler ; G_SETCIMG

commandJumpTable:
jumpTableEntry G_NOOP_handler

; 0x0370-0x037F: DMA Command Jump Table
jumpTableEntry G_VTX_handler
jumpTableEntry G_MODIFYVTX_handler
jumpTableEntry G_CULLDL_handler
jumpTableEntry G_BRANCH_WZ_handler ; different for F3DZEX
jumpTableEntry G_TRI1_handler
jumpTableEntry G_TRI2_handler
jumpTableEntry G_QUAD_handler
jumpTableEntry G_LINE3D_handler

; 0x0380-0x03C3: vertex pointers
vertexTable:

; The vertex table is a list of pointers to the location of each vertex in the buffer
; After the last vertex pointer, there is a pointer to the address after the last vertex
; This means there are really 33 entries in the table

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

; 0x03C4-0x040F: ??
.dh 0xFFFF
.dh 0x8000
.dh 0x0000
.dh 0x0000
.dh 0x8000

.if NoN == 1
.dw 0x30304080 ; No Nearclipping
.else
.dw 0x30304040 ; Nearclipping
.endif

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
.dw 0x00100000
.dw 0x00200000

.dw 0x10000000
.dw 0x20000000
.dw 0x00004000

.if NoN == 1
.dw 0x00000080 ; No Nearclipping
.else
.dw 0x00000040 ; Nearclipping
.endif

; 0x0410-0x041F: Overlay 2/3 table
overlayInfo2:
  OverlayEntry orga(Overlay2Address), orga(Overlay2End), Overlay2Address
overlayInfo3:
  OverlayEntry orga(Overlay3Address), orga(Overlay3End), Overlay3Address

; 0x0420-0x0919: Vertex buffer
vertexBuffer:
.skip (40 * 32) ; 40 bytes per vertex, 32 vertices

; 0x0920-0x09C7: Input buffer
inputBuffer:
inputBufferLength equ 0xA8
.skip inputBufferLength
inputBufferEnd:

.close ; DATA_FILE

geometryModeAddress equ lo(geometryModeLabel)
vtxTableAddress equ lo(vertexTable)

.create CODE_FILE, 0x00001080

; Initialization routines
; Everything up until displaylist_dma will get overwritten by ovl1
start:
.if UCODE_TYPE == TYPE_F3DZEX && UCODE_ID < 2
    vor $v0, $v16, $v16 ; Sets $v0 to $v16
.else
    vxor $v0, $v0, $v0 ; Sets $v0 to all 0
.endif
    lqv $v31[0], 0x01B0(r0)
    lqv $v30[0], 0x01C0(r0)
    li s7, 0x0BA8
.if !(UCODE_IS_206_OR_OLDER)
    vadd $v1, $v0, $v0
.endif
    li s6, 0x0D00
    vsub $v1, $v0, $v31[0]
    lwi t3, 0x00F0
    lwi t4, 0x0FC4
    li at, 0x2800
    beqz t3, f3dzex_000010C4
     mtc0 at, SP_STATUS
    andi t4, t4, 0x0001
    beqz t4, f3dzex_00001130
     swi r0, 0x0FC4
    j load_overlay1_init ; Skip the initialization and go straight to loading overlay 1
     lwi k0, 0x0BF8
f3dzex_000010C4:
    mfc0 t3, DPC_STATUS
    andi t3, t3, 0x0001
    bnez t3, f3dzex_000010FC
     mfc0 v0, DPC_END
    lwi v1, 0x0FE8
    sub t3, v1, v0
    bgtz t3, f3dzex_000010FC
     mfc0 at, DPC_CURRENT
    lwi a0, 0x0FEC
    beqz at, f3dzex_000010FC
     sub t3, at, a0
    bgez t3, f3dzex_000010FC
     nop
    bne at, v0, f3dzex_0000111C
f3dzex_000010FC:
     mfc0 t3, DPC_STATUS
    andi t3, t3, 0x0400
    bnez t3, f3dzex_000010FC
     li t3, 0x0001
    mtc0 t3, DPC_STATUS
    lwi v0, 0x0FEC
    mtc0 v0, DPC_START
    mtc0 v0, DPC_END
f3dzex_0000111C:
    swi v0, 0x00F0
    lwi t3, lo(matrixStackLength)
    bnez t3, f3dzex_00001130
     lwi t3, 0x0FE0
    swi t3, lo(matrixStackLength)
f3dzex_00001130:
    lwi at, 0x0FD0
    lwi v0, lo(overlayInfo0)
    lwi v1, lo(overlayInfo1)
    lwi a0, lo(overlayInfo2)
    lwi a1, lo(overlayInfo3)
    add v0, v0, at
    add v1, v1, at
    swi v0, lo(overlayInfo0)
    swi v1, lo(overlayInfo1)
    add a0, a0, at
    add a1, a1, at
    swi a0, lo(overlayInfo2)
    swi a1, lo(overlayInfo3)
    lwi k0, 0x0FF0
load_overlay1_init:
    li t3, overlayInfo1 ; set up loading of overlay 1
.if !(UCODE_IS_206_OR_OLDER)
    nop
.endif
    jal load_overlay_and_enter ; load overlay 1 and enter
     move t4, ra ; set up the return address, since load_overlay_and_enter returns to t4
displaylist_dma: ; loads inputBufferLength bytes worth of displaylist data via DMA into inputBuffer
    li s3, (inputBufferLength - 1) ; set the DMA length
    move t8, k0 ; set up the DRAM address to read from
    jal dma_read_write ; initiate the DMA read
     la s4, inputBuffer ; set the address to DMA read to
    addiu k0, k0, inputBufferLength ; increment the DRAM address to read from next time
    li k1, -inputBufferLength ; reset the DL word index
wait_for_dma_and_run_next_command:
G_D0_D2_handler: ; unknown D0/D2 commands?
    jal while_wait_dma_busy ; wait for the DMA read to finish
G_LINE3D_handler:
G_SPNOOP_handler:
.if !(UCODE_IS_F3DEX2_204H) ; F3DEX2 2.04H has this located elsewhere
G_SPECIAL_1_handler:
.endif
G_SPECIAL_2_handler:
G_SPECIAL_3_handler:
run_next_DL_command:
     mfc0 at, SP_STATUS ; load the status word into register at
    lw t9, (inputBufferEnd)(k1) ; load the command word into t9
    beqz k1, displaylist_dma ; load more DL commands if none are left
     andi at, at, SPSTATUS_SIGNAL0_SET ; check the status word for SPSTATUS_SIGNAL0_SET
    sra t4, t9, 24 ; extract DL command byte from command word
    sll t3, t4, 1 ; multiply command byte by 2 to get jump table offset
    lhu t3, lo(commandJumpTable)(t3) ; get command subroutine address from command jump table
    bnez at, load_overlay_0_and_enter ; load overlay 0 if SPSTATUS_SIGNAL0_SET is cleared
     lw t8, (inputBufferEnd + 0x04)(k1) ; load the next DL word into t8
    jr t3 ; jump to the loaded command handler
     addiu k1, k1, 0x0008 ; increment the DL index by 2 words

.if (UCODE_IS_F3DEX2_204H) ; Microcodes besides F3DEX2 2.04H have this as a noop
G_SPECIAL_1_handler: ; Seems to be a manual trigger for mvp recalculation
    li ra, run_next_DL_command
    li s5, lo(pMatrix)
    li s4, lo(mvMatrix)
    li s3, lo(mvpMatrix)
    j calculate_mvp_matrix
    sbi t9, lo(mvpValid)
.endif

G_DMA_IO_handler:
    jal segmented_to_virtual ; Convert the provided segmented address (in t8) to a virtual one
     lh s4, (inputBufferEnd - 0x07)(k1) ; Get the 16 bits in the middle of the command word (since k1 was already incremented for the next command)
    andi s3, t9, 0x0FF8 ; Mask out any bits in the DRAM address to ensure 8-byte alignment
    ; At this point, s4's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
    ; So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
    sra s4, s4, 2
    j dma_read_write ; Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of s4)
     li ra, wait_for_dma_and_run_next_command ; Setup the return address for running the next DL command
G_GEOMETRYMODE_handler:
    lwi t3, geometryModeAddress ; load the geometry mode value
    and t3, t3, t9 ; clears the flags in t9 (set in g*SPClearGeometryMode)
    or t3, t3, t8 ; sets the flags in t8 (set in g*SPSetGeometryMode)
    j run_next_DL_command ; run the next DL command
     swi t3, geometryModeAddress ; update the geometry mode value
G_ENDDL_handler:
    lbui at, lo(displayListStackLength) ; Load the DL stack index into at
    beqz at, load_overlay_0_and_enter ; Load overlay 0 if there is no DL return address, probably to output the image
     addi at, at, -0x0004 ; Decrement the DL stack index
    j f3dzex_ovl0_00001020 ; has a different version in ovl1
     lw k0, lo(displayListStack)(at) ; Load the address of the DL to return to into the k0 (the current DL address)
G_RDPHALF_2_handler:
    ldv $v29[0], 0x00D0(r0)
    lwi t9, 0x00D8
    addi s7, s7, 0x0008
    sdv $v29[0], 0x03F8(s7)
G_RDP_handler:
    sw t8, 0x0004(s7)           ; Add the second word of the command to the RDP command buffer
G_SYNC_handler:
G_NOOP_handler:
    sw t9, 0x0000(s7)           ; Add the command word to the RDP command buffer
    j f3dzex_00001258
     addi s7, s7, 0x0008        ; Increment the next RDP command pointer by 2 words
G_SETxIMG_handler:
    li ra, G_RDP_handler        ; Load the RDP command handler into the return address, then fall through to convert the address to virtual
segmented_to_virtual:
    srl t3, t8, 22              ; Copy (segment index << 2) into t3
    andi t3, t3, 0x003C         ; Clear the bottom 2 bits that remained during the shift
    lw t3, lo(segmentTable)(t3) ; Get the current address of the segment
    sll t8, t8, 8               ; Shift the address to the left so that the top 8 bits are shifted out
    srl t8, t8, 8               ; Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr ra
     add t8, t8, t3 ; Add the segment's address to the masked input address, resulting in the virtual address
G_RDPSETOTHERMODE_handler:
    swi t9, lo(otherMode0)  ; Record the local otherMode0 copy
    j G_RDP_handler         ; Send the command to the RDP
     swi t8, lo(otherMode1) ; Record the local otherMode1 copy
G_SETSCISSOR_handler:
    swi t9, lo(scissorUpLeft)       ; Record the local scissorUpleft copy
    j G_RDP_handler                 ; Send the command to the RDP
     swi t8, lo(scissorBottomRight) ; Record the local scissorBottomRight copy
f3dzex_00001258:
    li ra, run_next_DL_command      ; Set up the running the next DL command as the return address
f3dzex_0000125C:
     sub t3, s7, s6                 ; todo what are s6 and s7?
    blez t3, return_routine         ; Return if s6 >= s7
f3dzex_00001264:
     mfc0 t4, SP_DMA_BUSY
    lwi t8, 0x00F0
    addiu s3, t3, 0x0158
    bnez t4, f3dzex_00001264
     lwi t4, 0x0FEC
    mtc0 t8, DPC_END
    add t3, t8, s3
    sub t4, t4, t3
    bgez t4, f3dzex_000012A8
f3dzex_00001288:
     mfc0 t3, DPC_STATUS
    andi t3, t3, DPC_STATUS_START_VALID
    bnez t3, f3dzex_00001288
     lwi t8, 0x0FE8
f3dzex_00001298:
    mfc0 t3, DPC_CURRENT
    beq t3, t8, f3dzex_00001298
     nop
    mtc0 t8, DPC_START
f3dzex_000012A8:
    mfc0 t3, DPC_CURRENT
    sub t3, t3, t8
    blez t3, f3dzex_000012BC
     sub t3, t3, s3
    blez t3, f3dzex_000012A8
f3dzex_000012BC:
     add t3, t8, s3
    swi t3, 0x00F0
    addi s3, s3, -0x0001
    addi s4, s6, -0x2158
    xori s6, s6, 0x0208
    j dma_read_write
     addi s7, s6, -0x0158

Overlay23LoadAddress:
Overlay3Address:
    li t3, overlayInfo2 ; set up a load for overlay 2
    j load_overlay_and_enter ; load overlay 2
     li t4, Overlay2Address ; set the return address to overlay 2's start
f3dzex_ov3_000012E4:
    move s8, ra
f3dzex_ov3_000012E8:
    la a1, 0x0014
    la s2, 0x0006
    addiu t7, r0, (inputBufferEnd)
    sh at, 0x03CA(s2)
    sh v0, 0x03CC(s2)
    sh v1, 0x03CE(s2)
    sh r0, 0x03D0(s2)
    lwi sp, 0x03CC
f3dzex_00001308:
    lw t1, 0x03F8(a1)
    lw s0, 0x0024(v1)
    and s0, s0, t1
    addi s1, s2, -0x0006
    xori s2, s2, 0x001C
    addi s5, s2, -0x0006
f3dzex_00001320:
    lhu v0, 0x03D0(s1)
    addi s1, s1, 0x0002
    beqz v0, f3dzex_000014A8
     lw t3, 0x0024(v0)
    and t3, t3, t1
    beq t3, s0, f3dzex_00001494
     move s0, t3
    beqz s0, f3dzex_0000134C
     move s3, v0
    move s3, v1
    move v1, v0
f3dzex_0000134C:
    sll t3, a1, 1
    ldv $v2[0], 0x0180(t3)
    ldv $v4[0], 0x0008(s3)
    ldv $v5[0], 0x0000(s3)
    ldv $v6[0], 0x0008(v1)
    ldv $v7[0], 0x0000(v1)
    vmudh $v3, $v2, $v31[0]
    vmudn $v8, $v4, $v2
    vmadh $v9, $v5, $v2
    vmadn $v10, $v6, $v3
    vmadh $v11, $v7, $v3
    vaddc $v8, $v8, $v8[0q]
    lqv $v25[0], 0x01D0(r0)
    vadd $v9, $v9, $v9[0q]
    vaddc $v10, $v10, $v10[0q]
    vadd $v11, $v11, $v11[0q]
    vaddc $v8, $v8, $v8[1h]
    vadd $v9, $v9, $v9[1h]
    vaddc $v10, $v10, $v10[1h]
    vadd $v11, $v11, $v11[1h]
.if (UCODE_IS_F3DEX2_204H) ; Only in F3DEX2 2.04H
    vrcph $v29[0], $v11[3]
.else
    vor $v29, $v11, $v1[0]
    vrcph $v3[3], $v11[3]
.endif
    vrcpl $v2[3], $v10[3]
    vrcph $v3[3], $v0[0]
.if (UCODE_IS_F3DEX2_204H) ; Only in F3DEX2 2.04H
    vabs $v29, $v11, $v25[3]
.else
    vabs $v29, $v29, $v25[3]
.endif
    vmudn $v2, $v2, $v29[3]
    vmadh $v3, $v3, $v29[3]
    veq $v3, $v3, $v0[0]
    vmrg $v2, $v2, $v31[0]
    vmudl $v29, $v10, $v2[3]
    vmadm $v11, $v11, $v2[3]
    vmadn $v10, $v0, $v0[0]
    vrcph $v13[3], $v11[3]
    vrcpl $v12[3], $v10[3]
    vrcph $v13[3], $v0[0]
    vmudl $v29, $v12, $v10
    vmadm $v29, $v13, $v10
    vmadn $v10, $v12, $v11
    vmadh $v11, $v13, $v11
    vmudh $v29, $v1, $v31[1]
    vmadn $v10, $v10, $v31[4]
    vmadh $v11, $v11, $v31[4]
    vmudl $v29, $v12, $v10
    vmadm $v29, $v13, $v10
    vmadn $v12, $v12, $v11
    vmadh $v13, $v13, $v11
    vmudl $v29, $v8, $v12
    luv $v26[0], 0x0010(v1)
    vmadm $v29, $v9, $v12
    llv $v26[8], 0x0014(v1)
    vmadn $v10, $v8, $v13
    luv $v25[0], 0x0010(s3)
    vmadh $v11, $v9, $v13
    llv $v25[8], 0x0014(s3)
    vmudl $v29, $v10, $v2[3]
    vmadm $v11, $v11, $v2[3]
    vmadn $v10, $v10, $v0[0]
    vlt $v11, $v11, $v1[0]
    vmrg $v10, $v10, $v31[0]
    vsubc $v29, $v10, $v1[0]
    vge $v11, $v11, $v0[0]
    vmrg $v10, $v10, $v1[0]
    vmudn $v2, $v10, $v31[0]
    vmudl $v29, $v6, $v10[3]
    vmadm $v29, $v7, $v10[3]
    vmadl $v29, $v4, $v2[3]
    vmadm $v24, $v5, $v2[3]
    vmadn $v23, $v0, $v0[0]
    vmudm $v29, $v26, $v10[3]
    vmadm $v22, $v25, $v2[3]
    li a3, 0x0000
    li at, 0x0002
    sh t7, 0x03D0(s5)
    j f3dzex_000019F4
     addi ra, r0, f3dzex_00001870 + 0x8000 ; Why?
f3dzex_00001478:
.if (UCODE_IS_F3DEX2_204H)
    sdv $v25[0], 0x03C8(t7)
.else
    slv $v25[0], 0x01C8(t7)
.endif
    ssv $v26[4], 0x00CE(t7)
    suv $v22[0], 0x03C0(t7)
    slv $v22[8], 0x01C4(t7)
.if !(UCODE_IS_F3DEX2_204H) ; Not in F3DEX2 2.04H
    ssv $v3[4], 0x00CC(t7)
.endif
    addi t7, t7, -0x0028
    addi s5, s5, 0x0002
f3dzex_00001494:
    bnez s0, f3dzex_00001320
     move v1, v0
    sh v1, 0x03D0(s5)
    j f3dzex_00001320
     addi s5, s5, 0x0002
f3dzex_000014A8:
    sub t3, s5, s2
    bltz t3, f3dzex_000014EC
     sh r0, 0x03D0(s5)
    lhu v1, 0x03CE(s5)
    bnez a1, f3dzex_00001308
     addi a1, a1, -0x0004
    swi r0, 0x03CC
f3dzex_000014C4:
.if (UCODE_IS_F3DEX2_204H) ; In F3DEX2, s5 counts down instead of s2 counting up
    reg1 equ s5
    val1 equ -0x0002
.else
    reg1 equ s2
    val1 equ 0x0002
.endif
    lhu at, 0x03CA(s2)
    lhu v0, 0x03CC(reg1)
    lhu v1, 0x03CE(s5)
    mtc2  $1, $v2[10]
    vor $v3, $v0, $v31[5]
    mtc2  $2, $v4[12]
    jal f3dzex_00001A7C
     mtc2  $3, $v2[14]
    bne s5, s2, f3dzex_000014C4
     addi reg1, reg1, val1
f3dzex_000014EC:
    jr s8
     swi sp, 0x03CC
    nop

; Leave room for loading overlay 2 if it is larger than overlay 3 (true for f3dzex)
.orga max(Overlay2End - Overlay2Address + orga(Overlay3Address), orga())
Overlay3End:

G_VTX_handler:
    lhu s4, vtxTableAddress(t9) ; Load the address of the provided vertex array
    jal segmented_to_virtual ; Convert the vertex array's segmented address (in t8) to a virtual one
     lhu at, (inputBufferEnd - 0x07)(k1) ; Load the size of the vertex array to copy into reg at
    sub s4, s4, at ; Calculate the address to DMA the provided vertices into
    jal dma_read_write ; DMA read the vertices from DRAM
     addi s3, at, -0x0001 ; Set up the DMA length
    lhui a1, geometryModeAddress ; Load the geometry mode into a1
    srl at, at, 3
    sub t7, t9, at
    lhu t7, vtxTableAddress(t7)
    move t6, s4
    lbui t0, lo(mvpValid)
    andi a2, a1, hi(G_LIGHTING)
    bnez a2, Overlay23LoadAddress ; This will always end up in overlay 2, as the start of overlay 3 loads and enters overlay 2
     andi a3, a1, hi(G_FOG)

f3dzex_000017BC:
    bnez t0, g_vtx_load_mvp ; Skip recalculating the mvp matrix if it's already up-to-date
     sll a3, a3, 3
    sb t9, lo(mvpValid)
    li s5, 0x0040
    li s4, 0x0000
    ; Calculate the MVP matrix
    jal calculate_mvp_matrix
     li s3, mvpMatAddr

g_vtx_load_mvp:
    lqv $v8[0],  (mvpMatAddr +  0)(r0) ; load bytes  0-15 of the mvp matrix into v8
    lqv $v10[0], (mvpMatAddr + 16)(r0) ; load bytes 16-31 of the mvp matrix into v10
    lqv $v12[0], (mvpMatAddr + 32)(r0) ; load bytes 32-47 of the mvp matrix into v12
    lqv $v14[0], (mvpMatAddr + 48)(r0) ; load bytes 48-63 of the mvp matrix into v14

    copyv v9, v8                       ; copy v8 into v9
    ldv $v9[0],  (mvpMatAddr +  8)(r0) ; load bytes  8-15 of the mvp matrix into the lower half of v9
    copyv v11, v10                     ; copy v10 into v11
    ldv $v11[0], (mvpMatAddr + 24)(r0) ; load bytes 24-31 of the mvp matrix into the lower half of v11
    copyv v13, v12                     ; copy v10 into v11
    ldv $v13[0], (mvpMatAddr + 40)(r0) ; load bytes 40-47 of the mvp matrix into the lower half of v13
    copyv v15, v14                     ; copy v10 into v11
    ldv $v15[0], (mvpMatAddr + 56)(r0) ; load bytes 56-63 of the mvp matrix into the lower half of v13

    ldv $v8[8],  (mvpMatAddr +  0)(r0) ; load bytes  0- 8 of the mvp matrix into the upper half of v8
    ldv $v10[8], (mvpMatAddr + 16)(r0) ; load bytes 16-23 of the mvp matrix into the upper half of v10
    jal f3dzex_000019F4
     ldv $v12[8], (mvpMatAddr + 32)(r0) ; load bytes 32-39 of the mvp matrix into the upper half of v12
    jal while_wait_dma_busy
     ldv $v14[8], (mvpMatAddr + 48)(r0) ; load bytes 48-55 of the mvp matrix into the upper half of v14
    ldv $v20[0], (vtxSize * 0)(t6)     ; load the position of the 1st vertex into v20's lower 8 bytes
    vmov $v16[5], $v21[1]              ; moves v21[1-2] into v16[5-6]
    ldv $v20[8], (vtxSize * 1)(t6)     ; load the position of the 2nd vertex into v20's upper 8 bytes

f3dzex_0000182C:
    vmudn $v29, $v15, $v1[0]
    lw t3, 0x001C(t6) ; load the color/normal of the 2nd vertex into t3
    vmadh $v29, $v11, $v1[0]
    llv $v22[12], 0x0008(t6) ; load the texture coords of the 1st vertex into v22[12-15]
    vmadn $v29, $v12, $v20[0h]
    move t1, a2
    vmadh $v29, $v8, $v20[0h]
    lpv $v2[0], 0x00B0(t1)
    vmadn $v29, $v13, $v20[1h]
    sw t3, 0x0008(t6)
    vmadh $v29, $v9, $v20[1h]
    lpv $v7[0], 0x0008(t6)
    vmadn $v23, $v14, $v20[2h]
    bnez a2, light_vtx   ; If G_LIGHTING is on, then process vertices accordingly
     vmadh $v24, $v10, $v20[2h]
    vge $v27, $v25, $v31[3]
    llv $v22[4], 0x0018(t6) ; load the texture coords of the 2nd vertex into v22[4-7]
f3dzex_00001870:
.if !(UCODE_IS_F3DEX2_204H) ; Not in F3DEX2 2.04H
    vge $v3, $v25, $v0[0]
.endif
    addi at, at, -0x0004
    vmudl $v29, $v23, $v18[4]
    sub t3, t0, a3
    vmadm $v2, $v24, $v18[4]
    sbv $v27[15], 0x0073(t3)
    vmadn $v21, $v0, $v0[0]
    sbv $v27[7], 0x004B(t3)
.if !(UCODE_IS_F3DEX2_204H) ; Not in F3DEX2 2.04H
    vmov $v26[1], $v3[2]
    ssv $v3[12], 0x00F4(t0)
.endif
    vmudn $v7, $v23, $v18[5]
.if (UCODE_IS_F3DEX2_204H)
    sdv $v25[8], 0x03F0(t0)
.else
    slv $v25[8], 0x01F0(t0)
.endif
    vmadh $v6, $v24, $v18[5]
    sdv $v25[0], 0x03C8(t0)
    vrcph $v29[0], $v2[3]
    ssv $v26[12], 0x0F6(t0)
    vrcpl $v5[3], $v21[3]
.if (UCODE_IS_F3DEX2_204H)
    ssv $v26[4], 0x00CE(t0)
.else
    slv $v26[2], 0x01CC(t0)
.endif
    vrcph $v4[3], $v2[7]
    ldv $v3[0], 0x0008(t6)
    vrcpl $v5[7], $v21[7]
    sra t3, at, 31
    vrcph $v4[7], $v0[0]
    andi t3, t3, 0x0028
    vch $v29, $v24, $v24[3h]
    addi t7, t7, 0x0050
    vcl $v29, $v23, $v23[3h]
    sub t0, t7, t3
    vmudl $v29, $v21, $v5
    cfc2 t2, $1
    vmadm $v29, $v2, $v5
    sdv $v23[8], 0x03E0(t0)
    vmadn $v21, $v21, $v4
    ldv $v20[0], 0x0020(t6)
    vmadh $v2, $v2, $v4
    sdv $v23[0], 0x03B8(t7)
    vge $v29, $v24, $v0[0]
    lsv $v23[14], 0x00E4(t0)
    vmudh $v29, $v1, $v31[1]
    sdv $v24[8], 0x03D8(t0)
    vmadn $v26, $v21, $v31[4]
    lsv $v23[6], 0x00BC(t7)
    vmadh $v25, $v2, $v31[4]
    sdv $v24[0], 0x03B0(t7)
    vmrg $v2, $v0, $v31[7]
    ldv $v20[8], 0x0030(t6)
    vch $v29, $v24, $v6[3h]
    slv $v3[0], 0x01E8(t0)
    vmudl $v29, $v26, $v5
    lsv $v24[14], 0x00DC(t0)
    vmadm $v29, $v25, $v5
    slv $v3[4], 0x01C0(t7)
    vmadn $v5, $v26, $v4
    lsv $v24[6], 0x00B4(t7)
    vmadh $v4, $v25, $v4
    sh t2, -0x0002(t0)
    vmadh $v2, $v2, $v31[7]
    sll t3, t2, 4
    vcl $v29, $v23, $v7[3h]
    cfc2 t2, $1
    vmudl $v29, $v23, $v5[3h]
    ssv $v5[14], 0x00FA(t0)
    vmadm $v29, $v24, $v5[3h]
    addi t6, t6, 0x0020
    vmadn $v26, $v23, $v2[3h]
    sh t2, -0x0004(t0)
    vmadh $v25, $v24, $v2[3h]
    sll t2, t2, 4
    vmudm $v3, $v22, $v18
    sh t3, -0x002A(t7)
    sh t2, -0x002C(t7)
    vmudl $v29, $v26, $v18[4]
    ssv $v5[6], 0x00D2(t7)
    vmadm $v25, $v25, $v18[4]
    ssv $v4[14], 0x00F8(t0)
    vmadn $v26, $v0, $v0[0]
    ssv $v4[6], 0x00D0(t7)
    slv $v3[4], 0x01EC(t0)
    vmudh $v29, $v17, $v1[0]
    slv $v3[12], 0x01C4(t7)
    vmadh $v29, $v19, $v31[3]
    vmadn $v26, $v26, $v16
    bgtz at, f3dzex_0000182C
    vmadh $v25, $v25, $v16
    bltz ra, f3dzex_00001478 ; has a different version in ovl2

.if !(UCODE_IS_F3DEX2_204H) ; Handled differently by F3DEX2 2.04H
    vge $v3, $v25, $v0[0]
    slv $v25[8], 0x01F0(t0)
    vge $v27, $v25, $v31[3]
    slv $v25[0], 0x01C8(t7)
    ssv $v26[12], 0x00F6(t0)
    ssv $v26[4], 0x00CE(t7)
    ssv $v3[12], 0x00F4(t0)
    beqz a3, run_next_DL_command
     ssv $v3[4], 0x00CC(t7)
.else ; This is the F3DEX2 2.04H version
    vge $v27, $v25, $v31[3]
    sdv $v25[8], 0x03F0(t0)
    sdv $v25[0], 0x03C8(t7)
    ssv $v26[12], 0x00F6(t0)
    beqz a3, run_next_DL_command
     ssv $v26[4], 0x00CE(t7)
.endif

    sbv $v27[15], 0x006B(t0)
    j run_next_DL_command
     sbv $v27[7], 0x0043(t7)
f3dzex_000019F4:
    li t5, 0x0180
    ldv $v16[0], lo(viewport)(r0)
    ldv $v16[8], lo(viewport)(r0)
    llv $v29[0], 0x0060(t5)
    ldv $v17[0], 0x00E8(r0) ;8
    ldv $v17[8], 0x00E8(r0) ;8
    vlt $v19, $v31, $v31[3]
    vsub $v21, $v0, $v16
    llv $v18[4], 0x0068(t5)
    vmrg $v16, $v16, $v29[0]
    llv $v18[12], 0x0068(t5)
    vmrg $v19, $v0, $v1[0]
    llv $v18[8], 0x00DC(r0)
    vmrg $v17, $v17, $v29[1]
    lsv $v18[10], 0x0006(t5)
    vmov $v16[1], $v21[1]
    jr ra
     addi t0, s7, 0x0050
G_TRI2_handler:
G_QUAD_handler:
    jal f3dzex_00001A4C
     sw t8, 0x0004(s7)
G_TRI1_handler:
    li ra, run_next_DL_command
    sw t9, 0x0004(s7) ; store the command word (t9) into address s7 + 4
f3dzex_00001A4C:
    lpv $v2[0], 0x0000(s7)
    ; read the three vertex indices from the stored command word
    lbu at, 0x0005(s7) ; at = vertex 1 index
    lbu v0, 0x0006(s7) ; v0 = vertex 2 index
    lbu v1, 0x0007(s7) ; v1 = vertex 3 index
    vor $v3, $v0, $v31[5]
    lhu at, vtxTableAddress(at) ; convert vertex 1's index to its address
    vmudn $v4, $v1, $v31[6]
    lhu v0, vtxTableAddress(v0) ; convert vertex 2's index to its address
    vmadl $v2, $v2, $v30[1]
    lhu v1, vtxTableAddress(v1) ; convert vertex 3's index to its address
    vmadn $v4, $v0, $v0[0]
    move a0, at
f3dzex_00001A7C:
    vnxor $v5, $v0, $v31[7]
    llv $v6[0], 0x0018(at)
    vnxor $v7, $v0, $v31[7]
    llv $v4[0], 0x0018(v0)
    vmov $v6[6], $v2[5]
    llv $v8[0], 0x0018(v1)
    vnxor $v9, $v0, $v31[7]
    lw a1, 0x0024(at)
    vmov $v8[6], $v2[7]
    lw a2, 0x0024(v0)
    vadd $v2, $v0, $v6[1]
    lw a3, 0x0024(v1)
    vsub $v10, $v6, $v4
.if NoN == 1
    andi t3, a1, 0x70B0 ; No Nearclipping
.else
    andi t3, a1, 0x7070 ; Nearclipping
.endif
    vsub $v11, $v4, $v6
    and t3, a2, t3
    vsub $v12, $v6, $v8
    and t3, a3, t3
    vlt $v13, $v2, $v4[1]
    vmrg $v14, $v6, $v4
    bnez t3, return_routine
     lbui t3, 0x01EE
    vmudh $v29, $v10, $v12[1]
    lwi t4, 0x03CC
    vmadh $v29, $v12, $v11[1]
    or a1, a1, a2
    vge $v2, $v2, $v4[1]
    or a1, a1, a3
    vmrg $v10, $v6, $v4
    lw t3, 0x03C2(t3)
    vge $v6, $v13, $v8[1]
    mfc2 a2, $v29[0]
    vmrg $v4, $v14, $v8
    and a1, a1, t4
    vmrg $v14, $v8, $v14
    bnez a1, f3dzex_ov2_000012E4 ; has a different version in ovl3
    add t3, a2, t3
    vlt $v6, $v6, $v2
    bgez t3, return_routine
    vmrg $v2, $v4, $v10
    vmrg $v10, $v10, $v4
    mfc2  $1, $v14[12]
    vmudn $v4, $v14, $v31[5]
    beqz a2, return_routine
    vsub $v6, $v2, $v14
    mfc2  $2, $v2[12]
    vsub $v8, $v10, $v14
    mfc2  $3, $v10[12]
    vsub $v11, $v14, $v2
    lwi a2, geometryModeAddress
    vsub $v12, $v14, $v10
    llv $v13[0], 0x0020(at)
    vsub $v15, $v10, $v2
    llv $v13[8], 0x0020(v0)
    vmudh $v16, $v6, $v8[0]
    llv $v13[12], 0x0020(v1)
    vmadh $v16, $v8, $v11[0]
    sll t3, a2, 10 ; Moves the value of G_SHADE_SMOOTH into the sign bit
    vsar $v17, $v17, $v17[0]
    bgez t3, f3dzex_00001B94 ; Branch if G_SHADE_SMOOTH isn't set
    vsar $v16, $v16, $v16[1]
    lpv $v18[0], 0x0010(at)
    vmov $v15[2], $v6[0]
    lpv $v19[0], 0x0010(v0)
    vrcp $v20[0], $v15[1]
    lpv $v21[0], 0x0010(v1)
    vrcph $v22[0], $v17[1]
    vrcpl $v23[1], $v16[1]
    j f3dzex_00001BC0
    vrcph $v24[1], $v0[0]
f3dzex_00001B94:
    lpv $v18[0], 0x0010(a0)
    vrcp $v20[0], $v15[1]
    lbv $v18[6], 0x0013(at)
    vrcph $v22[0], $v17[1]
    lpv $v19[0], 0x0010(a0)
    vrcpl $v23[1], $v16[1]
    lbv $v19[6], 0x0013(v0)
    vrcph $v24[1], $v0[0]
    lpv $v21[0], 0x0010(a0)
    vmov $v15[2], $v6[0]
    lbv $v21[6], 0x0013(v1)
f3dzex_00001BC0:
.if (UCODE_IS_206_OR_OLDER)
    i1 equ 7
    i2 equ 2
    i3 equ 5
    i4 equ 2
    i5 equ 5
    i6 equ 6
    vec1 equ v31
    vec2 equ v20
.else
    i1 equ 3
    i2 equ 7
    i3 equ 2
    i4 equ 3
    i5 equ 6
    i6 equ 7
    vec1 equ v30
    vec2 equ v22
.endif
    vrcp $v20[2], $v6[1]
    vrcph $v22[2], $v6[1]
    lw a1, 0x0020(at)
    vrcp $v20[3], $v8[1]
    lw a3, 0x0020(v0)
    vrcph $v22[3], $v8[1]
    lw t0, 0x0020(v1)
    vmudl $v18, $v18, $v30[i1]
    lbui t1, 0x01E7
    vmudl $v19, $v19, $v30[i1]
    sub t3, a1, a3
    vmudl $v21, $v21, $v30[i1]
    sra t4, t3, 31
    vmov $v15[3], $v8[0]
    and t3, t3, t4
    vmudl $v29, $v20, $vec1[i2]
    sub a1, a1, t3
    vmadm $v22, $v22, $vec1[i2]
    sub t3, a1, t0
    vmadn $v20, $v0, $v0[0]
    sra t4, t3, 31
    vmudm $v25, $v15, $vec1[i3]
    and t3, t3, t4
    vmadn $v15, $v0, $v0[0]
    sub a1, a1, t3
    vsubc $v4, $v0, $v4
    sw a1, 0x0010(s7)
    vsub $v26, $v0, $v0
    llv $v27[0], 0x0010(s7)
    vmudm $v29, $v25, $v20
    mfc2  $5, $v17[1]
    vmadl $v29, $v15, $v20
    lbui a3, 0x01E6
    vmadn $v20, $v15, $v22
    lsv $v19[14], 0x001C(v0)
    vmadh $v15, $v25, $v22
    lsv $v21[14], 0x001C(v1)
    vmudl $v29, $v23, $v16
    lsv $v7[14], 0x001E(v0)
    vmadm $v29, $v24, $v16
    lsv $v9[14], 0x001E(v1)
    vmadn $v16, $v23, $v17
    ori t3, a2, 0x00C8
    vmadh $v17, $v24, $v17
    or t3, t3, t1
.if !(UCODE_IS_206_OR_OLDER)
    vand $v22, $v20, $v30[5]
.endif
    vcr $v15, $v15, $v30[i4]
    sb t3, 0x0000(s7)
    vmudh $v29, $v1, $v30[i5]
    ssv $v10[2], 0x0002(s7)
    vmadn $v16, $v16, $v30[4]
    ssv $v2[2], 0x0004(s7)
    vmadh $v17, $v17, $v30[4]
    ssv $v14[2], 0x0006(s7)
    vmudn $v29, $v3, $v14[0]
    andi t4, a1, 0x0080
    vmadl $v29, $vec2, $v4[1]
    or t4, t4, a3
    vmadm $v29, $v15, $v4[1]
    sb t4, 0x0001(s7)
    vmadn $v2, $vec2, $v26[1]
    beqz t1, f3dzex_00001D2C
    vmadh $v3, $v15, $v26[1]
    vrcph $v29[0], $v27[0]
    vrcpl $v10[0], $v27[1]
    vadd $v14, $v0, $v13[1q]
    vrcph $v27[0], $v0[0]
    vor $v22, $v0, $v31[7]
    vmudm $v29, $v13, $v10[0]
    vmadl $v29, $v14, $v10[0]
    llv $v22[0], 0x0014(at)
    vmadn $v14, $v14, $v27[0]
    llv $v22[8], 0x0014(v0)
    vmadh $v13, $v13, $v27[0]
    vor $v10, $v0, $v31[7]
    vge $v29, $v30, $v30[7]
    llv $v10[8], 0x0014(v1)
    vmudm $v29, $v22, $v14[0h]
    vmadh $v22, $v22, $v13[0h]
    vmadn $v25, $v0, $v0[0]
    vmudm $v29, $v10, $v14[6]
    vmadh $v10, $v10, $v13[6]
    vmadn $v13, $v0, $v0[0]
    sdv $v22[0], 0x0020(s7)
    vmrg $v19, $v19, $v22
    sdv $v25[0], 0x0028(s7) ;8
    vmrg $v7, $v7, $v25
    ldv $v18[8], 0x0020(s7) ;8
    vmrg $v21, $v21, $v10
    ldv $v5[8], 0x0028(s7) ;8
    vmrg $v9, $v9, $v13
f3dzex_00001D2C:
    vmudl $v29, $v16, $v23
    lsv $v5[14], 0x001E(at)
    vmadm $v29, $v17, $v23
    lsv $v18[14], 0x001C(at)
    vmadn $v23, $v16, $v24
    lh at, 0x0018(v0)
    vmadh $v24, $v17, $v24
    addiu v0, s7, 0x0020
    vsubc $v10, $v9, $v5
    andi v1, a2, 0x0004
    vsub $v9, $v21, $v18
    sll at, at, 14
    vsubc $v13, $v7, $v5
    sw at, 0x0008(s7)
    vsub $v7, $v19, $v18
    ssv $v3[6], 0x0010(s7)
    vmudn $v29, $v10, $v6[1]
    ssv $v2[6], 0x0012(s7)
    vmadh $v29, $v9, $v6[1]
    ssv $v3[4], 0x0018(s7)
    vmadn $v29, $v13, $v12[1]
    ssv $v2[4], 0x001A(s7)
    vmadh $v29, $v7, $v12[1]
    ssv $v15[0], 0x000C(s7)
    vsar $v2, $v2, $v2[1]
    ssv $v20[0], 0x000E(s7)
    vsar $v3, $v3, $v3[0]
    ssv $v15[6], 0x0014(s7)
    vmudn $v29, $v13, $v8[0]
    ssv $v20[6], 0x0016(s7)
    vmadh $v29, $v7, $v8[0]
    ssv $v15[4], 0x001C(s7)
    vmadn $v29, $v10, $v11[0]
    ssv $v20[4], 0x001E(s7)
    vmadh $v29, $v9, $v11[0]
    sll t3, v1, 4
    vsar $v6, $v6, $v6[1]
    add at, v0, t3
    vsar $v7, $v7, $v7[0]
    sll t3, t1, 5
    vmudl $v29, $v2, $v23[1]
    add s7, at, t3
    vmadm $v29, $v3, $v23[1]
    andi a2, a2, 0x0001
    vmadn $v2, $v2, $v24[1]
    sll t3, a2, 4
    vmadh $v3, $v3, $v24[1]
    add s7, s7, t3
    vmudl $v29, $v6, $v23[1]
    vmadm $v29, $v7, $v23[1]
    vmadn $v6, $v6, $v24[1]
    sdv $v2[0], 0x0018(v0)
    vmadh $v7, $v7, $v24[1]
    sdv $v3[0], 0x0008(v0)
    vmadl $v29, $v2, $v20[3]
    sdv $v2[8], 0x0018(at)
    vmadm $v29, $v3, $v20[3]
    sdv $v3[8], 0x0008(at)
    vmadn $v8, $v2, $v15[3]
    sdv $v6[0], 0x0038(v0)
    vmadh $v9, $v3, $v15[3]
    sdv $v7[0], 0x0028(v0)
    vmudn $v29, $v5, $v1[0]
    sdv $v6[8], 0x0038(at)
    vmadh $v29, $v18, $v1[0]
    sdv $v7[8], 0x0028(at)
    vmadl $v29, $v8, $v4[1]
    sdv $v8[0], 0x0030(v0)
    vmadm $v29, $v9, $v4[1]
    sdv $v9[0], 0x0020(v0)
    vmadn $v5, $v8, $v26[1]
    sdv $v8[8], 0x0030(at)
    vmadh $v18, $v9, $v26[1]
    sdv $v9[8], 0x0020(at)
    vmudn $v10, $v8, $v4[1]
    beqz a2, f3dzex_00001EB4
    vmudn $v8, $v8, $v30[i6]
    vmadh $v9, $v9, $v30[i6]
    sdv $v5[0], 0x0010(v0)
    vmudn $v2, $v2, $v30[i6]
    sdv $v18[0], 0x0000(v0)
    vmadh $v3, $v3, $v30[i6]
    sdv $v5[8], 0x0010(at)
    vmudn $v6, $v6, $v30[i6]
    sdv $v18[8], 0x0000(at)
    vmadh $v7, $v7, $v30[i6]
    ssv $v8[14], 0x00FA(s7)
    vmudl $v29, $v10, $v30[i6]
    ssv $v9[14], 0x00F8(s7)
    vmadn $v5, $v5, $v30[i6]
    ssv $v2[14], 0x00F6(s7)
    vmadh $v18, $v18, $v30[i6]
    ssv $v3[14], 0x00F4(s7)
    ssv $v6[14], 0x00FE(s7)
    ssv $v7[14], 0x00FC(s7)
    ssv $v5[14], 0x00F2(s7)
    j f3dzex_0000125C
    ssv $v18[14], 0x00F0(s7)
f3dzex_00001EB4:
    sdv $v5[0], 0x0010(v0)
    sdv $v18[0], 0x0000(v0)
    sdv $v5[8], 0x0010(at)
    j f3dzex_0000125C
     sdv $v18[8], 0x0000(at)
G_CULLDL_handler:
    lhu t9, vtxTableAddress(t9) ; load start vertex address
    lhu t8, vtxTableAddress(t8) ; load end vertex address
.if NoN == 1
    addiu at, r0, 0x70B0 ; todo what is this value (No Nearclipping)
.else
    addiu at, r0, 0x7070 ; todo what is this value (Nearclipping)
.endif
    lw t3, 0x0024(t9) ; todo what is this reading from the vertex?
culldl_loop:
    and at, at, t3
    beqz at, run_next_DL_command
     lw t3, 0x004C(t9)
    bne t9, t8, culldl_loop ; loop until reaching the last vertex
     addiu t9, t9, 0x0028 ; advance to the next vertex
    j G_ENDDL_handler ; otherwise skip the rest of the displaylist
G_BRANCH_WZ_handler:
     lhu t9, vtxTableAddress(t9) ; get the address of the vertex being tested
.if UCODE_TYPE == 1 ; BRANCH_W/BRANCH_Z difference
    lh t9, 0x0006(t9) ; read the w coordinate of the vertex (f3dzex)
.else
    lw t9, 0x001C(t9) ; read the z coordinate of the vertex (f3dex2)
.endif
    sub v0, t9, t8 ; subtract the w/z value being tested
    bgez v0, run_next_DL_command ; if vtx.w/z > w/z, continue running this DL
     lwi t8, 0x00D8 ; 
    j f3dzex_ovl1_00001008
G_MODIFYVTX_handler:
     lbu at, (inputBufferEnd - 0x07)(k1)
    j do_moveword
     lhu t9, vtxTableAddress(t9)

.orga 0xF2C
; This subroutine sets up the values to load overlay 0 and then falls through
; to load_overlay_and_enter to execute the load.
load_overlay_0_and_enter:
G_LOAD_UCODE_handler:
    li t4, Overlay0Address  ; Sets up return address
    li t3, lo(overlayInfo0) ; Sets up ovl0 table address
; This subroutine accepts the address of an overlay table entry and loads that overlay.
; It then jumps to that overlay's address after DMA of the overlay is complete.
; t4 is used to pass in a value to return to
load_overlay_and_enter:
    lw t8, overlay_load(t3)    ; Set up overlay dram address
    lhu s3, overlay_len(t3)    ; Set up overlay length
    jal dma_read_write         ; DMA the overlay
     lhu s4, overlay_imem(t3)  ; Set up overlay load address
    move ra, t4                ; Set the return address to the passed in t4 value
while_wait_dma_busy:
    mfc0 t3, SP_DMA_BUSY       ; Load the DMA_BUSY value into t3
while_dma_busy:
    bnez t3, while_dma_busy ; Loop until DMA_BUSY is cleared
     mfc0 t3, SP_DMA_BUSY      ; Update t3's DMA_BUSY value
; This routine is used to return via conditional branch
return_routine:
    jr ra
dma_read_write:
     mfc0 t3, SP_DMA_FULL      ; load the DMA_FULL value into t3
while_dma_full:
    bnez t3, while_dma_full ; Loop until DMA_FULL is cleared
     mfc0 t3, SP_DMA_FULL      ; Update t3's DMA_FULL value
    mtc0 s4, SP_MEM_ADDR       ; Set the DMEM address to DMA from/to
    bltz s4, dma_write         ; If the DMEM address is negative, this is a DMA write, if not read
     mtc0 t8, SP_DRAM_ADDR     ; Set the DRAM address to DMA from/to
    jr ra
     mtc0 s3, SP_RD_LEN        ; Initiate a DMA read with a length of the value of s3
dma_write:
    jr ra
     mtc0 s3, SP_WR_LEN        ; Initiate a DMA write with a length of the value of s3

; first overlay table at 0x02E0
; overlay 0 (0x98 bytes loaded into 0x1000)

.headersize 0x00001000 - orga()

; Overlay 0 controls the RDP and also stops the RSP when work is done
Overlay0Address:
    sub t3, s7, s6
    addiu t4, t3, 0x0157
f3dzex_ovl0_00001008:
    bgezal t4, f3dzex_00001264
    nop
    jal while_wait_dma_busy
     lwi t8, 0x00F0
    bltz at, f3dzex_ovl0_00001084
     mtc0 t8, DPC_END ; Set the end pointer of the RDP so that it starts the task
f3dzex_ovl0_00001020:
    bnez at, f3dzex_ovl0_00001060
     add k0, k0, k1
    lw t8, 0x09C4(k1) ; Should this be (inputBufferEnd - 0x04)?
    swi k0, 0x0FF0
    swi t8, 0x0FD0
    la s4, lo(start) ; DMA address
    jal dma_read_write ; initiate DMA read
     li s3, 0x0F47
f3dzex_ovl0_00001040:
    lwi t8, 0x00D8
    la s4, 0x0180 ; DMA address
    andi s3, t9, 0x0FFF
    add t8, t8, s4
    jal dma_read_write ; initate DMA read
     sub s3, s3, s4
    j while_wait_dma_busy
.if (UCODE_IS_F3DEX2_204H)
     li ra, f3dex2_204F_ovl0_00001080
.else
     li ra, f3dzex_ovl0_00001084
.endif
f3dzex_ovl0_00001060:
    lwi t3, 0x0FD0
    swi k0, 0x0BF8
    swi t3, 0x0BFC
    li t4, 0x5000
    lwi t8, 0x0FF8
    li s4, -0x8000
    li s3, 0x0BFF
    j dma_read_write
f3dex2_204F_ovl0_00001080: ; Only used in f3dex2 2.04H
     li ra, break
f3dzex_ovl0_00001084:
    li t4, 0x4000
break:
    mtc0 t4, SP_STATUS
    break 0
    nop
    nop
Overlay0End:

; end overlay 0
; overlay 1 (0x170 bytes loaded into 0x1000)

.headersize Overlay0Address - orga()
Overlay1Address:
G_DL_handler:
    lbui at, lo(displayListStackLength) ; Get the DL stack length
    sll v0, t9, 15 ; Shifts the push/nopush value to the highest bit in v0
f3dzex_ovl1_00001008:
    jal segmented_to_virtual
     add v1, k0, k1
    bltz v0, displaylist_dma ; If the operation is nopush (branch) then simply DMA the new displaylist
     move k0, t8 ; Set the
    sw v1, lo(displayListStack)(at)
    addi at, at, 0x0004 ; Increment the DL stack length
f3dzex_ovl1_00001020:
    j displaylist_dma
     sb at, lo(displayListStackLength)
G_TEXTURE_handler:
    li t3, 0x1140
G_TEXRECT_handler:
G_TEXRECTFLIP_handler:
    sw t9, -0x0F5C(t3)
G_RDPHALF_1_handler:
    j run_next_DL_command
     sw t8, -0x0F58(t3)
G_MOVEWORD_handler:
    srl v0, t9, 16 ; load the moveword command and word index into v0 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu at, (movewordTable - (G_MOVEWORD << 8))(v0) ; subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
do_moveword:
    add at, at, t9        ; adds the offset in the command word to the address from the table (the upper 4 bytes are effectively ignored)
    j run_next_DL_command ; process the next command
     sw t8, 0x0000(at)    ; moves the specified value (in t8) into the word (offset + moveword_table[index])
G_POPMTX_handler:
    lwi t3, lo(matrixStackLength)  ; Get the current matrix stack length
    lwi v0, 0x0FE0                 ; todo what is stored here? minimum stack length value? is this always 0?
    sub t8, t3, t8                 ; Decrease the matrix stack length by the amount passed in the second command word
    sub at, t8, v0                 ; Subtraction to check if the new length is greater than or equal to v0
    bgez at, do_popmtx             ; If the new matrix stack length is greater than or equal to v0, then use the new length as is
     nop
    move t8, v0                    ; If the new matrix stack length is less than v0, then use v0 as the length instead
do_popmtx:
    beq t8, t3, run_next_DL_command ; If no bytes were popped, then we don't need to make the mvp matrix as being out of date and can run the next command
     swi t8, lo(matrixStackLength)  ; Update the matrix stack length with the new value
    j do_movemem
     swi r0, lo(mvpValid)           ; Mark the MVP matrix as being out of date
G_D1_handler: ; unknown D1 command?
    lhu s3, 0x02F2(at)
    jal while_wait_dma_busy
     lhu s5, 0x02F2(at)
    li ra, run_next_DL_command
calculate_mvp_matrix:
    addi t4, s4, 0x0018
f3dzex_ovl1_0000108C:
    vmadn $v9, $v0, $v0[0]
    addi t3, s4, 0x0008
    vmadh $v8, $v0, $v0[0]
    addi s5, s5, -0x0020
    vmudh $v29, $v0, $v0[0]
f3dzex_ovl1_000010A0:
    ldv $v5[0], 0x0040(s5)
    ldv $v5[8], 0x0040(s5)
    lqv $v3[0], 0x0020(s4)
    ldv $v4[0], 0x0020(s5)
    ldv $v4[8], 0x0020(s5)
    lqv $v2[0], 0x0000(s4)
    vmadl $v29, $v5, $v3[0h]
    addi s4, s4, 0x0002
    vmadm $v29, $v4, $v3[0h]
    addi s5, s5, 0x0008
    vmadn $v7, $v5, $v2[0h]
    bne s4, t3, f3dzex_ovl1_000010A0
    vmadh $v6, $v4, $v2[0h]
    bne s4, t4, f3dzex_ovl1_0000108C
    addi s4, s4, 0x0008

    ; Store the results in the passed in matrix
    sqv $v9[0], 0x0020(s3)
    sqv $v8[0], 0x0000(s3)
    sqv $v7[0], 0x0030(s3)
    jr ra
     sqv $v6[0], 0x0010(s3)
G_MTX_handler:
    ; The lower 3 bits of G_MTX are, from LSb to MSb (0 value/1 value),
    ;   matrix type (modelview/projection)
    ;   load type (multiply/load)
    ;   push type (nopush/push)
    ; In F3DEX2 (and by extension F3DZEX), G_MTX_PUSH is inverted, so 1 is nopush and 0 is push
    andi t3, t9, G_MTX_P_MV | G_MTX_NOPUSH_PUSH ; Read the matrix type and push type flags into t3
    bnez t3, load_mtx                           ; If the matrix type is projection or this is not a push, skip pushing the matrix
     andi v0, t9, G_MTX_MUL_LOAD                ; Read the matrix load type into v0 (0 is multiply, 2 is load)
    lwi t8, lo(matrixStackLength) ; Load the matrix stack length into t8
    li s4, -0x2000      ; 
    jal dma_read_write  ; DMA read the matrix into memory
     li s3, 0x003F      ; Set the DMA length to the size of a matrix (minus 1 because DMA is inclusive)
    addi t8, t8, 0x0040 ; Increase the matrix stack length by the size of one matrix
    swi t8, lo(matrixStackLength) ; Update the matrix stack length
    lw t8, (inputBufferEnd - 0x04)(k1)
load_mtx:
    add t4, t4, v0       ; Shift the... todo what is going on here exactly?
    swi r0, lo(mvpValid) ; Mark the mvp matrix as out-of-date
G_MOVEMEM_handler:
    jal segmented_to_virtual ; convert the memory address (in t8) to a virtual one
do_movemem:
     andi at, t9, 0x00FE                ; Move the movemem table index into at (bits 1-7 of the first command word)
    lbu s3, (inputBufferEnd - 0x07)(k1) ; Move the second byte of the first command word into s3
    lhu s4, lo(movememTable)(at)        ; Load the address of the memory location for the given movemem index
    srl v0, t9, 5                       ; Left shifts the index by 5 (which is then added to the value read from the movemem table)
    lhu ra, 0x0336(t4)
    j dma_read_write
G_SETOTHERMODE_H_handler:
     add s4, s4, v0
G_SETOTHERMODE_L_handler:
    lw v1, -0x1074(t3)
    lui v0, 0x8000
    srav v0, v0, t9
    srl at, t9, 8
    srlv v0, v0, at
    nor v0, v0, r0
    and v1, v1, v0
    or v1, v1, t8
    sw v1, -0x1074(t3)
    lwi t9, lo(otherMode0)
    j G_RDP_handler
    lwi t8, lo(otherMode1)
Overlay1End:

.headersize Overlay23LoadAddress - orga()
Overlay2Address:
    lbui t3, 0x01DC
    j f3dzex_ov2_000012F4
     lbui a2, 0x01DD
f3dzex_ov2_000012E4:
    move s8, ra
    li t3, overlayInfo3 ; set up a load of overlay 3
    j load_overlay_and_enter ; load overlay 3
     li t4, f3dzex_ov3_000012E8 ; set up the return address in ovl3
f3dzex_ov2_000012F4:
    bnez t3, f3dzex_000017BC
     addi a2, a2, 0x0168
    sb t9, 0x01DC
    lqv $v12[0], 0x0020(r0)
    lqv $v8[0], 0x0000(r0)
    lsv $v13[2], 0x002A(r0)
    lsv $v9[2], 0x000A(r0)
    vmov $v13[0], $v12[1]
    lsv $v14[4], 0x0034(r0)
    vmov $v9[0], $v8[1]
    lsv $v10[4], 0x0014(r0)
    vmov $v14[0], $v12[2]
    li s4, 0x0150
    vmov $v10[0], $v8[2]
    lpv $v7[0], 0x00A8(s4)
    vmov $v14[1], $v12[6]
    lsv $v13[4], 0x0032(r0)
    vmov $v10[1], $v8[6]
    lsv $v9[4], 0x0012(r0)
    vmov $v12[1], $v12[4]
    lsv $v12[4], 0x0030(r0)
    vmov $v8[1], $v8[4]
    lsv $v8[4], 0x0010(r0)
f3dzex_ovl2_0x00001350:
    vmudn $v29, $v13, $v7[1]
    vmadh $v29, $v9, $v7[1]
    vmadn $v29, $v12, $v7[0]
    spv $v15[0], 0x00B0(s4)
    vmadh $v29, $v8, $v7[0]
    lw t4, 0x00B0(s4)
    vmadn $v29, $v14, $v7[2]
    vmadh $v29, $v10, $v7[2]
    vsar $v11, $v11, $v11[1]
    sw t4, 0x00B4(s4)
    vsar $v15, $v15, $v15[0]
    beq s4, a2, f3dzex_000017BC
    vmudl $v29, $v11, $v11
    vmadm $v29, $v15, $v11
    vmadn $v16, $v11, $v15
    beqz t3, f3dzex_ovl2_00001398
    vmadh $v17, $v15, $v15
    addi s4, s4, 0x0018
f3dzex_ovl2_00001398:
    vaddc $v18, $v16, $v16[1]
    li t3, 0x0001
    vadd $v29, $v17, $v17[1]
    vaddc $v16, $v18, $v16[2]
    vadd $v17, $v29, $v17[2]
    vrsqh $v29[0], $v17[0]
    lpv $v7[0], 0x00C0(s4)
    vrsql $v16[0], $v16[0]
    vrsqh $v17[0], $v0[0]
    vmudl $v29, $v11, $v16[0]
    vmadm $v29, $v15, $v16[0]
    vmadn $v11, $v11, $v17[0]
    vmadh $v15, $v15, $v17[0]
.if (UCODE_IS_206_OR_OLDER)
    i7 equ 7
.else
    i7 equ 3
.endif
    vmudn $v11, $v11, $v30[i7]
    j f3dzex_ovl2_0x00001350
    vmadh $v15, $v15, $v30[i7]
light_vtx:
    vadd $v6, $v0, $v7[1h]
.if UCODE_HAS_POINT_LIGHTING ; Point lighting difference
    luv $v29[0], 0x00B8(t1) ; f3dzex 2.08
.else
    lpv $v20[0], 0x0098(t1) ; f3dex2
.endif
    vadd $v5, $v0, $v7[2h]
    luv $v27[0], 0x0008(t6)
    vne $v4, $v31, $v31[3h]
.if !UCODE_HAS_POINT_LIGHTING ; Point lighting difference
    luv $v29[0], 0x00B8(t1) ; f3dex2
.endif

.if UCODE_HAS_POINT_LIGHTING ; point lighting
    andi t3, a1, hi(G_POINT_LIGHTING) ; check if point lighting is enabled
    beqz t3, f3dzex_ovl2_0000168C ; if not, then skip ahead
    li t4, -0x7F80
    vaddc $v28, $v27, $v0[0]
    suv $v29[0], 0x0008(t6)
    ori t3, r0, 0x0004
    vmov $v30[7], $v30[6]
    mtc2 t3, $v31[6]
f3dzex_ovl2_0000140C:
    lbu t3, 0x00A3(t1)
    bnez t3, f3dzex_ovl2_0000155C
    lpv $v2[0], 0x00B0(t1)
    luv $v29[0], 0x0008(t6)
    vmulu $v20, $v7, $v2[0h]
    vmacu $v20, $v6, $v2[1h]
    vmacu $v20, $v5, $v2[2h]
    luv $v2[0], 0x00A0(t1)
    vmrg $v29, $v29, $v28
    vand $v20, $v20, $v31[7]
    vmrg $v2, $v2, $v0[0]
    vmulf $v29, $v29, $v31[7]
    vmacf $v29, $v2, $v20[0h]
    suv $v29[0], 0x0008(t6)
    bne t1, t5, f3dzex_ovl2_0000140C
    addi t1, t1, -0x0018
f3dzex_ovl2_0000144C:
    lqv $v31[0], 0x01B0(r0)
    lqv $v30[0], 0x01C0(r0)
    llv $v22[4], 0x0018(t6)
    bgezal t4, f3dzex_ovl2_00001480
    li t4, -0x7F80
    andi t3, a1, hi(G_TEXTURE_GEN)
    vmrg $v3, $v0, $v31[5]
    beqz t3, f3dzex_00001870
    vge $v27, $v25, $v31[3]
    lpv $v2[0], 0x00B0(t1)
    lpv $v20[0], 0x0098(t1)
f3dzex_ovl2_00001478:
    j f3dzex_ovl2_00001708
    vmulf $v21, $v7, $v2[0h]
f3dzex_ovl2_00001480:
    lqv $v8[0], 0x0000(t4)
    lqv $v10[0], 0x0010(t4)
    lqv $v12[0], 0x0020(t4)
    lqv $v14[0], 0x0030(t4)
    copyv v9, v8
    ldv $v9[0], 0x0008(t4)
    copyv v11, v10
    ldv $v11[0], 0x0018(t4)
    copyv v13, v12
    ldv $v13[0], 0x0028(t4)
    copyv v15, v14
    ldv $v15[0], 0x0038(t4)
    ldv $v8[8], 0x0000(t4)
    ldv $v10[8], 0x0010(t4)
    ldv $v12[8], 0x0020(t4)
    jr ra
    ldv $v14[8], 0x0030(t4)
f3dzex_ovl2_000014C4:
    lsv $v4[0], 0x0000(r0)
    lsv $v3[0], 0x0020(r0)
    lsv $v21[0], 0x0002(r0)
    lsv $v28[0], 0x0022(r0)
    lsv $v30[0], 0x0004(r0)
    vmov $v4[4], $v4[0]
    lsv $v31[0], 0x0024(r0)
    vmov $v3[4], $v3[0]
    lsv $v4[2], 0x0008(r0)
    vmov $v21[4], $v21[0]
    lsv $v3[2], 0x0028(r0)
    vmov $v28[4], $v28[0]
    lsv $v21[2], 0x000A(r0)
    vmov $v30[4], $v30[0]
    lsv $v28[2], 0x002A(r0)
    vmov $v31[4], $v31[0]
    lsv $v30[2], 0x000C(r0)
    vmov $v4[5], $v4[1]
    lsv $v31[2], 0x002C(r0)
    vmov $v3[5], $v3[1]
    lsv $v4[4], 0x0010(r0)
    vmov $v21[5], $v21[1]
    lsv $v3[4], 0x0030(r0)
    vmov $v28[5], $v28[1]
    lsv $v21[4], 0x0012(r0)
    vmov $v30[5], $v30[1]
    lsv $v28[4], 0x0032(r0)
    vmov $v31[5], $v31[1]
    lsv $v30[4], 0x0014(r0)
    vmov $v4[6], $v4[2]
    lsv $v31[4], 0x0034(r0)
    vmov $v3[6], $v3[2]
    or t4, r0, r0
    vmov $v21[6], $v21[2]
    vmov $v28[6], $v28[2]
    vmov $v30[6], $v30[2]
    j f3dzex_ovl2_00001480
    vmov $v31[6], $v31[2]
f3dzex_ovl2_0000155C:
    ldv $v20[8], 0x0000(t6)
    bltzal t4, f3dzex_ovl2_000014C4
    ldv $v20[0], 0x0010(t6)
    vmudn $v2, $v15, $v1[0]
    ldv $v29[0], 0x00A8(t1)
    vmadh $v2, $v11, $v1[0]
    vmadn $v2, $v12, $v20[0h]
    vmadh $v2, $v8, $v20[0h]
    vmadn $v2, $v13, $v20[1h]
    ldv $v29[8], 0x00A8(t1)
    vmadh $v2, $v9, $v20[1h]
    vmadn $v2, $v14, $v20[2h]
    vmadh $v2, $v10, $v20[2h]
    vsub $v20, $v29, $v2
    vmrg $v29, $v20, $v0[0]
    vmudh $v2, $v29, $v29
    vsar $v2, $v2, $v2[0]
    vsar $v29, $v29, $v29[1]
    vaddc $v29, $v29, $v29[0q]
    vadd $v2, $v2, $v2[0q]
    vaddc $v29, $v29, $v29[2h]
    vadd $v2, $v2, $v2[2h]
    vrsqh $v29[3], $v2[1]
    vrsql $v29[3], $v29[1]
    vrsqh $v29[2], $v2[5]
    vrsql $v29[7], $v29[5]
    vrsqh $v29[6], $v0[0]
    vmudn $v2, $v3, $v20[0h]
    sll t3, t3, 4
    vmadh $v2, $v4, $v20[0h]
    lbu t8, 0x00AE(t1)
    vmadn $v2, $v28, $v20[1h]
    mtc2 t3, $v27[0]
    vmadh $v2, $v21, $v20[1h]
    vmadn $v2, $v31, $v20[2h]
    vmadh $v20, $v30, $v20[2h]
    vmudm $v2, $v20, $v29[3h]
    vmadh $v20, $v20, $v29[2h]
    vmudn $v2, $v2, $v31[3]
    vmadh $v20, $v20, $v31[3]
    vmulu $v2, $v7, $v20[0h]
    mtc2 t3, $v27[8]
    vmacu $v2, $v6, $v20[1h]
    lbu t3, 0x00A7(t1)
    vmacu $v2, $v5, $v20[2h]
    sll t8, t8, 5
    vand $v20, $v2, $v31[7]
    mtc2 t8, $v20[14]
    vrcph $v29[0], $v29[2]
    vrcpl $v29[0], $v29[3]
    vrcph $v29[4], $v29[6]
    vrcpl $v29[4], $v29[7]
    vmudh $v2, $v29, $v30[7]
    mtc2 t3, $v20[6]
    vmudl $v2, $v2, $v2[0h]
    vmulf $v29, $v29, $v20[3]
    vmadm $v29, $v2, $v20[7]
    vmadn $v29, $v27, $v30[3]
    vsar $v2, $v2, $v2[1]
    vrcph $v2[0], $v2[0]
    vrcpl $v2[0], $v29[0]
    vrcph $v2[4], $v2[4]
    vrcpl $v2[4], $v29[4]
    luv $v29[0], 0x0008(t6)
    vand $v2, $v2, $v31[7]
    vmulf $v2, $v2, $v20
    luv $v20[0], 0x00A0(t1)
    vmrg $v29, $v29, $v28
    vand $v2, $v2, $v31[7]
    vmrg $v20, $v20, $v0[0]
    vmulf $v29, $v29, $v31[7]
    vmacf $v29, $v20, $v2[0h]
    suv $v29[0], 0x0008(t6)
    bne t1, t5, f3dzex_ovl2_0000140C
    addi t1, t1, -0x0018
    j f3dzex_ovl2_0000144C
f3dzex_ovl2_0000168C:
    lpv $v20[0], 0x0098(t1)
.endif

f3dzex_ovl2_00001690:
    vmulu $v21, $v7, $v2[0h]
    luv $v4[0], 0x00A0(t1)
    vmacu $v21, $v6, $v2[1h]
    beq t1, t5, f3dzex_ovl2_00001758
    vmacu $v21, $v5, $v2[2h]
    vmulu $v28, $v7, $v20[0h]
    luv $v3[0], 0x0088(t1)
    vmacu $v28, $v6, $v20[1h]
    addi t3, t1, -0x0018
    vmacu $v28, $v5, $v20[2h]
    addi t1, t1, -0x0030
    vmrg $v29, $v29, $v27
    mtc2 r0, $v4[6]
    vmrg $v3, $v3, $v0[0]
    mtc2 r0, $v4[14]
    vand $v21, $v21, $v31[7]
    lpv $v2[0], 0x00B0(t1)
    vand $v28, $v28, $v31[7]
    lpv $v20[0], 0x0098(t1)
    vmulf $v29, $v29, $v31[7]
    vmacf $v29, $v4, $v21[0h]
    bne t3, t5, f3dzex_ovl2_00001690
    vmacf $v29, $v3, $v28[0h]
    vmrg $v3, $v0, $v31[5]
    llv $v22[4], 0x0018(t6)
f3dzex_ovl2_000016F4:
    vge $v27, $v25, $v31[3]
    andi t3, a1, hi(G_TEXTURE_GEN)
    vmulf $v21, $v7, $v2[0h]
    beqz t3, f3dzex_00001870
    suv $v29[0], 0x0008(t6)
f3dzex_ovl2_00001708:
    vmacf $v21, $v6, $v2[1h]
    andi t4, a1, hi(G_TEXTURE_GEN_LINEAR)
    vmacf $v21, $v5, $v2[2h]
    vxor $v4, $v3, $v31[5]
    vmulf $v28, $v7, $v20[0h]
    vmacf $v28, $v6, $v20[1h]
    vmacf $v28, $v5, $v20[2h]
    lqv $v2[0], 0x01D0(r0)
    vmudh $v22, $v1, $v31[5]
    vmacf $v22, $v3, $v21[0h]
    beqz t4, f3dzex_00001870
     vmacf $v22, $v4, $v28[0h]
    vmadh $v22, $v1, $v2[0]
    vmulf $v4, $v22, $v22
    vmulf $v3, $v22, $v31[7]
    vmacf $v3, $v22, $v2[2]
.if (UCODE_IS_F3DEX2_204H)
    vec3 equ v22
.else
    vec3 equ v21
.endif
    vmudh $vec3, $v1, $v31[5]
    vmacf $v22, $v22, $v2[1]
    j f3dzex_00001870
     vmacf $v22, $v4, $v3
f3dzex_ovl2_00001758:
    vmrg $v29, $v29, $v27
    vmrg $v4, $v4, $v0[0]
    vand $v21, $v21, $v31[7]
    veq $v3, $v31, $v31[3h]
    lpv $v2[0], 0x0080(t1)
    vmrg $v3, $v0, $v31[5]
    llv $v22[4], 0x0018(t6)
    vmulf $v29, $v29, $v31[7]
    j f3dzex_ovl2_000016F4
    vmacf $v29, $v4, $v21[0h]
Overlay2End:

.close ; CODE_FILE
