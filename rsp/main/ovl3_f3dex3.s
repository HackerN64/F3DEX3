ovl234_start:

ovl3_start:
// Clipping overlay.

// Jump here for basic lighting setup. If overlay 3 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_ltbasic_entrypoint_ovl3ver:         // same IMEM address as ovl234_ltbasic_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2

// Jump here for advanced lighting. If overlay 3 is loaded (this code), loads
// overlay 4 and jumps to right here, which is now in the new code.
ovl234_ltadv_entrypoint_ovl3ver:           // same IMEM address as ovl234_ltadv_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 1  // Count overlay 4 load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl4_start)  // set up a load for overlay 4

// Jump here for clipping and rare commands. If overlay 3 is loaded (this code), directly starts
// the clipping code.
ovl234_clipmisc_entrypoint:
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    bgez    $7, vtx_constants_for_clip     // $7 < 0: cmd byte. >= 0: vtx 2 clip flags with lhu.
     li     inVtx, -0x8000                 // inVtx < 0 means from clipping. Inc'd each vtx write by 2 * inputVtxSize, but this is large enough it should stay negative.
.if !(G_MEMSET & 0x80) || !(G_DMA_IO & 0x80)
    .error "Command handlers in ovl3 < 0 assumption broken"
.endif
    lw      cmd_w1_dram, (inputBufferEnd - 4)(inputBufferPos) // Overwritten by overlay load
    li      $3, -0x100 | G_DMA_IO
    beq     $3, $7, g_dma_io_ovl3
g_memset_ovl3: // otherwise
.include "rsp/handlers/memset.s"
    
g_dma_io_ovl3:
.include "rsp/handlers/dma_io.s"

.include "rsp/clipping/clipping.s"

ovl3_end:
.align 8
ovl3_padded_end:

.orga max(max(ovl2_padded_end - ovl2_start, ovl4_padded_end - ovl4_start) + orga(ovl3_start), orga())
ovl234_end:
