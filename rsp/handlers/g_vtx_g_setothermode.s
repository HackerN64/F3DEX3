align_with_warning 8, "One instruction of padding before G_VTX_handler"

G_VTX_handler: // 21
    // Vertex command is 01 0H L0 ee, where n = HL (number of vertices).
    // $v5[1] = 0H * 13, $v5[2] = L0 * 13.
    // ($v5[2] >> 10) * 2 = 0L * 26 = $v8[2]
    // ($v5[1] << 10) * 2 = H0 * 26 = $v9[1]
    // In segmented_to_physical, add, now $v8[2] = HL * 26 = n * 26.
    // Currently $v7[3] = end addr = (v0 + n) * 26 + base
    // Subtract -> $v8[3] = v0 * 26 + base = start addr.
    vmudl   $v8, $v5, $v3[3]       // 0x2000; elem 2 = low part
    mfc2    dmemAddr, $v7[6]       // (v0 + n) end address; up to 56 inclusive
    vmudn   $v9, $v5, vTRC_0020    // 0020; elem 1 = high part
    jal     segmented_to_physical  // Convert address in cmd_w1_dram to physical
     lhu    vtxLeft, (inputBufferEnd - 0x07)(inputBufferPos) // vtxLeft = size in bytes = vtx count * 0x10
    sub     dmemAddr, dmemAddr, vtxLeft  // Start addr = end addr - size. Rounded down to DMA word by H/W
    li      $ra, vtx_after_dma
    vsub    $v8, $v7, $v8[2]       // elem 3 = v0 start address
    j       dma_read_write
G_SETOTHERMODE_H_handler: // These handler labels must be 4 bytes apart for the code below to work
     addi   dmaLen, vtxLeft, -1                // Only for above, nop for below
G_SETOTHERMODE_L_handler:
    lw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($ra) // resolves to othermode0 or othermode1 based on which handler was jumped to
    lui     $2, 0x8000
    srav    $2, $2, cmd_w0
    srl     $11, cmd_w0, 8
    srlv    $2, $2, $11
    nor     $2, $2, $zero
    and     $3, $3, $2
    or      $3, $3, cmd_w1_dram
    sw      $3, (othermode0 - G_SETOTHERMODE_H_handler)($ra)
    j       G_RDP_handler
     lpv    $v4[0], (otherMode0)($zero)
