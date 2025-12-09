.include "rsp/setup.inc"
.include "rsp/rsp_defs.inc"
.include "rsp/gbi_common.inc"
.include "rsp/gbi_zsoex3.inc"

ENABLE_PROFILING equ 0 // For setup.inc

////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// DMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// RSP DMEM
.create DATA_FILE, 0x0000

argsAddress:
    .dh cpuInterface
cacheSize:
    .dh (cacheEnd - cacheStart)

movememTable:
    .dh triStateTodo  // G_MV_TRISTATE
    .dh cacheEnd      // G_MV_CACHEEND
    .dh viewport      // G_MV_VIEWPORT
    .dh lightColors   // G_MV_LIGHTCOLORS

movewordTable:
    .dh fxParams      // G_MW_FX
    .dh segmentTable  // G_MW_SEGMENT

viewport: // v31Value only used at init, so we can clobber it after that.
// constants for register $v31
.if (. & 15) != 0
    .error "Wrong alignment for v31value"
.endif
v31Value:
// v31 must go from lowest to highest (signed) values for vcc patterns.
// Also relies on the fact that $v31[0h] is -4,-4,-4,-4, 4, 4, 4, 4.
    .dh -4     // used in clipping, vtx write for Newton-Raphson reciprocal
    .dh -1     // used often
    .dh 0      // used often
    .dh 2      // used as clip ratio (vtx write, clipping) and in clipping
    .dh 4      // used for same Newton-Raphsons, occlusion plane scaling
    .dh 0x4000 // used in tri write, texgen
    .dh 0x7F00 // used in fog
    .dh 0x7FFF // used often

// constants for register vTRC
.if (. & 15) != 0
    .error "Wrong alignment for vTRCValue"
.endif
vTRCValue:
decalFixMult equ 0x0400
decalFixOff equ (-(decalFixMult / 2))
vTRCValue0 equ cacheStart // around 0x100; for converting vertex index to address
vTRCValue1 equ vtxSize << 7 // 0x0B00; it's not 0x1600 because vertex indices are *2
vTRCValue2 equ 0x7E00 // vertex index mask for snake
vTRCValue3 equ decalFixMult // defined above
vTRCValue4 equ decalFixOff  // negative
vTRCValue5 equ 0x0020 // used in tri write and vtx addr manip
vTRCValue6 equ 0x0100 // used several times in tri write
vTRCValue7 equ 0x1000 // some multiplier in tri write, vtx addr manip
    .dh vTRCValue0
    .dh vTRCValue1
    .dh vTRCValue2
    .dh vTRCValue3
    .dh vTRCValue4
    .dh vTRCValue5
    .dh vTRCValue6
    .dh vTRCValue7
.macro set_vcc_11110001
    vge    $v29, vTRC, vTRC[0]
.endmacro
.if !( vTRCValue0 >= vTRCValue0  \
    && vTRCValue1 >= vTRCValue0  \
    && vTRCValue2 >= vTRCValue0  \
    && vTRCValue3 >= vTRCValue0  \
    && vTRCValue4 <  vTRCValue0  \
    && vTRCValue5 <  vTRCValue0  \
    && vTRCValue6 <  vTRCValue0  \
    && vTRCValue7 >= vTRCValue0 )
    .error "VCC pattern for vTRC corrupted"
.endif
vTRC_VB   equ vTRC[0] // Vertex Buffer
vTRC_VS   equ vTRC[1] // Vertex Size
vTRC_7E00 equ vTRC[2]
vTRC_DM   equ vTRC[3] // Decal Multiplier
vTRC_DO   equ vTRC[4] // Decal Offset
vTRC_0020 equ vTRC[5]
vTRC_0100 equ vTRC[6]
vTRC_1000 equ vTRC[7]
vTRC_0100_addr equ (vTRCValue + 2 * 6)

// displaylist stack
displayListStack:
maxDisplayListCalls equ 12
displayListStackEnd equ ((4 * maxDisplayListCalls) + displayListStack)
// ucode text (shared with DL stack)
    .ascii ID_STR, 0x0A
endIdStr:
.if endIdStr < displayListStackEnd
    .fill (displayListStackEnd - endIdStr)
.elseif endIdStr > displayListStackEnd
    .error "ID_STR is too long"
    .align 16  // to suppress subsequent errors 
.endif

.macro miniTableEntry, addr
    .if addr < 0x1000 || addr >= 0x1400
        .error "Handler address out of range!"
    .endif
    .db (addr - 0x1000) >> 2
.endmacro

texgenLinearCoeffs:
    .dh 0x44D3
    .dh 0x6CB3

// RDP/Immediate Command Mini Table
// 1 byte per entry, after << 2 points to an addr in first 1/4 of IMEM

miniTableEntry G_FLUSH_handler
miniTableEntry G_GEOMETRYMODE_handler
miniTableEntry G_DL_handler
miniTableEntry G_ENDDL_handler
miniTableEntry G_SPNOOP_handler
miniTableEntry G_MOVEWORD_handler
miniTableEntry G_MOVEMEM_handler
miniTableEntry G_RDPHALF_1_handler
miniTableEntry G_TEXRECT_handler // G_TEXRECT
miniTableEntry G_TEXRECT_handler // G_TEXRECTFLIP
miniTableEntry G_RDP_handler // G_RDPLOADSYNC
miniTableEntry G_RDP_handler // G_RDPPIPESYNC
miniTableEntry G_RDP_handler // G_RDPTILESYNC
miniTableEntry G_RDP_handler // G_RDPFULLSYNC
miniTableEntry G_RDP_handler // G_SETKEYGB
miniTableEntry G_RDP_handler // G_SETKEYR
miniTableEntry G_RDP_handler // G_SETCONVERT
miniTableEntry G_RDP_handler // G_SETSCISSOR
miniTableEntry G_RDP_handler // G_SETPRIMDEPTH
miniTableEntry G_RDP_handler // G_RDPSETOTHERMODE
miniTableEntry G_RDP_handler // G_LOADTLUT
miniTableEntry G_RDPHALF_2_handler
miniTableEntry G_RDP_handler // G_SETTILESIZE
miniTableEntry G_RDP_handler // G_LOADBLOCK
miniTableEntry G_RDP_handler // G_LOADTILE
miniTableEntry G_RDP_handler // G_SETTILE
miniTableEntry G_RDP_handler // G_FILLRECT
miniTableEntry G_RDP_handler // G_SETFILLCOLOR
miniTableEntry G_RDP_handler // G_SETFOGCOLOR
miniTableEntry G_RDP_handler // G_SETBLENDCOLOR
miniTableEntry G_RDP_handler // G_SETPRIMCOLOR
miniTableEntry G_RDP_handler // G_SETENVCOLOR
miniTableEntry G_RDP_handler // G_SETCOMBINE
miniTableEntry G_RDP_handler // G_SETTIMG
miniTableEntry G_RDP_handler // G_SETZIMG
miniTableEntry G_RDP_handler // G_SETCIMG
cmdMiniTable:
miniTableEntry G_RDP_handler // G_NOOP
miniTableEntry G_RELSEGMENT_handler
miniTableEntry G_VTX_handler
miniTableEntry G_TRI1_handler
miniTableEntry G_TRI2_handler

endInitializedDmem:

displayListStackDepth:
    .skip 1 // starts at 0, increments by 4 for each "return address" pushed onto the stack

    .align 4

altBase: // TODO eliminate or reuse?
fxParams:
geometryModeLabel:
    .skip 4
alphaCompareCullMode:
    .skip 1 // 0 = disabled, 1 = cull if all < thresh, -1 = cull if all >= thresh
alphaCompareCullThresh:
    .skip 1 // Alpha threshold, 00 - FF

perspNorm:
    .skip 2

texrectState:
    .skip 8  // Only needs to be saved over texrect, half1, half2
    // TODO overlap with section tris struct

// First half of RDP value for split commands. Also used as temp storage for
// tri vertices during tri commands.
rdpHalf1Val:
    .skip 4

    .align 16 // TODO

.if (. & 3) != 0
    .error "cpuInterface must be aligned to 4"
.endif
cpuInterface:
ucodeTextStart:
    .skip 4
displayListStart:
rdpFifoPos: // displayListStart only used at init
    .skip 4
rdpFifoStart:
    .skip 4
rdpFifoEnd:
    .skip 4

segmentTable:
    .skip (4 * 16) // 16 DRAM pointers

lightColors:
    .skip 16

.if (. & 15) != 0
    .error "triStateTodo must be aligned to 16"
.endif
triStateTodo:
    .skip 192

.if (. & 7) != 0
    .error "cacheStart must be aligned to 8"
.endif
cacheStart:
    
INPUT_BUFFER_CMDS equ 21
INPUT_BUFFER_SIZE_BYTES equ (INPUT_BUFFER_CMDS * 8)

RDP_TRI_SIZE_NO_ZBUF equ 0xA0
RDP_CMD_BUFSIZE_TOTAL equ (2 * RDP_TRI_SIZE_NO_ZBUF)

CACHE_END_ADDR equ (0x1000 - INPUT_BUFFER_SIZE_BYTES - (2 * RDP_CMD_BUFSIZE_TOTAL))
.org CACHE_END_ADDR
cacheEnd:

// First RDP Command Buffer
rdpCmdBuffer1:
    .skip RDP_TRI_SIZE_NO_ZBUF
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer1End:
    .skip 8
rdpCmdBuffer1EndPlus1Word:
    // This is so that we can temporarily store vector regs here with lqv/sqv
    .skip RDP_TRI_SIZE_NO_ZBUF - 8
// Second RDP Command Buffer
rdpCmdBuffer2:
    .skip RDP_TRI_SIZE_NO_ZBUF
.if (. & 8) != 8
    .error "RDP command buffer alignment to 8 assumption broken"
.endif
rdpCmdBuffer2End:
    .skip 8
rdpCmdBuffer2EndPlus1Word:
    .skip RDP_TRI_SIZE_NO_ZBUF - 8

// Input buffer. After RDP cmd buffers so it can be vector addressed from end.
inputBuffer:
    .skip INPUT_BUFFER_SIZE_BYTES
inputBufferEnd:
inputBufferEndSgn equ (-(0x1000 - inputBufferEnd)) // Underflow DMEM address

.if . != 0x1000
    .error "DMEM organization incorrect"
.endif

.close // DATA_FILE

////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Naming ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

/*
Scalar regs:
      Tri write   Clip walk    Clip VW      Vtx write   ltbasic    ltadv    V/L init  Cmd dispatch
$zero ---------------------------------- Hardwired zero ------------------------------------------
$1    v1 texptr    clipIdx    <------------- vtxLeft ------------------------------>  temp, init 0
$2    v2 shdptr   <---------- clipAlloc -------> <----- lbPostAo   laPtr                  temp
$3    v3 shdflg   clipTempVtx <------------- vLoopRet --------->  laVtxLeft               temp
$4                                               <----- lbFakeAmb laSpecFres
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
$16
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

// Global scalar regs:
vGeomMid       equ $5    // Middle two bytes of geometry mode in lower 16 bits
perfCounterD   equ $12   // Performance counter D (functions depend on config)
altBaseReg     equ $13   // Alternate base address register for vector loads
rdpCmdBufEndP1 equ $22   // Pointer to one command word past "end" (middle) of RDP command buf
rdpCmdBufPtr   equ $23   // RDP command buffer current DMEM pointer
taskDataPtr    equ $26   // Task data (display list) DRAM pointer
inputBufferPos equ $27   // DMEM position within display list input buffer, relative to end
perfCounterA   equ $28   // Performance counter A (functions depend on config)
perfCounterB   equ $29   // Performance counter B (functions depend on config)
perfCounterC   equ $30   // Performance counter C (functions depend on config)

// Vertex init:
viLtFlag       equ $9    // Holds pointLightFlag or dirLightsXfrmValid

// Vertex write:
vtxLeft        equ $1    // Number of vertices left to process * 0x10
vLoopRet       equ $3    // Return address at end of vtx loop = top of loop or misc lighting
fogFlag        equ $7    // 8 if fog enabled, else 0
outVtx2        equ $8    // Pointer to second or dummy (= outVtx1) transformed vert
inVtx          equ $14   // Pointer to loaded vertex to transform; < 0 means from clipping.
outVtxBase     equ $15   // Pointer to vertex buffer to store transformed verts
outVtx1        equ $19   // Pointer to first transformed vert
flagsV1        equ $20   // Clip flags for vertex 1
flagsV2        equ $24   // Clip flags for vertex 2

// Lighting basic:
lbPostAo       equ $2    // Address to return to after AO
lbFakeAmb      equ $4    // Pointer to ambient light or to 8 bytes of zeros if AO enabled
lbTexgenOrRet  equ $6    // ltbasic_texgen as negative if texgen, else vtx_return_from_lighting
curLight       equ $9    // Current light pointer with offset
ambLight       equ $21   // Ambient (top) light pointer with offset
lbAfter        equ $25   // Address to return to after main lighting loop (vertex or extras)

// Lighting advanced:
laPtr          equ $2    // Pointer to current vertex pair being lit
laVtxLeft      equ $3    // Count of vertices left * 0x10
laSpecFres     equ $4    // Nonzero if doing ltadv_normal_to_vertex for specular or Fresnel
laSTKept       equ $6    // Texture coords of vertex 1 kept through processing
laPacked       equ $7    // Nonzero if packed normals enabled
laSpecular     equ $8    // Sign bit set if specular enabled
laL2A          equ $19   // Nonzero if light-to-alpha (cel shading) enabled
laTexgen       equ $20   // Nonzero if texgen enabled

// Misc:
nextRA         equ $10   // Address to return to after overlay load
dmaLen         equ $19   // DMA length in bytes minus 1
dmemAddr       equ $20   // DMA address in DMEM or IMEM. Also = rdpCmdBufPtr - rdpCmdBufEndP1 for flush_rdp_buffer
cmd_w1_dram    equ $24   // DL command word 1, which is also DMA DRAM addr
cmd_w0         equ $25   // DL command word 0, also holds next tris info

// Global vector regs:
// TODO can maybe get rid of vZero
vZero equ $v0  // All elements = 0; NOT global, only in tri write and clip. Mtx in vtx.
vTRC  equ $v1  // Triangle Constants; NOT global, only in tri write and clip. Mtx in vtx.
vOne  equ $v28 // All elements = 1; global
// $v29: permanent temp register, also write results here to discard
// $v30: vtx / lt = sSTO + persp norm + more lighting params
// $v31: Global constant vector register

// Vertex / lighting vector regs:
// Prefixes: v = vector register, vp = vertex pair, s = vertex store,
// l = basic lighting, a = advanced lighting
// Sadly, "vp" stands for vertex pair, view*projection matrix, and viewport

vMTX0I   equ $v0  // Matrix rows int/frac; MVP normally, or M in ltadv
vMTX1I   equ $v1
vMTX2I   equ $v2
vMTX3I   equ $v3
vMTX0F   equ $v4
vMTX1F   equ $v5
vMTX2F   equ $v6
vMTX3F   equ $v7
vTemp1   equ $v8  // Temporaries, used by lighting (along with some vp regs)
vTemp2   equ $v9
vKept1   equ $v10 // Kept across lighting
vKept2   equ $v11
vpMdl    equ $v12 // Vertex pair model space position
vpClpF   equ $v13 // Vertex pair clip space position frac
vpClpI   equ $v14 // Vertex pair clip space position int
vpScrF   equ $v15 // Vertex pair screen space position frac
vpScrI   equ $v16 // Vertex pair screen space position int
vpST     equ $v17 // Vertex pair ST texture coordinates
vpRGBA   equ $v18 // Vertex pair color
vpLtTot  equ $v19 // Vertex pair total light
vpNrmlX  equ $v20 // Vertex pair normal X (elems 3, 7)
vpNrmlY  equ $v21 // Vertex pair normal Y (elems 3, 7)
vpNrmlZ  equ $v22 // Vertex pair normal Z (elems 3, 7)
vLTC     equ $v23 // Lighting constants - first light dir, constants for packed normals
vPerm1   equ $v24 // Regs loaded in vtx_constants_for_clip and permanently kept through vtx/lt
vPerm2   equ $v25
vPerm3   equ $v26
vPerm4   equ $v27

// Lighting temporaries. Lighting also modifies vpNrmlX:Y:Z, vpLtTot, vpRGBA, and
// in texgen vpST. Only the two regs in the comments below and vKept1 are kept.
// vpClpI:F are kept, vpMdl is free to use as temp
lDOT equ vpMdl  // lighting DOT product
lCOL equ vKept2 // lighting total light COLor
lDTC equ vTemp1  // lighting DoT Clamped
lVCI equ vTemp2  // lighting Vertex Color In
lDIR equ vpRGBA  // lighting transformed light DIRection

// Kept
sCLZ equ vKept1 // vtx_store Clamped Z. Does have to be kept even though in instan_lt_vs_45 b/c need rest of lt temps at start of texgen (and advanced lighting).
sOCS equ $v29   // Does not exist

// Common vertex temporaries
sRTF equ vTemp1  // vtx_store Reciprocal Temp Frac
sRTI equ vTemp2  // vtx_store Reciprocal Temp Int
sFOG equ lCOL // lCOL -> sFOG in lt epilogue with NOC, else sFOG -> lCOL in lt prologue

// Misc temps used by both
s1WI equ vpNrmlX // vtx_store 1/W Int
s1WF equ vpLtTot // vtx_store 1/W Frac
sSCI equ sFOG    // vtx_store Scaled Clipping Int
sSCF equ vpMdl   // vtx_store Scaled Clipping Frac
sTCL equ sCLZ    // vtx_store Temp CoLor

// Misc temps used by only one
sST2 equ vpScrI  // vtx_store ST coordinates copy 2
sOTM equ $v29    // Does not exist

// Permanently kept through vertex/lighting
sVPS equ vPerm1 // vtx_store ViewPort Scale
sVPO equ vPerm2 // vtx_store ViewPort Offset
sFGM equ vPerm3 // vtx_store FoG Mask
sO03 equ $v29   // Does not exist
sO47 equ $v29
sOCM equ $v29
sOPM equ $v29
sSTS equ vPerm4

// ltadv:
aPNScl equ $v8  // ltadv Packed Normals Scales = (1<<0),(1<<5),(1<<11),XX, repeat
aNrmSc equ $v9  // ltadv Normals Scale = [0h:1h] scale to normalize all normals; elems 2,3,6,7 used for point light factors
aDOT   equ $v10 // ltadv Dot product = normals dot direction; also briefly light dir
aLen2I equ $v11 // ltadv Length 2quared Int part
// Uses vpMdl = $v12
vpWrlF equ $v13 // vertex pair World position Frac part
vpWrlI equ $v14 // vertex pair World position Int part
aDPosF equ $v15 // ltadv Delta Position Frac part
aDPosI equ $v16 // ltadv Delta Position Int part
aOAFrs equ $v17 // ltadv Offset Alpha (elem 3,7) and Fresnel (elem 0,4)
// Uses vpRGBA, vpLtTot, vpNrmlX, vpNrmlY, vpNrmlZ = $v18, $v19, $v20, $v21, $v22
aParam equ $v23 // ltadv Parameters = AO, texgen, and Fresnel params

aAOF2  equ aDOT   // Version of aAOF in init, can't be aDPosI/F or vpMdl there
aPLFcI equ aLen2I // ltadv Point Light Factor Int part
aLen2F equ vpMdl  // ltadv Length 2quared Frac part
aPLFcF equ vpMdl  // ltadv Point Light Factor Frac part
aLTC   equ vpMdl  // ltadv Light Color
aClOut equ vpWrlF // ltadv Color Out
aAlOut equ vpWrlI // ltadv Alpha Out
aDIR   equ aDPosF // ltadv Direction = normalize(light or cam - vertex)
aDotSc equ aDPosF // ltadv Dot product Scale factor
aLkDt0 equ aDPosF // ltadv Lookat Dot product 0 for texgen
aLenF  equ aDPosI // ltadv Length Frac part
aAOF   equ aDPosI // ltadv Ambient Occlusion Factor
aProj  equ aDPosI // ltadv Projection
aLkDt1 equ aDPosI // ltadv Lookat Dot product 1 for texgen
// vpST equ aOAFrs // ST used in texgen
vpWNrm equ vpNrmlX // vertex pair World space Normals
aRcpLn equ $v29 // ltadv Reciprocal of Length
aLenI  equ $v29 // ltadv Length Int part



// Temp storage after rdpCmdBufEndP1. There is 0xA8 of space here which will
// always be free during vtx load or clipping.
tempVpRGBA            equ 0x00        // Only used during loop
tempXfrmLt            equ tempVpRGBA  // ltbasic only used during init
tempVtx1ST            equ tempVpRGBA  // ltadv only during init
tempAmbient           equ 0x10        // ltbasic set during init, used during loop
tempPrevInvalVtxStart equ 0x20
tempPrevInvalVtx      equ (tempPrevInvalVtxStart + vtxSize) // 0x46; fog writes here
tempPrevInvalVtxEnd   equ (tempPrevInvalVtx + vtxSize)      // 0x6C; rest of vtx writes here
.if tempPrevInvalVtxEnd > (RDP_TRI_SIZE_NO_ZBUF - 8)
    .error "Too much temp storage used!"
.endif


////////////////////////////////////////////////////////////////////////////////
//////////////////////////////////// IMEM //////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

// RSP IMEM
.create CODE_FILE, 0x00001000

// Initialization routines
// Everything up until ovl01_end will get overwritten by ovl1
start:
    lqv     $v31[0], (v31Value)($zero)
    lw      $2, rdpFifoEnd                // Load FIFO end addr
    vadd    $v29, $v29, $v29 // Consume VCO (carry) value possibly set by the previous ucode
    li      perfCounterA, 0
    li      perfCounterB, 0
    mtc0    $2, DPC_START                 // Set RDP start addr to end of FIFO
    mtc0    $2, DPC_END                   // Set RDP end addr to end of FIFO
    lw      taskDataPtr, displayListStart // Must be before store to rdpFifoPos
    li      perfCounterC, 0
    vclr    vOne
    li      perfCounterD, 0
    sw      $2, rdpFifoPos                // Must be after load from displayListStart
    lqv     vTRC, (vTRCValue)($zero)      // Always as this value except vtx_store
    li      altBaseReg, altBase
    li      rdpCmdBufPtr, rdpCmdBuffer1
    li      rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word
    vsub    vOne, vOne, $v31[1]             // 1 = 0 - -1
    lhu     vGeomMid, geometryModeLabel + 1
    li      inputBufferPos, 0
    li      nextRA, displaylist_dma
    j       load_overlays_0_1
     li     cmd_w1_dram, orga(ovl1_start)

start_end:
.align 8
start_padded_end:

.orga max(orga(), max(ovl0_padded_end - ovl0_start, ovl1_padded_end - ovl1_start))
ovl01_end:

G_DL_handler:
    sll     $2, cmd_w0, 15                  // Shifts the push/nopush value to the sign bit
    lbu     $7, displayListStackDepth       // Get the DL stack depth
    jal     segmented_to_physical
     add    $3, taskDataPtr, inputBufferPos // Current DL pos to push on stack
    bltz    $2, call_ret_common             // Nopush = branch = flag is set
     move   taskDataPtr, cmd_w1_dram        // Set the new DL to the target display list
    sw      $3, (displayListStack)($7)
    addi    $7, $7, 4                       // Increment the DL stack depth
call_ret_common:
    sb      $7, displayListStackDepth
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
    j       wait_goto_next_ra                      // if not, continue normal processing
     sub    taskDataPtr, taskDataPtr, inputBufferPos   // increment the DRAM address to read from next time
    
load_overlay_0_and_enter:
    li      nextRA, 0x1000                  // Sets up return address
    li      cmd_w1_dram, orga(ovl0_start)   // Sets up ovl0 table address
load_overlays_0_1:
    lw      $11, ucodeTextStart             // TODO move this to start, move ovl0 stuff here
    li      dmaLen, ovl01_end - 0x1000 - 1
    li      dmemAddr, 0x1000
    j       dma_and_wait_goto_next_ra
     add    cmd_w1_dram, cmd_w1_dram, $11

G_RDPHALF_2_handler: // 8; should be after the handlers with alignment needs
    li      $11, texrectState
    ldv     $v29[0], (0)($11)
    lw      cmd_w0, rdpHalf1Val             // load the RDPHALF1 value into w0
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8
    addi    perfCounterB, perfCounterB, 1   // Increment number of tex/fill rects
    sdv     $v29[0], -8(rdpCmdBufPtr)
    sw      cmd_w0, 0(rdpCmdBufPtr)  // TODO can optimize this with vector ops
    j       commit_small_rdp_command
     sw     cmd_w1_dram, 4(rdpCmdBufPtr) // w1 is from the current command

G_RDP_handler:
     spv    $v4[0], 0(rdpCmdBufPtr)     // Whole command
commit_small_rdp_command:
    addi    perfCounterD, perfCounterD, 0x4000 // Increment small RDP command count
    addi    rdpCmdBufPtr, rdpCmdBufPtr, 8    // Increment the next RDP command pointer by 2 words
check_rdp_buffer_full_and_run_next_cmd:
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    bgezal  dmemAddr, flush_rdp_buffer
     // $7 on next instr survives flush_rdp_buffer
tris_end:
G_SPNOOP_handler:
run_next_DL_command:
     lb     $7, (inputBufferEnd)(inputBufferPos)        // Command byte
    lpv     $v4[0], (inputBufferEndSgn)(inputBufferPos) // Whole command
    vclr    vZero
    beqz    inputBufferPos, displaylist_dma             // Check if buffer is empty
     lbu    $ra, (cmdMiniTable)($7)                     // Load mini table entry
    vmudh   $v3, $v31, vTRC_1000                        // $v3[3] = 2 * 1000 = 2000 for vtx addr manip
    lw      cmd_w0, (inputBufferEnd)(inputBufferPos)    // Word 0
    vmudl   $v5, $v4, vTRC_VS                           // Vtx indices times length
    lw      cmd_w1_dram, (inputBufferEnd + 4)(inputBufferPos) // Word 1
    vmadn   $v7, vOne, vTRC_VB                          // Plus address of vertex buffer
    sll     $ra, $ra, 2                                 // Convert to a number of instructions
    vmadl   $v6, $v31, $v31[2]                          // 0; copy in v6
    jr      $ra                                         // Jump to handler
     addi   inputBufferPos, inputBufferPos, 0x0008      // increment the DL index by 2 words
    // $7 must retain the command byte for load_mtx and command dispatch in overlays 2 and 3
    // $ra must contain the handler called for several handlers

G_MOVEMEM_handler: // If called this handler, $7 = (-0x100 | G_MOVEMEM)
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
     andi   $3, cmd_w0, 0x001E            // Movemem table index into $3 (bits 1-4 of the word 0)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Second byte of word 0
    lhu     dmemAddr, (movememTable)($3)
    srl     $2, cmd_w0, 5                 // ((w0) >> 8) << 3; top 3 bits of idx must be 0
    add     dmemAddr, dmemAddr, $2        // This is bits 5-16 inclusive for 12 bit DMEM
    li      nextRA, run_next_DL_command
dma_and_wait_goto_next_ra:
    j       dma_read_write
     li     $ra, wait_goto_next_ra

G_FLUSH_handler: // 32
    jal     flush_rdp_buffer        // Flush once to push partial DMEM buf to FIFO
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Prereq; offset buffer fullness
    // If the DMEM buffer was empty, dmemAddr will be unchanged and valid for this next
    // jump. Otherwise, running the DMA write will cause dmemAddr to get set to a large
    // negative number. Then for this second jump, the same codepath will be triggered as
    // if the buffer was empty. The result is it will wait for the DMA to finish, set
    // DPC_END, and return to $ra. This is why the dmemAddr register (as opposed to,
    // for example, dmaLen) is used as the DMEM buf fullness.
    j       flush_rdp_buffer
     li     $ra, run_next_DL_command // Dual use for above and below

align_with_warning 8, "One instruction of padding before G_VTX_handler"

G_VTX_handler: // 21
    // Vertex command is 01 0H L0 ee, where n = HL (number of vertices).
    // $v5[1] = 0H * 13, $v5[2] = L0 * 13.
    // ($v5[2] >> 10) * 2 = 0L * 26 = $v8[2]
    // ($v5[1] << 10) * 2 = H0 * 26 = $v9[1]
    // In segmented_to_physical, add, now $v8[2] = HL * 26 = n * 26.
    // Currently $v7[3] = end addr = (v0 + n) * 26 + base
    // Subtract -> $v8[3] = v0 * 26 + base = start addr.
    vmudl   $v8, $v5, $v3[3]       // 0x2000; elem 2 = low part
    mfc2    dmemAddr, $v7[6]       // (v0 + n) end address; up to 56 inclusive
    vmudn   $v9, $v5, vTRC_0020    // 0020; elem 1 = high part
    jal     segmented_to_physical  // Convert address in cmd_w1_dram to physical
     lhu    vtxLeft, (inputBufferEnd - 0x07)(inputBufferPos) // vtxLeft = size in bytes = vtx count * 0x10
    sub     dmemAddr, dmemAddr, vtxLeft  // Start addr = end addr - size. Rounded down to DMA word by H/W
    li      $ra, vtx_after_dma
    vsub    $v8, $v7, $v8[2]       // elem 3 = v0 start address
    j       dma_read_write
     addi   dmaLen, vtxLeft, -1

// Converts the segmented address in cmd_w1_dram to the corresponding physical address
segmented_to_physical: // 8
    srl     $11, cmd_w1_dram, 22          // Copy (segment index << 2) into $11
    andi    $11, $11, 0x3C                // Clear the bottom 2 bits that remained during the shift
    vadd    $v8, $v8, $v9[1]              // elem 2 = vertex count * size
    lw      $11, (segmentTable)($11)      // Get the current address of the segment
    sll     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address to the left so that the top 8 bits are shifted out
    srl     cmd_w1_dram, cmd_w1_dram, 8   // Shift the address back to the right, resulting in the original with the top 8 bits cleared
    jr      $ra
     add    cmd_w1_dram, cmd_w1_dram, $11 // Add the segment's address to the masked input address, resulting in the virtual address

// H = highest on screen = lowest Y value; then M = mid, L = low
tHAtF equ $v5
tMAtF equ $v27
tLAtF equ $v9
tHAtI equ $v18
tMAtI equ $v19
tLAtI equ $v21
tHPos equ $v14
tMPos equ $v2
tLPos equ $v10
tPosMmH equ $v6
tPosLmH equ $v8
tPosHmM equ $v11
tDaDyI equ $v27

align_with_warning 8, "One instruction of padding before tris"

.macro tri_v1_move
    vmov    $v6[1], $v7[5] // Move next to cur vertex 1 addr. Must be after main tri code cause $v6 not saved.
.endmacro

G_TRI2_handler: // If we jumped here, want $ra next to be G_TRI1_handler
G_QUAD_handler:
    li      $ra, (G_TRI1_handler - (tris_end - G_TRI1_handler))
G_TRI1_handler: // Whether we get here from cmd handler or prev tri, $ra == G_TRI1_handler
    // $v6: -- V1 -- -- -- -- -- -- This vertex address 1
    // $v7: -- -- V2 V3 -- N1 N2 N3 This and next vertex addresses
    mfc2    $2, $v7[4]
    mfc2    $1, $v6[2] // Can't move this up, $v6 is not ready yet when coming from return_and_end_mat
    vmudh   $v6, vOne, $v6[1] // elem 2 of v6 = vertex 1 addr
    addi    $ra, $ra, (tris_end - G_TRI1_handler) // So next go to tris_end
    vmudh   $v4, vOne, $v7[2] // elem 2 of v4 = vertex 2 addr
    addi    perfCounterB, perfCounterB, 0x4000  // Increment number of tris requested
    vmudh   $v8, vOne, $v7[3] // elem 2 of v8 = vertex 3 addr
    mfc2    $3, $v7[6]
    vmov    $v7[3], $v7[7]    // Move next to cur vertex 3 addr.
    vnxor   tHAtF, vZero, $v31[7]  // v5 = 0x8000; init frac value for attrs for rounding
    llv     $v6[0], VTX_SCR_VEC($1) // Load pixel coords of vertex 1 into v6 (elems 0, 1 = x, y)
    vnxor   tMAtF, vZero, $v31[7]  // v7 = 0x8000; init frac value for attrs for rounding
    llv     $v4[0], VTX_SCR_VEC($2) // Load pixel coords of vertex 2 into v4
    vnxor   tLAtF, vZero, $v31[7]  // v9 = 0x8000; init frac value for attrs for rounding
    llv     $v8[0], VTX_SCR_VEC($3) // Load pixel coords of vertex 3 into v8
    vmov    $v7[2], $v7[6]    // Move next to cur vertex 2 addr.
    lhu     $6, VTX_CLIP($1)
    vmudh   $v2, vOne, $v6[1] // v2 all elems = y-coord of vertex 1
    lhu     $7, VTX_CLIP($2)
    vsub    $v10, $v6, $v4    // v10 = vertex 1 - vertex 2 (x, y, addr)
    lhu     $8, VTX_CLIP($3)
    vsub    $v12, $v6, $v8    // v12 = vertex 1 - vertex 3 (x, y, addr)
    andi    $11, $6, CLIP_SCRN_NPXY | CLIP_CAMPLANE // All three verts on wrong side of same plane
    vsub    $v11, $v4, $v6    // v11 = vertex 2 - vertex 1 (x, y, addr)
    and     $11, $11, $7
    vlt     $v13, $v2, $v4[1] // v13 = min(v1.y, v2.y), VCO = v1.y < v2.y
    and     $11, $11, $8
    vmrg    tHPos, $v6, $v4   // v14 = v1.y < v2.y ? v1 : v2 (lower vertex of v1, v2)
    bnez    $11, return_and_end_mat // Then the whole tri is offscreen, cull
     // 16 cycles (for tri2 first tri; tri1/only subtract 1 from counts)
     vmudh  $v29, $v10, $v12[1] // x = (v1 - v2).x * (v1 - v3).y ... 
    vmadh   $v26, $v12, $v11[1] // ... + (v1 - v3).x * (v2 - v1).y = cross product = dir tri is facing
    // nop
    vge     $v2, $v2, $v4[1]  // v2 = max(vert1.y, vert2.y), VCO = vert1.y > vert2.y
    sll     $20, vGeomMid, 29 // Original bit 10 (now bit 2) in the sign bit, for facing cull
    vmrg    tLPos, $v6, $v4   // v10 = vert1.y > vert2.y ? vert1 : vert2 (higher vertex of vert1, vert2)
    or      $10, $6, $7
    vge     $v6, $v13, $v8[1] // v6 = max(max(vert1.y, vert2.y), vert3.y), VCO = max(vert1.y, vert2.y) > vert3.y
    or      $10, $10, $8      // $10 = all clip bits which are true for any verts
    vmrg    $v4, tHPos, $v8   // v4 = max(vert1.y, vert2.y) > vert3.y : higher(vert1, vert2) ? vert3 (highest vertex of vert1, vert2, vert3)
    mfc2    $9, $v26[0]       // elem 0 = x = cross product => lower 16 bits, sign extended
    vmrg    tHPos, $v8, tHPos // v14 = max(vert1.y, vert2.y) > vert3.y : vert3 ? higher(vert1, vert2)
    andi    $10, $10, CLIP_SCAL_NPXY | CLIP_CAMPLANE
    vlt     $v29, $v6, $v2    // VCO = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y)
    bnez    $10, return_and_end_mat // Reject (instead of clipping)
     // 24 cycles
     srl    $11, $9, 31       // = 0 if x prod positive (back facing), 1 if x prod negative (front facing)
    vmudh   $v3, vOne, $v31[5] // 0x4000; some rounding factor
    sllv    $11, $20, $11     // Sign bit = bit 10 of geom mode if back facing, bit 9 if front facing
    vmrg    tMPos, $v4, tLPos // v2 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2, vert3) ? highest(vert1, vert2)
    bltz    $11, return_and_end_mat // Cull if bit is set (culled based on facing)
     // 27 cycles
     vmrg   tLPos, tLPos, $v4 // v10 = max(vert1.y, vert2.y, vert3.y) < max(vert1.y, vert2.y) : highest(vert1, vert2) ? highest(vert1, vert2, vert3)
tSubPxHF equ $v4
    vmudn   tSubPxHF, tHPos, $v31[5] // 0x4000
    beqz    $9, return_and_end_mat  // If cross product is 0, tri is degenerate (zero area), cull.
     // 29 cycles
     vsub   tPosMmH, tMPos, tHPos
    vsub    tPosLmH, tLPos, tHPos
    vsub    tPosHmM, tHPos, tMPos
    mfc2    $1, tHPos[4]     // tHPos = lowest Y value = highest on screen (x, y, addr)
    // 32 cycles if NOC
tPosCatI equ $v15 // 0 X L-M; 1 Y L-M; 2 X M-H; 3 X L-H; 4-7 garbage
    vsub    tPosCatI, tLPos, tMPos
    mfc2    $2, tMPos[4]     // tMPos = mid vertex (x, y, addr)
    vmov    tPosCatI[2], tPosMmH[0]
    // nop
    vmudh   $v29, tPosMmH, tPosLmH[0]
    li      $20, -8       // 0xFFF8; constant for some mask below
t1WI equ $v13 // elems 0, 4, 6
    vmadh   $v29, tPosLmH, tPosHmM[0]
    mfc2    $3, tLPos[4]     // tLPos = highest Y value = lowest on screen (x, y, addr)
tXPF equ $v16 // Triangle cross product
tXPI equ $v17
    vreadacc tXPI, ACC_UPPER
    // nop
    vreadacc tXPF, ACC_MIDDLE
    lpv     tHAtI[0], VTX_COLOR_VEC($1) // Load vert color of vertex 1
    vrcp    $v20[0], tPosCatI[1]
    lpv     tMAtI[0], VTX_COLOR_VEC($2) // Load vert color of vertex 2
    vmov    tPosCatI[3], tPosLmH[0]
    lpv     tLAtI[0], VTX_COLOR_VEC($3) // Load vert color of vertex 3
    vrcph   $v22[0], tXPI[1]
    // nop
tXPRcpF equ $v23 // Reciprocal of cross product (becomes that * 4)
tXPRcpI equ $v24
    vrcpl   tXPRcpF[1], tXPF[1]
    // nop
    vrcph   tXPRcpI[1], $v31[2]            // 0
    // 43 cycles
    vrcp    $v20[2], tPosMmH[1]
    ssv     tPosMmH[2], 0x0030(rdpCmdBufPtr) // MmHY -> first short (temp mem)
    vrcph   $v22[2], tPosMmH[1]
    llv     t1WI[0], VTX_INV_W_VEC($1)
    vrcp    $v20[3], tPosLmH[1]
    llv     t1WI[8], VTX_INV_W_VEC($2)
    vrcph   $v22[3], tPosLmH[1]
    llv     t1WI[12], VTX_INV_W_VEC($3)
    vmudl   tHAtI, tHAtI, vTRC_0100 // vertex color 1 >>= 8
    lb      $11, (alphaCompareCullMode)($zero)
    vmudl   tMAtI, tMAtI, vTRC_0100 // vertex color 2 >>= 8
    lw      $6, VTX_INV_W_VEC($1) // $6, $7, $8 = 1/W for H, M, L
    vmudl   tLAtI, tLAtI, vTRC_0100 // vertex color 3 >>= 8
    lw      $7, VTX_INV_W_VEC($2)
    vmudl   $v29, $v20, vTRC_0020
    lw      $8, VTX_INV_W_VEC($3)
    vmadm   $v22, $v22, vTRC_0020
    bnez    $11, tri_alpha_compare_cull
     vmadn  $v20, $v31, $v31[2] // 0
// $v6 <- tPosMmH; $v6 clobbered in alpha compare cull
tri_return_from_alpha_compare_cull: // Uses $v25, $v26
    // 53 cycles
tPosCatF equ $v25
    vmudm   tPosCatF, tPosCatI, vTRC_1000
    mtc2    $20, tMPos[14] // 0xFFF8; only elem 0, 1, 2 of this reg used now
    vmadn   tPosCatI, $v31, $v31[2] // 0
    sub     $11, $6, $7  // Four instr: $6 = max($6, $7)
    vsubc   tSubPxHF, vZero, tSubPxHF
    sra     $10, $11, 31
tSubPxHI equ $v26
    vsub    tSubPxHI, vZero, vZero
    and     $11, $11, $10
    vmudm   $v29, tPosCatF, $v20
    sub     $6, $6, $11
    vmadl   $v29, tPosCatI, $v20
    sub     $11, $6, $8  // Four instr: $6 = max($6, $8)
    vmadn   $v20, tPosCatI, $v22
    sra     $10, $11, 31
    vmadh   tPosCatI, tPosCatF, $v22
    and     $11, $11, $10
    vmudl   $v29, tXPRcpF, tXPF
    sub     $6, $6, $11
    vmadm   $v29, tXPRcpI, tXPF
    mfc2    $7, tXPI[1]
    vmadn   tXPF, tXPRcpF, tXPI
    lbu     $14, geometryModeLabel + 3 // Load lowest byte for G_SHADE, G_TEXTURE_ENABLE.
    vmadh   tXPI, tXPRcpI, tXPI
    // nop
    vand    $v22, $v20, tMPos[7] // 0xFFF8
    // nop
    vcr     tPosCatI, tPosCatI, vTRC_0100
    // nop
    vmudh   $v29, vOne, $v31[4] // 4
    ori     $11, $14, G_TRI_FILL // Combine geometry mode (only the low byte will matter) with the base triangle type to make the triangle command id
    vmadn   tXPF, tXPF, $v31[0] // -4
    andi    $9, $14, G_TEXTURE_ENABLE
    vmadh   tXPI, tXPI, $v31[0] // -4
    sw      $6, 0x0010(rdpCmdBufPtr) // Store max of three verts' 1/W (upper) to temp mem
tMx1W equ $v25 // <- tPosCatF
    vmudn   $v29, $v3, tHPos[0]
    llv     tMx1W[0], 0x0010(rdpCmdBufPtr) // Load max of three verts' 1/W
    vmadl   $v29, $v22, tSubPxHF[1]
    ssv     tMPos[2], 0x0004(rdpCmdBufPtr) // Store YM edge coefficient
    vmadm   $v29, tPosCatI, tSubPxHF[1]
    // nop
// $v2 <- tMPos
    vmadn   $v2, $v22, tSubPxHI[1]
    ssv     tLPos[2], 0x0002(rdpCmdBufPtr) // Store YL edge coefficient
    vmadh   $v3, tPosCatI, tSubPxHI[1]
    // nop
    vrcph   $v29[0], tMx1W[0] // Reciprocal of max 1/W = min W
    ssv     tHPos[2], 0x0006(rdpCmdBufPtr) // Store YH edge coefficient
tMnWF equ $v10 // <- tLPos
    vrcpl   tMnWF[0], tMx1W[1]
    li      $10, 0  // TODO Level and tile
t1WF equ $v14 // <- tHPos
    vmudh   t1WF, vOne, t1WI[1q]
    sb      $11, 0x0000(rdpCmdBufPtr) // Store the triangle command id
tMnWI equ $v25 // <- tMx1W
    vrcph   tMnWI[0], $v31[2]     // 0
    // nop
tSTWHMI equ $v22 // H = elems 0-2, M = elems 4-6; init W = 7FFF
    vmudh   tSTWHMI, vOne, $v31[7]  // 0x7FFF
    // nop
    vmudm   $v29, t1WI, tMnWF[0] // 1/W each vtx * min W = 1 for one of the verts, < 1 for others
    llv     tSTWHMI[0], VTX_TC_VEC($1)
    vmadl   $v29, t1WF, tMnWF[0]
    ssv     tPosLmH[0], 0x0032(rdpCmdBufPtr) // LmHX -> second short (temp mem)
    vmadn   t1WF, t1WF, tMnWI[0]
    llv     tSTWHMI[8], VTX_TC_VEC($2)
    vmadh   t1WI, t1WI, tMnWI[0]
    ssv     tPosHmM[0], 0x0034(rdpCmdBufPtr) // HmMX -> third short (temp mem)
tSTWLI equ $v10 // L = elems 4-6; init W = 7FFF
tSTWLF equ $v13
    vmudh   tSTWLI, vOne, $v31[7]  // 0x7FFF
    // nop
    set_vcc_11110001                // select RGBA___Z or ____STW_
    llv     tSTWLI[8], VTX_TC_VEC($3)
    vmudm   $v29, tSTWHMI, t1WF[0h] // (S, T, 7FFF) * (1 or <1) for H and M
    // nop
    vmadh   tSTWHMI, tSTWHMI, t1WI[0h]
    ldv     tPosLmH[8], 0x0030(rdpCmdBufPtr) // MmHY -> e4, LmHX -> e5, HmMX -> e6
tSTWHMF equ $v25 // <- tMnWI
    vmadn   tSTWHMF, $v31, $v31[2]  // 0
    andi    $7, $7, 0x0080 // Extract the left major flag from $7
    vmudm   $v29, tSTWLI, t1WF[6]  // (S, T, 7FFF) * (1 or <1) for L
    or      $7, $7, $10 // Combine the left major flag with the level and tile from the texture settings
    vmadh   tSTWLI, tSTWLI, t1WI[6]
    sb      $7, 0x0001(rdpCmdBufPtr) // Store the left major flag, level, and tile settings
    vmadn   tSTWLF, $v31, $v31[2]  // 0
    sdv     tSTWHMI[0], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int to temp mem
    vmrg    tMAtI, tMAtI, tSTWHMI // Merge S, T, W Mid into elems 4-6
    sdv     tSTWHMF[0], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac to temp mem
    vmrg    tMAtF, tMAtF, tSTWHMF // Merge S, T, W Mid into elems 4-6
// $v25 <- tSTWHMF
    ldv     tHAtI[8], 0x0020(rdpCmdBufPtr) // Move S, T, W Hi Int from temp mem
    vmrg    tLAtI, tLAtI, tSTWLI // Merge S, T, W Low into elems 4-6
    ldv     tHAtF[8], 0x0028(rdpCmdBufPtr) // Move S, T, W Hi Frac from temp mem
    vmrg    tLAtF, tLAtF, tSTWLF // Merge S, T, W Low into elems 4-6
    addi    perfCounterA, perfCounterA, 1 // Increment number of tris sent to RDP
    // 96 cycles
    vmudl   $v29, tXPF, tXPRcpF
    // nop
    vmadm   $v29, tXPI, tXPRcpF
    // nop
    vmadn   tXPRcpF, tXPF, tXPRcpI
    lh      $1, VTX_SCR_VEC($2)
    vmadh   tXPRcpI, tXPI, tXPRcpI
    addi    $2, rdpCmdBufPtr, 0x20 // Increment the triangle pointer by 0x20 bytes (edge coefficients)
    vmudh   tPosLmH, tPosLmH, $v31[0h] // e1 LmHY * -4 = 4*HmLY; e456 MmHY,LmHX,HmMX *= 4
    andi    $3, $14, G_SHADE
tAtLmHF equ $v10
tAtLmHI equ $v9
tAtMmHF equ $v13
tAtMmHI equ $v27
    vsubc   tAtLmHF, tLAtF, tHAtF
    sll     $1, $1, 14
    vsub    tAtLmHI, tLAtI, tHAtI
    // nop
    vsubc   tAtMmHF, tMAtF, tHAtF
    sw      $1, 0x0008(rdpCmdBufPtr)         // Store XL edge coefficient
    vsub    tAtMmHI, tMAtI, tHAtI
    ssv     $v3[6], 0x0010(rdpCmdBufPtr)     // Store XH edge coefficient (integer part)
// DaDx = (v3 - v1) * factor + (v2 - v1) * factor
tDaDxF equ $v2
tDaDxI equ $v3
    vmudn   $v29, tAtLmHF, tPosLmH[4] // MmHY * 4
    ssv     $v2[6], 0x0012(rdpCmdBufPtr)     // Store XH edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[4] // MmHY * 4
    ssv     $v3[4], 0x0018(rdpCmdBufPtr)     // Store XM edge coefficient (integer part)
    vmadn   $v29, tAtMmHF, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     $v2[4], 0x001A(rdpCmdBufPtr)     // Store XM edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[1] // LmHY * -4 = HmLY * 4
    ssv     tPosCatI[0], 0x000C(rdpCmdBufPtr)    // Store DxLDy edge coefficient (integer part)
    vreadacc tDaDxF, ACC_MIDDLE
    ssv     $v20[0], 0x000E(rdpCmdBufPtr)    // Store DxLDy edge coefficient (fractional part)
    vreadacc tDaDxI, ACC_UPPER
    ssv     tPosCatI[6], 0x0014(rdpCmdBufPtr)    // Store DxHDy edge coefficient (integer part)
// DaDy = (v2 - v1) * factor + (v3 - v1) * factor
tDaDyF equ $v6
// tDaDyI <- $v27
    vmudn   $v29, tAtMmHF, tPosLmH[5] // LmHX * 4
    ssv     $v20[6], 0x0016(rdpCmdBufPtr)    // Store DxHDy edge coefficient (fractional part)
    vmadh   $v29, tAtMmHI, tPosLmH[5] // LmHX * 4
    ssv     tPosCatI[4], 0x001C(rdpCmdBufPtr)    // Store DxMDy edge coefficient (integer part)
    vmadn   $v29, tAtLmHF, tPosLmH[6] // HmMX * 4
    ssv     $v20[4], 0x001E(rdpCmdBufPtr)    // Store DxMDy edge coefficient (fractional part)
    vmadh   $v29, tAtLmHI, tPosLmH[6] // HmMX * 4
    sll     $11, $3, 4              // Shift (geometry mode & G_SHADE) by 4 to get 0x40 if G_SHADE is set
    vreadacc tDaDyF, ACC_MIDDLE
    add     $1, $2, $11             // Increment the triangle pointer by 0x40 bytes (shade coefficients) if G_SHADE is set
    vreadacc tDaDyI, ACC_UPPER
    sll     $11, $9, 5              // Shift texture enabled (which is 2 when on) by 5 to get 0x40 if textures are on
// DaDx, DaDy *= more factors
    vmudl   $v29, tDaDxF, tXPRcpF[1]
    add     rdpCmdBufPtr, $1, $11   // Increment the triangle pointer by 0x40 bytes (texture coefficients) if textures are on
    vmadm   $v29, tDaDxI, tXPRcpF[1]
    // nop
    vmadn   tDaDxF, tDaDxF, tXPRcpI[1]
    // nop
    vmadh   tDaDxI, tDaDxI, tXPRcpI[1]
    // nop
    vmudl   $v29, tDaDyF, tXPRcpF[1]
    // nop
    vmadm   $v29, tDaDyI, tXPRcpF[1]
    sub     dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Check if we need to write out to RDP
    vmadn   tDaDyF, tDaDyF, tXPRcpI[1]
    sdv     tDaDxF[0], 0x0018($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (fractional)
    vmadh   tDaDyI, tDaDyI, tXPRcpI[1]
    sdv     tDaDxI[0], 0x0008($2)   // Store DrDx, DgDx, DbDx, DaDx shade coefficients (integer)
// DaDe = DaDx * factor
tDaDeF equ $v8
tDaDeI equ $v9
    // 125 cycles
    vmadl   $v29, tDaDxF, $v20[3]
    sdv     tDaDxF[8], 0x0018($1)   // Store DsDx, DtDx, DwDx texture coefficients (fractional)
    vmadm   $v29, tDaDxI, $v20[3]
    sdv     tDaDxI[8], 0x0008($1)   // Store DsDx, DtDx, DwDx texture coefficients (integer)
    vmadn   tDaDeF, tDaDxF, tPosCatI[3]
    sdv     tDaDyF[0], 0x0038($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (fractional)
    vmadh   tDaDeI, tDaDxI, tPosCatI[3]
    sdv     tDaDyI[0], 0x0028($2)   // Store DrDy, DgDy, DbDy, DaDy shade coefficients (integer)
// Base value += DaDe * factor
    vmudn   $v29, tHAtF, vOne[0]
    sdv     tDaDyF[8], 0x0038($1)   // Store DsDy, DtDy, DwDy texture coefficients (fractional)
    vmadh   $v29, tHAtI, vOne[0]
    sdv     tDaDyI[8], 0x0028($1)   // Store DsDy, DtDy, DwDy texture coefficients (integer)
    vmadl   $v29, tDaDeF, tSubPxHF[1]
    sdv     tDaDeF[0], 0x0030($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (fractional)
    vmadm   $v29, tDaDeI, tSubPxHF[1]
    sdv     tDaDeI[0], 0x0020($2)   // Store DrDe, DgDe, DbDe, DaDe shade coefficients (integer)
    vmadn   tHAtF, tDaDeF, tSubPxHI[1]
    sdv     tDaDeF[8], 0x0030($1)   // Store DsDe, DtDe, DwDe texture coefficients (fractional)
    vmadh   tHAtI, tDaDeI, tSubPxHI[1]
    sdv     tDaDeI[8], 0x0020($1)   // Store DsDe, DtDe, DwDe texture coefficients (integer)
    sdv     tHAtF[0], 0x0010($2)   // Store RGBA shade color (fractional)
    sdv     tHAtI[0], 0x0000($2)   // Store RGBA shade color (integer)
    tri_v1_move                    // From return_and_end_mat, we didn't go there
    sdv     tHAtF[8], 0x0010($1)   // Store S, T, W texture coefficients (fractional)
    bltz    dmemAddr, return_and_end_mat     // Return if rdpCmdBufPtr < end+1 i.e. ptr <= end
     sdv    tHAtI[8], 0x0000($1)   // Store S, T, W texture coefficients (integer)
     // 146 cycles
flush_rdp_buffer: // Prereq: dmemAddr = rdpCmdBufPtr - rdpCmdBufEndP1, or dmemAddr = large neg num -> only wait and set DPC_END
    mfc0    $11, SP_DMA_BUSY                 // Check if any DMA is in flight
    lw      cmd_w1_dram, rdpFifoPos          // FIFO pointer = end of RDP read, start of RSP write
    lw      $10, rdpFifoEnd                  // Load FIFO end addr
    bnez    $11, flush_rdp_buffer            // Wait until no DMAs are active
     addi   dmaLen, dmemAddr, RDP_TRI_SIZE_NO_ZBUF + 8  // dmaLen = size of DMEM buffer to copy
    blez    dmaLen, old_return_routine       // Exit if nothing to copy, or if dmemAddr is large negative num from last flush DMA write
     mtc0   cmd_w1_dram, DPC_END             // Set RDP to execute until FIFO end (buf pushed last time)
    add     $11, cmd_w1_dram, dmaLen         // $11 = future FIFO pointer if we append this new buffer
    sub     $10, $10, $11                    // $10 = FIFO end addr - future pointer
    bgez    $10, @@has_room                  // Branch if we can fit this
@@await_rdp_dblbuf_avail:
     mfc0   $11, DPC_STATUS                  // Read RDP status
    andi    $11, $11, DPC_STATUS_START_VALID // Start valid = second start addr in dbl buf
    bnez    $11, @@await_rdp_dblbuf_avail    // Wait until double buffered start/end available
     addi   perfCounterC, perfCounterC, 7    // 4 instr + 2 after mfc + 1 taken branch
    lw      cmd_w1_dram, rdpFifoStart        // Start of FIFO
@@await_past_first_instr:
    mfc0    $11, DPC_CURRENT                 // Load RDP current pointer
    beq     $11, cmd_w1_dram, @@await_past_first_instr // Wait until RDP moved past start
     addi   perfCounterC, perfCounterC, 6    // 3 instr + 2 after mfc + 1 taken branch
    // Start was previously the start of the FIFO, unless this is the first buffer,
    // in which case it was the end of the FIFO. Normally, when the RDP gets to end, if we
    // have a new end value waiting (END_VALID), it'll load end but leave current. By
    // setting start here, it will also load current with start.
    mtc0    cmd_w1_dram, DPC_START           // Set RDP start to start of FIFO
@@keep_waiting:
    // This is here so we only count it when stalling below or on FIFO end codepath
    addi    perfCounterC, perfCounterC, 10   // 7 instr + 2 after mfc + 1 taken branch
@@has_room:
    mfc0    $11, DPC_CURRENT                 // Load RDP current pointer
    sub     $11, $11, cmd_w1_dram            // Current - current end (rdpFifoPos or start)
    blez    $11, @@copy_buffer               // Current is behind or at current end, can do copy
     sub    $11, $11, dmaLen                 // If amount current is ahead of current end
    blez    $11, @@keep_waiting              // is <= size of buffer to copy, keep waiting
@@copy_buffer:
     add    $11, cmd_w1_dram, dmaLen         // New end is current end + buffer size
    sw      $11, rdpFifoPos
    // Set up the DMA from DMEM to the RDP fifo in RDRAM
    addi    dmaLen, dmaLen, -1                                  // subtract 1 from the length
    addi    dmemAddr, rdpCmdBufEndP1, -(0x2000 | (RDP_TRI_SIZE_NO_ZBUF + 8)) // The 0x2000 is meaningless, negative means write
    xori    rdpCmdBufEndP1, rdpCmdBufEndP1, rdpCmdBuffer1EndPlus1Word ^ rdpCmdBuffer2EndPlus1Word // Swap between the two RDP command buffers
    j       dma_read_write
     addi   rdpCmdBufPtr, rdpCmdBufEndP1, -(RDP_TRI_SIZE_NO_ZBUF + 8)

/*

vtx_select_lighting:
    lbu     ambLight, numLightsxSize
    lb      viLtFlag, dirLightsXfrmValid
    addi    ambLight, ambLight, altBase    // Point to ambient light; stored through vtx proc
    bnez    viLtFlag, ltbasic_setup_after_xfrm  // Skip if lights were valid
     addi   lbFakeAmb, ambLight, ltBufOfs  // Ptr to load amb light from; normally actual ambient light
xfrm_dir_lights:
lpWrld  equ $v11  // light pair world direction
lpMdl   equ $v12  // light pair model space direction (not yet normalized)
lpFinal equ $v13  // light pair normalized model space direction
lpSqrI  equ $v14  // Light pair direction squared int part
lpSqrF  equ $v15  // Light pair direction squared frac part
lpMdl2  equ $v19  // Copy of lpMdl for pipelining
lpSumI  equ $v20  // Light pair direction sum of squares int part
lpSumF  equ $v21  // Light pair direction sum of squares frac part
lpRsqI  equ $v22  // Light pair reciprocal square root int part
lpRsqF  equ $v23  // Light pair reciprocal square root frac part
    // Transform directional lights' direction by M transpose.
    // First, load M transpose. $v0-$v7 is the MVP matrix and $v24-$v31 is
    // permanent values, leaving $v8-$v15 and $v16-$v23 for the transposes.
    // This is mainly just an excuse to use the rare ltv and swv instructions.
    // The F3DEX2 implementation takes 18 instructions and 11 cycles.
    // This implementation is 23 instructions and 17 cycles, but this version
    // loads M transpose to both halves of each vector so we can process two
    // lights at a time, which matters because there's always at least 3 lights
    // (technically 2 for EX3)--the lookat directions. Plus, those 17 cycles
    // also include a few instructions starting the loop.
    // Memory at mMatrix contains, in shorts within qwords, for the elements we care about:
    // A B C - D E F - (X int, Y int)
    // G H I - - - - - (Z int, W int)
    // M N O - P Q R - (X frac, Y frac)
    // S T U - - - - - (Z frac, W frac)
    // First, load this pattern in $v8-$v15 (int) and $v16-$v23 (frac).
    // $v8  A - G - A - G -   $v16 M - S - M - S -
    // $v9  - B - H - B - H   $v17 - N - T - N - T
    // $v10 I - C - I - C -   $v18 U - O - U - O -
    // $v11 - - - - - - - -   $v19 - - - - - - - -
    // $v12 D - - - D - - -   $v20 P - - - P - - -
    // $v13 - E - - - E - -   $v21 - Q - - - Q - -
    // $v14 - - F - - - F -   $v22 - - R - - - R -
    // $v15 - - - - - - - -   $v23 - - - - - - - -
    ltv     $v8[0],   (mMatrix + 0x00)($zero) // A to $v8[0] etc.
    ltv     $v8[12],  (mMatrix + 0x10)($zero) // G to $v8[2] etc.
    ltv     $v8[8],   (mMatrix + 0x00)($zero) // A to $v8[4] etc.
    ltv     $v8[4],   (mMatrix + 0x10)($zero) // G to $v8[6] etc.
    ltv     $v16[0],  (mMatrix + 0x20)($zero)
    ltv     $v16[12], (mMatrix + 0x30)($zero)
    ltv     $v16[8],  (mMatrix + 0x20)($zero)
    ltv     $v16[4],  (mMatrix + 0x30)($zero)
    veq     $v29, $v31, $v31[0q] // Set VCC to 10101010
    vmudh   $v9, vOne, $v9[1q]                // B - H - B - H -
    lsv     $v18[6],  (mMatrix + 0x2C)($zero) // U - O(R)U - O -
    vmrg    $v8, $v8, $v12[0q]                // A D G - A D G -
    lsv     $v18[14], (mMatrix + 0x2C)($zero) // U - O R U - O(R)
    vmrg    $v10, $v10, $v14[0q]              // I - C F I - C F
    lpv     lpWrld[0], (lightBufferLookat - altBase)(altBaseReg) // Lookat 0 and 1
    vmudh   $v17, vOne, $v17[1q]              // N - T - N - T -
    li      curLight, altBase - 4 * lightSize // + ltBufOfs = light -4; write pointer
    vmrg    $v9, $v9, $v13                    // B E H - B E H -
    li      $11, 0x7F                         // Mark lights valid. Could use some other reg known to be zero, but need a nop here.
    vmrg    $v16, $v16, $v20[0q]              // M P S - M P S -
    swv     $v18[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores O R U - O R U -
    vmudh   $v29,  $v8,  lpWrld[0h]           // Start transforming lookat
    lqv     $v18,    (tempXfrmLt)(rdpCmdBufEndP1)
    // This is slightly wrong, vmrg writes accum lo. But only affects lookat and
    // we are only reading accum mid result. Basically rounding error.
    vmrg    $v17, $v17, $v21                  // N Q T - N Q T -
    swv     $v10[4], (tempXfrmLt)(rdpCmdBufEndP1) // Stores C F I - C F I -
    vmadh   $v29,  $v9,  lpWrld[1h]
    lqv     $v10,    (tempXfrmLt)(rdpCmdBufEndP1)
    vmadn   $v29,  $v16, lpWrld[0h]
    sb      $11, dirLightsXfrmValid
    // 18 cycles
xfrm_light_loop_1:
    vmadn   $v29,  $v18, lpWrld[2h]
xfrm_light_loop_2:
    vmadn   $v29,  $v17, lpWrld[1h]
    vmadh   lpMdl, $v10, lpWrld[2h]  // lpMdl[0:2] and [4:6] = two lights dir in model space
    vrsqh   $v29[0], lpSumI[0]
    vrsql   lpRsqF[0], lpSumF[0]
    vrsqh   lpRsqI[0], lpSumI[4]
    addi    curLight, curLight, 2 * lightSize // Iters: -2, 0, 2, ...
    vrsql   lpRsqF[4], lpSumF[4]
    lw      $20, (ltBufOfs + 8 + 2 * lightSize)(curLight) // First iter = light 0
    vrsqh   lpRsqI[4], $v31[2]       // 0
    lw      $24, (ltBufOfs + 8 + 3 * lightSize)(curLight) // First iter = light 1
    vmudh   $v29, lpMdl, lpMdl       // Squared
    sub     $10, curLight, altBaseReg // Is curLight (write ptr) <= 0?
    vreadacc lpSqrF, ACC_MIDDLE      // Read not-clamped value
    sub     $11, curLight, ambLight  // Is curLight (write ptr) <, =, or > ambient light?
    vreadacc lpSqrI, ACC_UPPER
    sw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Store light 0
    vmudm   $v29,    lpMdl2, lpRsqF[0h] // Vec int * frac scaling
    sw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Store light 1
    vmadh   lpFinal, lpMdl2, lpRsqI[0h] // Vec int * int scaling
    lpv     lpWrld[0], (tempXfrmLt)(rdpCmdBufEndP1) // Load dirs 0-2, 4-6
    vmudm   $v29, vOne, lpSqrF[2h]  // Sum of squared components
    vmadh   $v29, vOne, lpSqrI[2h]
    vmadm   $v29, vOne, lpSqrF[1h]
    vmadh   $v29, vOne, lpSqrI[1h]
    spv     lpFinal[0], (tempXfrmLt)(rdpCmdBufEndP1) // Store elem 0-2, 4-6 as bytes to temp memory
    vmadn   lpSumF, lpSqrF,  vOne     // elem 0, 4; swapped so we can do vmadn and get result
    lw      $20, (tempXfrmLt)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vmadh   lpSumI, lpSqrI,  vOne
    lw      $24, (tempXfrmLt + 4)(rdpCmdBufEndP1) // Load 3 (4) bytes to scalar unit
    vcopy   lpMdl2, lpMdl
    blez    $10, xfrm_light_store_lookat // curLight = -2 or 0
     vmudh  $v29, $v8,  lpWrld[0h]
     // 20 cycles from xfrm_light_loop_2 not counting land
    vmadh   $v29, $v9,  lpWrld[1h]
    bgtz    $11, ltbasic_setup_after_xfrm // curLight > ambient; only one light valid
     sw     $20, (ltBufOfs + 0xC - 2 * lightSize)(curLight) // Write light relative -2
    vmadn   $v29, $v16, lpWrld[0h]
    bltz    $11, xfrm_light_loop_1   // curLight < ambient; more lights to compute
     sw     $24, (ltBufOfs + 0xC - 1 * lightSize)(curLight) // Write light relative -1
ltbasic_setup_after_xfrm:
    // Constants registers:
    //       e0     e1     e2     e3     e4     e5     e6     e7
    // vLTC  0xF800 Lt1 Z  AOAmb  AODir  Lt1 X  Lt1 Y  AOAmb  AODir
    // $v30  SOffs  TOffs  0/AOa  Persp  SOffs  TOffs  0x0020 0x0800
    lpv     vLTC[0], (ltBufOfs + 8 - lightSize)(ambLight) // First lt xfrmed dir in elems 4-6
    li      vLoopRet, ltbasic_start_standard
    andi    $11, vGeomMid, (G_AMBOCCLUSION | G_PACKED_NORMALS | G_LIGHTTOALPHA | G_TEXTURE_GEN) >> 8
    vmov    $v30[2], $v31[2] // 0 as AO alpha offset
    vmov    vLTC[1], vLTC[6] // Move first lt Z to elem 1; watch stall on vLTC load
    beqz    $11, vtx_after_lt_setup  // None of the above features enabled
     li     lbAfter, vtx_return_from_lighting
    andi    $11, vGeomMid, G_TEXTURE_GEN >> 8
    beqz    $11, @@skip_texgen
     andi   $10, vGeomMid, G_PACKED_NORMALS >> 8
    li      lbAfter, -0x8000 | ltbasic_texgen // Negative is used as flag
@@skip_texgen:
    beqz    $10, @@skip_packed
     move   lbTexgenOrRet, lbAfter
    // Packed normals setup
    sbv     $v31[15], (3)(lbFakeAmb)  // 0xFF; Set ambient "alpha" to FF / 7F80
    vmov    $v30[6], $v31[2] // 0; clear element 6, will overwrite second byte of it below
    sbv     $v31[15], (7)(lbFakeAmb)  // 0xFF; so vpLtTot alpha ~= 7FFF, so * vtx alpha
    li      lbAfter, ltbasic_packed
    li      vLoopRet, ltbasic_start_packed
    lsv     vLTC[0], (packedNormalsMaskConstant - altBase)(altBaseReg) // 0xF800; cull mode already zeroed
    llv     $v30[13], (packedNormalsConstants - altBase)(altBaseReg) // 00[20 0800 OB]; out of bounds truncates
@@skip_packed:
    andi    $11, vGeomMid, G_LIGHTTOALPHA >> 8
    beqz    $11, @@skip_l2a
     andi   $10, vGeomMid, G_AMBOCCLUSION >> 8
    li      lbAfter, ltbasic_l2a
@@skip_l2a:
    beqz    $10, vtx_after_lt_setup
     // AO setup
     move   lbPostAo, lbAfter // Harmless to be done even if not AO
    addi    lbFakeAmb, rdpCmdBufEndP1, tempAmbient  // Temp mem as ambient light
    vmov    $v30[2], $v31[7] // 7FFF as AO alpha offset
    spv     vOne[0], (0)(lbFakeAmb) // Store all zeros here (upper bytes of vOne are 0)
    llv     vLTC[4], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 2, 3
    llv     vLTC[12], (aoAmbientFactor - altBase)(altBaseReg) // Ambient and dir to elems 6, 7
    j       vtx_after_lt_setup
     li     lbAfter, ltbasic_ao
    
.align 8
xfrm_light_store_lookat:
    vmadh   $v29, $v9,  lpWrld[1h]
    spv     lpFinal[0], (xfrmLookatDirs)($zero) // Store lookat. 1st time garbage, 2nd real
    vmadn   $v29, $v16, lpWrld[0h]
    j       xfrm_light_loop_2
     vmadn  $v29, $v18, lpWrld[2h]

// Lighting within vertex loop

.macro instan_lt_vec_1
    vmadh   $v29, vMTX1I, vpMdl[1h]
.endmacro
.macro instan_lt_vec_2
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
.endmacro
.macro instan_lt_vec_3
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
.endmacro
// lDOT <- vpMdl
.macro instan_lt_scl_1
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
.endmacro
.macro instan_lt_scl_2
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
.endmacro
// sFOG <- lCOL
.macro instan_lt_vs_45
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    sh      flagsV1, (VTX_CLIP      )(outVtx1) // Store first vertex flags
.endmacro

.align 8

// If lighting, vLoopRet = ltbasic_start_packed if packed, else ltbasic_start_standard

ltbasic_start_packed:
    instan_lt_vec_1
    instan_lt_vec_2
    instan_lt_vec_3
    vand    vpNrmlX, vpMdl, vLTC[0]  // 0xF800; mask X to only top 5 bits
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load RGBA
    vmudn   vpNrmlY, vpMdl, $v30[6]  // (1 << 5) = 0x0020; left shift normals Y
    j       ltbasic_after_start
     vmudn  vpNrmlZ, vpMdl, $v30[7]  // (1 << 11) = 0x0800; left shift normals Z

.align 8
ltbasic_start_standard:
    // Using elem 3, 7 for regular normals because packed normal results are there.
    instan_lt_vec_1
    lpv     vpNrmlX[3], (tempVpRGBA)(rdpCmdBufEndP1) // X to elem 3, 7
    instan_lt_vec_2
    lpv     vpNrmlY[2], (tempVpRGBA)(rdpCmdBufEndP1) // Y to elem 3, 7
    instan_lt_vec_3
    lpv     vpNrmlZ[1], (tempVpRGBA)(rdpCmdBufEndP1) // Z to elem 3, 7
    vnop
    luv     lVCI[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Load vertex color input
ltbasic_after_start:
    vmulf   $v29,  vpNrmlX, vLTC[4] // Normals X elems 3, 7 * first light dir X
// lDIR <- (NOC: -, Occ: sOTM)
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(ambLight) // Xfrmed dir in elems 4-6; temp reg
    vmacf   $v29,  vpNrmlY, vLTC[5] // Normals Y elems 3, 7 * first light dir Y
    luv     vpLtTot,    (0)(lbFakeAmb)  // Total light level, init to ambient or zeros if AO
// lDOT <- (NOC: vpMdl, Occ: sCLZ)
    vmacf   lDOT, vpNrmlZ, vLTC[1] // Normals Z elems 3, 7 * first light dir Z
    instan_lt_scl_1  // $11 can be used as a temporary, except b/w instan_lt_scl_1...
    vsub    lVCI, lVCI, $v30[2] // Offset alpha for AO, or 0 normally
    instan_lt_scl_2 // ...and instan_lt_scl_2
// lCOL <- (Occ: sFOG here / NOC: sSCI earlier)
    // vnop
    beq     ambLight, altBaseReg, ltbasic_post
     move   curLight, ambLight                   // Point to ambient light
ltbasic_loop:
    vge     lDTC, lDOT, $v31[2] // 0; clamp dot product to >= 0
    vmulf   $v29,  vpNrmlX, lDIR[4] // Normals X elems 3, 7 * next light dir
    luv     lCOL,   (ltBufOfs + 0 - 1*lightSize)(curLight) // Light color
    vmacf   $v29,  vpNrmlY, lDIR[5] // Normals Y elems 3, 7 * next light dir
    addi    curLight, curLight, -lightSize
    vmacf   lDOT, vpNrmlZ, lDIR[6] // Normals Z elems 3, 7 * next light dir
    lpv     lDIR[0], (ltBufOfs + 8 - 2*lightSize)(curLight) // Xfrmed dir in elems 4-6; DOES dual-issue
    vmudh   $v29, vOne, vpLtTot // Load accum mid with current light level
    bne     curLight, altBaseReg, ltbasic_loop
     vmacf  vpLtTot, lCOL, lDTC[3h] // + light color * dot product
ltbasic_post:
// (NOC: sFOG here / Occ: vpClpI later) <- lCOL
    instan_lt_vs_45
    vne     $v29, $v31, $v31[3h]           // Set VCC to 11101110
    jr      lbAfter
// vpRGBA <- lDIR
     vmrg   vpRGBA, vpLtTot, lVCI  // RGB = light, A = vtx alpha

// lbAfter       = ltbasic_ao if AO else
// lbPostAo      = ltbasic_l2a if L2A else
//                 ltbasic_packed if packed else
// lbTexgenOrRet = ltbasic_texgen if texgen else
//                 vtx_return_from_lighting
     
ltbasic_ao:
    vmudn   $v29, vLTC, lVCI[3h]      // (aoAmb 2 6, aoDir 3 7) * (alpha - 1)
    luv     vpRGBA, (ltBufOfs + 0)(ambLight)  // Ambient light level
    vmadh   lDTC, vOne, $v31[7]       // + 0x7FFF (1 in s.15)
    vadd    lVCI, lVCI, $v31[7]       // 0x7FFF; undo offset alpha
    vmulf   $v29, vpLtTot, lDTC[3h]   // Sum of dir lights *= dir factor
    vmacf   vpLtTot, vpRGBA, lDTC[2h] // + ambient * amb factor
    jr      lbPostAo                  // Return, texgen, l2a, or packed
     vmacf  vpRGBA, $v31, $v31[2]     // 0; need it in vpRGBA if returning, else in vpLtTot
     
ltbasic_l2a:
    // Light-to-alpha (cel shading): alpha = max of light components, RGB = vertex color
    vge     vpLtTot, vpLtTot, vpLtTot[1h] // elem 0 = max(R0, G0); elem 4 = max(R1, G1)
    vge     vpLtTot, vpLtTot, vpLtTot[2h] // elem 0 = max(R0, G0, B0); equiv for elem 4
    vne     $v29, $v31, $v31[3h]          // Reset VCC to 11101110 (clobbered by vge)
    jr      lbTexgenOrRet
     vmrg   vpRGBA, lVCI, vpLtTot[0h]     // RGB is vcol (garbage if not packed); A is light
    
ltbasic_packed:
    bgez    lbTexgenOrRet, vtx_return_from_lighting // < 0 for texgen
     vmulf  vpRGBA, vpLtTot, lVCI      // (Light color, 7FFF alpha) * vertex RGBA.
ltbasic_texgen:
// Texgen: in vpNrmlX:Y:Z; temps vpLtTot, lDOT, lDTC; out vpST.
lLkDrs equ lDTC    // lighting Lookat Directions
lLkDt0 equ vpLtTot // lighting Lookat Dot product 0
lLkDt1 equ lDOT    // lighting Lookat Dot product 1
    lpv     lLkDrs[0], (xfrmLookatDirs + 0)($zero) // Lookat 0 in 0-2, 1 in 4-6
.macro texgen_dots, lookats, dot0, dot1
    vmulf   $v29, vpNrmlX, lookats[0]  // Normals X * lookat 0 X
    vmacf   $v29, vpNrmlY, lookats[1]  // Normals Y * lookat 0 Y
    vmacf   dot0, vpNrmlZ, lookats[2]  // Normals Z * lookat 0 Z
    vmulf   $v29, vpNrmlX, lookats[4]  // Normals X * lookat 1 X
    vmacf   $v29, vpNrmlY, lookats[5]  // Normals Y * lookat 1 Y
    vmacf   dot1, vpNrmlZ, lookats[6]  // Normals Z * lookat 1 Z
.endmacro
    texgen_dots lLkDrs, lLkDt0, lLkDt1
// In ltbasic, normals are in elems 3, 7; in ltadv, elems 0, 4
    vmudh   lLkDt0, vOne, lLkDt0[3h] // Move dot 0 from elems 3, 7 to 0, 4
.macro texgen_body, lookats, dot0, dot1, normalselem, branch_no_texgen_linear
// lookats now holds texgen linear coefficients elems 0, 1
    llv     lookats[0], (texgenLinearCoeffs - altBase)(altBaseReg)
    vne     $v29, $v31, $v31[1h]    // Set VCC to 10111011
    andi    $11, vGeomMid, G_TEXTURE_GEN_LINEAR >> 8
    vmrg    dot0, dot0, dot1[normalselem] // Dot products in elements 0, 1, 4, 5
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    beqz    $11, branch_no_texgen_linear
     vmacf  vpST, dot0, $v31[5]     // + dot products * 0x4000 ( / 2)
    // Texgen_Linear:
    vmulf   vpST, dot0, $v31[5]     // dot products * 0x4000 ( / 2)
// dot0 now holds lighting Lookat ST squared
    vmulf   dot0, vpST, vpST        // ST squared
    vmulf   $v29, vpST, $v31[7]     // Move ST to accumulator (0x7FFF = 1)
// dot1 now holds lighting Lookat Temp
    vmacf   dot1, vpST, lookats[1]  // + ST * 0x6CB3
    vmudh   $v29, vOne, $v31[5]     // 1 * 0x4000
    vmacf   vpST, vpST, lookats[0]  // + ST * 0x44D3
.endmacro
    texgen_body lLkDrs, lLkDt0, lLkDt1, 3h, vtx_return_from_texgen
    j       vtx_return_from_texgen
.macro texgen_lastinstr, dot0, dot1
     vmacf  vpST, dot0, dot1        // + ST squared * (ST + ST * coeff)
.endmacro
     texgen_lastinstr lLkDt0, lLkDt1

*/


tri_alpha_compare_cull:
// Alpha compare culling
    vge     $v26, tHAtI, tMAtI
    lbu     $19, alphaCompareCullThresh
    vlt     $v25, tHAtI, tMAtI
    bgtz    $11, @@skip1
     vge    $v26, $v26, tLAtI // If alphaCompareCullMode > 0, $v26 = max of 3 verts
    vlt     $v26, $v25, tLAtI // else if < 0, $v26 = min of 3 verts
@@skip1: // $v26 elem 3 has max or min alpha value
    mfc2    $24, $v26[6]
    sub     $24, $24, $19 // sign bit set if (max/min) < thresh
    xor     $24, $24, $11 // invert sign bit if other cond. Sign bit set -> cull,
    bgez    $24, tri_return_from_alpha_compare_cull // if max < thresh or if min >= thresh.
return_and_end_mat:
     tri_v1_move // overwrites $v6[1]
    jr      $ra
     nop

vtx_after_dma:
    mfc2    outVtxBase, $v8[6]                 // Address of output start
    andi    inVtx, dmemAddr, 0xFFF8            // Round down input start addr to DMA word
    sll     $11, vtxLeft, 12                   // Vtx count * 0x10000
    add     perfCounterA, perfCounterA, $11    // Add to vertex count
    // Sets up constants needed for vertex loop
    // Results fill vPerm1:4. Uses misc temps.
    ldv     sVPO[0], (viewport + 8)($zero)        // Load vtrans duplicated in 0-3 and 4-7
    ldv     sVPO[8], (viewport + 8)($zero)
    ldv     sVPS[0], (viewport)($zero)            // Load vscale duplicated in 0-3 and 4-7
    ldv     sVPS[8], (viewport)($zero)
    lsv     $v30[6], (perspNorm - altBase)(altBaseReg) // Perspective norm elem 3
    li      vLoopRet, vtx_loop_no_lighting
vtx_after_lt_setup:
    li      $11, cacheEnd - 0x50
    ldv     vMTX0I[0],  (0x00)($11)  // Load MVP matrix
    ldv     vMTX1I[0],  (0x08)($11)
    ldv     vMTX2I[0],  (0x10)($11)
    ldv     vMTX3I[0],  (0x18)($11)
    ldv     vMTX0F[0],  (0x20)($11)
    ldv     vMTX1F[0],  (0x28)($11)
    ldv     vMTX2F[0],  (0x30)($11)
    ldv     vMTX3F[0],  (0x38)($11)
    ldv     vMTX0I[8],  (0x00)($11) // TODO other matrix
    ldv     vMTX1I[8],  (0x08)($11)
    ldv     vMTX2I[8],  (0x10)($11)
    ldv     vMTX3I[8],  (0x18)($11)
    ldv     vMTX0F[8],  (0x20)($11)
    ldv     vMTX1F[8],  (0x28)($11)
    ldv     vMTX2F[8],  (0x30)($11)
    ldv     vMTX3F[8],  (0x38)($11)
    andi    fogFlag, vGeomMid, G_FOG >> 8  // Can't put before lt b/c fogFlag = mtx valid flag.
    srl     fogFlag, fogFlag, 5            // 8 if G_FOG is set, 0 otherwise
    addi    outVtx1, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
    addi    outVtx2, rdpCmdBufEndP1, tempPrevInvalVtx // Write prev loop vtx garbage here
    jal     while_wait_dma_busy  // Wait for vertex load to finish
     addi   outVtxBase, outVtxBase, -vtxSize   // Will inc by 2, but need point to 2nd
    ldv     vpMdl[0], (VTX_IN_OB + 0 * inputVtxSize)(inVtx) // 1st vec pos
    ldv     vpMdl[8], (VTX_IN_OB + 1 * inputVtxSize)(inVtx) // 2nd vec pos
    llv     sTCL[8],  (VTX_IN_CN + 0 * inputVtxSize)(inVtx) // RGBA in 4:5
    llv     sTCL[12], (VTX_IN_CN + 1 * inputVtxSize)(inVtx) // RGBA in 6:7
    llv     vpST[0],  (VTX_IN_TC + 0 * inputVtxSize)(inVtx) // ST in 0:1
    j       vtx_store_loop_entry
     llv    vpST[8],  (VTX_IN_TC + 1 * inputVtxSize)(inVtx) // ST in 4:5
     
align_with_warning 8, "One instruction of padding before vertex loop"

vtx_loop_no_lighting:
// lCOL <- sSCI
// lDTC <- sRTF
// lVCI <- sRTI
// vpLtTot <- s1WF
// vpNrmlX <- s1WI
    vmadh   $v29, vMTX1I, vpMdl[1h]
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpClpF, vMTX2F, vpMdl[2h]
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    vmadh   vpClpI, vMTX2I, vpMdl[2h]
    sh      flagsV1,        (VTX_CLIP      )(outVtx1) // Store first vertex flags
// lDOT <- vpMdl
// sFOG <- lCOL
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    luv     vpRGBA[0],    (tempVpRGBA)(rdpCmdBufEndP1) // Vtx pair RGBA
// sCLZ <- sTCL
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    addi    vtxLeft, vtxLeft, -2*inputVtxSize // Decrement vertex count by 2
vtx_return_from_lighting:
vtx_return_from_texgen:
    vmudl   $v29, vpClpF, $v30[3]       // Persp norm
    sub     $11, outVtx2, fogFlag       // Points 8 before outVtx2 if fog, else 0
// s1WI <- vpNrmlX
    vmadm   s1WI, vpClpI, $v30[3]       // Persp norm
    addi    outVtxBase, outVtxBase, 2*vtxSize // Points to SECOND output vtx
// s1WF <- vpLtTot
    vmadn   s1WF, $v31, $v31[2]         // 0
    sbv     sFOG[15], (VTX_COLOR_A + 8)($11) // In VTX_SCR_Y if fog disabled...
    vmov    vpScrF[1], sCLZ[2]
    sbv     sFOG[7],  (VTX_COLOR_A + 8 - vtxSize)($11) // ...which gets overwritten below
// sSCF <- lDOT
    vmudn   sSCF, vpClpF, $v31[3]        // W * clip ratio for scaled clipping
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
// sSCI <- sFOG
    vmadh   sSCI, vpClpI, $v31[3]        // W * clip ratio for scaled clipping
    slv     vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    vrcph   $v29[0], s1WI[3]
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
// sRTF <- lDTC
    vrcpl   sRTF[2], s1WF[3]
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
// sRTI <- lVCI
    vrcph   sRTI[3], s1WI[7]
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    vrcpl   sRTF[6], s1WF[7]
    sra     $11, vtxLeft, 31   // All 1s if on single-vertex last iter
    vrcph   sRTI[7], $v31[2] // 0
    andi    $11, $11, vtxSize  // vtxSize if on single-vertex last iter, else normally 0
    vch     $v29, vpClpI, vpClpI[3h] // Clip screen high
    sub     outVtx2, outVtxBase, $11 // First output vtx on last iter, else second
    vcl     $v29, vpClpF, vpClpF[3h] // Clip screen low
    addi    outVtx1, outVtxBase, -vtxSize  // First output vtx always
    vmudl   $v29, s1WF, sRTF[2h]
    cfc2    flagsV1, $vcc                   // Screen clip results
    vmadm   $v29, s1WI, sRTF[2h]
    // nop
    vmadn   s1WF, s1WF, sRTI[3h]
// sTCL <- sCLZ
    ldv     sTCL[0],   (VTX_IN_TC + 2 * inputVtxSize)(inVtx) // ST in 0:1, RGBA in 2:3
    vmadh   s1WI, s1WI, sRTI[3h]
    // nop
    vch     $v29, vpClpI, sSCI[3h] // Clip scaled high
    // nop
    vmudh   $v29, vOne, $v31[4]  // 4
    // nop
    vmadn   s1WF, s1WF, $v31[0]  // -4
    // nop
    vmadh   s1WI, s1WI, $v31[0]  // -4
    // nop
    vcopy   sST2, vpST
    ldv     sTCL[8],   (VTX_IN_TC + 3 * inputVtxSize)(inVtx) // ST in 4:5, RGBA in 6:7
// sST2 <- vpScrI
    // vnop
    suv     vpRGBA[4],  (VTX_COLOR_VEC )(outVtx2) // Store RGBA for second vtx
    vmudl   $v29, s1WF, sRTF[2h]
    // nop
    vmadm   $v29, s1WI, sRTF[2h]
    suv     vpRGBA[0],  (VTX_COLOR_VEC )(outVtx1) // Store RGBA for first vtx
    vmadn   s1WF, s1WF, sRTI[3h]
    // nop
    vmadh   s1WI, s1WI, sRTI[3h]
    srl     flagsV2, flagsV1, 4            // Shift second vertex screen clipping to first slots
    vcl     $v29, vpClpF, sSCF[3h] // Clip scaled low
    andi    flagsV2, flagsV2, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vcopy   vpST, sTCL
    cfc2    $11, $vcc                   // Scaled clip results
    vmudl   $v29, vpClpF, s1WF[3h] // Pos times inv W
    ssv     s1WF[14],          (VTX_INV_W_FRAC)(outVtx2)
    vmadm   $v29, vpClpI, s1WF[3h] // Pos times inv W
// vpMdl <- sSCF
    ldv     vpMdl[0], (VTX_IN_OB + 2 * inputVtxSize)(inVtx) // Pos of 1st vector for next iteration
    vmadn   vpClpF, vpClpF, s1WI[3h]
    ldv     vpMdl[8], (VTX_IN_OB + 3 * inputVtxSize)(inVtx) // Pos of 2nd vector on next iteration
    vmadh   vpClpI, vpClpI, s1WI[3h] // vpClpI:vpClpF = pos times inv W
    addi    inVtx, inVtx, (2 * inputVtxSize) // Advance two positions forward in the input vertices
    vmov    sTCL[4], vpST[2] // First vtx RG to elem 4
    andi    flagsV1, flagsV1, CLIP_SCRN_NPXY | CLIP_CAMPLANE // Mask to only screen bits we care about
    vmov    sTCL[5], vpST[3] // First vtx BA to elem 5
    sll     $10, $11, 4            // Shift first vertex scaled clipping to second slots
    vmudl   $v29, vpClpF, $v30[3] // Persp norm
    ssv     s1WF[6],           (VTX_INV_W_FRAC)(outVtx1)
    vmadm   vpClpI, vpClpI, $v30[3] // Persp norm
    ssv     s1WI[14],          (VTX_INV_W_INT )(outVtx2)
    vmadn   vpClpF, $v31, $v31[2] // 0; Now vpClpI:vpClpF = projected position
    ssv     s1WI[6],           (VTX_INV_W_INT )(outVtx1)
    // vnop  // TODO maybe can rotate the loop so this is the jr land slot?
    slv     sST2[8],           (VTX_TC_VEC    )(outVtx2) // Store scaled S, T vertex 2
    vmudh   $v29, sVPO, vOne // offset * 1
    slv     sST2[0],           (VTX_TC_VEC    )(outVtx1) // Store scaled S, T vertex 1
    // vnop
    andi    $11, $11, CLIP_SCAL_NPXY // Mask to only bits we care about
    vmadn   vpScrF, vpClpF, sVPS   // + pos frac * scale
    or      flagsV2, flagsV2, $11    // Combine results for second vertex
// vpScrI <- sST2
    vmadh   vpScrI, vpClpI, sVPS   // int part, vpScrI:vpScrF is now screen space pos
    sh      flagsV2,           (VTX_CLIP      )(outVtx2) // Store second vertex clip flags
vtx_store_loop_entry:
    vmudn   $v29, vMTX3F, vOne
    blez    vtxLeft, vtx_epilogue
     vmadh  $v29, vMTX3I, vOne
    vmadn   $v29, vMTX0F, vpMdl[0h]
    sdv     sTCL[8],      (tempVpRGBA)(rdpCmdBufEndP1) // Vtx 0 and 1 RGBA in order
    vmadh   $v29, vMTX0I, vpMdl[0h]
    jr      vLoopRet
     vmadn  $v29, vMTX1F, vpMdl[1h]
    
vtx_epilogue:
    vge     sFOG, vpScrI, $v31[6]  // Clamp W/fog to >= 0x7F00 (low byte is used)
    andi    $10, $10, CLIP_SCAL_NPXY // Mask to only bits we care about
    vge     sCLZ, vpScrI, $v31[2]              // 0; clamp Z to >= 0
    or      flagsV1, flagsV1, $10          // Combine results for first vertex
    beqz    fogFlag, @@skip_fog
     slv    vpScrI[8],  (VTX_SCR_VEC    )(outVtx2)
    sbv     sFOG[15], (VTX_COLOR_A    )(outVtx2)
    sbv     sFOG[7],  (VTX_COLOR_A    )(outVtx1)
@@skip_fog:
    vmov    vpScrF[1], sCLZ[2]
    ssv     sCLZ[12], (VTX_SCR_Z      )(outVtx2)
    slv     vpScrI[0],  (VTX_SCR_VEC    )(outVtx1)
    ssv     vpScrF[12], (VTX_SCR_Z_FRAC )(outVtx2)
    slv     vpScrF[2],  (VTX_SCR_Z      )(outVtx1)
    sh      flagsV1, (VTX_CLIP)(outVtx1) // Store first vertex flags
    j       run_next_DL_command
     lqv    vTRC, (vTRCValue)($zero)         // Restore value overwritten by matrix


endFreeImemAddr equ 0x1FC4
startFreeImem:
.if . > endFreeImemAddr
    .error "Out of IMEM space"
.endif
.org endFreeImemAddr
endFreeImem:

wait_goto_next_ra:
    move    $ra, nextRA
    // Fallthrough to while_wait_dma_busy
    
.if . != 0x1FC8
    // This has to be at this address for boot and S2DEX compatibility
    .error "Error in organization of end of IMEM"
.endif

// The code from here to the end is shared with S2DEX, so great care is needed for changes.
while_wait_dma_busy:
    mfc0    $11, SP_DMA_BUSY    // Load the DMA_BUSY value
@@while_dma_busy:
    bnez    $11, @@while_dma_busy // Loop until DMA_BUSY is cleared
     mfc0   $11, SP_DMA_BUSY      // Update DMA_BUSY value
old_return_routine:
    jr      $ra
     // Has mfc0 in branch delay slot, causes a stall if first instr after ret is load

dma_read_write:
shared_dma_read_write:
     mfc0   $11, SP_DMA_FULL          // load the DMA_FULL value
@@while_dma_full:
    bnez    $11, @@while_dma_full     // Loop until DMA_FULL is cleared
     mfc0   $11, SP_DMA_FULL          // Update DMA_FULL value
dma_read_write_not_full:
    mtc0    dmemAddr, SP_MEM_ADDR     // Set the DMEM address to DMA from/to
    bltz    dmemAddr, dma_write       // If the DMEM address is negative, this is a DMA write, if not read
     mtc0   cmd_w1_dram, SP_DRAM_ADDR // Set the DRAM address to DMA from/to
    jr      $ra
     mtc0   dmaLen, SP_RD_LEN         // Initiate a DMA read with a length of dmaLen
dma_write:
    jr      $ra
     mtc0   dmaLen, SP_WR_LEN         // Initiate a DMA write with a length of dmaLen

.if . != 0x00002000
    .error "Code at end of IMEM shared with other ucodes has been corrupted"
.endif

.headersize 0x00001000 - orga()

ovl0_start:
    jal     flush_rdp_buffer   // See G_FLUSH_handler for docs on these 3 instructions.
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1
    jal     flush_rdp_buffer
     add    taskDataPtr, taskDataPtr, inputBufferPos // inputBufferPos <= 0; taskDataPtr was where in the DL after the current chunk loaded
    sw      perfCounterA, cpuInterface + 0x0
    sw      perfCounterB, cpuInterface + 0x4
    sw      perfCounterC, cpuInterface + 0x8
    sw      perfCounterD, cpuInterface + 0xC
    li      $10, SP_SET_SIG2   // task done signal
    mtc0    $10, SP_STATUS
    break   0
    nop

ovl0_end:
.align 8
ovl0_padded_end:

.if ovl0_padded_end > ovl01_end
    .error "Automatic resizing for overlay 0 failed"
.endif

// overlay 1
.headersize 0x00001000 - orga()

ovl1_start:

G_ENDDL_handler:
    lbu     $7, displayListStackDepth       // Load the DL stack index; if end stack,
    beqz    $7, load_overlay_0_and_enter    // load overlay 0; $7 == -4 signals end
     addi   $7, $7, -4                      // Decrement the DL stack index
    j       call_ret_common                 // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($7) // Load addr of DL to return to

/* This is a crazy optimization, and it was completely accidental!
When G_RELSEGMENT was implemented, we did not notice the G_MOVEWORD behavior of
subtracting (G_MOVEWORD << 8) from the movewordTable address in order to remove
the command byte. Since the command byte is G_RELSEGMENT, not G_MOVEWORD, the
final address is completely wrong. However, DMEM wraps at 4 KiB--only the lowest
4 bits of any address are significant. And, G_RELSEGMENT **happened** to end in
0xB, the same as G_MOVEWORD! So the wrong address aliases to the correct one!
I only noticed this when I tried to move G_RELSEGMENT to a different command
byte and got crashes. */
.if (G_RELSEGMENT & 0xF) != (G_MOVEWORD & 0xF)
    .error "Crazy relsegment optimization broken, don't change command byte assignments"
.endif
G_RELSEGMENT_handler: // 9
    jal     segmented_to_physical    // Resolve new segment address relative to existing segment
G_MOVEWORD_handler:
     srl    $2, cmd_w0, 16           // load the moveword command and word index into $2 (e.g. 0xDB06 for G_MW_SEGMENT)
    lhu     $10, (movewordTable - ((G_MOVEWORD & 0xF) << 8))($2) // subtract the moveword label and offset the word table by the word index (e.g. 0xDB06 becomes 0x0304)
    sll     $11, cmd_w0, 16          // Sign bit = upper bit of offset
    add     $10, $10, cmd_w0         // Offset + base; only lower 12 bits matter
    bltz    $11, run_next_DL_command // If upper bit of offset is set, exit after halfword
     sh     cmd_w1_dram, ($10)       // Store value from cmd into halfword
    j       run_next_DL_command
     sw     cmd_w1_dram, ($10)       // Store value from cmd into word (offset + moveword_table[index])

G_TEXRECT_handler: // 3; should be towards the start of ovl1
    j       run_next_DL_command
     spv    $v4[0], (texrectState)($zero)

G_GEOMETRYMODE_handler: // 6
    lw      $11, geometryModeLabel        // load the geometry mode value
    and     $11, $11, cmd_w0              // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      cmd_w1_dram, cmd_w1_dram, $11 // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    srl     vGeomMid, cmd_w1_dram, 8      // Middle 2 bytes of geom mode to lower 16 bits. Ordered this way to avoid stalls.
G_RDPHALF_1_handler: // $ra = ., 0x10 ahead of geometry mode
.if (G_RDPHALF_1_handler - G_GEOMETRYMODE_handler) != (rdpHalf1Val - geometryModeLabel)
    .error "G_RDPHALF_1 optimization broken"
.endif
    j       run_next_DL_command
     sw     cmd_w1_dram, (geometryModeLabel - G_GEOMETRYMODE_handler)($ra)

ovl1_end:
align_with_warning 8, "One instruction of padding at end of ovl1"
ovl1_padded_end:

.if ovl1_padded_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif
// Currently want exactly 92 instructions (based on current size of start)
.if ovl1_padded_end > start_padded_end
    warn_if_base "ovl1 is larger than start, try to move something out"
.endif
.if ovl1_padded_end < start_padded_end
    warn_if_base "ovl1 is smaller than start, wasting space!"
.endif

.close // CODE_FILE
