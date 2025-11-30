G_SETxIMG_handler: // 12
    lb      $3, materialCullMode            // Get current mode
    jal     segmented_to_physical           // Convert image to physical address
     lw     $2, lastMatDLPhyAddr            // Get last material physical addr
    bnez    $3, send_w0_w1_to_rdp           // If not in normal mode (0), exit
     add    $10, taskDataPtr, inputBufferPos // Current material physical addr
    beq     $10, $2, @@skip                 // Branch if we are executing the same mat again
     sw     $10, lastMatDLPhyAddr           // Store material physical addr
    li      $7, 1                           // > 0: in material first time
@@skip:                                     // Otherwise $7 was < 0 (SETxIMG command byte): cull mode (in mat second time)
    sb      $7, materialCullMode
send_w0_w1_to_rdp:
    sw      cmd_w0, 0(rdpCmdBufPtr)
send_w1_to_rdp:
    j       commit_small_rdp_command
     sw     cmd_w1_dram, 4(rdpCmdBufPtr)
