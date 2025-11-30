// Lighting advanced scalar regs:
laPtr          equ $2    // Pointer to current vertex pair being lit
laVtxLeft      equ $3    // Count of vertices left * 0x10
laSpecFres     equ $4    // Nonzero if doing ltadv_normal_to_vertex for specular or Fresnel
laSTKept       equ $6    // Texture coords of vertex 1 kept through processing
laPacked       equ $7    // Nonzero if packed normals enabled
laSpecular     equ $8    // Sign bit set if specular enabled
laL2A          equ $19   // Nonzero if light-to-alpha (cel shading) enabled
laTexgen       equ $20   // Nonzero if texgen enabled

// ltadv vector regs:
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

