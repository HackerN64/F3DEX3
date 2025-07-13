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
after $ra exclusive; this is in order to capture the extra latency and stalls in
F3DEX2.

|                            | F3DEX2 | F3DEX3_NOC | F3DEX3 |
|----------------------------|--------|------------|--------|
| Command dispatch           | 12     | 12         | 12     |
| Small RDP command          | 14     | 5          | 5      |
| Only/2nd tri to offscreen  | 27     | 26         | 26     |
| 1st tri to offscreen       | 28     | 27         | 27     |
| Only/2nd tri to clip       | 32     | 31         | 31     |
| 1st tri to clip            | 33     | 32         | 32     |
| Only/2nd tri to backface   | 38     | 38         | 38     |
| 1st tri to backface        | 39     | 39         | 39     |
| Only/2nd tri to degenerate | 42     | 40         | 40     |
| 1st tri to degenerate      | 43     | 41         | 41     |
| Only/2nd tri to occluded   | Can't  | Can't      | 49     |
| 1st tri to occluded        | Can't  | Can't      | 50     |
| Only/2nd tri to draw       | 172    | 159        | 162    |
| 1st tri to draw            | 173    | 160        | 163    |
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
| Vtx pair, 0 point lts      | Can't  | TODO       | +16    |
| Vtx pair, 1 point lt       | TODO   | TODO       | +16    |
| Vtx pair, 2 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 3 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 4 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 5 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 6 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 7 point lts      | TODO   | TODO       | +16    |
| Vtx pair, 8 point lts      | Can't  | TODO       | +16    |
| Vtx pair, 9 point lts      | Can't  | TODO       | +16    |
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
