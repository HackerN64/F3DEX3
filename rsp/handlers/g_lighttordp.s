G_LIGHTTORDP_handler: // 9
    sw      cmd_w1_dram, 0(rdpCmdBufPtr) // Store second word as first (cmd byte, prim level)
    lbu     $11, numLightsxSize          // Ambient light
    lbu     $1, (inputBufferEnd - 0x6)(inputBufferPos) // Byte 2 = light count from end * size
    andi    $2, cmd_w0, 0x00FF           // Byte 3 = alpha
    sub     $1, $11, $1                  // Light address; byte 2 counts from end
    lw      $3, (lightBufferMain-1)($1)  // Load light RGB into lower 3 bytes
    sll     $3, $3, 8                    // Shift light RGB to upper 3 bytes and clear alpha byte
    j       send_w1_to_rdp               // Write word w1 to RDP
     or     cmd_w1_dram, $3, $2          // Combine RGB and alpha in second word
