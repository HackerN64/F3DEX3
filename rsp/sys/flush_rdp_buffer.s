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
