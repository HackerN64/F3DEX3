@page counters Performance Counters

This example code is for HackerOoT. The structs and the general method of
reading the counters will be the same for any game. The structs are valid though
the other code is a little simplistic. A full implementation exists in
HackerOoT, which includes a full CPU+RSP profiler with tracing, see
`src/debug/profiler.c` and related files.

Build the microcode with one of the `CFG_PROFILING_*` options below to select one
of these sets of performance counters, or without any `CFG_PROFILING_*` option for
the default set. You can even include all the microcode versions in your game,
and let the player/developer swap which one is used for a given frame in order
to switch which set of performance counters they're seeing. If you want, you
only need to keep the currently used one in RDRAM--you can load a different one
from the cart over it when the user swaps.

For the options other than the default, the microcode uses the RDP's CLK counter
for its own timing. You should clear this counter just before launching F3DEX3
on the RSP (in the graphics task setup); usually you'd also read the counter
value, to optionally print on screen, after the RDP is finished. Make sure not
to clear/modify the CLK counter while the RSP is running, or the profiling
results may be garbage.

Note that all "cycles" counters reported by F3DEX3 are RCP cycles, at 62.5 MHz.

Finally, note that the implementation of the stallDMACycles counter in 
`CFG_PROFILING_C` is compatible with loading S2DEX via SPLoadUcode, but it may not
be compatible with other microcodes. If you run into crashes when using
`CFG_PROFILING_C` but not A or B or the default, contact Sauraen, as you will need
a customized implementation based on the other microcode you are using.

In some header, needs to be accessible to variables.h:
```
typedef struct {  /* Default performance counters, if no CFG_PROFILING_* is enabled */
    /* Number of vertices processed by the RSP */
    u16 vertexCount;
    /* Number of tris actually drawn, after clipping and all types of culling */
    u16 rdpOutTriCount;
    /* Number of tris which processing started on the RSP (before clipping / culling) */
    u32 rspInTriCount:18;
    /* Number of fill rects and tex rects drawn */
    u32 rectCount:14;
    /* Number of cycles the RSP was stalled because the RDP FIFO was full */
    u32 stallRDPFifoFullCycles;
    /* Unused, zero */
    u32 dummy;
} F3DEX3ProfilingDefault;

typedef struct {  /* Counters for CFG_PROFILING_A */
    /* Number of cycles the RSP spent processing vertex commands, including vertex DMAs */
    u32 vertexProcCycles;
    /* Number of display list commands fetched from DRAM, >= dlCommandCount */
    u16 fetchedDLCommandCount;
    /* Number of display list commands executed */
    u16 dlCommandCount;
    /* Number of cycles the RSP was stalled because the RDP FIFO was full */
    u32 stallRDPFifoFullCycles;
    /* Number of cycles the RSP spent processing triangle commands, NOT including buffer flushes (i.e. FIFO full) */
    u32 triProcCycles;
} F3DEX3ProfilingA;

typedef struct {  /* Counters for CFG_PROFILING_B */
    /* Number of vertices processed by the RSP */
    u16 vertexCount;
    /* Number of vertices processed which had lighting enabled */
    u16 litVertexCount;
    /* Number of tris culled by the occlusion plane */
    u32 occlusionPlaneCullCount:18;
    /* Number of RSP/input triangles which got clipped */
    u32 clippedTriCount:14;
    /* Number of times any microcode overlay was loaded */
    u32 allOverlayLoadCount:18;
    /* Number of times overlay 2 (lighting) was loaded */
    u32 lightingOverlayLoadCount:14;
    /* Number of times overlay 3 (clipping) was loaded */
    u32 clippingOverlayLoadCount:18;
    /* Number of times overlay 4 (mIT matrix, matrix multiply, etc.) was loaded */
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
    /* Number of display list commands executed */
    u16 dlCommandCount;
    /* Number of commands sent to the RDP except for triangle commands */
    u32 smallRDPCommandCount:18;
    /* Number of matrix loads, of any type */
    u32 matrixCount:14;
    /* Number of cycles the RSP was stalled waiting for any DMAs: vertex loads,
    matrix loads, copying command buffers to the RDP FIFO, overlay loads, etc. */
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
```

In variables.h with the ENABLE_SPEEDMETER section:
```
extern volatile F3DEX3YieldDataFooter gRSPProfilingResults;
```

In the true codepath of Sched_TaskComplete:
```
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
```

In speed_meter.c:
```
volatile F3DEX3YieldDataFooter gRSPProfilingResults;
```

You can display them on screen however you wish. Here is an example, in
SpeedMeter_DrawTimeEntries
```
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
    ...
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
```
