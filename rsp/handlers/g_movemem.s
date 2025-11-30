G_MOVEMEM_handler: // If called this handler, $7 = (-0x100 | G_MOVEMEM)
    jal     segmented_to_physical   // convert the memory address cmd_w1_dram to a virtual one
do_movemem: // Coming from popmtx; $7 was set to (-0x100 | G_MOVEMEM)
     // 0: load M, 2: mul M -> load temp, 4: load VP, 6: mul VP -> load temp
     andi   $3, cmd_w0, 0x00FE            // Movemem table index into $3 (bits 1-7 of the word 0)
    lbu     dmaLen, (inputBufferEnd - 0x07)(inputBufferPos) // Second byte of word 0
    lhu     dmemAddr, (movememTable)($3)  // $3 reused in G_MTX_multiply_end
    srl     $2, cmd_w0, 5                 // ((w0) >> 8) << 3; top 3 bits of idx must be 0; lower 1 bit of len byte must be 0
    add     dmemAddr, dmemAddr, $2
    lh      nextRA, (afterMovememRaTable - (-0x100 | G_MOVEMEM))($7)
dma_and_wait_goto_next_ra:
    j       dma_read_write
     li     $ra, wait_goto_next_ra
