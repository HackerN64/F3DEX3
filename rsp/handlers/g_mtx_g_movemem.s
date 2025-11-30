G_MTX_handler: // 12
.if CFG_PROFILING_C
    addi    perfCounterC, perfCounterC, 1  // Increment matrix count
.endif
    andi    $11, cmd_w0, G_MTX_VP_M | G_MTX_NOPUSH_PUSH
    beqz    $11, ovl234_ltbasic_entrypoint   // Model and push: go to overlay for push
     sh     $zero, mvpValid                  // Also zeroes dirLightsXfrmValid
load_mtx: // Coming from mtx_push
    andi    $7, cmd_w0, G_MTX_MUL_LOAD       // Matrix load type: 2 is multiply, 0 is load
    addi    $7, $7, (-0x100 | G_MOVEMEM)     // As if came from G_MOVEMEM_handler, or +2 for multiply
.include "rsp/handlers/g_movemem.s"
