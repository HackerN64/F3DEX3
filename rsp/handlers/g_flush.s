G_FLUSH_handler: // 32
    jal     flush_rdp_buffer        // Flush once to push partial DMEM buf to FIFO
     sub    dmemAddr, rdpCmdBufPtr, rdpCmdBufEndP1 // Prereq; offset buffer fullness
    // If the DMEM buffer was empty, dmemAddr will be unchanged and valid for this next
    // jump. Otherwise, running the DMA write will cause dmemAddr to get set to a large
    // negative number. Then for this second jump, the same codepath will be triggered as
    // if the buffer was empty. The result is it will wait for the DMA to finish, set
    // DPC_END, and return to $ra. This is why the dmemAddr register (as opposed to,
    // for example, dmaLen) is used as the DMEM buf fullness.
    j       flush_rdp_buffer
