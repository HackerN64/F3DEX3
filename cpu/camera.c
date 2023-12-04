/* This example code is for HackerOoT. For other games, similarly send the
camera world position to the RSP whenever you send / apply the view matrix. */

/* In z_view.c somewhere towards the top */
PlainVtx* View_GetCameraWorld(View* view){
    PlainVtx* cameraWorldPos = Graph_Alloc(view->gfxCtx, sizeof(PlainVtx));
    cameraWorldPos->c.pos[0] = (s16)view->eye.x;
    cameraWorldPos->c.pos[1] = (s16)view->eye.y;
    cameraWorldPos->c.pos[2] = (s16)view->eye.z;
    return cameraWorldPos;
}

/* Before CLOSE_DISPS in View_ApplyPerspective */
PlainVtx* cameraWorldPos = View_GetCameraWorld(view);
gSPCameraWorld(POLY_OPA_DISP++, cameraWorldPos);
gSPCameraWorld(POLY_XLU_DISP++, cameraWorldPos);

/* Before CLOSE_DISPS in View_ApplyPerspectiveToOverlay */
gSPCameraWorld(OVERLAY_DISP++, View_GetCameraWorld(view));

/* After sending the viewing matrix to the RSP in View_ApplyTo */
gSPCameraWorld(gfx++, View_GetCameraWorld(view));
