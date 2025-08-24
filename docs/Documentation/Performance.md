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
| Tri snake                  | Can't  | *          | *      |
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
| + Fresnel                  | Can't  | 23         | 23     |
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

## Triangle Snake Cycle Counts

### Very Long Snakes

For this section, we assume almost all tris are contained in very long snakes,
so the overhead of starting and ending snakes is negligible. This overhead is
discussed in the next section.

We are assuming that the same set of tris is being drawn with or without snakes.
Thus, cycles from `tri_main_from_snake` through the instruction after the return
exclusive are not counted here, as they are the same regardless of which method
is being used.

For a pair of tris drawn without snakes, i.e. with a single `SP2Triangles`
command, the cycles are:
- Command dispatch: 12
- First tri up to `tri_main_from_snake`: 5
- Second tri up to `tri_main_from_snake`: 4
- Total: 21

For a pair of tris which are part of a long snake, the cycles are:
- Each tri up to `tri_main_from_snake`: 11
- Total: 22

However, there's also the memory bandwidth savings. The `SP2Triangles` command
is 8 bytes and the two tris in a long snake are 2 bytes, so switching to snake
saves 6 bytes of bandwidth. Testing has shown that RSP DMAs on average transfer
about 2.2 bytes per cycle, though it depends on the length. So this is a savings
of about 2.7 cycles of RDRAM / RDP time. Since the DMAs loading this data are
input buffer loads, and the RSP stalls waiting for input buffer loads (it does
not do useful work during this time), this is also 2.7 cycles of RSP time. This
offsets the 1 extra cycle of processing the tri pair above.

Therefore, switching to snake (assuming very long snakes) saves about 2.7
cycles of RDRAM / RDP time and 1.7 cycles of RSP time per two tris, or about
0.9 RSP cycles and 1.4 RDRAM cycles per tri.

### Starting a Snake

Since a `SPTriSnake` command encodes 5 triangles, for comparison to
`SP2Triangles` we will consider the overhead for 10 triangles total / two snake
starts.

For `SPTriSnake`, this is 2 x (12 cycles command dispatch + 4 cycles snake
initialization + 5 tris x 11 cycles per tri as discussed above) = 142 RSP
cycles. And it is 16 bytes of loads = 7.3 cycles of RDRAM / RDP time and stall
RSP time. So the total cost is 149.3 RSP and 7.3 RDRAM cycles.

For `SP2Triangles`, this is 5 x (21 cycles as discussed above) = 105 RSP cycles.
And it is 40 bytes of loads = 18.2 cycles of RDRAM / RDP time and stall RSP
time. So the total cost is 123.2 RSP and 18.2 RDRAM cycles.

But drawing those 10 tris as part of very long snakes would have saved 13.5
RDRAM cycles and 8.5 RSP cycles. So the relative cost of drawing these tris as
two start-of-snakes instead of in very long snakes is 34.6 RSP cycles and 2.6
RDRAM cycles. Thus the cost of each start-of-snake relative to long snakes is
17.3 RSP cycles and 1.3 RDRAM cycles.

### Ending a Snake

Ending a snake costs 12 cycles of RSP time and has no direct impact on memory
traffic. However, calculating the overall performance is more complicated: the
snake can end after 1-8 bytes of the `SPContinueSnake` command, and the
remaining bytes are "wasted" in that they do not contribute to drawing tris
with memory bandwidth savings.

From a mesh optimization standpoint, this is not an issue. If you have a snake
which has filled 8 bytes of the previous `SPContinueSnake` command, and you have
another triangle to draw, there are only two cases. If that tri can't be
appended to the snake, you have to draw it with a `SP1Triangle` command either
way, so there is no performance difference. If it can be appended to the snake,
doing so will take 8 bytes of memory traffic--the same as the `SP1Triangle`
command. The snake end penalty will have to be paid whether before or after this
tri. And it's 11 RSP cycles to draw one more tri in an existing snake, whereas
the command dispatch plus second tri code for `SP1Triangle` is 16 cycles. So
it's better to continue a snake than to stop it early and use non-snake
commands, even if this leads to a mostly empty `SPContinueSnake` command. Of
course, if you can fill up even more tris in the command, the performance
benefit increases.

Assuming snake lengths are uniformly distributed, on average a snake will end
after 4.5 bytes (the same number of triangles) of a `SPContinueSnake` command.
In this case, the command will take 4.5 tris x 11 cycles per tri + 12 cycle end
snake penalty = 61.5 RSP cycles, and 8 bytes of memory traffic = 3.6 RDRAM
cycles. If these 4.5 tris were instead drawn with `SP2Triangles` commands, that
would be 2.25 commands = 47.3 RSP cycles and 18 bytes = 8.2 RDRAM cycles. Thus
on average, the snake end costs 14.2 RSP cycles and saves 4.6 RDRAM cycles
compared to `SP2Triangles` commands. But drawing those 4.5 tris as part of very
long snakes would have saved 3.9 RSP cycles and 6.1 RDRAM cycles. So the average
cost of ending a snake relative to very long snakes is 18.1 RSP and 1.5 RDRAM
cycles.

### Example

Suppose there are 4000 tris on screen. Suppose that 90% of them have been
encoded with snakes--the rest are disconnected single tris or tri pairs (quads).
That 10% are then encoded with `SP2Triangles` commands, which is the same
performance with or without snakes, so we ignore those tris, and there are
3600 "snakeable" tris in the scene.

Suppose that the average snake length is 16, to account for some objects with
more contiguous tris with the same material, and others with smaller disjoint
parts. Thus, for 3600 tris, there are 225 snakes.

Switching the 3600 tris from `SP2Triangles` commands to long snakes saves
4860 RDRAM cycles and 3060 RSP cycles. However, the 225 snake starts and ends
cost 630 RDRAM and 7965 RSP cycles relative to this. So the total performance
change of switching to snakes in this case is that the RDRAM / RDP goes faster
by 4230 cycles = 68 us, but the RSP goes slower by 4905 cycles = 78 us.
