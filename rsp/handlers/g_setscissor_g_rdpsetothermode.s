G_SETSCISSOR_handler: // 3; should be towards the start of ovl1
    li      $ra, scissorUpLeft - (otherMode0 - (G_RDPSETOTHERMODE_handler & 0xFFF))
G_RDPSETOTHERMODE_handler: // $ra = .
.if (. & 7) != 0
    .error "G_RDPSETOTHERMODE_handler alignment broken"
.endif
    j       G_RDP_handler  // Send the command to the RDP
     spv    $v4[0], (otherMode0 - (G_RDPSETOTHERMODE_handler & 0xFFF))($ra)
