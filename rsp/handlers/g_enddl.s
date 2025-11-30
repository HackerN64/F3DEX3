G_ENDDL_handler:
    lbu     $7, displayListStackLength      // Load the DL stack index; if end stack,
    beqz    $7, load_overlay_0_and_enter    // load overlay 0; $7 == -4 signals end
     addi   $7, $7, -4                      // Decrement the DL stack index
    j       call_ret_common                 // has a different version in ovl1
     lw     taskDataPtr, (displayListStack)($7) // Load addr of DL to return to
