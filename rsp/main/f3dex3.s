.include "rsp/include/setup.inc"
.include "rsp/include/rsp_defs.inc"
.include "rsp/include/gbi_f3dex3.inc"

.include "rsp/include/cfg_f3dex3.inc"

.include "rsp/main/dmem_f3dex3.s"

.include "rsp/main/regs_f3dex3.s"

.include "rsp/main/temp_f3dex3.s"

.include "rsp/sys/start_f3d.s"

.include "rsp/handlers/group_displaylist_dma.s"

.include "rsp/handlers/g_geometrymode.s"

.include "rsp/handlers/g_rdphalf_2.s"

.include "rsp/handlers/g_setximg.s"

.include "rsp/handlers/group_dl_command.s"

.include "rsp/handlers/g_mtx_g_movemem.s"

.if !ENABLE_PROFILING
.include "rsp/handlers/g_lighttordp.s"
.endif

.include "rsp/tri/snake_main.s"

.include "rsp/tri/defs.inc"

.include "rsp/tri/decal_fix.s"

.include "rsp/tri/main.s"

.include "rsp/lighting/vtx_select_lighting.s"

.include "rsp/main/ovl3_f3dex3.s"

.include "rsp/tri/alpha_cull_end.s"

.include "rsp/vtx/after_dma.s"

.if CFG_NO_OCCLUSION_PLANE
.include "rsp/vtx/loop_noc.s"
.else // not CFG_NO_OCCLUSION_PLANE
.include "rsp/vtx/loop_occ.s"
.endif

.include "rsp/vtx/epilogue_main.s"

.include "rsp/tri/snake_end.s"

.if !ENABLE_PROFILING
.include "rsp/tri/flat_shading.s"
.endif

.include "rsp/sys/end_f3d.s"

.include "rsp/sys/ovl0_f3d.s"

.include "rsp/main/ovl1_f3dex3.s"

.include "rsp/main/ovl2_f3dex3.s"

.include "rsp/main/ovl4_f3dex3.s"

.close // CODE_FILE
