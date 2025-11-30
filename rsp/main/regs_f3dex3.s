////////////////////////////////////////////////////////////////////////////////
/////////////////////////////// Register Naming ////////////////////////////////
////////////////////////////////////////////////////////////////////////////////

#include "rsp/regs.s"

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

// Tri write:
origV1Addr     equ $4    // Original / current vertex 1 address
flatV1Offset   equ $16   // Offset +'d to vtx 1 addr for flat shading. 0 except in clipping.

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

// Clipping across walk - vertex write - tri write:
clipAlloc      equ $2    // Whether each temp vtx is in use, during VW
clipPtrs       equ $6    // On-off-gen vtx ptrs for each subdivision, during VW
clipMaskIdx    equ $21   // Selects clipping plane / mask index, 4 -> 0
clipDrawPtr    equ $21   // Pointer to output clip polygon during tri draw
clipVOnsc      equ $20   // Onscreen vertex, only during setup for vtx write
clipVOffsc     equ $24   // Offscreen vertex, only during setup for vtx write

// Clip walk only:
clipIdx        equ $1    // Current index within polygon memory, 0 -> E
clipTempVtx    equ $3    // Allocated temporary vertex address
clipWalkCount  equ $7    // How many steps taken around polygon; if too many, timeout
clipLastVtx    equ $8    // Last vertex address on polygon
clipCurVtx     equ $19   // Current vertex address on polygon
clipMaskShift  equ $20   // Amount to left shift clip flags to put current condition bit in sign bit
clipWalkPhase  equ $24   // Current action on walk: e.g. looking for onscreen-to-offscreen transition

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
.if CFG_NO_OCCLUSION_PLANE
// vpClpI:F are kept, vpMdl is free to use as temp
lDOT equ vpMdl  // lighting DOT product
lCOL equ vKept2 // lighting total light COLor
.else
// vpMdl is kept, these are free to use as temps
lDOT equ vpClpF
lCOL equ vpClpI
.endif
lDTC equ vTemp1  // lighting DoT Clamped
lVCI equ vTemp2  // lighting Vertex Color In
lDIR equ vpRGBA  // lighting transformed light DIRection

// Kept
.if CFG_NO_OCCLUSION_PLANE
sCLZ equ vKept1 // vtx_store Clamped Z. Does have to be kept even though in instan_lt_vs_45 b/c need rest of lt temps at start of texgen (and advanced lighting).
sOCS equ $v29   // Does not exist
.else
sOCS equ vKept1 // vtx_store Occlusion State
sCLZ equ vpClpF // Not a kept in this config
.endif

// Common vertex temporaries
sRTF equ vTemp1  // vtx_store Reciprocal Temp Frac
sRTI equ vTemp2  // vtx_store Reciprocal Temp Int
sFOG equ lCOL // lCOL -> sFOG in lt epilogue with NOC, else sFOG -> lCOL in lt prologue

// Misc temps used by both
.if CFG_NO_OCCLUSION_PLANE
s1WI equ vpNrmlX // vtx_store 1/W Int
s1WF equ vpLtTot // vtx_store 1/W Frac
sSCI equ sFOG    // vtx_store Scaled Clipping Int
sSCF equ vpMdl   // vtx_store Scaled Clipping Frac
sTCL equ sCLZ    // vtx_store Temp CoLor
.else
s1WI equ vpMdl
s1WF equ vpNrmlX
sSCI equ vpScrI
sSCF equ vpScrF
sTCL equ vpLtTot
.endif

// Misc temps used by only one
.if CFG_NO_OCCLUSION_PLANE
sST2 equ vpScrI  // vtx_store ST coordinates copy 2
sOTM equ $v29    // Does not exist
.else
sST2 equ $v29    // Does not exist
sOTM equ vpRGBA  // vtx_store Occlusion Temporary
.endif

// Permanently kept through vertex/lighting
.if CFG_NO_OCCLUSION_PLANE
sVPS equ vPerm1 // vtx_store ViewPort Scale
sVPO equ vPerm2 // vtx_store ViewPort Offset
sFGM equ vPerm3 // vtx_store FoG Mask
sO03 equ $v29   // Does not exist
sO47 equ $v29
sOCM equ $v29
sOPM equ $v29
.else
// These are temps, not permanents, on this codepath
sVPS equ vpScrI // Temp, not permament, on this codepath
sVPO equ vpScrF // Temp, not permament, on this codepath
sFGM equ $v29   // Does not exist
sO03 equ vPerm1 // vtx_store Occlusion plane edge coefficients 0-3
sO47 equ vPerm2 // vtx_store Occlusion plane edge coefficients 4-7
sOCM equ vPerm3 // vtx_store Occlusion plane Mid coefficients
sOPM equ vKept2 // vtx_store Occlusion Plus Minus. Loaded in vtx_after_lt_setup not vtx_constants_for_clip b/c clobbered by lighting.
.endif
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


