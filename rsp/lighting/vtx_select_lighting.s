align_with_warning 8, "One instruction of padding before ovl234"

vtx_select_lighting:
.if CFG_PROFILING_B
    srl     $11, vtxLeft, 4                  // Vertex count
    add     perfCounterA, perfCounterA, $11  // Add to number of lit vertices
.endif
    bltz    viLtFlag, ovl234_ltadv_entrypoint  // Advanced lighting if have point lights
     andi   $10, vGeomMid, (G_LIGHTING_SPECULAR | G_FRESNEL_COLOR | G_FRESNEL_ALPHA) >> 8
    bnez    $10, ovl234_ltadv_entrypoint  // Advanced lighting if specular or Fresnel
     lb     viLtFlag, dirLightsXfrmValid
    // Fallthrough to ltbasic on whichever overlay is loaded

.if (. & 4)
    .error "vtx_select_lighting must be an even number of instructions"
.endif
