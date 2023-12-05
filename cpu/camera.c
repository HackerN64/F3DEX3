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

/* Bonus: To convert Fresnel lo and hi (values for where the Fresnel fade begins
/* and ends, normally between 0.0 and 1.0) to scale and offset for SPFresnel */
void FresnelParams(s16* scale, s16* offset, float lo, float hi){
    s32 dotMin = (s32)(lo * 0x7FFF);
    s32 dotMax = (s32)(hi * 0x7FFF);
    if(dotMax == dotMin) ++dotMax;
    s32 scale32 = 0x3F8000 / (dotMax - dotMin);
    s32 offset32 = -(0x7F * dotMin) / (dotMax - dotMin);
    *scale = (s16)MAX(MIN(scale32, 0x7FFF), -0x8000);
    *offset = (s16)MAX(MIN(offset32, 0x7FFF), -0x8000);
}
