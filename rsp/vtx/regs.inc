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
