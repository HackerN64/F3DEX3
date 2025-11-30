//
// Profiling configurations. To make space for the profiling features, if any of
// the profiling configurations are enabled, G_LIGHTTORDP and !G_SHADING_SMOOTH
// are removed, i.e. G_LIGHTTORDP behaves as a no-op and all tris are smooth
// shaded.
//

// Profiling Configuration A
// perfCounterA:
//     cycles RSP spent processing vertex commands (incl. vertex DMAs)
// perfCounterB:
//     upper 16 bits: fetched DL command count
//     lower 16 bits: DL command count
// perfCounterC:
//     cycles RSP was stalled because RDP FIFO was full
// perfCounterD:
//     cycles RSP spent processing triangle commands, not including FIFO stalls
.if CFG_PROFILING_A
.if CFG_PROFILING_B || CFG_PROFILING_C
.error "At most one CFG_PROFILING_ option can be enabled at a time"
.endif
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 0
COUNTER_C_FIFO_FULL equ 1

// Profiling Configuration B
// perfCounterA:
//     upper 16 bits: vertex count
//     lower 16 bits: lit vertex count
// perfCounterB:
//     upper 18 bits: tris culled by occlusion plane count
//     lower 14 bits: clipped (input) tris count
// perfCounterC:
//     upper 18 bits: overlay (all 0-4) load count
//     lower 14 bits: overlay 2 (lighting) load count
// perfCounterD:
//     upper 18 bits: overlay 3 (clipping) load count
//     lower 14 bits: overlay 4 (misc) load count
.elseif CFG_PROFILING_B
.if CFG_PROFILING_C
.error "At most one CFG_PROFILING_ option can be enabled at a time"
.endif
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 1
COUNTER_C_FIFO_FULL equ 0

// Profiling Configuration C
// perfCounterA:
//     cycles RSP believes it was running (this ucode only)
// perfCounterB:
//     upper 16 bits: samples GCLK was alive (sampled once per DL command count)
//     lower 16 bits: DL command count
// perfCounterC:
//     upper 18 bits: small RDP command count (all RDP cmds except tris)
//     lower 14 bits: matrix loads count
// perfCounterD:
//     cycles RSP was stalled waiting for miscellaneous DMAs to finish
.elseif CFG_PROFILING_C
ENABLE_PROFILING equ 1
COUNTER_A_UPPER_VERTEX_COUNT equ 0
COUNTER_C_FIFO_FULL equ 0

// Default (extra profiling disabled)
// perfCounterA:
//     upper 16 bits: vertex count
//     lower 16 bits: RDP/out tri count
// perfCounterB:
//     upper 18 bits: RSP/in tri count
//     lower 14 bits: tex rect count
// perfCounterC:
//     cycles RSP was stalled because RDP FIFO was full
// perfCounterD:
//     unused/zero
.else
ENABLE_PROFILING equ 0
COUNTER_A_UPPER_VERTEX_COUNT equ 1
COUNTER_C_FIFO_FULL equ 1

.endif

CFG_DEBUG_NORMALS equ 0 // Can manually enable here
