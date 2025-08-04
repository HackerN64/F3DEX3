@page performance Performance Results

# Performance Results

F3DEX3_NOC matches or beats the RSP performance of F3DEX2 on **all** critical
paths in the microcode, including command dispatch, vertex processing, and
triangle processing. Then, the RDP and memory traffic performance improvements
of F3DEX3--56 vertex buffer, auto-batched rendering, etc.--should further
improve overall game performance from there.

## Cycle Counts

These are cycle counts for many key paths in the microcode. Lower numbers are
better. The timings are hand-counted taking into account all pipeline stalls and
all dual-issue conditions. Instruction alignment after branches is usually taken
into account, but in some cases it is assumed to be optimal.

All numbers assume default profiling configuration. Tri numbers assume texture,
shade, and Z, and not flushing the buffer. Tri numbers are measured from the
first cycle of the command handler inclusive, to the first cycle of whatever is
after $ra exclusive; this is in order to capture an extra stall cycle in F3DEX2
when finishing a triangle and going to the next command.

Vertex numbers assume no extra F3DEX3 features (packed normals, ambient
occlusion, etc.). These features are listed below as the number of extra cycles
the feature costs per vertex pair. ltbasic is the codepath when point lighting,
specular, and Fresnel are disabled; ltadv is the codepath with any of these
enabled. The reason timings are listed separately for each number of lights is
because some implementations are pipelined for two lights, so going from an
even to an odd number of lights adds a different time than vice versa.

|                            | F3DEX2 | F3DEX3_NOC | F3DEX3 |
|----------------------------|--------|------------|--------|
| Command dispatch           | 12     | 12         | 12     |
| Small RDP command          | 14     | 5          | 5      |
| Only/2nd tri to offscreen  | 27     | 25         | 25     |
| 1st tri to offscreen       | 28     | 26         | 26     |
| Only/2nd tri to clip       | 32     | 30         | 30     |
| 1st tri to clip            | 33     | 31         | 31     |
| Only/2nd tri to backface   | 38     | 36         | 36     |
| 1st tri to backface        | 39     | 37         | 37     |
| Only/2nd tri to degenerate | 42     | 38         | 38     |
| 1st tri to degenerate      | 43     | 39         | 39     |
| Only/2nd tri to occluded   | Can't  | Can't      | 42     |
| 1st tri to occluded        | Can't  | Can't      | 43     |
| Only/2nd tri to draw       | 172    | 156        | 158    |
| 1st tri to draw            | 173    | 157        | 159    |
| Extra per tri from snake   | Can't  | 9          | 9      |
| Vtx before DMA start       | 16     | 17         | 17     |
| Vtx pair, no lighting      | 54     | 54         | 70     |
| Vtx pair, 0 dir lts        | Can't  | 65         | 81     |
| Vtx pair, 1 dir lt         | 73     | 70         | 86     |
| Vtx pair, 2 dir lts        | 76     | 77         | 93     |
| Vtx pair, 3 dir lts        | 88     | 84         | 100    |
| Vtx pair, 4 dir lts        | 91     | 91         | 107    |
| Vtx pair, 5 dir lts        | 103    | 98         | 114    |
| Vtx pair, 6 dir lts        | 106    | 105        | 121    |
| Vtx pair, 7 dir lts        | 118    | 112        | 128    |
| Vtx pair, 8 dir lts        | Can't  | 119        | 135    |
| Vtx pair, 9 dir lts        | Can't  | 126        | 142    |
| Vtx pair, 0 point lts      | Can't  | 117        | 133    |
| Vtx pair, 1 point lt       | 276    | 194        | 210    |
| Vtx pair, 2 point lts      | 420    | 271        | 287    |
| Vtx pair, 3 point lts      | 564    | 348        | 364    |
| Vtx pair, 4 point lts      | 708    | 425        | 441    |
| Vtx pair, 5 point lts      | 852    | 502        | 518    |
| Vtx pair, 6 point lts      | 996    | 579        | 595    |
| Vtx pair, 7 point lts      | 1140   | 656        | 672    |
| Vtx pair, 8 point lts      | Can't  | 733        | 749    |
| Vtx pair, 9 point lts      | Can't  | 810        | 826    |
| Packed normals, ltbasic    | Can't  | 6          | 6      |
| Light-to-alpha, ltbasic    | Can't  | 10         | 10     |
| Ambient occlusion, ltbasic | Can't  | 9          | 9      |
| Packed normals, ltadv      | Can't  | -3         | -3     |
| Light-to-alpha, ltadv      | Can't  | 6          | 6      |
| Ambient occlusion, ltadv   | Can't  | 0          | 0      |
| Specular or fresnel        | Can't  | 47         | 47     |
| + Fresnel                  | Can't  | 27         | 27     |
| + Specular per dir lt      | Can't  | 13         | 13     |
| + Specular per point lt    | Can't  | 13         | 13     |
| Light dir xfrm, 0 dir lts  | Can't  | 92         | 92     |
| Light dir xfrm, 1 dir lt   | 141    | 92         | 92     |
| Light dir xfrm, 2 dir lts  | 180    | 93         | 93     |
| Light dir xfrm, 3 dir lts  | 219    | 118        | 118    |
| Light dir xfrm, 4 dir lts  | 258    | 119        | 119    |
| Light dir xfrm, 5 dir lts  | 297    | 144        | 144    |
| Light dir xfrm, 6 dir lts  | 336    | 145        | 145    |
| Light dir xfrm, 7 dir lts  | 375    | 170        | 170    |
| Light dir xfrm, 8 dir lts  | Can't  | 171        | 171    |
| Light dir xfrm, 9 dir lts  | Can't  | 196        | 196    |
