.include "rsp/include/setup.inc"
.include "rsp/include/rsp_defs.inc"
.include "rsp/include/gbi_f3dex3.inc"

.include "rsp/include/cfg_f3dex3.inc"

.include "rsp/main/dmem_f3dex3.s"

/*
Scalar regs:
      Tri write   Clip walk    Clip VW      Vtx write   ltbasic    ltadv    V/L init  Cmd dispatch
$zero ---------------------------------- Hardwired zero ------------------------------------------
$1    v1 texptr    clipIdx    <------------- vtxLeft ------------------------------>  temp, init 0
$2    v2 shdptr   <---------- clipAlloc -------> <----- lbPostAo   laPtr                  temp
$3    v3 shdflg   clipTempVtx <------------- vLoopRet --------->  laVtxLeft               temp
$4    <--------------- origV1Addr -------------> <----- lbFakeAmb laSpecFres
$5    ------------------------------------- vGeomMid ---------------------------------------------
$6    v1flag temp <---------- clipPtrs --------> <-- lbTexgenOrRet laSTKept
$7    v2flag tile clipWalkCount <----------- fogFlag ---------->  laPacked  mtx valid   cmd byte
$8    v3flag      clipLastVtx <------------- outVtx2 ---------->  laSpecular outVtx2
$9    xp texenab                                 <----- curLight ---------> viLtFlag
$10   -------------------------------------- temp2 -----------------------------------------------
$11   --------------------------------------- temp -----------------------------------------------
$12   ----------------------------------- perfCounterD -------------------------------------------
$13   ------------------------------------ altBaseReg --------------------------------------------
$14   geom mode   <-------------------------- inVtx ------------------------------->
$15                           <------------ outVtxBase ---------------------------->
$16   ----------------------------------- flatV1Offset -------------------------------------------
$17   
$18   
$19      temp     clipCurVtx  <------------- outVtx1 ---------->   laL2A    <---------   dmaLen
$20      temp   clipMaskShift clipVOnscr <-- flagsV1 ---------->  laTexgen  <---------  dmemAddr
$21   <----- clipMaskIdx / clipDrawPtr -------> <----- ambLight             ambLight  ovlInitClock
$22   ---------------------------------- rdpCmdBufEndP1 ------------------------------------------
$23   ----------------------------------- rdpCmdBufPtr -------------------------------------------
$24      temp   clipWalkPhase clipVOffscr <- flagsV2 ---------->   fp temp  <--------- cmd_w1_dram
$25     cmd_w0 --------------------------------> <----- lbAfter             <---------   cmd_w0
$26   ------------------------------------ taskDataPtr -------------------------------------------
$27   ---------------------------------- inputBufferPos ------------------------------------------
$28   ----------------------------------- perfCounterA -------------------------------------------
$29   ----------------------------------- perfCounterB -------------------------------------------
$30   ----------------------------------- perfCounterC -------------------------------------------
$ra   return address, command handler address, sometimes sign bit is flag ------------------------
*/

.include "rsp/include/regs.s"
.include "rsp/vtx/regs.inc"

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

.include "rsp/tri/regs.inc"

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
