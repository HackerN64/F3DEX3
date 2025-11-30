.headersize ovl234_start - orga()

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

#include "rsp/ltbasic.s"
