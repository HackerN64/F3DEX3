
// Temp storage after rdpCmdBufEndP1. There is 0xA8 of space here which will
// always be free during vtx load or clipping.
tempVpRGBA            equ 0x00        // Only used during loop
tempXfrmLt            equ tempVpRGBA  // ltbasic only used during init
tempVtx1ST            equ tempVpRGBA  // ltadv only during init
tempAmbient           equ 0x10        // ltbasic set during init, used during loop
tempClipPtrs          equ tempAmbient // set during clipping, kept through vtx write
tempPrevInvalVtxStart equ 0x20
tempPrevInvalVtx      equ (tempPrevInvalVtxStart + vtxSize) // 0x46; fog writes here
tempPrevInvalVtxEnd   equ (tempPrevInvalVtx + vtxSize)      // 0x6C; rest of vtx writes here
.if tempPrevInvalVtxEnd > (RDP_CMD_BUFSIZE_EXCESS - 8)
    .error "Too much temp storage used!"
.endif
