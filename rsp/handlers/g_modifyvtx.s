G_MODIFYVTX_handler: // 3
    mfc2    $10, $v7[6]  // Byte 3 = vtx being modified
    j       do_moveword  // Moveword adds cmd_w0 to $10 for final addr
     lbu    cmd_w0, (inputBufferEnd - 0x07)(inputBufferPos)  // offset in vtx, bit 15 clear
