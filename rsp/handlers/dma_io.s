    jal     segmented_to_physical // Convert the provided segmented address (in cmd_w1_dram) to a virtual one
     lh     dmemAddr, (inputBufferEnd - 0x07)(inputBufferPos) // Get the 16 bits in the middle of the command word (since inputBufferPos was already incremented for the next command)
    andi    dmaLen, cmd_w0, 0x0FF8 // Mask out any bits in the length to ensure 8-byte alignment
    li      nextRA, run_next_DL_command
    j       dma_and_wait_goto_next_ra  // Trigger a DMA read or write, depending on the G_DMA_IO flag (which will occupy the sign bit of dmemAddr)
     // At this point, dmemAddr's highest bit is the flag, it's next 13 bits are the DMEM address, and then it's last two bits are the upper 2 of size
     // So an arithmetic shift right 2 will preserve the flag as being the sign bit and get rid of the 2 size bits, shifting the DMEM address to start at the LSbit
     sra    dmemAddr, dmemAddr, 2