
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
    li      nextRA, displaylist_dma
    lw      $11, rdpFifoPos
    lw      $2, OSTask + OSTask_flags
    li      $1, SP_CLR_SIG2 | SP_CLR_SIG1   // Clear task done and yielded signals
    vsub    vOne, vOne, $v31[1]             // 1 = 0 - -1
    beqz    $11, initialize_rdp             // If RDP FIFO not set up yet, starting ucode from scratch
     mtc0   $1, SP_STATUS
    andi    $2, $2, OS_TASK_YIELDED         // Resumed from yield or came from called ucode?
    beqz    $2, continue_from_os_task       // If latter, load DL (task data) pointer from OSTask
     // Otherwise continuing from yield; perf counters saved here at yield
     lw     perfCounterA, yieldDataFooter + YDF_OFFSET_PERFCOUNTERA
    lw      perfCounterB, yieldDataFooter + YDF_OFFSET_PERFCOUNTERB
    lw      perfCounterC, yieldDataFooter + YDF_OFFSET_PERFCOUNTERC
    lw      perfCounterD, yieldDataFooter + YDF_OFFSET_PERFCOUNTERD
.if CFG_PROFILING_A
    mfc0    $10, DPC_CLOCK // Start tri profiling again in case we came from snake
    sw      perfCounterC, startFifoStallTime   // Save initial FIFO stall time
    sw      $10, startCounterTime
.endif
    lw      taskDataPtr, yieldDataFooter + YDF_OFFSET_TASKDATAPTR
    lh      origV1Addr, yieldOrigV1Addr
    j       finish_setup
     li     nextRA, displaylist_dma_from_yield

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
    lw      taskDataPtr, OSTask + OSTask_data_ptr
finish_setup:
.if CFG_PROFILING_C
    mfc0    $11, DPC_CLOCK
    sw      $11, startCounterTime
.endif
    sh      $zero, mvpValid  // and dirLightsXfrmValid
    lhu     vGeomMid, geometryModeLabel + 1
    li      flatV1Offset, 0
    li      inputBufferPos, 0
    j       load_overlays_0_1
     li     cmd_w1_dram, orga(ovl1_start)

start_end:
.align 8
start_padded_end:

.orga max(orga(), max(ovl0_padded_end - ovl0_start, ovl1_padded_end - ovl1_start) - 0x80)
ovl01_end:
