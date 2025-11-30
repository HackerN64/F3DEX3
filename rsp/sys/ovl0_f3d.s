.headersize 0x00001000 - orga()

// Overlay 0 handles three cases of stopping the current microcode.
// The action here is controlled by $7:
// - If yielding, $7 == SP_STATUS_SIG0 == 0x0080
// - If this was G_LOAD_UCODE, $7 == G_LOAD_UCODE == 0xDD (as negative)
// - If we got to the end of the parent DL, $7 == -4.
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
    addi    $7, $7, 4 // Now 0 if end, > 0 if yield, < 0 if load ucode
    bgez    $7, task_done_or_yield  // Continue to load ucode if negative
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
    beqz    $7, task_done           // see above
     sw     perfCounterD, yieldDataFooter + YDF_OFFSET_PERFCOUNTERD
task_yield: // Otherwise CPU requested yield
    sh      origV1Addr, yieldOrigV1Addr
.if CFG_PROFILING_A
    lh      $2, tempTriRA
.endif
    lw      $3, OSTask + OSTask_ucode          // Save pointer to current ucode
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
.if CFG_PROFILING_A
    bgez    $2, @@not_snake                    // Snake next RA is negative
.endif
     li     dmemAddr, -0x8000                  // 0, but negative = write
.if CFG_PROFILING_A
    mfc0    $11, DPC_CLOCK                     // Finish tri perf counting
    lw      $10, startCounterTime
    lw      $2, startFifoStallTime
    sub     $11, $11, $10
    add     perfCounterD, perfCounterD, $11  // Add to tri cycles perf counter
    sub     $2, perfCounterC, $2             // RDP FIFO stall time elapsed during tri draw
    sub     perfCounterD, perfCounterD, $2   // Subtract final RDP FIFO stall time from tri time
    sw      perfCounterD, yieldDataFooter + YDF_OFFSET_PERFCOUNTERD // Was stored above, but have modified
@@not_snake:
.endif
    li      dmaLen, OS_YIELD_DATA_SIZE - 1
    li      $10, SP_SET_SIG1 | SP_SET_SIG2     // yielded and task done signals
    sw      taskDataPtr, yieldDataFooter + YDF_OFFSET_TASKDATAPTR // Save pointer to where in DL
    sw      $3, yieldDataFooter + YDF_OFFSET_UCODE
    j       dma_read_write
     li     $ra, set_status_and_break

task_done:
    // Copy just the yield data footer, which has the perf counters.
    lw      cmd_w1_dram, OSTask + OSTask_yield_data_ptr
    addi    cmd_w1_dram, cmd_w1_dram, yieldDataFooter
    li      dmemAddr, -0x8000 | yieldDataFooter // negative = write
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
