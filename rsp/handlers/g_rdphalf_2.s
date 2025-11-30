G_RDPHALF_2_handler: // 8; should be after the handlers with alignment needs
    li      $11, texrectState
    ldv     $v29[0], (0)($11)
    sb      $zero, materialCullMode         // This covers tex and fill rects
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
.if !ENABLE_PROFILING
    addi    perfCounterB, perfCounterB, 1   // Increment number of tex/fill rects
.endif
    j       send_w0_w1_to_rdp               // w1 is from the current command
     sdv    $v29[0], -8(rdpCmdBufPtr)
