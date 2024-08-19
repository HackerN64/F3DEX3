@page performance Performance Results

# Philosophy

The base version of F3DEX3 was created for RDP bound games like OoT, where new
visual effects are desired and increasing the RSP time a bit does not affect the
overall performance. If your game is RSP bound, using the base version of F3DEX3
will make it slower.

Conversely, F3DEX3_LVP_NOC was created with the goal of matching the RSP
performance of F3DEX2 on all critical paths in the microcode: command dispatch,
vertex processing, and triangle processing. Then, the RDP and memory traffic
performance improvements of F3DEX3--56 vertex buffer, auto-batched rendering,
etc.--should improve performance from there. This means that F3DEX3_LVP_NOC can
improve performance regardless of whether your game is RSP bound or RDP bound.

Note that F3DEX3_LVP_NOC is still slightly slower than F3DEX2 for various other
tasks--for example, the one-time setup when loading vertices, outside the loop
over vertices, is a little slower.


# Performance Results

These are cycle counts for all the critical paths in the microcode. Lower is
better. The timings are hand-counted taking into account all pipeline stalls and
all dual-issue conditions. Instruction alignment is sometimes taken into
account, otherwise assumed to be optimal.

Vertex / lighting numbers assume no special features (texgen, packed normals,
etc.) Tri numbers assume texture, shade, and Z. All numbers assume default
profiling configuration. Empty cells are "not measured yet".

|                            | F3DEX2 | F3DEX3_LVP_NOC | F3DEX3_LVP | F3DEX3_NOC | F3DEX3 |
|----------------------------|--------|----------------|------------|------------|--------|
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
| Command dispatch           | 12     | 12                                             ||||
| Only/2nd tri to offscreen  | 27     | 29                                             ||||
| 1st tri to offscreen       | 28     | 29                                             ||||
| Only/2nd tri to clip       | 32     | 31                                             ||||
| 1st tri to clip            | 33     | 31                                             ||||
| Only/2nd tri to backface   | 38     | 40                                             ||||
| 1st tri to backface        | 39     | 40                                             ||||
| Only/2nd tri to degenerate | 42     | 42                                             ||||
| 1st tri to degenerate      | 43     | 42                                             ||||
| Only/2nd tri to occluded   | Can't  | Can't          | 49         | Can't      | 49     |
| 1st tri to occluded        | Can't  | Can't          | 49         | Can't      | 49     |
| Only/2nd tri to draw       | 172    | 170            | 171        | 170        | 171    |
| 1st tri to draw            | 173    | 170            | 171        | 170        | 171    |


Tri numbers are measured from the first cycle of the command handler inclusive,
to the first cycle of whatever is after the return exclusive. This is in order
to capture the extra mfc0 to mfc0 stall due to return_routine in F3DEX2.


Vertex processing time as reported by the performance counter in the `PA`
configuration.
- Scene 1: Kakariko, adult day, from DMT entrance
- Scene 2: Custom empty scene with Suzanne monkey head with 1 dir light
- Scene 3: Same but Suzanne has vertex colors instead of lighting (Link is still
  on screen and has lighting)

| Microcode      | Scene 1 | Scene 2 | Scene 3 |
|----------------|---------|---------|---------|
| F3DEX3         | 7.64ms  | 3.13ms  | 2.37ms  |
| F3DEX3_NOC     | 7.07ms  | 2.89ms  | 2.14ms  |
| F3DEX3_LVP     | 4.57ms  | 1.77ms  | 1.67ms  |
| F3DEX3_LVP_NOC | Outdated  | | |
| F3DEX2         | No*     | No*     | No*     |
| Vertex count   | 3664    | 1608    | 1608    |

*F3DEX2 does not contain performance counters, so the portion of the RSP time
taken for vertex processing cannot be measured.
