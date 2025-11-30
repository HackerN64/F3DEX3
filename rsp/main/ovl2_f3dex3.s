.headersize ovl234_start - orga()

.include "rsp/lighting/ltbasic_regs.inc"

ovl2_start:
// Basic lighting overlay.

// Jump here for basic lighting setup. If overlay 2 is loaded (this code), jumps into the
// rest of the lighting code below.
ovl234_ltbasic_entrypoint:
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       ltbasic_continue_setup
     lbu    ambLight, numLightsxSize

// Jump here for advanced lighting. If overlay 2 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ltadv_entrypoint_ovl2ver:           // same IMEM address as ovl234_ltadv_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here for clipping and rare commands. If overlay 2 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipmisc_entrypoint_ovl2ver:        // same IMEM address as ovl234_clipmisc_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

ltbasic_continue_setup:
    bltz    $7, ovl2_command_handlers      // $7 < 0: cmd byte. >= 0: mtx valid (0 or 0x18)
     addi   ambLight, ambLight, altBase    // Point to ambient light; stored through vtx proc
.include "rsp/lighting/ltbasic.s"

ovl2_command_handlers:
.if !(G_POPMTX & 0x80) || !(G_MTX & 0x80)
    .error "Command handlers in ovl2 < 0 assumption broken"
.endif
    lw      cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Overwritten by overlay load
    li      $3, -0x100 | G_MTX
    beq     $3, $7, g_mtx_push_ovl2
g_popmtx_ovl2:  // otherwise
     lw     $11, matrixStackPtr             // Current matrix stack pointer
    lw      $2, OSTask + OSTask_dram_stack  // Top of the stack
    sub     cmd_w1_dram, $11, cmd_w1_dram   // Decrease pointer by amount in command
    sub     $3, cmd_w1_dram, $2             // Is it still valid / within the stack?
    bgez    $3, @@skip                      // If so, skip the failsafe
     sh     $zero, mvpValid                 // and dirLightsXfrmValid; mark both mtx and dir lts invalid
    move    cmd_w1_dram, $2                 // Use the top of the stack as the new pointer
@@skip:    
    sw      cmd_w1_dram, matrixStackPtr     // Update the matrix stack pointer
    j       do_movemem
     li     $7, (-0x100 | G_MOVEMEM)        // As if came from G_MOVEMEM_handler, don't multiply

g_mtx_push_ovl2:
    lw      cmd_w1_dram, matrixStackPtr     // Set up the DMA from dmem to rdram at the matrix stack pointer
    li      dmemAddr, -0x8000 | mMatrix     // mMatrix, negative = write
    jal     dma_read_write                  // DMA the current matrix from dmem to rdram
     li     dmaLen, 0x0040 - 1              // Set the DMA length to the size of a matrix (minus 1 because DMA is inclusive)
    addi    cmd_w1_dram, cmd_w1_dram, 0x40  // Increase the matrix stack pointer by the size of one matrix
    sw      cmd_w1_dram, matrixStackPtr     // Update the matrix stack pointer
    j       load_mtx
     lw     cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Load command word 1 again

ovl2_end:
.align 8
ovl2_padded_end:
