G_GEOMETRYMODE_handler: // 6
    lw      $11, geometryModeLabel        // load the geometry mode value
    and     $11, $11, cmd_w0              // clears the flags in cmd_w0 (set in g*SPClearGeometryMode)
    or      cmd_w1_dram, cmd_w1_dram, $11 // sets the flags in cmd_w1_dram (set in g*SPSetGeometryMode)
    srl     vGeomMid, cmd_w1_dram, 8      // Middle 2 bytes of geom mode to lower 16 bits. Ordered this way to avoid stalls.
G_RDPHALF_1_handler: // $ra = ., 0x10 ahead of geometry mode
.if (G_RDPHALF_1_handler - G_GEOMETRYMODE_handler) != (rdpHalf1Val - geometryModeLabel)
    .error "G_RDPHALF_1 optimization broken"
.endif
    j       run_next_DL_command
     sw     cmd_w1_dram, (geometryModeLabel - G_GEOMETRYMODE_handler)($ra)
