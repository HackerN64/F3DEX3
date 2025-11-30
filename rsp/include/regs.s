// Global scalar regs:
vGeomMid       equ $5    // Middle two bytes of geometry mode in lower 16 bits
perfCounterD   equ $12   // Performance counter D (functions depend on config)
altBaseReg     equ $13   // Alternate base address register for vector loads
rdpCmdBufEndP1 equ $22   // Pointer to one command word past "end" (middle) of RDP command buf
rdpCmdBufPtr   equ $23   // RDP command buffer current DMEM pointer
taskDataPtr    equ $26   // Task data (display list) DRAM pointer
inputBufferPos equ $27   // DMEM position within display list input buffer, relative to end
perfCounterA   equ $28   // Performance counter A (functions depend on config)
perfCounterB   equ $29   // Performance counter B (functions depend on config)
perfCounterC   equ $30   // Performance counter C (functions depend on config)

// Misc:
nextRA         equ $10   // Address to return to after overlay load
dmaLen         equ $19   // DMA length in bytes minus 1
dmemAddr       equ $20   // DMA address in DMEM or IMEM. Also = rdpCmdBufPtr - rdpCmdBufEndP1 for flush_rdp_buffer
ovlInitClock   equ $21   // Temp for profiling. Share register with values not kept across ovl load.
cmd_w1_dram    equ $24   // DL command word 1, which is also DMA DRAM addr
cmd_w0         equ $25   // DL command word 0, also holds next tris info

// Tri write scalar regs:
origV1Addr     equ $4    // Original / current vertex 1 address
flatV1Offset   equ $16   // Offset +'d to vtx 1 addr for flat shading. 0 except in clipping.

// Global vector regs:
// TODO can maybe get rid of vZero
vZero equ $v0  // All elements = 0; NOT global, only in tri write and clip. Mtx in vtx.
vTRC  equ $v1  // Triangle Constants; NOT global, only in tri write and clip. Mtx in vtx.
vOne  equ $v28 // All elements = 1; global
// $v29: permanent temp register, also write results here to discard
// $v30: vtx / lt = sSTO + persp norm + more lighting params; tri write = snake saved index
// $v31: Global constant vector register
