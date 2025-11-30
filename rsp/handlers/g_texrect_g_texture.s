G_TEXRECT_handler: // 3; should be towards the start of ovl1
    li      $ra, texrectState - (textureSettings1 - (G_TEXTURE_handler & 0xFFF))
G_TEXTURE_handler: // $ra = .
.if (. & 7) != 0
    .error "G_TEXTURE_handler alignment broken"
.endif
    j       run_next_DL_command
     spv    $v4[0], (textureSettings1 - (G_TEXTURE_handler & 0xFFF))($ra)
