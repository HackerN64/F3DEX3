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

// ltv patterns: all 8 instr below produce (values are address loaded to each element)
ltv     $v0[ 0], (0x00)($11) // $v0 = 00 10 20 30 40 50 60 70 // $v0 always gets bytes 0-1
ltv     $v0[14], (0x10)($11) // $v1 = 72 02 12 22 32 42 52 62 // $v1 always gets bytes 2-3
ltv     $v0[12], (0x20)($11) // $v2 = 64 74 04 14 24 34 44 54
ltv     $v0[10], (0x30)($11) // $v3 = 56 66 76 06 16 26 36 46
ltv     $v0[ 8], (0x40)($11) // $v4 = 48 58 68 78 08 18 28 38
ltv     $v0[ 6], (0x50)($11) // $v5 = 3A 4A 5A 6A 7A 0A 1A 2A
ltv     $v0[ 4], (0x60)($11) // $v6 = 2C 3C 4C 5C 6C 7C 0C 1C
ltv     $v0[ 2], (0x70)($11) // $v7 = 1E 2E 3E 4E 5E 6E 7E 0E
// Or this pattern
ltv     $v0[ 0], (0x00)($11) // $v0 = 00 70 60 50 40 30 20 10
ltv     $v0[ 2], (0x10)($11) // $v1 = 12 02 72 62 52 42 32 22
ltv     $v0[ 4], (0x20)($11) // $v2 = 24 14 04 74 64 54 44 34
ltv     $v0[ 6], (0x30)($11) // $v3 = 36 26 16 06 76 66 56 46
ltv     $v0[ 8], (0x40)($11) // $v4 = 48 38 28 18 08 78 68 58
ltv     $v0[10], (0x50)($11) // $v5 = 5A 4A 3A 2A 1A 0A 7A 6A
ltv     $v0[12], (0x60)($11) // $v6 = 6C 5C 4C 3C 2C 1C 0C 7C
ltv     $v0[14], (0x70)($11) // $v7 = 7E 6E 5E 4E 3E 2E 1E 0E

// stv patterns: values are 16 bit reg/elem stored, e.g. 45 = $v4[e5]
stv     $v0[ 0], (0x00)($11) // mem[0x00] = 00 11 22 33 44 55 66 77
stv     $v0[ 2], (0x10)($11) // mem[0x10] = 10 21 32 43 54 65 76 07
stv     $v0[ 4], (0x20)($11) // mem[0x20] = 20 31 42 53 64 75 06 17
stv     $v0[ 6], (0x30)($11) // mem[0x30] = 30 41 52 63 74 05 16 27
stv     $v0[ 8], (0x40)($11) // mem[0x40] = 40 51 62 73 04 15 26 37
stv     $v0[10], (0x50)($11) // mem[0x50] = 50 61 72 03 14 25 36 47
stv     $v0[12], (0x60)($11) // mem[0x60] = 60 71 02 13 24 35 46 57
stv     $v0[14], (0x70)($11) // mem[0x70] = 70 01 12 23 34 45 56 67
