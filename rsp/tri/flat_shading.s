tri_flat_shading:
    vlt     $v29, $v31, $v31[3]       // Set vcc to 11100000
    vmrg    tHAtI, $v25, tHAtI        // RGB from original vtx 1, alpha from $1
    vmrg    tMAtI, $v25, tMAtI        // RGB from original vtx 1, alpha from $2
    j       tri_return_from_flat_shading
     vmrg   tLAtI, $v25, tLAtI        // RGB from original vtx 1, alpha from $3
