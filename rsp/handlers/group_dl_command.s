G_MEMSET_handler:
    j       ovl234_clipmisc_entrypoint       // Delay slot is harmless
.include "rsp/handlers/run_next_dl_command_pre.s"
.if !CFG_PROFILING_A
tris_end:
.endif
.if ENABLE_PROFILING
G_LIGHTTORDP_handler:
.endif
.include "rsp/handlers/run_next_dl_command.s"
