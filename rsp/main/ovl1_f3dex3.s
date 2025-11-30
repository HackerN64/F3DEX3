// overlay 1
.headersize 0x00001000 - orga()

ovl1_start:

.include "rsp/handlers/g_culldl_g_enddl.s"

.include "rsp/handlers/g_setscissor_g_rdpsetothermode.s"

.include "rsp/handlers/g_relsegment_g_moveword.s"

.include "rsp/handlers/g_texrect_g_texture.s"

.include "rsp/handlers/g_flush.s"
.include "rsp/handlers/g_mtx_multiply_end.s"

.include "rsp/handlers/g_vtx_g_setothermode.s"

.include "rsp/handlers/g_modifyvtx.s"

displaylist_dma_from_yield: // 2
    j       displaylist_dma_goto_next_ra
     lh     nextRA, tempTriRA

.include "rsp/handlers/segmented_to_physical.s"

ovl1_end:
align_with_warning 8, "One instruction of padding at end of ovl1"
ovl1_padded_end:

.if ovl1_padded_end > ovl01_end
    .error "Automatic resizing for overlay 1 failed"
.endif
// Currently want exactly 92 instructions (based on current size of start)
.if ovl1_padded_end > start_padded_end
    warn_if_base "ovl1 is larger than start, try to move something out"
.endif
.if ovl1_padded_end < start_padded_end
    warn_if_base "ovl1 is smaller than start, wasting space!"
.endif
