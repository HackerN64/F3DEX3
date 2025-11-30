    bltz    inVtx, clip_after_vtx_store  // inVtx < 0 means from clipping
     sh     flagsV1, (VTX_CLIP)(outVtx1) // Store first vertex flags
.if CFG_PROFILING_A
    li      $ra, 0                           // Flag for coming from vtx
    lqv     vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix
tris_end:
    mfc0    $11, DPC_CLOCK
    lw      $10, startCounterTime
    sub     $11, $11, $10
    beqz    $ra, run_next_DL_command         // $ra != 0 if from tri cmds
     add    perfCounterA, perfCounterA, $11  // Add to vert cycles perf counter
    lw      $2, startFifoStallTime           // From tris
    sub     perfCounterA, perfCounterA, $11  // Undo add to vert perf counter
    add     perfCounterD, perfCounterD, $11  // Add to tri cycles perf counter
    sub     $2, perfCounterC, $2             // RDP FIFO stall time elapsed during tri draw
    j       run_next_DL_command
     sub    perfCounterD, perfCounterD, $2   // Subtract final RDP FIFO stall time from tri time
.else
    j       run_next_DL_command
     lqv    vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix
.endif
