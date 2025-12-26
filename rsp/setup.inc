.rsp

// This file assumes DATA_FILE and CODE_FILE are set on the command line

.if version() < 110
    .error "armips 0.11 or newer is required"
.endif

// Sign-extends the immediate using addi. ori would zero-extend.
.macro li, reg, imm
    addi    reg, $zero, imm
.endmacro

.macro move, dst, src
    ori     dst, src, 0
.endmacro

// Prohibit macros involving slt; this silently clobbers $1. You can of course
// manually write the slt and branch instructions if you want this behavior.
.macro blt, ra, rb, lbl
    .error "blt is a macro using slt, and silently clobbers $1!"
.endmacro

.macro bgt, ra, rb, lbl
    .error "bgt is a macro using slt, and silently clobbers $1!"
.endmacro

.macro ble, ra, rb, lbl
    .error "ble is a macro using slt, and silently clobbers $1!"
.endmacro

.macro bge, ra, rb, lbl
    .error "bge is a macro using slt, and silently clobbers $1!"
.endmacro

// This version doesn't depend on $v0 to be vZero, which it often is not in
// F3DEX3, and also doesn't get corrupted if $vco is set / consume $vco which
// may be needed for a subsequent instruction.
.macro vcopy, dst, src
    vor     dst, src, src
.endmacro

// Using $v31 instead of dst as the source because $v31 doesn't change, whereas
// dst might have been modified 2 or 3 cycles ago, causing a stall.
.macro vclr, dst
    vxor    dst, $v31, $v31
.endmacro

// Also using $v31 for the dummy args here to avoid stalls. dst was once written
// in vanilla tri code just before reading (should have been $v29), leading to
// stalls!
ACC_UPPER equ 0
ACC_MIDDLE equ 1
ACC_LOWER equ 2
.macro vreadacc, dst, N
    vsar    dst, $v31, $v31[N]
.endmacro

// Only raise a warning in base modes; in profiling modes, addresses will be off
.macro warn_if_base, warntext
    .if !ENABLE_PROFILING
        .warning warntext
    .endif
.endmacro

.macro align_with_warning, alignment, warntext
    .if (. & (alignment - 1))
        warn_if_base warntext
    .endif
    .align alignment
.endmacro

.macro assert_alignment, alignment, errtext
    .if (. & (alignment - 1))
        .error errtext
    .endif
.endmacro
