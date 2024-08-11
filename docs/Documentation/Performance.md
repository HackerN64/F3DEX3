@page performance Performance Results

# Performance Results

Vertex pipeline cycles per **vertex pair** in steady state (lower is better).
Hand-counted timings taking into account all pipeline stalls and all dual-issue
conditions. Instruction alignment is only taken into account for LVP_NOC.

| Microcode      | No Lighting | First Dir Lt | Total for 1 Dir Lt | Extra Dir Lts |
|----------------|-------------|--------------|--------------------|---------------|
| F3DEX3         | 98          | 103          | 201                | 29            |
| F3DEX3_NOC     | 79          | 103          | 182                | 29            |
| F3DEX3_LVP     | 81          | 15           | 96                 | 7             |
| F3DEX3_LVP_NOC | 54          | 16           | 70                 | 7, 7, 7, 7, ...   |
| F3DEX2         | 54          | 19           | 73                 | 3, 12, 3, 12, ... |

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
