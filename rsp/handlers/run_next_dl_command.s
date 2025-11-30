G_SPNOOP_handler:
run_next_DL_command:
     lb     $7, (inputBufferEnd)(inputBufferPos)        // Command byte
    lpv     $v4[0], (inputBufferEndSgn)(inputBufferPos) // Whole command
    vclr    vZero
    beqz    inputBufferPos, displaylist_dma             // Check if buffer is empty
     lbu    $ra, (cmdMiniTable)($7)                     // Load mini table entry
    vmudh   $v3, $v31, vTRC_1000                        // $v3[3] = 2 * 1000 = 2000 for vtx addr manip
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // Word 0
    vmudl   $v5, $v4, vTRC_VS                           // Vtx indices times length
    lw      cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // Word 1
.if CFG_PROFILING_C
    mfc0    $10, DPC_STATUS
.endif
    vmadn   $v7, vOne, vTRC_VB                          // Plus address of vertex buffer
    sll     $ra, $ra, 2                                 // Convert to a number of instructions
.if CFG_PROFILING_C
    addi    perfCounterB, perfCounterB, 1               // Count commands
    andi    $10, $10, DPC_STATUS_GCLK_ALIVE             // Sample whether GCLK is active now
    sll     $10, $10, 16 - 3                            // move from bit 3 to bit 16
    add     perfCounterB, perfCounterB, $10             // Add to the perf counter
.elseif CFG_PROFILING_A
    mfc0    $10, DPC_CLOCK
    sw      perfCounterC, startFifoStallTime            // Save initial FIFO stall time
    addi    perfCounterB, perfCounterB, 1               // Count commands
    sw      $10, startCounterTime
.endif
    vmadl   $v6, $v31, $v31[2]                          // 0; copy in v6
    jr      $ra                                         // Jump to handler
     addi   inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
    // $7 must retain the command byte for load_mtx and command dispatch in overlays 2 and 3
    // $ra must contain the handler called for several handlers
