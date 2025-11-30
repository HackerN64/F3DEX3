G_CULLDL_handler: // 15
    mfc2    $10, $v7[6]                     // Start vtx addr (index was byte 3)
    mfc2    $3, $v7[14]                     // End vertex addr (index was byte 7)
    /*
    CLIP_OCCLUDED can't be included here because: Suppose the list consists of N-1
    verts which are behind the occlusion plane, and 1 vert which is behind the camera
    plane and therefore randomly erroneously also set as behind the occlusion plane.
    However, the convex hull of all the verts goes through visible area. This will be
    incorrectly culled here. We can't afford the extra few instructions to disable
    the occlusion plane if the vert is behind the camera, because this only matters for
    G_CULLDL and not for tris.
    */
    li      $1, (CLIP_SCRN_NPXY | CLIP_CAMPLANE)
    lhu     $11, VTX_CLIP($10)
culldl_loop:
    and     $1, $1, $11
    beqz    $1, run_next_DL_command         // Some vertex is on the screen-side of all clipping planes; have to render
     lhu    $11, (vtxSize + VTX_CLIP)($10)  // next vertex clip flags
    bne     $10, $3, culldl_loop            // loop until reaching the last vertex
     addi   $10, $10, vtxSize               // advance to the next vertex
    li      cmd_w0, 0                       // Clear count of DL cmds to skip loading
.include "rsp/handlers/g_enddl.s"
