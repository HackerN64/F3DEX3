.headersize ovl234_start - orga()

ovl4_start:
// Advanced lighting overlay.

// Jump here for basic lighting setup. If overlay 4 is loaded (this code), loads overlay 2
// and jumps to right here, which is now in the new code.
ovl234_ltbasic_entrypoint_ovl4ver:         // same IMEM address as ovl234_ltbasic_entrypoint
.if CFG_PROFILING_B
    addi    perfCounterC, perfCounterC, 1  // Count lighting overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl2_start)  // set up a load for overlay 2
     
// Jump here for advanced lighting. If overlay 4 is loaded (this code), starts
// advanced lighting.
ovl234_ltadv_entrypoint:
.if CFG_PROFILING_B
    nop                                    // Needs to take up the space for the other perf counter
.endif
    j       vtx_load_mtx
     li     $11, mMatrix

// Jump here for clipping and rare commands. If overlay 4 is loaded (this code), loads overlay 3
// and jumps to right here, which is now in the new code.
ovl234_clipmisc_entrypoint_ovl4ver:        // same IMEM address as ovl234_clipmisc_entrypoint
    sh      $ra, tempTriRA                 // Tri return after clipping
.if CFG_PROFILING_B
    addi    perfCounterD, perfCounterD, 0x4000  // Count clipping overlay load
.endif
    jal     load_overlays_2_3_4            // Not a call; returns to $ra-8 = here
     li     cmd_w1_dram, orga(ovl3_start)  // set up a load for overlay 3

#include "rsp/ltadv.s"
