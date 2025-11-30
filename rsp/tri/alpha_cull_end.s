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
tri_culled_by_occlusion_plane:
.if CFG_PROFILING_B
     nop
    addi    perfCounterB, perfCounterB, 0x4000
.endif
return_and_end_mat:
     tri_v1_move // overwrites $v6[1]
    jr      $ra
     sb     $zero, materialCullMode // This covers all tri early exits except clipping
