G_POPMTX_handler:
G_DMA_IO_handler:
    j       ovl234_ltbasic_entrypoint   // Delay slot is harmless
G_BRANCH_WZ_handler:
     mfc2   $10, $v7[6]                 // Vertex addr (index was byte 3)
.if CFG_G_BRANCH_W                      // G_BRANCH_W/G_BRANCH_Z difference; this defines F3DZEX vs. F3DEX2
    lh      $10, VTX_W_INT($10)         // read the w coordinate of the vertex (f3dzex)
.else
    lw      $10, VTX_SCR_Z($10)         // read the screen z coordinate (int and frac) of the vertex (f3dex2)
.endif
    sub     $2, $10, cmd_w1_dram        // subtract the w/z value being tested
    bgez    $2, run_next_DL_command     // if vtx.w/z >= cmd w/z, continue running this DL
     lw     cmd_w1_dram, rdpHalf1Val    // load the RDPHALF1 value as the location to branch to
    li      cmd_w0, -0x8000             // Bit 16 set (via negative) = nopush, bits 3-7 = 0 for hint
G_DL_handler:
    sll     $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
    lbu     $7, displayListStackLength      // Get the DL stack length
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
    bltz    $2, call_ret_common             // Nopush = branch = flag is set
     move   taskDataPtr, cmd_w1_dram        // Set the new DL to the target display list
    sw      $3, (displayListStack)($7)
    addi    $7, $7, 4                       // Increment the DL stack length
call_ret_common:
    sb      $zero, materialCullMode         // This covers call, branch, return, and cull and branchZ successes
    sb      $7, displayListStackLength
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
    mfc0    $7, SP_STATUS                              // load the status word into register $1
    sub     taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
.if CFG_PROFILING_A
    sll     $11, inputBufferPos, 16 - 3                // Divide by 8 for num cmds to load, then move to upper 16
    sub     perfCounterB, perfCounterB, $11            // Negative so subtract
.endif
    andi    $7, $7, SP_STATUS_SIG0                     // check if the task should yield
    beqz    $7, wait_goto_next_ra                      // if not, continue normal processing
     sh     nextRA, tempTriRA                          // Save address to come back to after yield
G_LOAD_UCODE_handler: // If jumped here, $7 = G_LOAD_UCODE
load_overlay_0_and_enter:
    li      nextRA, 0x1000                  // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)   // Sets up ovl0 table address
load_overlays_0_1:
    li      dmaLen, ovl01_end - 0x1000 - 1
    j       load_overlay_inner
     li     dmemAddr, 0x1000
