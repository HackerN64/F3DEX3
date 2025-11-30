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
     nop
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
