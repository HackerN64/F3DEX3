load_cmds_handler:
     lb     $3, materialCullMode
    bltz    $3, run_next_DL_command  // If cull mode is < 0, in mat second time, skip the load
G_RDP_handler:
     spv    $v4[0], 0(rdpCmdBufPtr)     // Whole command
commit_small_rdp_command:
.if CFG_PROFILING_C
    addi    perfCounterC, perfCounterC, 0x4000 // Increment small RDP command count
.endif
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8    // Increment the next RDP command pointer by 2 words
check_rdp_buffer_full_and_run_next_cmd:
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    bgezal  dmemAddr, flush_rdp_buffer
     // $7 on next instr survives flush_rdp_buffer
