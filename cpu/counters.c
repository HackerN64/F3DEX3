/* This example code is for HackerOoT. The F3DEX3PerfCounters struct and the
method of reading it will be the same for any other game. */

/* In variables.h with the ENABLE_SPEEDMETER section */
extern volatile u16 gRSPGfxVertexCount;
extern volatile u16 gRSPGfxTriDrawCount;
extern volatile u32 gRSPGfxTriRequestCount;
extern volatile u16 gRSPGfxRectCount;

/* In sched.c somewhere before Sched_TaskComplete, or in some header */
typedef struct {
    u16 vertexCount;
    u16 triDrawCount;
    u32 triRequestCount:18;
    u32 rectCount:14;
} F3DEX3PerfCounters;

/* In the true codepath of Sched_TaskComplete: */
#ifdef ENABLE_SPEEDMETER
    /* Fetch number of primitives drawn from yield data */
    if(task->list.t.type == M_GFXTASK){
        F3DEX3PerfCounters* counters = (F3DEX3PerfCounters*)(
            (u8*)gGfxSPTaskYieldBuffer + OS_YIELD_DATA_SIZE - 0x10);
        osInvalDCache(counters, sizeof(F3DEX3PerfCounters));
        gRSPGfxVertexCount = counters->vertexCount;
        gRSPGfxTriDrawCount = counters->triDrawCount;
        gRSPGfxTriRequestCount = counters->triRequestCount;
        gRSPGfxRectCount = counters->rectCount;
    }
#endif

/* In speed_meter.c */
/* Number of vertices processed by the RSP */
volatile u16 gRSPGfxVertexCount;
/* Number of tris actually drawn, after clipping and all types of culling */
volatile u16 gRSPGfxTriDrawCount;
/* Number of tris which processing started on the RSP (before clipping / culling) */
volatile u32 gRSPGfxTriRequestCount;
/* Number of fill rects and tex rects drawn */
volatile u16 gRSPGfxRectCount;

/* You can display them on screen however you wish. Here is an example, in
SpeedMeter_DrawTimeEntries */
GfxPrint printer;
Gfx* opaStart;
Gfx* gfx;

GfxPrint_Init(&printer);
opaStart = POLY_OPA_DISP;
gfx = Graph_GfxPlusOne(POLY_OPA_DISP);
gSPDisplayList(OVERLAY_DISP++, gfx);
GfxPrint_Open(&printer, gfx);

GfxPrint_SetColor(&printer, 255, 100, 0, 255);
GfxPrint_SetPos(&printer, 33, 25);
GfxPrint_Printf(&printer, "%5dV", gRSPGfxVertexCount);
GfxPrint_SetPos(&printer, 33, 26);
GfxPrint_Printf(&printer, "%5dt", gRSPGfxTriRequestCount);
GfxPrint_SetPos(&printer, 33, 27);
GfxPrint_Printf(&printer, "%5dT", gRSPGfxTriDrawCount);
GfxPrint_SetPos(&printer, 33, 28);
GfxPrint_Printf(&printer, "%5dR", gRSPGfxRectCount);

gfx = GfxPrint_Close(&printer);
gSPEndDisplayList(gfx++);
Graph_BranchDlist(opaStart, gfx);
POLY_OPA_DISP = gfx;
