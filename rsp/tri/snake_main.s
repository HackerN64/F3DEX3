align_with_warning 8, "One instruction of padding before tri snake"

.macro snake_c_to_v30
    lpv     $v30[1], (inputBufferEndSgn)(inputBufferPos) // c (pos+1) to elem 2
.endmacro

// Index = bits 1-6; direction flag = bit 0; end flag = bit 7
// CM 02 01 03 04 05 06 07
//               [bb cc]   Indices b and c
//                |
//                inputBufferPos + inputBufferEnd
tri_snake_ret_from_input_buffer:
    lpv     $v30[2], (inputBufferEndSgn)(inputBufferPos) // c (pos+0) to elem 2
    lbu     $3, (inputBufferEnd)(inputBufferPos) // Load c; clear real index b sign bit -> don't exit
    j       tri_snake_loop_from_input_buffer // inputBufferPos pointing to first byte loaded
G_TRISNAKE_handler:
     li     $ra, tri_snake_loop          // For both init and above (clobbered by DMA).
    lpv     $v30[7], (inputBufferEndSgn - 0x10)(inputBufferPos) // 03 to elem 2; becomes new origV1Addr
    slv     $v7[4], (rdpHalf1Val - altBase)(altBaseReg) // Store past addrs b, c (01 03)
    addi    inputBufferPos, inputBufferPos, -6 // Point to byte 2: looks at done flag from 01 and dir flag from 03
    mfc2    origV1Addr, $v7[2]           // 02; will get stored below as c
tri_snake_loop:
    // $v30 elem 2 has new index c, which will become new origV1Addr.
    // origV1Addr has last one, which gets stored to the V2 or V3 spot.
    lh      $3, (inputBufferEnd)(inputBufferPos) // Load indices b and c
    addi    inputBufferPos, inputBufferPos, 1  // Increment indices being read
tri_snake_loop_from_input_buffer:
    vand    $v6, $v30, vTRC_7E00         // Mask out dir flag and end flag
    vmudn   $v29, vOne, vTRC_VB          // Address of vertex buffer
    beqz    inputBufferPos, tri_snake_over_input_buffer // == 0 at end of input buffer
     andi   $11, $3, 1                   // Get direction flag from index c
    sll     $11, $11, 1                  // Halfword address
    snake_c_to_v30
    vmadl   $v6, $v6, vTRC_VS            // Plus vtx indices times length
    sh      origV1Addr, (rdpHalf1Val)($11) // Store old v1 as 2 if dir clear or 3 if set
    bltz    $3, tri_snake_end            // Upper bit of real index b set = done
     llv    $v7[4], (rdpHalf1Val - altBase)(altBaseReg) // Load addresses 2, 3 to elem 2, 3
    mfc2    origV1Addr, $v6[4]           // In elem 2 (not elem 1 like 1tri)
    j       tri_from_snake          // Repeat next instr so we can skip lbu origV1Addr
     lh     $2, (rdpHalf1Val + 0)($zero)
     