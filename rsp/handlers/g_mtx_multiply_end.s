G_MTX_multiply_end:
     li     $ra, run_next_DL_command // Dual use for above and below
    lhu     $3, (movememTable - G_MV_TEMPMTX0)($3) // $3=2->0=M; $3=6->4=VP
    move    $2, $3 // Input 0 = output
mtx_multiply:
    // $2 and dmemAddr are input matrices; $3 is output matrix
    addi    $10, dmemAddr, 0x0018
@@loop:
    vmadn   $v7, $v31, $v31[2]  // 0
    addi    $11, dmemAddr, 0x0008
    vmadh   $v6, $v31, $v31[2]  // 0
    addi    $2, $2, -0x0020
    vmudh   $v29, $v31, $v31[2] // 0
@@innerloop:
    ldv     $v3[0], 0x0040($2)
    ldv     $v3[8], 0x0040($2)
    lqv     vTemp2[0], 0x0020(dmemAddr) // Input 1
    ldv     $v2[0], 0x0020($2)
    ldv     $v2[8], 0x0020($2)
    lqv     vTemp1[0], 0x0000(dmemAddr) // Input 1
    vmadl   $v29, $v3, vTemp2[0h]
    addi    dmemAddr, dmemAddr, 0x0002
    vmadm   $v29, $v2, vTemp2[0h]
    addi    $2, $2, 0x0008 // Increment input 0 pointer
    vmadn   $v5, $v3, vTemp1[0h]
    bne     dmemAddr, $11, @@innerloop
     vmadh  $v4, $v2, vTemp1[0h]
    bne     dmemAddr, $10, @@loop
     addi   dmemAddr, dmemAddr, 0x0008
    sqv     $v7[0], (0x0020)($3)
    sqv     $v6[0], (0x0000)($3)
    sqv     $v4[0], (0x0010)($3)
    jr      $ra
     sqv    $v5[0], (0x0030)($3)
