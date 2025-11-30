dump_dmem:
    jal     segmented_to_physical
     lw     cmd_w1_dram, dumpDmemBuffer
    li      dmemAddr, 0x8000 // address 0, negative = write
    j       dma_and_wait_goto_next_ra
     li     dmaLen, 0x1000 - 1 // all of DMEM, DMA lengths always minus 1