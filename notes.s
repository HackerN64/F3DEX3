// Dot product summation, i.e. vOut[0] = vIn[0] + vIn[1] + vIn[2],
// vOut[4] = vIn[4] + vIn[5] + vIn[6]. Standard implementation:
vmudh   $v29, vOne, vIn[0h]
vmadh   $v29, vOne, vIn[1h]
vmadh   vOut, vOne, vIn[2h]
// This code pattern is a faster way, because the first instruction here does
// not depend on vIn, so the RSP has one less stall cycle at the beginning. This
// takes advantage of vadd writing the accumulator, which is normally useless
// because it only writes low and leaves mid and high, so it has to be cleared
// in advance. The built-in saturation (clamping) in vmadn does not affect this
// result.
// Unfortunately, even if the data being summed theoretically should not
// overflow, imprecision in the inputs / dot product can cause overflow here,
// which wraps, causing wrong results. So this is not useful unless you can
// be sure the sum will never overflow. The standard implementation clamps
// instead.
vmudh   $v29, $v31, $v31[2] // 0; clear whole accumulator
vadd    $v29, vIn, vIn[1h] // accum lo 0 = 0 + 1, 4 = 4 + 5
vmadn   vOut, vOne, vIn[2h] // + 2,6; built-in saturation (clamping) ends up not a problem

// lpv patterns. Same works for luv. Assuming $11 is 8 byte aligned (does not have
// to be 16 byte aligned).
//                       Elem  0  1  2  3  4  5  6  7
lpv     $v27[1], (-8)($11) // 07 F8 F9 FA FB FC FD FE  Byte
lpv     $v27[2], (-8)($11) // 06 07 F8 F9 FA FB FC FD  addr
lpv     $v27[3], (-8)($11) // 05 06 07 F8 F9 FA FB FC  relative
lpv     $v27[4], (-8)($11) // 04 05 06 07 F8 F9 FA FB  to
lpv     $v27[5], (-8)($11) // 03 04 05 06 07 F8 F9 FA  $11
lpv     $v27[6], (-8)($11) // 02 03 04 05 06 07 F8 F9
lpv     $v27[7], (-8)($11) // 01 02 03 04 05 06 07 F8
lpv     $v27[0], ( 0)($11) // 00 01 02 03 04 05 06 07
lpv     $v27[1], ( 0)($11) // 0F 00 01 02 03 04 05 06
lpv     $v27[2], ( 0)($11) // 0E 0F 00 01 02 03 04 05
lpv     $v27[3], ( 0)($11) // 0D 0E 0F 00 01 02 03 04
lpv     $v27[4], ( 0)($11) // 0C 0D 0E 0F 00 01 02 03
lpv     $v27[5], ( 0)($11) // 0B 0C 0D 0E 0F 00 01 02
lpv     $v27[6], ( 0)($11) // 0A 0B 0C 0D 0E 0F 00 01
lpv     $v27[7], ( 0)($11) // 09 0A 0B 0C 0D 0E 0F 00

// spv and suv always store to the 8 bytes at/after the scalar reg + offset.
// What is stored starts at lane e, increments and wraps at lane 8. However for
// the lanes >= 8, the functionality of spv and suv swaps.
//        Mem addr rel to $11  0  1  2  3  4  5  6  7
spv     $v27[0], ( 0)($11) // P0 P1 P2 P3 P4 P5 P6 P7  Lane number
spv     $v27[1], ( 0)($11) // P1 P2 P3 P4 P5 P6 P7 U0  P = packed (top 8 bits)
spv     $v27[2], ( 0)($11) // P2 P3 P4 P5 P6 P7 U0 U1  U = unsigned (bits 14:7)
spv     $v27[3], ( 0)($11) // P3 P4 P5 P6 P7 U0 U1 U2
spv     $v27[4], ( 0)($11) // P4 P5 P6 P7 U0 U1 U2 U3
spv     $v27[5], ( 0)($11) // P5 P6 P7 U0 U1 U2 U3 U4
spv     $v27[6], ( 0)($11) // P6 P7 U0 U1 U2 U3 U4 U5
spv     $v27[7], ( 0)($11) // P7 U0 U1 U2 U3 U4 U5 U6
suv     $v27[0], ( 0)($11) // U0 U1 U2 U3 U4 U5 U6 U7 = spv $v27[8], (0)($11)
suv     $v27[1], ( 0)($11) // U1 U2 U3 U4 U5 U6 U7 P0
suv     $v27[2], ( 0)($11) // U2 U3 U4 U5 U6 U7 P0 P1
suv     $v27[3], ( 0)($11) // U3 U4 U5 U6 U7 P0 P1 P2
suv     $v27[4], ( 0)($11) // U4 U5 U6 U7 P0 P1 P2 P3
suv     $v27[5], ( 0)($11) // U5 U6 U7 P0 P1 P2 P3 P4
suv     $v27[6], ( 0)($11) // U6 U7 P0 P1 P2 P3 P4 P5
suv     $v27[7], ( 0)($11) // U7 P0 P1 P2 P3 P4 P5 P6
