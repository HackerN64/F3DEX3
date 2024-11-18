@page performance Performance Results

# Philosophy

The base version of F3DEX3 was created for RDP bound games like OoT, where new
visual effects are desired and increasing the RSP time a bit does not affect the
overall performance. If your game is RSP bound, using the base version of F3DEX3
will make it slower.

Conversely, F3DEX3_LVP_NOC matches or beats the RSP performance of F3DEX2 on
**all** critical paths in the microcode, including command dispatch, vertex
processing, and triangle processing. Then, the RDP and memory traffic
performance improvements of F3DEX3--56 vertex buffer, auto-batched rendering,
etc.--should further improve performance from there. This means that switching
from F3DEX2 to F3DEX3_LVP_NOC should always improve performance regardless of
whether your game is RSP bound or RDP bound.


# Performance Results

## Cycle Counts

These are cycle counts for many key paths in the microcode. Lower numbers are
better. The timings are hand-counted taking into account all pipeline stalls and
all dual-issue conditions. Instruction alignment after branches is sometimes
taken into account, otherwise assumed to be optimal.

Vertex / lighting numbers assume no special features (texgen, packed normals,
etc.) Tri numbers assume texture, shade, and Z, and not flushing the buffer.
All numbers assume default profiling configuration. Empty cells are "not
measured yet".

|                            | F3DEX2 | F3DEX3_LVP_NOC | F3DEX3_LVP | F3DEX3_NOC | F3DEX3 |
|----------------------------|--------|----------------|------------|------------|--------|
| Command dispatch           | 12     | 12             | 12         | 12         | 12     |
| Small RDP command          | 14     | 5              | 5          | 5          | 5      |
| Vtx before DMA start       | 16     | 17             | 17         | 17         | 17     |
| Vtx pair, no lighting      | 54     | 54             | 81         | 79         | 98     |
| Vtx pair, 0 dir lts        | Can't  | 64             |            |            |        |
| Vtx pair, 1 dir lt         | 73     | 70             | 96         | 182        | 201    |
| Vtx pair, 2 dir lts        | 76     | 77             | 103        | 211        | 230    |
| Vtx pair, 3 dir lts        | 88     | 84             | 110        | 240        | 259    |
| Vtx pair, 4 dir lts        | 91     | 91             | 117        | 269        | 288    |
| Vtx pair, 5 dir lts        | 103    | 98             | 124        | 298        | 317    |
| Vtx pair, 6 dir lts        | 106    | 105            | 131        | 327        | 346    |
| Vtx pair, 7 dir lts        | 118    | 112            | 138        | 356        | 375    |
| Vtx pair, 8 dir lts        | Can't  | 119            | 145        | 385        | 404    |
| Vtx pair, 9 dir lts        | Can't  | 126            | 152        | 414        | 433    |
| Light dir xfrm, 0 dir lts  | Can't  | 95             | 95         | None       | None   |
| Light dir xfrm, 1 dir lt   | 141    | 95             | 95         | None       | None   |
| Light dir xfrm, 2 dir lts  | 180    | 96             | 96         | None       | None   |
| Light dir xfrm, 3 dir lts  | 219    | 121            | 121        | None       | None   |
| Light dir xfrm, 4 dir lts  | 258    | 122            | 122        | None       | None   |
| Light dir xfrm, 5 dir lts  | 297    | 147            | 147        | None       | None   |
| Light dir xfrm, 6 dir lts  | 336    | 148            | 148        | None       | None   |
| Light dir xfrm, 7 dir lts  | 375    | 173            | 173        | None       | None   |
| Light dir xfrm, 8 dir lts  | Can't  | 174            | 174        | None       | None   |
| Light dir xfrm, 9 dir lts  | Can't  | 199            | 199        | None       | None   |
| Only/2nd tri to offscreen  | 27     | 26             | 26         | 26         | 26     |
| 1st tri to offscreen       | 28     | 27             | 27         | 27         | 27     |
| Only/2nd tri to clip       | 32     | 31             | 31         | 31         | 31     |
| 1st tri to clip            | 33     | 32             | 32         | 32         | 32     |
| Only/2nd tri to backface   | 38     | 38             | 38         | 38         | 38     |
| 1st tri to backface        | 39     | 39             | 39         | 39         | 39     |
| Only/2nd tri to degenerate | 42     | 40             | 40         | 40         | 40     |
| 1st tri to degenerate      | 43     | 41             | 41         | 41         | 41     |
| Only/2nd tri to occluded   | Can't  | Can't          | 49         | Can't      | 49     |
| 1st tri to occluded        | Can't  | Can't          | 50         | Can't      | 50     |
| Only/2nd tri to draw       | 172    | 160            | 163        | 160        | 163    |
| 1st tri to draw            | 173    | 160            | 163        | 160        | 163    |


Tri numbers are measured from the first cycle of the command handler inclusive,
to the first cycle of whatever is after $ra exclusive. This is in order
to capture the extra latency and stalls in F3DEX2.

## Measurements

Vertex processing time as reported by the performance counter in the `PA`
configuration.
- Scene 1: Kakariko, adult day, from DMT entrance
- Scene 2: Custom empty scene with Suzanne monkey head with 1 dir light
- Scene 3: Same but Suzanne has vertex colors instead of lighting (Link is still
  on screen and has lighting)

| Microcode      | Scene 1 | Scene 2 | Scene 3 |
|----------------|---------|---------|---------|
| F3DEX3         | 7.41ms  | 2.99ms  | 2.22ms  |
| F3DEX3_NOC     | 6.85ms  | 2.75ms  | 1.98ms  |
| F3DEX3_LVP     | 4.12ms  | 1.59ms  | 1.48ms  |
| F3DEX3_LVP_NOC | 3.34ms  | 1.27ms  | 1.16ms  |
| F3DEX2         | Can't*  | Can't*  | Can't*  |
| Vertex count   | 3557    | 1548    | 1548    |

*F3DEX2 does not contain performance counters, so the portion of the RSP time
taken for vertex processing cannot be measured.
