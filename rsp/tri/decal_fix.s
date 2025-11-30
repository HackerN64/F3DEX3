tri_decal_fix_z:
    // Valid range of tHAtI = 0 to 7FFF, but most of the scene is large values
    vmudh   $v29, vOne, vTRC_DO  // accum all elems = -DM/2
    vmadm   $v25, tHAtI, vTRC_DM // elem 7 = (0 to DM/2-1) - DM/2 = -DM/2 to -1
    vcr     tDaDyI, tDaDyI, $v25[7] // Clamp DzDyI (6) to <= -val or >= val; clobbers DzDyF (7)
    j       tri_return_from_decal_fix_z
     set_vcc_11110001 // Clobbered by vcr
