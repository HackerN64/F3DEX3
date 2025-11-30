tri_snake_over_input_buffer: // inputBufferPos is now 0; load whole buffer
    bgez    $3, displaylist_dma_goto_next_ra // If $3 < 0, last tri flag set, proceed to end
     li     nextRA, -0x8000 | tri_snake_ret_from_input_buffer // Negative is flag for from snake
tri_snake_end:
    addi    inputBufferPos, inputBufferPos, 7 // Round up to whole input command
    addi    $11, $zero, 0xFFFFFFF8            // Sign-extend; andi is zero-extend!
    j       tris_end
     and    inputBufferPos, inputBufferPos, $11 // inputBufferPos has to be negative
