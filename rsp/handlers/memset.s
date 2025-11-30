     llv    $v2[0], (rdpHalf1Val - altBase)(altBaseReg) // Load the memset value
    sll     cmd_w0, cmd_w0, 8           // Clear upper byte
    jal     segmented_to_physical
     srl    cmd_w0, cmd_w0, 8           // Number of bytes to memset (must be mult of 16)
    li      $3, memsetBufferStart + 0x10 // Last qword set is memsetBufferStart
    jal     @@clamp_to_memset_buffer
     vmudh  $v2, vOne, $v2[1]           // Move element 1 (lower bytes) to all
    addi    $2, $2, memsetBufferStart   // First qword set is one below end
@@pre_loop:
    sqv     $v2, (-0x10)($2)
    bne     $2, $3, @@pre_loop
     addi   $2, -0x10
@@transaction_loop:
    jal     @@clamp_to_memset_buffer
     li     dmemAddr, -0x8000 | memsetBufferStart  // Always write from start of buffer
    jal     dma_read_write
     addi   dmaLen, $2, -1
    sub     cmd_w0, cmd_w0, $2
    bgtz    cmd_w0, @@transaction_loop
     add    cmd_w1_dram, cmd_w1_dram, $2
    j       while_wait_dma_busy
     li     $ra, run_next_DL_command
@@clamp_to_memset_buffer:
    addi    $11, cmd_w0, -memsetBufferSize // $2 = min(cmd_w0, memsetBufferSize)
    sra     $10, $11, 31
    and     $11, $11, $10
    jr      $ra
     addi   $2, $11, memsetBufferSize