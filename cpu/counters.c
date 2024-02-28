/* This example code is for HackerOoT. The structs and the general method of
reading the counters will be the same for any game.

Build the microcode with one of the CFG_PROFILING_* options below to select one
of these sets of performance counters, or without any CFG_PROFILING_* option for
the default set. You can even include all the microcode versions in your game,
and let the player/developer swap which one is used for a given frame in order
to switch which set of performance counters they're seeing. You only need to
keep the currently used one in RDRAM, you can load a different one from the cart
over it when the user swaps.

For the options other than the default, the microcode uses the RDP's CLK counter
for its own timing. You should clear this counter just before launching F3DEX3
on the RSP (in the graphics task setup); usually you'd also read the counter
value, to optionally print on screen, after the RDP is finished. Make sure not
to clear/modify the CLK counter while the RSP is running, or the profiling
results may be garbage.
*/

/* In some header, needs to be accessible to variables.h */
typedef struct {  /* Default performance counters, if no CFG_PROFILING_* is enabled */
    /* Number of vertices processed by the RSP */
    u16 vertexCount;
    /* Number of tris actually drawn, after clipping and all types of culling */
    u16 rdpOutTriCount;
    /* Number of tris which processing started on the RSP (before clipping / culling) */
    u32 rspInTriCount:18;
    /* Number of fill rects and tex rects drawn */
    u32 rectCount:14;
    u32 stallRDPFifoFullCycles;
    u32 dummy;
} F3DEX3ProfilingDefault;

typedef struct {  /* Counters for CFG_PROFILING_A */
    u32 vertexProcCycles;
    u16 fetchedDLCommandCount;
    u16 dlCommandCount;
    u32 stallRDPFifoFullCycles;
    u32 triProcCycles;
} F3DEX3ProfilingA;

typedef struct {  /* Counters for CFG_PROFILING_B */
    u16 vertexCount;
    u16 litVertexCount;
    u32 smallRDPCommandCount:18; /* All RDP commands except tris */
    u32 clippedTriCount:14; /* Number of RSP/input triangles which got clipped */
    u32 allOverlayLoadCount:18;
    u32 lightingOverlayLoadCount:14;
    u32 clippingOverlayLoadCount:18;
    u32 miscOverlayLoadCount:14;
} F3DEX3ProfilingB;

typedef struct {  /* Counters for CFG_PROFILING_C */
    /* Total cycles F3DEX3 believes it was running, not including SPLoadUcode */
    u32 ex3UcodeCycles;
    /* The "GCLK is alive" bit of the RDP status is sampled once every time a
    display list command is started. This counts the number of times that bit
    was 1. Divide by dlCommandCount to get an approximate measurement of the
    percentage of time the RDP was doing useful work, as opposed to waiting
    for framebuffer / Z buffer memory transactions to complete. */
    u16 commandsSampledGclkActive;
    u16 dlCommandCount;
    u32 stallRDPFifoFullCycles;
    u32 stallDMACycles;
} F3DEX3ProfilingC;

typedef struct {
    union {
        F3DEX3ProfilingDefault def;
        F3DEX3ProfilingA a;
        F3DEX3ProfilingB b;
        F3DEX3ProfilingC c;
        u64 dummy_alignment[2];
    };
    u32 taskdataptr; /* Not a perf counter, can ignore */
    u32 ucode; /* Not a perf counter, can ignore */
} F3DEX3YieldDataFooter;

/* In variables.h with the ENABLE_SPEEDMETER section */
extern volatile F3DEX3YieldDataFooter gRSPProfilingResults;

/* In the true codepath of Sched_TaskComplete: */
#ifdef ENABLE_SPEEDMETER
    /* Fetch number of primitives drawn from yield data */
    if(task->list.t.type == M_GFXTASK){
        F3DEX3YieldDataFooter* footer = (F3DEX3YieldDataFooter*)(
            (u8*)gGfxSPTaskYieldBuffer +
            OS_YIELD_DATA_SIZE - sizeof(F3DEX3YieldDataFooter));
        osInvalDCache(footer, sizeof(F3DEX3YieldDataFooter));
        bcopy(footer, &gRSPProfilingResults, sizeof(F3DEX3YieldDataFooter));
    }
#endif

/* In speed_meter.c */
volatile F3DEX3YieldDataFooter gRSPProfilingResults;

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
if(f3dex3_version_CFG_PROFILING_A){
    
}else if(f3dex3_version_CFG_PROFILING_B){
    ...
}else if(f3dex3_version_CFG_PROFILING_C){
    ...
}else{
    GfxPrint_SetPos(&printer, 33, 25);
    GfxPrint_Printf(&printer, "%5dV", gRSPProfilingResults.def.vertexCount);
    GfxPrint_SetPos(&printer, 33, 26);
    GfxPrint_Printf(&printer, "%5dt", gRSPProfilingResults.def.rspInTriCount);
    GfxPrint_SetPos(&printer, 33, 27);
    GfxPrint_Printf(&printer, "%5dT", gRSPProfilingResults.def.rdpOutTriCount);
    ...
}

gfx = GfxPrint_Close(&printer);
gSPEndDisplayList(gfx++);
Graph_BranchDlist(opaStart, gfx);
POLY_OPA_DISP = gfx;
