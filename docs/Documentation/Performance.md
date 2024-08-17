@page performance Performance Results

# Performance Results

Cycle counts; lower is better. These are hand-counted timings taking into
account all pipeline stalls and all dual-issue conditions. Instruction alignment
is sometimes taken into account, otherwise assumed to be optimal.

Vertex / lighting numbers assume no special features (texgen, packed normals,
etc.) Tri numbers assume texture, shade, and Z. Empty cells are "not measured
yet".

|                       | F3DEX2 | F3DEX3_LVP_NOC | F3DEX3_LVP | F3DEX3_NOC | F3DEX3 |
|-----------------------|--------|----------------|------------|------------|--------|
| Vtx pair, no lighting | 54     | 54             | 81         | 79         | 98     |
| Vtx pair, 0 dir lts   | Can't  |                |            |            |        |
| Vtx pair, 1 dir lt    | 73     | 70             | 96         | 182        | 201    |
| Vtx pair, 2 dir lts   | 76     | 77             | 103        | 211        | 230    |
| Vtx pair, 3 dir lts   | 88     | 84             | 110        | 240        | 259    |
| Vtx pair, 4 dir lts   | 91     | 91             | 117        | 269        | 288    |
| Vtx pair, 5 dir lts   | 103    | 98             | 124        | 298        | 317    |
| Vtx pair, 6 dir lts   | 106    | 105            | 131        | 327        | 346    |
| Vtx pair, 7 dir lts   | 118    | 112            | 138        | 356        | 375    |
| Vtx pair, 8 dir lts   | Can't  | 119            | 145        | 385        | 404    |
| Vtx pair, 9 dir lts   | Can't  | 126            | 152        | 414        | 433    |




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
