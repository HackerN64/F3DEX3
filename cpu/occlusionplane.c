/*
This is a bit outdated but still generally okay. A full implementation is
present in HackerOoT, see src/code/occlusionplanes.c and related files.

This is a working demo implementation of the occlusion plane, set up in an
OoT scene render function. Here are some rough guidelines on how to properly
implement this in your game.

1. Move the structs to some header, and the rest of the code to a source file.
Yes, all this code really is needed except for the commented-out parts for
debugging (see below)--the algorithms really are this complicated.

2. If this is an OoT codebase, see the discussion in camera.c (in this repo)
about how OoT updates the camera at the end of the frame and retroactively
changes the view matrix at the start of the frame. You should similarly insert
the gSPOcclusionPlane command into the main display list near the beginning,
e.g. after writing the camera matrices etc., and with a NULL pointer. Then
update the occlusion plane after updating the camera and write the pointer to
this occlusion plane into the existing DL command near the beginning.

3. Create a system in your game engine for dynamically choosing or creating an
occlusion plane. For example, you might have a set of pre-determined occlusion
planes in the scene, and at runtime pick the one which you think is most
optimal. Some criteria to use for this include:
  - whether the camera is on the correct side of the occlusion plane
  - the distance from the camera to the full (infinite) plane
  - how far the point of the camera projected onto the full (infinite) plane is
    from the bounds of the finite plane (or if it's inside it)
  - how close the camera is to looking directly at the plane (negative dot
    product between plane normal and camera view direction)
  - some of these things scaled by the (constant per candiate) world-space area
    of the finite plane
You can get even more relevant metrics by using parts of the code here. For
example, the screen area of the occlusion plane can be computed from the clipped
screen-space polygon. However, it's probably not worth it to run that much of
the code here for every candidate occlusion plane.

4. Take a look at the commented out code using occPlaneMessage. Except for
"Offscreen" and the candidate counts, all the messages written to it represent
errors or problems with the occlusion plane setup (or bugs in these algorithms).
For example, "Edge %d now has no cands" occurs when the occlusion plane is being
viewed nearly edge-on, causing there to be too many edges oriented too similarly
to be representable by the occlusion plane equations. If you get this message,
your choice of occlusion plane was poor and the occlusion plane will be
disabled.

While it's not recommended to use occPlaneMessage besides for debugging, you
should create an "error flag" which is set if any of these messages would have
been written, and display something visually on the screen (such as an error
icon, short text string, etc.) if this happens. This is important because:
  - while this code seems to work, it is not tested super thoroughly, especially
    for extreme transformations of the occlusion plane (e.g. camera at a sharp
    angle very close to it)
  - if the occlusion plane doesn't work, you won't notice visually in the game,
    it'll just not occlude anything and you'll get lower performance

Please confirm the occlusion plane is actually working in your game, and let me
know of any issues!
*/

typedef struct {
    Vec3f clip;
    float w;
    Vec2f scrn;
    u8 isScreenEdge;
} ClipVertex;

typedef struct {
    s16 cScale;
    s16 cOffset;
    u8 edgeID;
} EdgeCandidate;

s16 FloatToS16Clamp(float f){
    f = CLAMP(f, -32768.0f, 32767.0f);
    return (s16)f;
}

s16 FloatMinus1To1ToS16(float f){
    return FloatToS16Clamp(f * 32768.0f);
}

void ClipToScreenSpace(PlayState* play, const Vec3f* clipXYZ, float clipW, Vec2f* screen){
    if(clipW < 0.001f){
        // Behind camera plane
        screen->x = 0x8000;
        screen->y = 0x8000;
        return;
    }
    float invW = 1.0f / clipW;
    float preViewportX = clipXYZ->x * invW;
    float preViewportY = clipXYZ->y * invW;
    Vp* vp = &play->view.vp;
    screen->x =  (float)vp->vp.vscale[0] * preViewportX + (float)vp->vp.vtrans[0];
    screen->y = -(float)vp->vp.vscale[1] * preViewportY + (float)vp->vp.vtrans[1];
}

bool ClipPolygon(PlayState* play, ClipVertex* verts, s8* indices, s8** idxFinalStart, s8** idxFinalEnd){
    // This is roughly a reimplementation of the F3D family clipping code
    // (Overlay 3), except with hardcoded clip ratio of 1 (screen clipping)
    s8 igen = 4; // gen vertex pointer
    s32 idxSelect = 0;
    ClipVertex* v3 = &verts[indices[3]];
    s8* idxWrite;
    for(s32 condition=4; condition>=0; --condition){
        s8* idxRead = &indices[idxSelect];
        idxSelect ^= 10;
        idxWrite = &indices[idxSelect];
        while(true){
            s8 i2 = *idxRead;
            if(i2 < 0) break;
            ClipVertex* v2 = &verts[i2];
            ++idxRead;
            bool v2Offscreen, v3Offscreen;
            switch(condition){
            case 4: // -W
                v2Offscreen = v2->w <= 0.0f;
                v3Offscreen = v3->w <= 0.0f;
                break;
            case 3: // +X
                v2Offscreen = v2->clip.x >= v2->w;
                v3Offscreen = v3->clip.x >= v3->w;
                break;
            case 2: // -X
                v2Offscreen = v2->clip.x <= -v2->w;
                v3Offscreen = v3->clip.x <= -v3->w;
                break;
            case 1: // +Y
                v2Offscreen = v2->clip.y >= v2->w;
                v3Offscreen = v3->clip.y >= v3->w;
                break;
            case 0: // -Y
                v2Offscreen = v2->clip.y <= -v2->w;
                v3Offscreen = v3->clip.y <= -v3->w;
                break;
            }
            if(v2Offscreen != v3Offscreen){
                // Clip this edge
                ClipVertex* v19 = v2;
                if(v2Offscreen){
                    v19 = v3;
                    v3 = v2;
                }
                // v19 is on screen, v3 is off screen
                float clOnScreen, clOffScreen;
                if(condition == 4){
                    clOnScreen = 0.0f;
                    clOffScreen = 0.0f;
                }else if(condition <= 1){
                    clOnScreen = v19->clip.y;
                    clOffScreen = v3->clip.y;
                }else{
                    clOnScreen = v19->clip.x;
                    clOffScreen = v3->clip.x;
                }
                float mult = (condition & 1) ? -1.0f : 1.0f;
                clOnScreen += mult * v19->w;
                clOffScreen += mult * v3->w;
                float clBase = clOnScreen;
                float clDiff = clOnScreen - clOffScreen;
                float clFade1;
                if(fabsf(clDiff) < 1e-6f){
                    clFade1 = 1.0f;
                }else{
                    clFade1 = clBase / clDiff;
                    clFade1 = CLAMP(clFade1, 0.0f, 1.0f);
                }
                float clFade2 = 1.0f - clFade1;
                if(igen >= 14){
                    // Too many generated vertices
                    return false;
                }
                if(idxWrite - &indices[idxSelect] >= 9){
                    // Polygon has too many vertices
                    return false;
                }
                verts[igen].clip.x = clFade2 * v19->clip.x + clFade1 * v3->clip.x;
                verts[igen].clip.y = clFade2 * v19->clip.y + clFade1 * v3->clip.y;
                verts[igen].w = clFade2 * v19->w + clFade1 * v3->w;
                verts[igen].isScreenEdge = v2Offscreen || v3->isScreenEdge;
                ClipToScreenSpace(play, &verts[igen].clip, verts[igen].w, &verts[igen].scrn);
                *idxWrite = igen;
                ++idxWrite;
                ++igen;
            }
            if(!v2Offscreen){
                if(idxWrite - &indices[idxSelect] >= 9){
                    // Polygon has too many vertices
                    return false;
                }
                *idxWrite = i2;
                ++idxWrite;
            }
            v3 = v2;
        }
        *idxWrite = -1;
        if(idxWrite - &indices[idxSelect] < 3){
            // Less than 3 verts in written polygon
            return false;
        }
        v3 = &verts[*(idxWrite-1)];
    }
    *idxFinalStart = &indices[idxSelect];
    *idxFinalEnd = idxWrite;
    return true;
}

// For debugging only
//static char occPlaneMessage[64];

// The occlusion plane settings for "disable the occlusion plane". This is just
// stored once, and the SPOcclusionPlane DL command is set to point here if the
// occlusion plane is disabled or invalid.
static OcclusionPlane sNoOcclusionPlane = {
    0x0000,
    0x0000,
    0x0000,
    0x0000,
    0x8000,
    0x8000,
    0x8000,
    0x8000,
    0x0000,
    0x0000,
    0x0000,
    0x8000
};

OcclusionPlane* ComputeOcclusionPlane(PlayState* play, Vec3f* worldBounds){
    //occPlaneMessage[0] = 0;
    
    ClipVertex verts[14]; // 4 initial verts, 5 tips cut off polygon with 2 gen verts each
    s8 indices[20]; // Polygon starts with 4 verts, 5 tips cut off = 9, plus 1 entry -1, times read and write
    for(s32 i=0; i<4; ++i){
        SkinMatrix_Vec3fMtxFMultXYZW(&play->viewProjectionMtxF,
            &worldBounds[i], &verts[i].clip, &verts[i].w);
        ClipToScreenSpace(play, &verts[i].clip, verts[i].w, &verts[i].scrn);
        verts[i].isScreenEdge = 0;
        indices[i] = i;
    }
    indices[4] = -1;
    
    // Clip space plane
    float kxf, kyf, kzf, kcf;
    Math3D_DefPlane(&verts[0].clip, &verts[2].clip, &verts[1].clip,
        &kxf, &kyf, &kzf, &kcf);
    s16 kx = FloatMinus1To1ToS16(kxf);
    s16 ky = FloatMinus1To1ToS16(kyf);
    s16 kz = FloatMinus1To1ToS16(kzf);
    s16 kc = (s16)(kcf * 0.5f);
    if((kx | ky | kz) == 0){
        // Degenerate plane, disable the clipping
        //sprintf(occPlaneMessage, "Clip space degenerate");
        return &sNoOcclusionPlane;
    }
    
    // Clip the polygon to the screen edges. Screen edges don't require an
    // occlusion plane equation.
    s8 *idxFinalStart, *idxFinalEnd, *idx;
    if(!ClipPolygon(play, verts, indices, &idxFinalStart, &idxFinalEnd)){
        // Resulting polygon is degenerate; occlusion plane is fully offscreen. No occlusion.
        //sprintf(occPlaneMessage, "Offscreen");
        return &sNoOcclusionPlane;
    }
    
    /*
    // Visualize the clipped polygon by drawing its vertices.
    OPEN_DISPS(play->state.gfxCtx);
    gDPPipeSync(OVERLAY_DISP++);
    gDPSetCycleType(OVERLAY_DISP++, G_CYC_FILL);
    gDPSetRenderMode(OVERLAY_DISP++, G_RM_NOOP, G_RM_NOOP2);
    u8 r = 0xFF, g = 0, b = 0;
    gDPSetFillColor(OVERLAY_DISP++, (GPACK_RGBA5551(r, g, b, 1) << 16) | GPACK_RGBA5551(r, g, b, 1));
    
    idx = idxFinalStart;
    while(idx != idxFinalEnd){
        s16 x = verts[*idx].scrn.x;
        s16 y = verts[*idx].scrn.y;
        ++idx;
        x >>= 2;
        y >>= 2;
        if(x < 3) x = 3;
        if(x > 315) x = 315;
        if(y < 1) y = 1;
        if(y > 236) y = 236;
        gDPScisFillRectangle(OVERLAY_DISP++, x-2, y-2, x+2, y+2);
    }
    
    gDPPipeSync(OVERLAY_DISP++);
    gDPSetCycleType(OVERLAY_DISP++, G_CYC_2CYCLE);
    CLOSE_DISPS(play->state.gfxCtx);
    */
    
    // Candidates for each of the 4 equations. Up to 3 edges can be candidates for each.
    EdgeCandidate cands[4][3];
    u8 numCands[4];
    numCands[0] = numCands[1] = numCands[2] = numCands[3] = 0;
    u8 totalEdges = 0;
    u8 candsForEdge[4];
    
    // Traverse the clipped polygon. For each edge which is not a screen edge,
    // see if it can be represented as each of the four equations. For any it can
    // be, compute its representation as that equation and store as a candidate.
    ClipVertex* vtxA;
    ClipVertex* vtxB = &verts[*(idxFinalEnd-1)];
    idx = idxFinalStart;
    while(idx < idxFinalEnd){
        vtxA = vtxB;
        vtxB = &verts[*idx];
        ++idx;
        if(vtxA->isScreenEdge) continue;
        // Should only be 4 edges not along a screen edge
        if(totalEdges >= 4){
            //sprintf(occPlaneMessage, "Too many edges");
            return &sNoOcclusionPlane;
        }
        
        u8 numCandsFit = 0;
        float dx = vtxB->scrn.x - vtxA->scrn.x;
        float dy = vtxB->scrn.y - vtxA->scrn.y;
        for(s32 q=0; q<4; ++q){
            float du, dv, uA, vA; // Equation V <> U * cScale + cOffset
            if((q & 1)){
                dv = dx;
                du = dy;
                vA = vtxA->scrn.x;
                uA = vtxA->scrn.y;
            }else{
                du = dx;
                dv = dy;
                uA = vtxA->scrn.x;
                vA = vtxA->scrn.y;
            }
            // Check side of edge using cross product. For example, if the
            // equation is Y > something, which side of that line is inside /
            // outside the clipped polygon depends on dx.
            // Eqn 0: Y > something -> dx > 0 -> du > 0
            // Eqn 1: X > something -> dy < 0 -> du < 0
            // Eqn 2: Y < something -> dx < 0 -> du < 0
            // Eqn 3: X < something -> dy > 0 -> du > 0
            if((q == 0 || q == 3) != (du > 0.0f)) continue;
            // cScale (after 1/8th scale) is limited to +/- 1. This also takes
            // care of the divided by 0 case, as the left side will always be
            // greater than or equal to 0.
            if(fabsf(dv) >= 8.0f * fabsf(du)) continue;
            float cScale = dv / du;
            float cOffset = vA - uA * cScale;
            cScale *= 0.125f;
            cOffset *= 0.5f;
            if(q >= 2){
                cScale = -cScale;
            }else{
                cOffset = -cOffset;
            }
            if(fabsf(cOffset) > 32767.0f) continue;
            
            if(numCands[q] >= 3){
                // Each equation should have no more than 3 candidate edges
                //sprintf(occPlaneMessage, "Eqn has too many cands");
                return &sNoOcclusionPlane;
            }
            EdgeCandidate* cand = &cands[q][numCands[q]];
            cand->cScale = FloatMinus1To1ToS16(cScale);
            cand->cOffset = (s16)cOffset;
            cand->edgeID = totalEdges;
            ++numCandsFit;
            ++(numCands[q]);
        }
        if(numCandsFit == 0){
            //sprintf(occPlaneMessage, "Edge fit in no cands");
            return &sNoOcclusionPlane;
        }else if(numCandsFit > 3){
            // Each edge should have no more than 3 candidate equations
            //sprintf(occPlaneMessage, "Edge fit in too many cands");
            return &sNoOcclusionPlane;
        }
        candsForEdge[totalEdges] = numCandsFit;
        
        ++totalEdges;
    }
    //sprintf(occPlaneMessage, "%de %dv %d> %d^ %d<", totalEdges,
    //    numCands[0], numCands[1], numCands[2], numCands[3]);
    
    // Assign candidates to equations.
    while(true){
        // Check fail condition: if now there is some edge which has no candidates
        for(s32 e=0; e<totalEdges; ++e){
            if(candsForEdge[e] == 0){
                //sprintf(occPlaneMessage, "Edge %d now has no cands", e);
                return &sNoOcclusionPlane;
            }
        }
        // Check done condition: all equations have 0 or 1 candidates
        bool done = true;
        for(s32 q=0; q<4; ++q){
            if(numCands[q] >= 2){
                done = false;
                break;
            }
        }
        if(done) break;
        // Check for an equation which has more than one candidate edge, but
        // one of those edges only has one candidate, so that edge has to be
        // assigned to that equation.
        bool madeChange = false;
        for(s32 q=0; q<4 && !madeChange; ++q){
            if(numCands[q] <= 1) continue;
            for(s32 c=0; c<numCands[q]; ++c){
                if(candsForEdge[cands[q][c].edgeID] == 1){
                    madeChange = true;
                    // Decrement num candidates for other edges in this equation
                    for(s32 i=0; i<numCands[q]; ++i){
                        if(i == c) continue;
                        --(candsForEdge[cands[q][i].edgeID]);
                    }
                    // Move found edge to position 0 and truncate list
                    cands[q][0] = cands[q][c];
                    numCands[q] = 1;
                    break;
                }
            }
        }
        if(madeChange) continue; // Restart loop
        // Take the first equation which has more than one candidate edge, and
        // assign the edge with smallest abs(cScale)
        for(s32 q=0; q<4; ++q){
            if(numCands[q] <= 1) continue;
            s32 bestC = 0;
            s32 bestScale = ABS((s32)cands[q][0].cScale);
            for(s32 c=1; c<numCands[q]; ++c){
                s32 scale = ABS((s32)cands[q][c].cScale);
                if(scale < bestScale){
                    bestScale = scale;
                    bestC = c;
                }
            }
            // Assigning equation q to edge e (edge currently as candidate bestC)
            s32 e = cands[q][bestC].edgeID;
            // Decrement num candidates for other edges in this equation
            for(s32 i=0; i<numCands[q]; ++i){
                if(i == bestC) continue;
                --(candsForEdge[cands[q][i].edgeID]);
            }
            // Move found edge to position 0 and truncate list
            cands[q][0] = cands[q][bestC];
            numCands[q] = 1;
            // Remove this edge from other candidate lists
            for(s32 j=0; j<4; ++j){
                if(q == j) continue;
                s32 i;
                for(i=0; i<numCands[j]; ++i){
                    if(cands[j][i].edgeID == e) break;
                }
                if(i == numCands[j]) continue;
                for(; i<numCands[j] - 1; ++i){
                    cands[j][i] = cands[j][i+1];
                }
                --(numCands[j]);
                --(candsForEdge[e]);
            }
            if(candsForEdge[e] != 1){
                //sprintf(occPlaneMessage, "Internal error 2");
                return &sNoOcclusionPlane;
            }
            madeChange = true;
            break;
        }
        if(!madeChange){
            //sprintf(occPlaneMessage, "Internal error 1");
            return &sNoOcclusionPlane;
        }
    }
    
    // Move equations to occlusion plane
    OcclusionPlane* occ = Graph_Alloc(play->state.gfxCtx, sizeof(OcclusionPlane));
    for(s32 q=0; q<4; ++q){
        occ->c[q]   = (numCands[q] == 0) ? 0x0000 : cands[q][0].cScale;
        occ->c[q+4] = (numCands[q] == 0) ? 0x7FFF : cands[q][0].cOffset;
    }
    occ->o.kx = kx;
    occ->o.ky = ky;
    occ->o.kz = kz;
    occ->o.kc = kc;
    return occ;
}

void someDrawFunction(PlayState* play) {
    ...
    
    // Replace this with some dynamic choice of the occulsion plane in your
    // game engine. This comment is about the constraints on the four points
    // defining the corner of the plane.
    // 
    // These points must be coplanar and form a convex quadrilateral. They must
    // also be in winding order, i.e. when viewed from the front (occlude things
    // on the far side of the plane), the verts must be in this order:
    //     1  2
    //     0  3
    // This can be rotated / scaled / sheared (as the camera moves). However, it
    // won't work properly if it is flipped (the camera is moved to be on the
    // occlusion side of it).
    static Vec3f PortalBoundingPointsWorld[4] = {
        {200.0f,   0.0f, -210.0f},
        {200.0f, 150.0f, -210.0f},
        {200.0f, 150.0f, -100.0f},
        {200.0f,   0.0f, -100.0f}
    };
    
    // Compute the occlusion plane and write the pointer to it into the display
    // list. Do this as early as possible in the full frame's DL, e.g. after
    // setting up the camera. Depending on your framebuffer clearing strategy
    // you may want to do this before or after that. There is no need to put
    // this in POLY_XLU_DISP too; its state will be retained through the full
    // graphics task.
    gSPOcclusionPlane(POLY_OPA_DISP++,
        ComputeOcclusionPlane(play, PortalBoundingPointsWorld));
    
    /*
    if(occPlaneMessage[0] != 0){
        GfxPrint printer;
        GfxPrint_Init(&printer);
        Gfx *opaStart = POLY_OPA_DISP;
        Gfx *gfx = Graph_GfxPlusOne(POLY_OPA_DISP);
        gSPDisplayList(OVERLAY_DISP++, gfx);
        GfxPrint_Open(&printer, gfx);
        GfxPrint_SetColor(&printer, 0, 0, 255, 255);
        GfxPrint_SetPos(&printer, 12, 28);
        GfxPrint_Printf(&printer, "%s", occPlaneMessage);
        gfx = GfxPrint_Close(&printer);
        gSPEndDisplayList(gfx++);
        Graph_BranchDlist(opaStart, gfx);
        POLY_OPA_DISP = gfx;
    }
    */
    
    ...
}
