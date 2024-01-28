/* This example code is for HackerOoT. The F3DEX3PerfCounters struct and the
method of reading it will be the same for any other game. */

/* In variables.h with the ENABLE_SPEEDMETER section */
extern volatile u32 gRSPGfxRDPWaitCycles;
extern volatile u16 gRSPGfxCommandsSampledGclkActive;
extern volatile u16 gRSPGfxCommandCount;
extern volatile u16 gRSPGfxVertexCount;
extern volatile u16 gRSPGfxTriDrawCount;
extern volatile u32 gRSPGfxTriRequestCount;
extern volatile u16 gRSPGfxRectCount;

/* In sched.c somewhere before Sched_TaskComplete, or in some header */
typedef struct {
    u32 rdpWaitCycles;
    u16 commandsSampledGclkActive;
    u16 commandCount;
    u16 vertexCount;
    u16 triDrawCount;
    u32 triRequestCount:18;
    u32 rectCount:14;
    u32 taskdataptr; /* Not a perf counter */
    u32 ucode; /* Not a perf counter */
} F3DEX3YieldDataFooter;

/* In the true codepath of Sched_TaskComplete: */
#ifdef ENABLE_SPEEDMETER
    /* Fetch number of primitives drawn from yield data */
    if(task->list.t.type == M_GFXTASK){
        F3DEX3YieldDataFooter* footer = (F3DEX3YieldDataFooter*)(
            (u8*)gGfxSPTaskYieldBuffer +
            OS_YIELD_DATA_SIZE - sizeof(F3DEX3YieldDataFooter));
        osInvalDCache(footer, sizeof(F3DEX3YieldDataFooter));
        gRSPGfxRDPWaitCycles = footer->rdpWaitCycles;
        gRSPGfxCommandsSampledGclkActive = footer->commandsSampledGclkActive;
        gRSPGfxCommandCount = footer->commandCount;
        gRSPGfxVertexCount = footer->vertexCount;
        gRSPGfxTriDrawCount = footer->triDrawCount;
        gRSPGfxTriRequestCount = footer->triRequestCount;
        gRSPGfxRectCount = footer->rectCount;
    }
#endif

/* In speed_meter.c */
/* Number of cycles the RSP is waiting for space in the RDP FIFO in DRAM */
volatile u32 gRSPGfxRDPWaitCycles;
/* If CFG_GCLK_SAMPLE is enabled, the "GCLK is alive" bit of the RDP status is
sampled once every time a display list command is started. This counts the
number of times that bit was 1. */
volatile u16 gRSPGfxCommandsSampledGclkActive;
/* Number of display list commands the microcode processed. If CFG_GCLK_SAMPLE
is disabled, this will be zero, so be careful about dividing the glck cycles
above by this. */
volatile u16 gRSPGfxCommandCount;
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
