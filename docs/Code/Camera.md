For any game, the idea is to send the camera world position to the RSP
whenever you send / apply the view matrix. For OoT, this is not trivial because
the game allocates the view matrix at the beginning of the frame and runs
gSPMatrix, but at the end of the frame it updates the camera and then rewrites
the allocated view matrix, changing it retroactively for the frame. So, we have
to similarly save a pointer to the camera position, set at the beginning of the
frame, and update it at the end of the frame.

In z64view.h, in the definition of the View struct, after Mtx* viewingPtr
```
PlainVtx* cameraWorldPosPtr;
```

In z_view.c somewhere towards the top
```
void View_SetCameraWorld(PlainVtx* cameraWorldPos, View* view){
    cameraWorldPos->c.pos[0] = (s16)view->eye.x;
    cameraWorldPos->c.pos[1] = (s16)view->eye.y;
    cameraWorldPos->c.pos[2] = (s16)view->eye.z;
}
PlainVtx* View_CreateCameraWorld(View* view){
    PlainVtx* cameraWorldPos = Graph_Alloc(view->gfxCtx, sizeof(PlainVtx));
    View_SetCameraWorld(cameraWorldPos, view);
    return cameraWorldPos;
}
```

After each place in the functions in z_view.c where view->viewingPtr gets
set
```
PlainVtx* cameraWorldPos = View_CreateCameraWorld(view);
view->cameraWorldPosPtr = cameraWorldPos;
```

In those same functions, right after the calls to
`gSPMatrix(GFX, viewing, G_MTX_NOPUSH | G_MTX_MUL | G_MTX_PROJECTION)`
where `GFX` is `POLY_OPA_DISP++`, `POLY_XLU_DISP++`, `OVERLAY_DISP++`, or `gfx++`
```
gSPCameraWorld(GFX, cameraWorldPos);
```

The important part: in View_UpdateViewingMatrix
```
View_SetCameraWorld(view->cameraWorldPosPtr, view);
```

The same issue happens (in the vanilla game) for lookat vectors--they are
computed during the frame based on the camera position and direction, but
these are updated at the end of the frame so the lookat vectors are one frame
behind. You can see this when going into C-up next to an object with hilite
or env map-- it's wrong for one frame and then is fixed. You could solve
this by either tracking all lookat vectors created during the frame and
updating them at the end as we did here. Another option is to only send
lookat once at the start of each frame (and update it at the end of the
frame), rather than once per object using it. This is not exactly the same
for objects not in the middle of the screen, but the difference is minor.
