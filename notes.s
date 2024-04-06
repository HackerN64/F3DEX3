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
