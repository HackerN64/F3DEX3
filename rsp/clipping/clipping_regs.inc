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


cPosOnOfF equ vpClpF
cPosOnOfI equ vpClpI
cPosOfF   equ vpScrF
cPosOfI   equ vpScrI
cRGBAOf   equ vpLtTot
cRGBAOn   equ vpRGBA
cSTOf     equ vpST
cSTOn     equ sSTS // Intentionally overwriting this kept reg. Vtx scales ST again, need to re-store unscaled value.
// Also uses sRTF, sRTI = vTemp1, vTemp2, and vtx_final_setup_for_clip sets sOPM = vKept2
cTemp     equ vpMdl
cBaseF    equ vpNrmlX
cBaseI    equ vpNrmlY
cDiffF    equ $v2
cDiffI    equ $v3
cRRF      equ $v4  // Range Reduction frac
cRRI      equ $v5  // Range Reduction int
cFadeOf   equ $v4
cFadeOn   equ $v5