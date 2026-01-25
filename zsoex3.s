.include "rsp/setup.inc"
.include "rsp/rsp_defs.inc"
.include "rsp/gbi_common.inc"
.include "rsp/gbi_zsoex3.inc"

ENABLE_PROFILING equ 0 // For setup.inc

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// DMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// RSP DMEM
.create DATA_FILE, 0x0000

argsAddress:
    .dh cpuInterface
cacheSize:
    .dh (cacheEnd - cacheStart)

movememTable:
    .dh cacheEnd      // G_MV_CACHEEND
    .dh viewport      // G_MV_VIEWPORT
    .dh lightColors   // G_MV_LIGHTCOLORS

movewordTable:
    .dh fxParams      // G_MW_FX
    .dh segmentTable  // G_MW_SEGMENT

unused1:
    .dh 0

viewport: // v31Value only used at init, so we can clobber it after that.
// constants for register $v31
assert_alignment 16, "Wrong alignment for v31value"
v31Value:
// v31 must go from lowest to highest (signed) values for vcc patterns.
// Also relies on the fact that $v31[0h] is -4,-4,-4,-4, 4, 4, 4, 4.
    .dh -4     // used for Newton-Raphsons
    .dh -1     // used a couple times
    .dh 0      // used often
    .dh 2      // clip ratio in vtx write
    .dh 4      // used for Newton-Raphsons
    .dh 0x4000 // used in tri write, texgen
    .dh 0x7F00 // unused
    .dh 0x7FFF // used a couple times

// constants for register vTRC
assert_alignment 16, "Wrong alignment for vTRCValue"
vTRCValue:
vTRCValue0 equ cacheStart // Currently 0x1D0; for converting vertex index to address
vTRCValue1 equ cacheEnd   // Currently 0xCD8; for vtx mtx address
vTRCValue2 equ 0x0100 // used several times in tri write, vtx mtx address
vTRCValue3 equ 0x1000 // some multiplier in tri write, vtx address
vTRCValue4 equ 0x0020 // used in tri write
vTRCValue5 equ 0x0010 // used in vtx mtx address
vTRCValue6 equ -mtxSize // used in vtx mtx address
vTRCValue7 equ vtxSize << 8 // Currently 0x1400
    .dh vTRCValue0
    .dh vTRCValue1
    .dh vTRCValue2
    .dh vTRCValue3
    .dh vTRCValue4
    .dh vTRCValue5
    .dh vTRCValue6
    .dh vTRCValue7
.macro set_vcc_11110001
    vge    $v29, vTRC, vTRC[2]
.endmacro
.if !( vTRCValue0 >= vTRCValue2  \
    && vTRCValue1 >= vTRCValue2  \
    && vTRCValue2 >= vTRCValue2  \
    && vTRCValue3 >= vTRCValue2  \
    && vTRCValue4 <  vTRCValue2  \
    && vTRCValue5 <  vTRCValue2  \
    && vTRCValue6 <  vTRCValue2  \
    && vTRCValue7 >= vTRCValue2 )
    .error "VCC pattern for vTRC corrupted"
.endif
vTRC_CCHS equ vTRC[0] // Cache Start
vTRC_CCHE equ vTRC[1] // Cache End
vTRC_0100 equ vTRC[2]
vTRC_1000 equ vTRC[3]
vTRC_0020 equ vTRC[4]
vTRC_0010 equ vTRC[5]
vTRC_M_50 equ vTRC[6] // -0x50
vTRC_OVSZ equ vTRC[7] // Output Vertex SiZe

// displaylist stack
displayListStack:
maxDisplayListCalls equ 12
displayListStackEnd equ ((4 * maxDisplayListCalls) + displayListStack)
// ucode text (shared with DL stack)
    .ascii ID_STR, 0x0A
endIdStr:
.if endIdStr < displayListStackEnd
    .fill (displayListStackEnd - endIdStr)
.elseif endIdStr > displayListStackEnd
    .error "ID_STR is too long"
    .align 16  // to suppress subsequent errors 
.endif

texgenLinearCoeffs:
    .dh 0x44D3
    .dh 0x6CB3

.macro miniTableEntry, addr
    .if addr < 0x1000 || addr >= 0x1400
        .error "Handler address out of range!"
    .endif
    .db (addr - 0x1000) >> 2
.endmacro

// RDP/Immediate Command Mini Table
// 1 byte per entry, after << 2 points to an addr in first 1/4 of IMEM

miniTableEntry G_FLUSH_handler
miniTableEntry G_DL_handler
miniTableEntry G_ENDDL_handler
miniTableEntry G_SPNOOP_handler
miniTableEntry G_MOVEWORD_handler
miniTableEntry G_MOVEMEM_handler
miniTableEntry G_RDPHALF_1_handler
miniTableEntry G_TEXRECT_handler // G_TEXRECT
miniTableEntry G_TEXRECT_handler // G_TEXRECTFLIP
miniTableEntry G_RDP_handler // G_RDPLOADSYNC
miniTableEntry G_RDP_handler // G_RDPPIPESYNC
miniTableEntry G_RDP_handler // G_RDPTILESYNC
miniTableEntry G_RDP_handler // G_RDPFULLSYNC
miniTableEntry G_RDP_handler // G_SETKEYGB
miniTableEntry G_RDP_handler // G_SETKEYR
miniTableEntry G_RDP_handler // G_SETCONVERT
miniTableEntry G_RDP_handler // G_SETSCISSOR
miniTableEntry G_RDP_handler // G_SETPRIMDEPTH
miniTableEntry G_RDP_handler // G_RDPSETOTHERMODE
miniTableEntry G_RDP_handler // G_LOADTLUT
miniTableEntry G_RDPHALF_2_handler
miniTableEntry G_RDP_handler // G_SETTILESIZE
miniTableEntry G_RDP_handler // G_LOADBLOCK
miniTableEntry G_RDP_handler // G_LOADTILE
miniTableEntry G_RDP_handler // G_SETTILE
miniTableEntry G_RDP_handler // G_FILLRECT
miniTableEntry G_RDP_handler // G_SETFILLCOLOR
miniTableEntry G_RDP_handler // G_SETFOGCOLOR
miniTableEntry G_RDP_handler // G_SETBLENDCOLOR
miniTableEntry G_RDP_handler // G_SETPRIMCOLOR
miniTableEntry G_RDP_handler // G_SETENVCOLOR
miniTableEntry G_RDP_handler // G_SETCOMBINE
miniTableEntry G_RDP_handler // G_SETTIMG
miniTableEntry G_RDP_handler // G_SETZIMG
miniTableEntry G_RDP_handler // G_SETCIMG
cmdMiniTable:
miniTableEntry G_RDP_handler // G_NOOP
miniTableEntry G_RELSEGMENT_handler
miniTableEntry G_VTX_handler
miniTableEntry G_ZSOSECTION_handler

endInitializedDmem:

displayListStackDepth:
    .skip 1 // starts at 0, increments by 4 for each "return address" pushed onto the stack

    .align 4

altBase: // TODO eliminate or reuse?
fxParams:

asoScale:
    .dh 0x0100 // 0x0100 for ASO disable, 0xFF80 for ASO enable
asoColorOffset:
    .db 0 // 0 for ASO disable, (0x100 - shade color threshold) / 2 for ASO
asoAlphaOffset:
    .db 0 // 0 for ASO disable, (0x100 - shade alpha threshold) / 2 for ASO

perspNorm:
    .skip 2

geometryModeLabel:
    .skip 2

    .align 4 // TODO

// First half of RDP value for split commands. Also used as temp storage for
// tri vertices during tri commands.
rdpHalf1Val:
    .skip 4

assert_alignment 4, "cpuInterface misaligned"
cpuInterface:
ucodeTextStart:
    .skip 4
displayListStart:
rdpFifoPos: // displayListStart only used at init
    .skip 4
rdpFifoStart:
    .skip 4
rdpFifoEnd:
    .skip 4
debugBuffer:
    .skip 4

    .align 8 // TODO

segmentTable:
    .skip (4 * 16) // 16 DRAM pointers

assert_alignment 8, "texrectState misaligned"
texrectState:  // Only needs to be saved over texrect, half1, half2
    .skip 8 // TODO

assert_alignment 8, "lightColors misaligned"
lightColors:
    .skip 16

assert_alignment 8, "cacheStart misaligned"
cacheStart:
    
INPUT_BUFFER_CMDS equ 21
INPUT_BUFFER_SIZE_BYTES equ (INPUT_BUFFER_CMDS * 8)

RDP_TRI_SIZE_NO_ZBUF equ 0xA0
RDP_CMD_BUFSIZE_TOTAL equ (2 * RDP_TRI_SIZE_NO_ZBUF)

CACHE_END_ADDR equ (0x1000 - INPUT_BUFFER_SIZE_BYTES - (2 * RDP_CMD_BUFSIZE_TOTAL))
.org CACHE_END_ADDR
cacheEnd:

// First RDP Command Buffer
rdpCmdBuffer1:
    .skip RDP_TRI_SIZE_NO_ZBUF
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer1End:
    .skip 8
rdpCmdBuffer1EndPlus1Word:
    // This is so that we can temporarily store vector regs here with lqv/sqv
    .skip RDP_TRI_SIZE_NO_ZBUF - 8
// Second RDP Command Buffer
rdpCmdBuffer2:
    .skip RDP_TRI_SIZE_NO_ZBUF
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer2End:
    .skip 8
rdpCmdBuffer2EndPlus1Word:
    .skip RDP_TRI_SIZE_NO_ZBUF - 8

// Input buffer. After RDP cmd buffers so it can be vector addressed from end.
inputBuffer:
    .skip INPUT_BUFFER_SIZE_BYTES
inputBufferEnd:
inputBufferEndSgn equ (-(0x1000 - inputBufferEnd)) // Underflow DMEM address

.if . != 0x1000
    .error "DMEM organization incorrect"
.endif

.close // DATA_FILE

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Naming ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/*
Scalar regs:
      Tri write      Vtx write    Cmd dispatch
$zero ------------Hardwired zero -------------
$1    v1 texptr       vtxLeft     temp, init 0
$2    v2 shdptr       mtx1Addr        temp
$3    v3              mtx2Addr        temp
$4    facingFlip           
$5    -------------- geomMode ----------------
$6    indexBuf
$7        v2c         outVtx2       cmd byte
$8    indexBufEnd
$9    indexBufInc
$10   ---------------- temp2 -----------------
$11   ---------------- temp ------------------
$12   ------------ perfCounterD --------------
$13   ------------- altBaseReg ---------------
$14   subSec           inVtx
$15   subSecEnd      outVtxBase
$16   sectionBase
$17   subSecOfsShf
$18   alccThresh
$19       v1c         outVtx1        dmaLen
$20      temp         flagsV1       dmemAddr
$21   
$22   ------------rdpCmdBufEndP1 -------------
$23   ------------ rdpCmdBufPtr --------------
$24      temp         flagsV2      cmd_w1_dram
$25       v3c                        cmd_w0
$26   ------------- taskDataPtr --------------
$27   ------------inputBufferPos -------------
$28   ------------ perfCounterA --------------
$29   ------------ perfCounterB --------------
$30   ------------ perfCounterC --------------
$ra   return address, command handler address, sometimes sign bit is flag
*/

// Global scalar regs:
geomMode       equ $5    // Geometry mode; facing flag in sign bit
perfCounterD   equ $12   // Performance counter D (functions depend on config)
altBaseReg     equ $13   // Alternate base address register for vector loads
rdpCmdBufEndP1 equ $22   // Pointer to one command word past "end" (middle) of RDP command buf
rdpCmdBufPtr   equ $23   // RDP command buffer current DMEM pointer
taskDataPtr    equ $26   // Task data (display list) DRAM pointer
inputBufferPos equ $27   // DMEM position within display list input buffer, relative to end
perfCounterA   equ $28   // Performance counter A (functions depend on config)
perfCounterB   equ $29   // Performance counter B (functions depend on config)
perfCounterC   equ $30   // Performance counter C (functions depend on config)

// Tri write:
v1c            equ $19
v2c            equ $7
v3c            equ $25
facingFlip     equ $4    // 0 or -0x8000, XOR'd into facing every tri for strip
indexBuf       equ $6    // Draw tri bytes +1, +2, +3 from here
indexBufEnd    equ $8    // Stop drawing tris when indexBuf reaches here
indexBufInc    equ $9    // 1 for strip or 3 for full tris
subSec         equ $14   // Subsection index, 0 to nss-1
subSecEnd      equ $15   // Number of subsections
sectionBase    equ $16   // Start address of ZSOSection
subSecOfsShf   equ $17   // Left shift applied to offsets

// Vertex write:
vtxLeft        equ $1    // Number of vertices left to process * 0x10
mtx1Addr       equ $2    // Matrix 1 end address
mtx2Addr       equ $3    // Matrix 2 end address
outVtx2        equ $7    // Pointer to second or dummy (= outVtx1) transformed vert
inVtx          equ $14   // Pointer to loaded vertex to transform; < 0 means from clipping.
outVtxBase     equ $15   // Pointer to vertex buffer to store transformed verts
outVtx1        equ $19   // Pointer to first transformed vert
flagsV1        equ $20   // Clip flags for vertex 1
flagsV2        equ $24   // Clip flags for vertex 2

// Misc:
nextRA         equ $10   // Address to return to after overlay load
dmaLen         equ $19   // DMA length in bytes minus 1
dmemAddr       equ $20   // DMA address in DMEM or IMEM. Also = rdpCmdBufPtr - rdpCmdBufEndP1 for flush_rdp_buffer
cmd_w1_dram    equ $24   // DL command word 1, which is also DMA DRAM addr
cmd_w0         equ $25   // DL command word 0, also holds next tris info

// Global vector regs:
// TODO can maybe get rid of vZero
vZero equ $v0  // All elements = 0; NOT global, only in tri write and clip. Mtx in vtx.
vTRC  equ $v1  // Triangle Constants; NOT global, only in tri write and clip. Mtx in vtx.
vOne  equ $v28 // All elements = 1; global
// $v29: permanent temp register, also write results here to discard
// $v30: unused now
// $v31: Global constant vector register

// Vertex / lighting vector regs:
// Prefixes: v = vector register, vp = vertex pair, s = vertex store
// Sadly, "vp" stands for vertex pair, view*projection matrix, and viewport

vMTX0I   equ $v0  // MVP matrix rows int/frac
vMTX1I   equ $v1  // Elems 0-3 matrix 1, elems 4-7 matrix 2
vMTX2I   equ $v2
vMTX3I   equ $v3
vMTX0F   equ $v4
vMTX1F   equ $v5
vMTX2F   equ $v6
vMTX3F   equ $v7
ldM1     equ $v8  // Light dir in model space for matrix 1. elem 3 = persp norm
ldM2     equ $v9  // Same for matrix 2
sVPS     equ $v10 // Viewport scale
sVPO     equ $v11 // Viewport offset
vpMdl    equ $v15
vpScrI   equ $v16
lDIR     equ $v17
vM1Wt    equ $v18 // Matrix 1 weight in 3, 7; matrix 2 weight is vpMdl[3h]
vpNrmlX  equ $v19
vpNrmlY  equ $v20
vpNrmlZ  equ $v21
clp1F    equ $v22
clp1I    equ $v23
clp2F    equ $v24
clp2I    equ $v25
vpClpF   equ $v26
vpClpI   equ $v27

s1WF   equ vpNrmlX
s1WI   equ vpNrmlY
vpRGBA equ vpNrmlZ
sSCF   equ clp1F
sSCI   equ clp1I
sTCL   equ clp2F
sTC2   equ clp2I
sRTF   equ clp2F
sRTI   equ clp2I

// Temp storage after rdpCmdBufEndP1. There is 0x98 of space here which will
// always be free during vtx load or clipping.
tempVXchg                     equ 0x00
sizeVXchg        equ 0x20
tempOldTC                     equ tempVXchg + sizeVXchg
sizeOldTC        equ 0x10
tempVpRGBA                    equ tempOldTC + sizeOldTC        
sizeVpRGBA       equ 0x08
tempPrevInvalVtx              equ tempVpRGBA + sizeVpRGBA
sizePrevInvalVtx equ vtxSize
tempEnd                       equ tempPrevInvalVtx + sizePrevInvalVtx
.if tempEnd > (RDP_TRI_SIZE_NO_ZBUF - 8)
    .error "Too much temp storage used!"
.endif


////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// IMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// RSP IMEM
.create CODE_FILE, 0x00001000

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl1
start:
    lqv     $v31[0], (v31Value)($zero)
    lw      $2, rdpFifoEnd                // Load FIFO end addr
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    li      perfCounterA, 0
    li      perfCounterB, 0
    mtc0    $2, DPC_START                 // Set RDP start addr to end of FIFO
    mtc0    $2, DPC_END                   // Set RDP end addr to end of FIFO
    lw      taskDataPtr, displayListStart // Must be before store to rdpFifoPos
    li      perfCounterC, 0
    vclr    vOne
    li      perfCounterD, 0
    sw      $2, rdpFifoPos                // Must be after load from displayListStart
    lqv     vTRC, (vTRCValue)($zero)      // Always as this value except vtx_store
    li      altBaseReg, altBase
    li      rdpCmdBufPtr, rdpCmdBuffer1
    li      rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word
    vsub    vOne, vOne, $v31[1]             // 1 = 0 - -1
    lh      geomMode, geometryModeLabel
    li      inputBufferPos, 0
    li      nextRA, displaylist_dma
    j       load_overlays_0_1
     li     cmd_w1_dram, orga(ovl1_start)

start_end:
.align 8
start_padded_end:

.orga max(orga(), max(ovl0_padded_end - ovl0_start, ovl1_padded_end - ovl1_start))
ovl01_end:

G_DL_handler:
    sll     $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
    lbu     $7, displayListStackDepth       // Get the DL stack depth
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
    bltz    $2, call_ret_common             // Nopush = branch = flag is set
     move   taskDataPtr, cmd_w1_dram        // Set the new DL to the target display list
    sw      $3, (displayListStack)($7)
    addi    $7, $7, 4                       // Increment the DL stack depth
call_ret_common:
    sb      $7, displayListStackDepth
    andi    inputBufferPos, cmd_w0, 0x00F8  // Byte 3, how many cmds to drop from load (max 0xA0)
displaylist_dma:
    li      nextRA, run_next_DL_command
displaylist_dma_goto_next_ra:
    // Load INPUT_BUFFER_SIZE_BYTES - inputBufferPos cmds (inputBufferPos >= 0, mult of 8)
    addi    inputBufferPos, inputBufferPos, -INPUT_BUFFER_SIZE_BYTES // inputBufferPos = - num cmds
    nor     dmaLen, inputBufferPos, $zero              // DMA length = -inputBufferPos - 1 = ones compliment
    move    cmd_w1_dram, taskDataPtr                   // set up the DRAM address to read from
    jal     dma_read_write
     addi   dmemAddr, inputBufferPos, inputBufferEnd   // set the address to DMA read to
    j       wait_goto_next_ra                      // if not, continue normal processing
     sub    taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
    
load_overlay_0_and_enter:
    li      nextRA, 0x1000                  // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)   // Sets up ovl0 table address
load_overlays_0_1:
    lw      $11, ucodeTextStart             // TODO move this to start, move ovl0 stuff here
    li      dmaLen, ovl01_end - 0x1000 - 1
    li      dmemAddr, 0x1000
    j       dma_and_wait_goto_next_ra
     add    cmd_w1_dram, cmd_w1_dram, $11

G_RDPHALF_2_handler: // 8; should be after the handlers with alignment needs
    li      $11, texrectState
    ldv     $v29[0], (0)($11)
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
    addi    perfCounterB, perfCounterB, 1   // Increment number of tex/fill rects
    sdv     $v29[0], -8(rdpCmdBufPtr)
    sw      cmd_w0, 0(rdpCmdBufPtr)  // TODO can optimize this with vector ops
    j       commit_small_rdp_command
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // w1 is from the current command

G_RDP_handler:
    spv     $v4[0], 0(rdpCmdBufPtr)     // Whole command
commit_small_rdp_command:
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8    // Increment the next RDP command pointer by 2 words
check_rdp_buffer_full_and_run_next_cmd:
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    bgezal  dmemAddr, flush_rdp_buffer
     // $7 on next instr survives flush_rdp_buffer
tris_end:
G_SPNOOP_handler:
run_next_DL_command:
     lb     $7, (inputBufferEnd)(inputBufferPos)        // Command byte
    lpv     $v4[0], (inputBufferEndSgn)(inputBufferPos) // Whole command
    vclr    vZero
    beqz    inputBufferPos, displaylist_dma             // Check if buffer is empty
     lbu    $ra, (cmdMiniTable)($7)                     // Load mini table entry
    vmudn   $v29, vOne, vTRC_CCHS                       // Cache start address
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // Word 0
    vmadl   $v7, $v4, vTRC_OVSZ                         // Plus vtx indices times output vertex size
    lw      cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // Word 1
    vmadl   $v6, $v31, $v31[2]                          // 0; copy in v6 TODO not used
    sll     $ra, $ra, 2                                 // Convert to a number of instructions
    vmudl   $v8, $v4, vTRC_1000                         // Input vertex size elem 2
    jr      $ra                                         // Jump to handler
     addi   inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
    // $7 must retain the command byte for load_mtx and command dispatch in overlays 2 and 3
    // $ra must contain the handler called for several handlers

align_with_warning 8, "One instruction of padding before G_VTX_handler"

G_VTX_handler: // 11
    vadd    $v3, $v31, vTRC_0010   // Elem 1 = -1 + 10 = 0x000F
    jal     segmented_to_physical  // Convert address in cmd_w1_dram to physical
     mfc2   vtxLeft, $v8[4]        // Input vertices size in bytes
    mfc2    dmemAddr, $v7[6]       // End address
    vsub    $v9, $v7, $v5[2]       // Elem 3 = end address - output size = output start addr
    li      $ra, vtx_after_dma
    vmudh   $v29, vOne, vTRC_CCHE  // Cache end
    addi    dmaLen, vtxLeft, -1
    vmadh   $v2, $v2, vTRC_M_50    // Minus matrix index times size; elems 2=m2, 5=m1
    j       dma_read_write         // DMA start addr = end addr - input size
     sub    dmemAddr, dmemAddr, vtxLeft // Rounded down to DMA word by H/W

align_with_warning 8, "One instruction of padding before segmented_to_physical"

// Converts the segmented address in cmd_w1_dram to the corresponding physical address
segmented_to_physical: // 8
    vmudl   $v2, vTRC, $v4[1]      // Byte 1 = mtx idxs. Elem 2 bits 3:0 = mtx 2. Elem 5 bits 3:0 = mtx 1.
    srl     $11, cmd_w1_dram, 22          // Copy (segment index << 2) into $11
    vmudl   $v5, $v4, vTRC_OVSZ    // Output vertices size elem 2
    andi    $11, $11, 0x3C                // Only 4 bits for segment
    lw      $11, (segmentTable)($11)      // Get the current address of the segment
    sll     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address to the left so that the top 8 bits are shifted out
    srl     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    vand    $v2, $v2, $v3[1]       // 0x000F. Elem 2 = mtx 2 idx, elem 5 = mtx 1 idx
    jr      $ra
     add    cmd_w1_dram, cmd_w1_dram, $11 // Add the segment's address to the masked input address, resulting in the virtual address

G_MOVEMEM_handler: // If called this handler, $7 = (-0x100 | G_MOVEMEM)
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
     andi   $3, cmd_w0, 0x001E            // Movemem table index into $3 (bits 1-4 of the word 0)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Second byte of word 0
    lhu     dmemAddr, (movememTable)($3)
    srl     $2, cmd_w0, 5                 // ((w0) >> 8) << 3; top 3 bits of idx must be 0
    add     dmemAddr, dmemAddr, $2        // This is bits 5-16 inclusive for 12 bit DMEM
    li      nextRA, run_next_DL_command
dma_and_wait_goto_next_ra:
    j       dma_read_write
     li     $ra, wait_goto_next_ra

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
     li     $ra, run_next_DL_command

/*
$v0  = vZero
$v1  = vTRC
$v2  = tASO
$v3  = [tXYI1, tXYITmp1], tPosMmH, | t1WF
$v4  = [tXYI2, tXYITmp2] | [tMnWF, tSTWLI, tDaDxI]
$v5  = tXYI3, tPosLmH (becomes multi)
$v6  = t2m1, tPosHmM,    | [tMx1W, tMnWI, tSTWHMF]
$v7  = next vertex addresses
$v8  = tXYITmp0, tMPos, tXHMF
$v9  =                  tXHMI
$v10 = [tRcpDyI, tAndCatF]
$v11 = [tRcpDyF, tNewCatF, tDaDeF]
$v12 = tTemp, [tPosCatI, tDaDeI]
$v13 = tXPRcpF
$v14 = tXPRcpI
$v15 = tXPF
$v16 = tXPI
$v17 = tHPos
$v18 = tXYITmp3    |       [t1WI, tSTWLF, tDaDxF]
$v19 = t1m2, tLPos, tSubPxH
$v20 = tPosCatF,                  tSTWHMI
$v21 = 
$v22 = [tLAtF, tAtLmHF, tDaDyF]
$v23 = [tLAtI, tAtLmHI, tDaDyI]
$v24 = [tMAtF, tAtMmHF]
$v25 = [tMAtI, tAtMmHI]
$v26 = tHAtF
$v27 = tHAtI
$v28 = vOne
$v29 = discard
$v30 = 
$v31 = constants
*/

G_ZSOSECTION_handler:
    jal     segmented_to_physical
     srl    dmemAddr, cmd_w0, 7-3 // Bits 3:11 of DMEM address, bit 12 is 0 to select DMEM
    addi    dmemAddr, dmemAddr, cacheStart // Relative to cache start
    sll     dmaLen, cmd_w0, 3 // Bits 3:9 of DMA length - 1
    jal     dma_read_write
     andi   dmaLen, dmaLen, 0x3F8 // Mask out lower 2 bits of addr
    andi    sectionBase, dmemAddr, 0xFF8 // Can't leave it in dmemAddr b/c tri write DMA clobbers
    srl     subSecEnd, cmd_w0, 17 // Subsection count minus 1
    andi    subSecEnd, subSecEnd, 0x1F
    addi    subSecEnd, subSecEnd, 1 // Remove the minus 1
    add     subSecEnd, subSecEnd, sectionBase // End address
    srl     subSecOfsShf, cmd_w0, 22 // Offsets are left shifted by this much
    jal     while_wait_dma_busy
     andi   subSecOfsShf, subSecOfsShf, 3
    // Convert reference vertices from index -> address
    lpv     $v2, (0x20)(sectionBase)
    lpv     $v3, (0x28)(sectionBase)
    lpv     $v4, (0x30)(sectionBase)
    lpv     $v5, (0x38)(sectionBase)
    vmudn   $v29, vOne, vTRC_CCHS  // Cache start address
    vmadl   $v2,  $v2,  vTRC_OVSZ  // Plus vtx indices times output vertex size
    move    subSec, sectionBase
    vmudn   $v29, vOne, vTRC_CCHS  // Cache start address
    move    $1, rdpCmdBufEndP1
    vmadl   $v3,  $v3,  vTRC_OVSZ  // Plus vtx indices times output vertex size
    vmudn   $v29, vOne, vTRC_CCHS  // Cache start address
    sqv     vZero, (0x40)(rdpCmdBufEndP1) // Set invalid vertex Zs to 0 (close to camera)
    vmadl   $v4,  $v4,  vTRC_OVSZ  // Plus vtx indices times output vertex size
    sqv     vZero, (0x50)(rdpCmdBufEndP1)
    vmudn   $v29, vOne, vTRC_CCHS  // Cache start address
    sqv     vZero, (0x60)(rdpCmdBufEndP1)
    vmadl   $v5,  $v5,  vTRC_OVSZ  // Plus vtx indices times output vertex size
    sqv     vZero, (0x70)(rdpCmdBufEndP1)
    sqv     $v2, (0x00)(rdpCmdBufEndP1)
    sqv     $v3, (0x10)(rdpCmdBufEndP1)
    sqv     $v4, (0x20)(rdpCmdBufEndP1)
    sqv     $v5, (0x30)(rdpCmdBufEndP1)
    // Convert reference vertices from address -> Z position
@@loop:
    lhu     $3, (0)($1)
    addi    $1, $1, 2
    lhu     $3, (VTX_SCR_Z)($3)
    addi    subSec, subSec, 1
    bne     subSec, subSecEnd, @@loop
     sh     $3, (0x40 - 2)($1)
    // Load offsets and Zs
    lqv     $v20, (0x40)(rdpCmdBufEndP1)
tASO equ $v2
    vclr    tASO
    lpv     $v21, (0x00)(sectionBase)
    lqv     $v22, (0x50)(rdpCmdBufEndP1)
    lpv     $v23, (0x08)(sectionBase)
    lqv     $v24, (0x60)(rdpCmdBufEndP1)
    lpv     $v25, (0x10)(sectionBase)
    lqv     $v26, (0x70)(rdpCmdBufEndP1)
    lpv     $v27, (0x18)(sectionBase)
    // Optimal 8 element sorting network from
    // https://bertdobbelaere.github.io/sorting_networks.html#N8L19D6
    // Elements 0 and 1 from each of 4 vectors (a, b, c, d). 4 groups of these in parallel
    // E.g. a0 is $v20[0], a1 is $v20[1], b0 is $v22[0], etc.
    // Then another a0 is $v20[2], and another is $v20[4], and last is $v20[6]
.macro sort_swap, ozh, oih, ozl, oil, z0, i0, z1, i1
    vge     ozh, z0, z1
    vmrg    oih, i0, i1
    vlt     ozl, z0, z1
    vmrg    oil, i0, i1
.endmacro
.macro sort_swap_toeven, ozh, oih, z0, i0
    vge     ozh, z0, z0[1q]
    vmrg    oih, i0, i0[1q]
    vlt     z0, z0, z0[1q]
    vmrg    i0, i0, i0[1q]
.endmacro
    sort_swap $v12, $v13, $v14, $v15, $v20, $v21, $v22, $v23 // swap(a0, b0), swap(a1, b1)
    lbv     tASO[1], (asoColorOffset - altBase)(altBaseReg)
    sort_swap $v16, $v17, $v18, $v19, $v24, $v25, $v26, $v27 // swap(c0, d0), swap(c1, d1)
    lbv     tASO[3], (asoColorOffset - altBase)(altBaseReg)
    sort_swap $v20, $v21, $v24, $v25, $v12, $v13, $v16, $v17 // swap(a0, c0), swap(a1, c1)
    lbv     tASO[5], (asoColorOffset - altBase)(altBaseReg)
    sort_swap $v22, $v23, $v26, $v27, $v14, $v15, $v18, $v19 // swap(b0, d0), swap(b1, d1)
    lbv     tASO[7], (asoAlphaOffset - altBase)(altBaseReg)
    sort_swap_toeven $v12, $v13, $v20, $v21 // new a0, new a1
    lsv     $v8[8], (asoScale - altBase)(altBaseReg) // elem 4
    sort_swap_toeven $v14, $v15, $v22, $v23 // new b0, new b1
    li      $11, -8        // 0xFFF8; constant for some mask in tri write
    sort_swap_toeven $v16, $v17, $v24, $v25 // new c0, new c1
    mtc2    $11, $v8[10]   // 0xFFF8; elem 5
    sort_swap_toeven $v18, $v19, $v26, $v27 // new d0, new d1
    sort_swap $v10, $v11, $v16, $v17, $v14, $v15, $v16, $v17 // new b0, c0 = swap(b0, c0)
    sort_swap $v14, $v15, $v24, $v25, $v22, $v23, $v24, $v25 // new b1, c1 = swap(b1, c1)
    sort_swap $v22, $v23, $v16, $v17, $v20, $v21, $v16, $v17 // new a1, c0 = swap(a1, c0)
    sort_swap $v20, $v21, $v18, $v19, $v14, $v15, $v18, $v19 // new b1, d0 = swap(b1, d0)
    sort_swap $v14, $v15, $v10, $v11, $v22, $v23, $v10, $v11 // new a1, b0 = swap(a1, b0)
    sort_swap $v22, $v23, $v16, $v17, $v20, $v21, $v16, $v17 // new b1, c0 = swap(b1, c0)
    move    subSec, sectionBase
    sort_swap $v20, $v21, $v18, $v19, $v24, $v25, $v18, $v19 // new c1, d0 = swap(c1, d0)
    sqv     vZero, (0x80)(rdpCmdBufEndP1) // So when lists run off end, get z = 0
    // Element 0 of these regs are sorted in order, same for 2, 4, 6
    // These regs + 1 = indices
    // $v12, $v14, $v10, $v22, $v16, $v20, $v18, $v26
    veq     $v29, $v31, $v31[0q] // vcc = 10101010
    li      $24, 0xFF
    vmrg    $v12, $v12, $v13[0q] // Interleave Z, index, Z, index, Z, index, Z, index
    addi    $1, rdpCmdBufEndP1, 0x0
    vmrg    $v14, $v14, $v15[0q]
    addi    $2, rdpCmdBufEndP1, 0x4
    vmrg    $v10, $v10, $v11[0q]
    addi    $3, rdpCmdBufEndP1, 0x8
    vmrg    $v22, $v22, $v23[0q]
    addi    $4, rdpCmdBufEndP1, 0xC
    vmrg    $v16, $v16, $v17[0q]
    sqv     $v12, (0x00)(rdpCmdBufEndP1)
    vmrg    $v20, $v20, $v21[0q]
    sqv     $v14, (0x10)(rdpCmdBufEndP1)
    vmrg    $v18, $v18, $v19[0q]
    sqv     $v10, (0x20)(rdpCmdBufEndP1)
    vmrg    $v12, $v12, $v31[2] // 0; clear indices
    sqv     $v22, (0x30)(rdpCmdBufEndP1)
    vmrg    $v26, $v26, $v27[0q]
    sqv     $v16, (0x40)(rdpCmdBufEndP1)
    vmudh   tASO, tASO, $v31[1] // -1; negate color and alpha offsets in elems 0-3
    sqv     $v20, (0x50)(rdpCmdBufEndP1)
    vnop
    sqv     $v18, (0x60)(rdpCmdBufEndP1)
    vadd    $v13, $v12, $v31[1] // -1; subtract 1 from Z values
    j       merge_sort_entry
     sqv    $v26, (0x70)(rdpCmdBufEndP1)

merge_sort_loop:
    vadd    $v13, $v12, $v31[1] // -1; subtract 1 from Z values to turn vlt into vle
    blez    $10, sort_done_z0 // Z<=0, stop early
     addi   subSec, subSec, 1
    beq     subSec, subSecEnd, sort_done_regular
     sb     $11, (-1)(subSec)
merge_sort_entry:
    vlt     $v29, $v13, $v12[0] // v12-1 < v12[0] :=: v12 <= v12[0] :=: v12[0] >= v12
    cfc2    $20, $vcc
    vlt     $v29, $v13, $v12[2] // Or the head of list 2?
    cfc2    $10, $vcc
    vlt     $v29, $v13, $v12[4] // Or list 4?
    beq     $20, $24, merge_sort_list_0
     cfc2   $11, $vcc
    beq     $10, $24, merge_sort_list_2
     nop
    beq     $11, $24, merge_sort_list_4
     nop
merge_sort_list_6:
.macro merge_sort_list, vbyte, ptr
    mfc2    $10, $v12[vbyte] // Get selected Z value
    lsv     $v12[vbyte], (0x10)(ptr) // Load next Z value
    lbu     $11, (0x2)(ptr) // Load offset
    j       merge_sort_loop
     addi   ptr, ptr, 0x10
.endmacro
    merge_sort_list 12, $4
merge_sort_list_4:
    merge_sort_list 8, $3
merge_sort_list_2:
    merge_sort_list 4, $2
merge_sort_list_0:
    merge_sort_list 0, $1

sort_done_z0:
    addi    subSecEnd, subSec, -1  // Just incremented subSec, but it was already one too far
sort_done_regular:
    vlt     $v29, $v31, $v31[4] // Set vcc to 11110000
    move    subSec, sectionBase
    vmrg    tASO, tASO, $v8 // Additional constants which were not negated
subsec_loop:
    lbu     indexBuf, (0)(subSec)
    lh      geomMode, geometryModeLabel // Reset geometry mode modified by facingFlip
    beq     subSec, subSecEnd, run_next_DL_command
     sllv   indexBuf, indexBuf, subSecOfsShf
    add     indexBuf, indexBuf, sectionBase
tTemp equ $v12
    lpv     tTemp[0], (0)(indexBuf) // First tri indices to elems 1, 2, 3
    lb      $24, (0)(indexBuf) // Metadata byte
    addi    subSec, subSec, 1
    li      facingFlip, -0x8000    // Facing is sign bit
    vmudn   $v29, vOne, vTRC_CCHS  // Cache start address
    andi    indexBufEnd, $24, 0x7F // Tri count
    vmadl   $v7, tTemp, vTRC_OVSZ   // Plus vtx indices times output vertex size
    sll     $11, indexBufEnd, 14   // RSP tris counter starts at bit 14
    add     perfCounterB, perfCounterB, $11
    bltz    $24, @@skip_not_tri_strip
     li     indexBufInc, 1
    li      facingFlip, 0
    li      indexBufInc, 3
    sll     $11, indexBufEnd, 1
    add     indexBufEnd, indexBufEnd, $11 // Byte count = tri count * 3
@@skip_not_tri_strip:
    j       tri_start
     add    indexBufEnd, indexBufEnd, indexBuf // + start addr

align_with_warning 8, "One instruction of padding before tri_start"

tri_end:
tri_start: // $v7 elems 1, 2, 3 hold vtx addrs
tXYI1 equ $v3
    vmudh   tXYI1, vOne, $v7[1] // elem 2 of v6 = vertex 1 addr
    beq     indexBuf, indexBufEnd, subsec_loop
     mfc2   $1, $v7[2]
tXYI2 equ $v4
    vmudh   tXYI2, vOne, $v7[2] // elem 2 of v4 = vertex 2 addr
    mfc2    $2, $v7[4]
tXYI3 equ $v5
    vmudh   tXYI3, vOne, $v7[3] // elem 2 of v8 = vertex 3 addr
    add     indexBuf, indexBuf, indexBufInc
tHAtF equ $v26
    vnxor   tHAtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    lpv     tTemp[0], (0)(indexBuf)
tMAtF equ $v24
    vnxor   tMAtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    mfc2    $3, $v7[6]
tLAtF equ $v22
    vnxor   tLAtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    llv     tXYI1[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
tXHMI equ $v9
    vmudh   tXHMI, vOne, $v31[5] // 0x4000; some rounding factor
    llv     tXYI2[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vmudn   $v29, vOne, vTRC_CCHS      // Cache start address
    llv     tXYI3[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vmadl   $v7, tTemp, vTRC_OVSZ        // Plus vtx indices times output vertex size
    lhu     v1c, VTX_CLIP($1)
tXYITmp0 equ $v8
    vmudh   tXYITmp0, vOne, tXYI1[1] // v2 all elems = y-coord of vertex 1
    lhu     v2c, VTX_CLIP($2)
t1m2 equ $v19
    vsub    t1m2, tXYI1, tXYI2    // v10 = vertex 1 - vertex 2 (x, y, addr)
    lhu     v3c, VTX_CLIP($3)
    vsub    tTemp, tXYI1, tXYI3    // v12 = vertex 1 - vertex 3 (x, y, addr)
    xor     geomMode, geomMode, facingFlip
t2m1 equ $v6
    vsub    t2m1, tXYI2, tXYI1    // v11 = vertex 2 - vertex 1 (x, y, addr)
    or      $10, v1c, v2c
tXYITmp3 equ $v18
    vlt     tXYITmp3, tXYITmp0, tXYI2[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    or      $10, $10, v3c     // $10 = all clip bits which are true for any verts
tHPos equ $v17
    vmrg    tHPos, tXYI1, tXYI2   // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    andi    $10, $10, CLIP_SCAL_NPXY | CLIP_CAMPLANE
    vmudh   $v29, t1m2, tTemp[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    bnez    $10, tri_end // Reject (instead of clipping)
     vmadh  tTemp, tTemp, t2m1[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    vge     tXYITmp0, tXYITmp0, tXYI2[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    and     $11, v1c, v2c
tLPos equ t1m2
    vmrg    tLPos, tXYI1, tXYI2   // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    and     $11, $11, v3c
tXYITmp1 equ tXYI1
    vge     tXYITmp1, tXYITmp3, tXYI3[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    bnez    $11, tri_end // All three verts on the same side of any plane, exit
     mfc2   $10, tTemp[0]      // elem 0 = x = cross product => lower 16 bits, sign extended
tXYITmp2 equ tXYI2
    vmrg    tXYITmp2, tHPos, tXYI3   // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    ssv     $v31[14], 0x0036(rdpCmdBufEndP1) // 0x7FFF
    vmrg    tHPos, tXYI3, tHPos // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    ori     $24, geomMode, G_TRI_FILL // Geom mode low byte -> tri cmd ID
    vlt     $v29, tXYITmp1, tXYITmp0    // VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    xor     $11, $10, geomMode // Sign bit clear if x prod positive (back facing), set if x prod negative (front facing)
    vnop
    bgez    $11, tri_end // Cull if bit is clear (culled based on facing)
tMPos equ tXYITmp0
     vmrg   tMPos, tXYITmp2, tLPos // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    vmrg    tLPos, tLPos, tXYITmp2 // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
    mfc2    $1, tHPos[4]     // tHPos = lowest Y value = highest on screen (x, y, addr)
    vnop
    beqz    $10, tri_end  // If cross product is 0, tri is degenerate (zero area), cull.
     li     $ra, tri_end // Only matters if we continue to flush_rdp_buffer
tPosMmH equ tXYITmp1
    vsub    tPosMmH, tMPos, tHPos
tHAtI equ $v27
    lpv     tHAtI[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
tPosLmH equ tXYI3
    vsub    tPosLmH, tLPos, tHPos
    mfc2    $2, tMPos[4]     // tMPos = mid vertex (x, y, addr)
tPosHmM equ t2m1
    vsub    tPosHmM, tHPos, tMPos
    addi    $11, rdpCmdBufEndP1, -2 // For MmHX, MmHY
tPosCatI equ tTemp // 0 X L-M; 1 Y L-M; 2 X M-H; 3 X L-H; 4-7 garbage
    vsub    tPosCatI, tLPos, tMPos
    lw      v1c, VTX_INV_W_VEC($1) // v1c, v2c, v3c = 1/W for H, M, L
    vmudn   $v29, tHAtI, tASO[4] // asoScale
    mfc2    $3, tLPos[4]     // tLPos = highest Y value = lowest on screen (x, y, addr)
    vmadh   tHAtI, vOne, tASO // Color and alpha offsets elems 0-3
tMAtI equ $v25
    lpv     tMAtI[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vmudh   $v29, tPosMmH, tPosLmH[0]
    lw      v2c, VTX_INV_W_VEC($2)
    vmadh   $v29, tPosLmH, tPosHmM[0]
    lw      v3c, VTX_INV_W_VEC($3)
tXPI equ $v16
    vreadacc tXPI, ACC_UPPER
t1WI equ tXYITmp3
    llv     t1WI[0], VTX_INV_W_VEC($1)
tXPF equ $v15
    vreadacc tXPF, ACC_MIDDLE
    sub     v2c, v1c, v2c  // Four instr: v1c = max(v1c, v2c)
    vmudn   $v29, tMAtI, tASO[4] // asoScale
    llv     t1WI[8], VTX_INV_W_VEC($2)
    vmadh   tMAtI, vOne, tASO // Color and alpha offsets elems 0-3
    sb      $24, 0x0000(rdpCmdBufPtr) // Store the triangle command id
tRcpDyF equ $v11
    vrcp    tRcpDyF[0], tPosCatI[1]
    llv     t1WI[12], VTX_INV_W_VEC($3)
tRcpDyI equ $v10
    vrcph   tRcpDyI[0], tXPI[1]
    slv     tPosMmH[0],  0x0030($11) // MmHX -> 0x2E, MmHY -> first short (temp mem)
tXPRcpF equ $v13 // Reciprocal of cross product
    vrcpl   tXPRcpF[1], tXPF[1]
    lsv     tPosCatI[4], 0x002E(rdpCmdBufEndP1) // MmHX -> pos cat e2
tXPRcpI equ $v14
    vrcph   tXPRcpI[1], $v31[2] // 0
    ssv     tPosLmH[0],  0x0032(rdpCmdBufEndP1) // LmHX -> second short (temp mem)
    vrcp    tRcpDyF[2], tPosMmH[1]
    lsv     tPosCatI[6], 0x0032(rdpCmdBufEndP1) // LmHX -> pos cat e3
    vrcph   tRcpDyI[2], tPosMmH[1]
    ssv     tPosHmM[0],  0x0034(rdpCmdBufEndP1) // HmMX -> third short (temp mem)
    vrcp    tRcpDyF[3], tPosLmH[1]
tLAtI equ $v23
    lpv     tLAtI[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vrcph   tRcpDyI[3], tPosLmH[1]
    mfc2    $24, tXPI[1]
tPosCatF equ $v20
    vmudm   tPosCatF, tPosCatI, vTRC_1000
    sra     $10, v2c, 31
    vmadn   tPosCatI, $v31, $v31[2] // 0
    and     v2c, v2c, $10
    vmudl   $v29,    tRcpDyF, vTRC_0020
    sub     v1c, v1c, v2c
    vmadm   tRcpDyI, tRcpDyI, vTRC_0020
    sub     $11, v1c, v3c  // Four instr: v1c = max(v1c, v3c)
    vmadn   tRcpDyF, $v31, $v31[2] // 0
    sra     $10, $11, 31
    vmudl   $v29, tXPRcpF, tXPF
    and     $11, $11, $10
    vmadm   $v29, tXPRcpI, tXPF
    sub     v1c, v1c, $11
    vmadn   tXPF, tXPRcpF, tXPI
    sw      v1c, 0x0038(rdpCmdBufEndP1) // Store max of three verts' 1/W (upper) to temp mem
    vmadh   tXPI, tXPRcpI, tXPI
tMx1W equ tPosHmM
    llv     tMx1W[0], 0x0038(rdpCmdBufEndP1) // Load max of three verts' 1/W
    vmudm   $v29, tPosCatF, tRcpDyF
    ssv     tHPos[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
    vmadl   $v29, tPosCatI, tRcpDyF
tNewCatF equ tRcpDyF
    vmadn   tNewCatF, tPosCatI, tRcpDyI
    vmadh   tPosCatI, tPosCatF, tRcpDyI
    vrcph   $v29[0], tMx1W[0] // Reciprocal of max 1/W = min W
tMnWF equ tXYITmp2
    vrcpl   tMnWF[0], tMx1W[1] // TODO tMnWF and tMnWI can be same reg
tMnWI equ tMx1W
    vrcph   tMnWI[0], $v31[2]     // 0
t1WF equ tPosMmH
    vmudh   t1WF, vOne, t1WI[1q] // TODO Move frac parts from elem 1,5,7 to 0,4,6
    vmudn   $v29, tLAtI, tASO[4] // asoScale
    vmadh   tLAtI, vOne, tASO // Color and alpha offsets elems 0-3
tSTWHMI equ tPosCatF // H = elems 0-2, M = elems 4-6; init W = 7FFF
    vmudm   $v29, t1WI, tMnWF[0] // 1/W each vtx * min W = 1 for one of the verts, < 1 for others
    lsv     tSTWHMI[4], 0x0036(rdpCmdBufEndP1) // 0x7FFF; elem 2 = W
    vmadl   $v29, t1WF, tMnWF[0]
    lsv     tSTWHMI[12], 0x0036(rdpCmdBufEndP1) // 0x7FFF; elem 6 = W
    vmadn   t1WF, t1WF, tMnWI[0]
    llv     tSTWHMI[0], VTX_TC_VEC($1)
    vmadh   t1WI, t1WI, tMnWI[0]
    llv     tSTWHMI[8], VTX_TC_VEC($2)
    vmudh   $v29, vOne, $v31[4] // 4
    lhu     v3c, 0x0006(rdpCmdBufPtr) // YH
tSTWLI equ tMnWF // L = elems 4-6; init W = 7FFF
    vmadn   tXPF, tXPF, $v31[0] // -4
    lsv     tSTWLI[12], 0x0036(rdpCmdBufEndP1) // 0x7FFF; elem 6 = W
    vmadh   tXPI, tXPI, $v31[0] // -4
    llv     tSTWLI[8],  VTX_TC_VEC($3)
    vmudm   $v29,    tSTWHMI, t1WF[0h] // (S, T, 7FFF) * (1 or <1) for H and M
    andi    v3c, v3c, 3
    vmadh   tSTWHMI, tSTWHMI, t1WI[0h]
    sll     v3c, v3c, 14
tSTWHMF equ tMnWI
    vmadn   tSTWHMF, $v31, $v31[2]  // 0
    sub     v3c, $zero, v3c
    vmudm   $v29,   tSTWLI, t1WF[6]  // (S, T, 7FFF) * (1 or <1) for L
    ssv     tMPos[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadh   tSTWLI, tSTWLI, t1WI[6]
    ssv     tLPos[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
tSTWLF equ t1WI
    vmadn   tSTWLF, $v31, $v31[2]  // 0
    ldv     tPosLmH[8], 0x0030(rdpCmdBufEndP1) // MmHY -> e4, LmHX -> e5, HmMX -> e6
    vmudl   $v29, tXPF, tXPRcpF
    sw      v3c, 0x003C(rdpCmdBufEndP1)
    vmadm   $v29, tXPI, tXPRcpF
tSubPxH equ tLPos
    llv     tSubPxH[0], 0x003C(rdpCmdBufEndP1) // int elem 0, frac elem 1
    vmadn   tXPRcpF, tXPF, tXPRcpI
    sqv     tSTWHMF, 0x0050(rdpCmdBufEndP1) // Move S, T, W Hi and Mid Frac to temp mem
    vmadh   tXPRcpI, tXPI, tXPRcpI
    ldv     tHAtF[8], 0x0050(rdpCmdBufEndP1) // Move S, T, W Hi Frac from temp mem
tAndCatF equ tRcpDyI
    vand    tAndCatF, tNewCatF, tASO[5] // 0xFFF8
    sqv     tSTWHMI, 0x0060(rdpCmdBufEndP1) // Move S, T, W Hi and Mid Int to temp mem
    vcr     tPosCatI, tPosCatI, vTRC_0100
    ldv     tHAtI[8], 0x0060(rdpCmdBufEndP1) // Move S, T, W Hi Int from temp mem
    vmudh   tPosLmH, tPosLmH, $v31[0h] // e1 LmHY * -4 = 4*HmLY; e456 MmHY,LmHX,HmMX *= 4
    sdv     tSTWLF[8], 0x0040(rdpCmdBufEndP1) // Move S, T, W Lo Int to temp mem
    vmudn   $v29, tXHMI, tHPos[0]
    ldv     tLAtF[8], 0x0040(rdpCmdBufEndP1) // Move S, T, W Lo Frac from temp mem
    vmadl   $v29, tAndCatF, tSubPxH[1]
    sdv     tSTWLI[8], 0x0048(rdpCmdBufEndP1) // Move S, T, W Lo Int to temp mem
    vmadm   $v29, tPosCatI, tSubPxH[1]
    ldv     tLAtI[8], 0x0048(rdpCmdBufEndP1) // Move S, T, W Lo Int from temp mem
tXHMF equ tMPos
    vmadn   tXHMF, tAndCatF, tSubPxH[0]
    ldv     tMAtF[8], 0x0058(rdpCmdBufEndP1) // Move S, T, W Mid Frac from temp mem
    vmadh   tXHMI, tPosCatI, tSubPxH[0]
    ldv     tMAtI[8], 0x0068(rdpCmdBufEndP1) // Move S, T, W Mid Int from temp mem
tAtLmHF equ tLAtF
tAtLmHI equ tLAtI
tAtMmHF equ tMAtF
tAtMmHI equ tMAtI
    vsubc   tAtLmHF, tLAtF, tHAtF
    lh      $10, VTX_SCR_X($2)                 // Load X of Mid
    vsub    tAtLmHI, tLAtI, tHAtI
    addi    perfCounterA, perfCounterA, 1 // Increment number of tris sent to RDP
    vsubc   tAtMmHF, tMAtF, tHAtF
    andi    $24, $24, 0x0080 // Extract the left major flag from v2c; assume level and tile are 0
    vsub    tAtMmHI, tMAtI, tHAtI
    sb      $24, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
// DaDx = AtLmH * YMmH - AtMmH * YLmH
tDaDxF equ tSTWLF
tDaDxI equ tSTWLI
    vmudn   $v29, tAtLmHF, tPosLmH[4] // MmHY * 4
    sll     $10, $10, 14
    vmadh   $v29, tAtLmHI, tPosLmH[4] // MmHY * 4
    sw      $10, 0x0008(rdpCmdBufPtr)          // Store X of Mid as XL edge coefficient (yes)
    vmadn   $v29, tAtMmHF, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     tXHMI[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
    vmadh   $v29, tAtMmHI, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     tXHMF[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vreadacc tDaDxF, ACC_MIDDLE
    ssv     tXHMI[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vreadacc tDaDxI, ACC_UPPER
    ssv     tXHMF[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
// DaDy = AtMmH * XLmH - AtLmH * XMmH
tDaDyF equ tAtLmHF
tDaDyI equ tAtLmHI
    vmudn   $v29, tAtMmHF, tPosLmH[5] // LmHX * 4
    ssv     tPosCatI[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vmadh   $v29, tAtMmHI, tPosLmH[5] // LmHX * 4
    ssv     tNewCatF[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vmadn   $v29, tAtLmHF, tPosLmH[6] // HmMX * 4
    ssv     tPosCatI[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
    vmadh   $v29, tAtLmHI, tPosLmH[6] // HmMX * 4
    ssv     tNewCatF[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vreadacc tDaDyF, ACC_MIDDLE
    ssv     tPosCatI[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vreadacc tDaDyI, ACC_UPPER
    ssv     tNewCatF[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
// DaDx, DaDy /= tri area
    vmudl   $v29, tDaDxF, tXPRcpF[1]
    addi    $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
    vmadm   $v29, tDaDxI, tXPRcpF[1]
    andi    $11, geomMode, G_SHADE
    vmadn   tDaDxF, tDaDxF, tXPRcpI[1]
    sll     $11, $11, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vmadh   tDaDxI, tDaDxI, tXPRcpI[1]
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vmudl   $v29, tDaDyF, tXPRcpF[1]
    andi    $11, geomMode, G_TEXTURE_ENABLE
    vmadm   $v29, tDaDyI, tXPRcpF[1]
    sll     $11, $11, 5             // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
    vmadn   tDaDyF, tDaDyF, tXPRcpI[1]
    add     rdpCmdBufPtr, $1, $11   // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadh   tDaDyI, tDaDyI, tXPRcpI[1]
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Check if we need to write out to RDP
// DaDe = DaDx * DxHDy
tDaDeF equ tNewCatF
tDaDeI equ tPosCatI
    vmadl   $v29, tDaDxF, tNewCatF[3]
    sdv     tDaDxF[0], 0x0018($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadm   $v29, tDaDxI, tNewCatF[3]
    sdv     tDaDxI[0], 0x0008($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
    vmadn   tDaDeF, tDaDxF, tPosCatI[3]
    sdv     tDaDxF[8], 0x0018($1)   // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadh   tDaDeI, tDaDxI, tPosCatI[3]
    sdv     tDaDxI[8], 0x0008($1)   // Store DsDx, DtDx, DwDx texture coefficients (integer)
// Base attribute = high attribute - DaDe * subpixel
    vmudn   $v29, tHAtF, vOne[0]
    sdv     tDaDyF[0], 0x0038($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   $v29, tHAtI, vOne[0]
    sdv     tDaDyI[0], 0x0028($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
    vmadl   $v29, tDaDeF, tSubPxH[1]
    sdv     tDaDyF[8], 0x0038($1)   // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadm   $v29, tDaDeI, tSubPxH[1]
    sdv     tDaDyI[8], 0x0028($1)   // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadn   tHAtF, tDaDeF, tSubPxH[0]
    sdv     tDaDeF[0], 0x0030($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadh   tHAtI, tDaDeI, tSubPxH[0]
    sdv     tDaDeI[0], 0x0020($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    sdv     tDaDeF[8], 0x0030($1)   // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    sdv     tDaDeI[8], 0x0020($1)   // Store DsDe, DtDe, DwDe texture coefficients (integer)
    sdv     tHAtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    sdv     tHAtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    sdv     tHAtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    bltz    dmemAddr, tri_end     // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
     sdv    tHAtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)


     // 146 cycles
flush_rdp_buffer: // Prereq: dmemAddr = rdpCmdBufPtr - rdpCmdBufEndP1, or dmemAddr = large neg num -> only wait and set DPC_END
    mfc0    $11, SP_DMA_BUSY                 // Check if any DMA is in flight
    lw      cmd_w1_dram, rdpFifoPos          // FIFO pointer = end of RDP read, start of RSP write
    lw      $10, rdpFifoEnd                  // Load FIFO end addr
    bnez    $11, flush_rdp_buffer            // Wait until no DMAs are active
     addi   dmaLen, dmemAddr, RDP_TRI_SIZE_NO_ZBUF + 8  // dmaLen = size of DMEM buffer to copy
    blez    dmaLen, old_return_routine       // Exit if nothing to copy, or if dmemAddr is large negative num from last flush DMA write
     mtc0   cmd_w1_dram, DPC_END             // Set RDP to execute until FIFO end (buf pushed last time)
    add     $11, cmd_w1_dram, dmaLen         // $11 = future FIFO pointer if we append this new buffer
    sub     $10, $10, $11                    // $10 = FIFO end addr - future pointer
    bgez    $10, @@has_room                  // Branch if we can fit this
@@await_rdp_dblbuf_avail:
     mfc0   $11, DPC_STATUS                  // Read RDP status
    andi    $11, $11, DPC_STATUS_START_VALID // Start valid = second start addr in dbl buf
    bnez    $11, @@await_rdp_dblbuf_avail    // Wait until double buffered start/end available
     addi   perfCounterC, perfCounterC, 7    // 4 instr + 2 after mfc + 1 taken branch
    lw      cmd_w1_dram, rdpFifoStart        // Start of FIFO
@@await_past_first_instr:
    mfc0    $11, DPC_CURRENT                 // Load RDP current pointer
    beq     $11, cmd_w1_dram, @@await_past_first_instr // Wait until RDP moved past start
     addi   perfCounterC, perfCounterC, 6    // 3 instr + 2 after mfc + 1 taken branch
    // Start was previously the start of the FIFO, unless this is the first buffer,
    // in which case it was the end of the FIFO. Normally, when the RDP gets to end, if we
    // have a new end value waiting (END_VALID), it'll load end but leave current. By
    // setting start here, it will also load current with start.
    mtc0    cmd_w1_dram, DPC_START           // Set RDP start to start of FIFO
@@keep_waiting:
    // This is here so we only count it when stalling below or on FIFO end codepath
    addi    perfCounterC, perfCounterC, 10   // 7 instr + 2 after mfc + 1 taken branch
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
    addi    dmemAddr, rdpCmdBufEndP1, -(0x2000 | (RDP_TRI_SIZE_NO_ZBUF + 8)) // The 0x2000 is meaningless, negative means write
    xori    rdpCmdBufEndP1, rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word ^ rdpCmdBuffer2EndPlus1Word // Swap between the two RDP command buffers
    j       dma_read_write
     addi   rdpCmdBufPtr, rdpCmdBufEndP1, -(RDP_TRI_SIZE_NO_ZBUF + 8)


vtx_after_dma:
    andi    inVtx, dmemAddr, 0xFFF8            // Round down input start addr to DMA word
    mfc2    mtx1Addr, $v2[10]                  // Elem 5
    mfc2    mtx2Addr, $v2[4]                   // Elem 2
    sll     $11, vtxLeft, 12                   // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
    mfc2    outVtxBase, $v9[6]                 // Address of output start
    addi    outVtx1, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
    addi    outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
    addi    outVtxBase, outVtxBase, -vtxSize // Will inc by 2, but need point to 2nd
    ldv     vMTX0I[0],  (0x00 - mtxSize)(mtx1Addr) // MVP matrix 1
    ldv     vMTX1I[0],  (0x08 - mtxSize)(mtx1Addr)
    ldv     vMTX2I[0],  (0x10 - mtxSize)(mtx1Addr)
    ldv     vMTX3I[0],  (0x18 - mtxSize)(mtx1Addr)
    ldv     vMTX0F[0],  (0x20 - mtxSize)(mtx1Addr)
    ldv     vMTX1F[0],  (0x28 - mtxSize)(mtx1Addr)
    ldv     vMTX2F[0],  (0x30 - mtxSize)(mtx1Addr)
    ldv     vMTX3F[0],  (0x38 - mtxSize)(mtx1Addr)
    lpv     ldM1[0],    (0x40 - mtxSize)(mtx1Addr) // Light dir 0 from matrix 1
    ldv     vMTX0I[8],  (0x00 - mtxSize)(mtx2Addr) // MVP matrix 2
    ldv     vMTX1I[8],  (0x08 - mtxSize)(mtx2Addr)
    ldv     vMTX2I[8],  (0x10 - mtxSize)(mtx2Addr)
    ldv     vMTX3I[8],  (0x18 - mtxSize)(mtx2Addr)
    ldv     vMTX0F[8],  (0x20 - mtxSize)(mtx2Addr)
    ldv     vMTX1F[8],  (0x28 - mtxSize)(mtx2Addr)
    ldv     vMTX2F[8],  (0x30 - mtxSize)(mtx2Addr)
    ldv     vMTX3F[8],  (0x38 - mtxSize)(mtx2Addr)
    lpv     ldM2[0],    (0x40 - mtxSize)(mtx2Addr) // Light dir 0 from matrix 2
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    ldv     sVPS[8], (viewport)($zero)
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
    ldv     sVPO[8], (viewport + 8)($zero)
    jal     while_wait_dma_busy  // Wait for vertex load to finish
     lsv    ldM1[6], (perspNorm - altBase)(altBaseReg) // Perspective norm elem 3
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // 1st vec pos
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // 2nd vec pos
align_with_warning 8, "One instruction of padding before vertex loop"
vtx_loop:
    vxor    vM1Wt, vpMdl, $v31[1] // 0xFFFF
// sTCL <- sRTF
    ldv     sTCL[0],   (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    ldv     sTCL[8],   (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
// sTC2 <- sRTI
    lqv     sTC2,      (tempOldTC)(rdpCmdBufEndP1) // TC of WRITE vtx 1, 2
    vmadn   vpClpF, vpClpF, s1WI[3h]
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmudn   $v29,  vMTX3F, vOne
    ssv     s1WF[14],   (VTX_INV_W_FRAC)(outVtx2)
    vmadh   $v29,  vMTX3I, vOne
    ssv     s1WF[6],    (VTX_INV_W_FRAC)(outVtx1)
    vmadn   $v29,  vMTX0F, vpMdl[0]
    ssv     s1WI[14],   (VTX_INV_W_INT )(outVtx2)
    vmadh   $v29,  vMTX0I, vpMdl[0]
    ssv     s1WI[6],    (VTX_INV_W_INT )(outVtx1)
    vmadn   $v29,  vMTX1F, vpMdl[1]
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for vtx 2, clobbers ST
    vmadh   $v29,  vMTX1I, vpMdl[1]
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for vtx 1, clobbers ST
// clp1F <- sSCF
    vmadn   clp1F, vMTX2F, vpMdl[2]
    slv     sTC2[8],    (VTX_TC_VEC    )(outVtx2) // Store WRITE S, T vertex 2
// clp1I <- sSCI
    vmadh   clp1I, vMTX2I, vpMdl[2]
    slv     sTC2[0],    (VTX_TC_VEC    )(outVtx1) // Store WRITE S, T vertex 1
    vmudn   $v29,  vMTX3F, vOne
    slv     sTCL[12],   (tempVpRGBA + 4)(rdpCmdBufEndP1) // READ vtx 2 RGBA
    vmadh   $v29,  vMTX3I, vOne
    slv     sTCL[4],    (tempVpRGBA + 0)(rdpCmdBufEndP1) // READ vtx 1 RGBA
    vmadn   $v29,  vMTX0F, vpMdl[4]
    sdv     clp1F[8], (tempVXchg + 0x00)(rdpCmdBufEndP1)
    vmadh   $v29,  vMTX0I, vpMdl[4]
    sdv     clp1I[8], (tempVXchg + 0x08)(rdpCmdBufEndP1)
    vmadn   $v29,  vMTX1F, vpMdl[5]
    sqv     sTCL[0],    (tempOldTC)(rdpCmdBufEndP1) // TC of READ vtx 1, 2
    vmadh   $v29,  vMTX1I, vpMdl[5]
// vpNrmlX <- s1WF
    lpv     vpNrmlX[3], (tempVpRGBA)(rdpCmdBufEndP1) // X to elem 3, 7
// clp2F <- sTCL
    vmadn   clp2F, vMTX2F, vpMdl[6]
// vpNrmlY <- s1WI
    lpv     vpNrmlY[2], (tempVpRGBA)(rdpCmdBufEndP1) // Y to elem 3, 7
// clp2I <- sTC2
    vmadh   clp2I, vMTX2I, vpMdl[6]
// vpNrmlZ <- vpRGBA
    lpv     vpNrmlZ[1], (tempVpRGBA)(rdpCmdBufEndP1) // Z to elem 3, 7
    vmudl   $v29,   vpClpF, ldM1[3] // Persp norm
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmadm   vpClpI, vpClpI, ldM1[3] // Persp norm
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    sdv     clp2F[0], (tempVXchg + 0x10)(rdpCmdBufEndP1)
    vmudm   $v29, ldM1, vM1Wt[3h]
    sdv     clp2I[0], (tempVXchg + 0x18)(rdpCmdBufEndP1)
    vmadm   lDIR, ldM2, vpMdl[3h] // lDIR elem 0, 1, 2; 4, 5, 6
    ldv     clp1F[8], (tempVXchg + 0x10)(rdpCmdBufEndP1)
    vmudh   $v29, sVPO, vOne       // offset * 1
    ldv     clp1I[8], (tempVXchg + 0x18)(rdpCmdBufEndP1)
    vmadn   $v29,   vpClpF, sVPS   // + pos frac * scale
    ldv     clp2F[0], (tempVXchg + 0x00)(rdpCmdBufEndP1)
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI is now screen space pos
    ldv     clp2I[0], (tempVXchg + 0x08)(rdpCmdBufEndP1)
    vmudl   $v29,   clp1F, vM1Wt[3h]
    or      flagsV2, flagsV2, $11    // Combine results for second vertex
    vmadm   $v29,   clp1I, vM1Wt[3h]
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadl   $v29,   clp2F, vpMdl[3h]
    or      flagsV1, flagsV1, $10    // Combine results for first vertex
    vmadm   vpClpI, clp2I, vpMdl[3h]
    sdv     vpScrI[8], (VTX_SCR_VEC   )(outVtx2) // XYZ and clobbers flags
    vmadn   vpClpF, $v31, $v31[2] // 0
    sdv     vpScrI[0], (VTX_SCR_VEC   )(outVtx1) // XYZ and clobbers flags
    vmulf   $v29,   vpNrmlX, lDIR[0h]
    sh      flagsV2,   (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
    vmacf   $v29,   vpNrmlY, lDIR[1h]
    sh      flagsV1,   (VTX_CLIP      )(outVtx1) // Store first vertex flags
// vpRGBA <- vpNrmlZ
    vmacf   vpRGBA, vpNrmlZ, lDIR[2h]
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
    vmudl   $v29, vpClpF, ldM1[3]       // Persp norm
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
// s1WI <- vpNrmlY
    vmadm   s1WI, vpClpI, ldM1[3]       // Persp norm
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
// s1WF <- vpNrmlX
    vmadn   s1WF, $v31, $v31[2]         // 0
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
// sSCF <- clp1F
    vmudn   sSCF, vpClpF, $v31[3]        // W * clip ratio for scaled clipping
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
// sSCI <- clp1I
    vmadh   sSCI, vpClpI, $v31[3]        // W * clip ratio for scaled clipping
    vrcph   $v29[0], s1WI[3]
// sRTF <- clp2F
    vrcpl   sRTF[2], s1WF[3]
// sRTI <- clp2I
    vrcph   sRTI[3], s1WI[7]
    vrcpl   sRTF[6], s1WF[7]
    vrcph   sRTI[7], $v31[2] // 0
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadm   $v29, s1WI, sRTF[2h]
    vmadn   s1WF, s1WF, sRTI[3h]
    vmadh   s1WI, s1WI, sRTI[3h]
    vge     vpRGBA, vOne, vpRGBA[3h]
    vmudh   $v29, vOne, $v31[4]  // 4
    vmadn   s1WF, s1WF, $v31[0]  // -4
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vmadh   s1WI, s1WI, $v31[0]  // -4
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    $11, $vcc                   // Scaled clip results
    vmadm   $v29, s1WI, sRTF[2h]
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadn   s1WF, s1WF, sRTI[3h]
    bgtz    vtxLeft, vtx_loop
     vmadh  s1WI, s1WI, sRTI[3h]
     // vnop in branch delay slot
vtx_epilogue:
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    lqv     sTC2,      (tempOldTC)(rdpCmdBufEndP1) // TC of WRITE vtx 1, 2
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
    vmadn   vpClpF, vpClpF, s1WI[3h]
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    ssv     s1WF[14],   (VTX_INV_W_FRAC)(outVtx2)
    vnop
    ssv     s1WF[6],    (VTX_INV_W_FRAC)(outVtx1)
    vnop
    ssv     s1WI[14],   (VTX_INV_W_INT )(outVtx2)
    vmudl   $v29,   vpClpF, ldM1[3] // Persp norm
    ssv     s1WI[6],    (VTX_INV_W_INT )(outVtx1)
    vmadm   vpClpI, vpClpI, ldM1[3] // Persp norm
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for vtx 2, clobbers ST
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for vtx 1, clobbers ST
    vmudh   $v29, sVPO, vOne       // offset * 1
    slv     sTC2[8],    (VTX_TC_VEC    )(outVtx2) // Store WRITE S, T vertex 2
    vmadn   $v29,   vpClpF, sVPS   // + pos frac * scale
    slv     sTC2[0],    (VTX_TC_VEC    )(outVtx1) // Store WRITE S, T vertex 1
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI is now screen space pos
    or      flagsV2, flagsV2, $11    // Combine results for second vertex
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    or      flagsV1, flagsV1, $10    // Combine results for first vertex
    sdv     vpScrI[8], (VTX_SCR_VEC   )(outVtx2) // XYZ and clobbers flags
    sdv     vpScrI[0], (VTX_SCR_VEC   )(outVtx1) // XYZ and clobbers flags
    sh      flagsV2,   (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
    sh      flagsV1,   (VTX_CLIP      )(outVtx1) // Store first vertex flags
    j       run_next_DL_command
     lqv    vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix
    
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
@@while_dma_busy:
    bnez    $11, @@while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   $11, SP_DMA_BUSY      // Update DMA_BUSY value
old_return_routine:
    jr      $ra
     // Has mfc0 in branch delay slot, causes a stall if first instr after ret is load

dma_read_write:
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

ovl0_start:
    jal     flush_rdp_buffer   // See G_FLUSH_handler for docs on these 3 instructions.
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    jal     flush_rdp_buffer
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
    sw      perfCounterA, cpuInterface + 0x0
    sw      perfCounterB, cpuInterface + 0x4
    sw      perfCounterC, cpuInterface + 0x8
    sw      perfCounterD, cpuInterface + 0xC
    li      $10, SP_SET_SIG2   // task done signal
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

G_ENDDL_handler:
    lbu     $7, displayListStackDepth       // Load the DL stack index; if end stack,
    beqz    $7, load_overlay_0_and_enter    // load overlay 0; $7 == -4 signals end
     addi   $7, $7, -4                      // Decrement the DL stack index
    j       call_ret_common                 // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($7) // Load addr of DL to return to

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
    lhu     $10, (movewordTable - ((G_MOVEWORD & 0xF) << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
    sll     $11, cmd_w0, 16          // Sign bit = upper bit of offset
    add     $10, $10, cmd_w0         // Offset + base; only lower 12 bits matter
    sh      cmd_w1_dram, ($10)       // Store value from cmd into halfword
    bltz    $11, run_next_DL_command // If upper bit of offset is set, exit after halfword
     lh     geomMode, geometryModeLabel // Might have modified this
    j       run_next_DL_command
     sw     cmd_w1_dram, ($10)       // Store value from cmd into word (offset + moveword_table[index])

G_TEXRECT_handler: // 3; should be towards the start of ovl1
    j       run_next_DL_command
     spv    $v4[0], (texrectState)($zero)

G_RDPHALF_1_handler:
    j       run_next_DL_command
     sw     cmd_w1_dram, rdpHalf1Val

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

.close // CODE_FILE
