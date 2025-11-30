.include "rsp/include/gbi.inc"

// GBI commands
G_CULLDL            equ 0x03
G_BRANCH_WZ         equ 0x04
G_TRI1              equ 0x05
G_TRI2              equ 0x06
G_QUAD              equ 0x07


G_BRANCH_Z equ G_BRANCH_WZ
G_BRANCH_W equ G_BRANCH_WZ

// Note that load and push are inverted in the GBI encoding.
G_MTX_VP_M        equ 0x04  // Binary: set for VP, clear for M
G_MTX_MUL_LOAD    equ 0x02  // Binary: set for mul, clear for load
G_MTX_NOPUSH_PUSH equ 0x01  // Binary: set for nopush, clear for push

G_MV_MMTX     equ 0x00
G_MV_TEMPMTX0 equ 0x02
G_MV_VPMTX    equ 0x04
G_MV_TEMPMTX1 equ 0x06
G_MV_VIEWPORT equ 0x08
G_MV_LIGHT    equ 0x0A

ZMODE_DEC equ 0x0C00  // from othermode low; the value is the mask


YIELD_DATA_FOOTER_SIZE equ 0x18

// OSTask data member offsets
OSTask_type             equ 0x0000 //                      EX3: clipPoly ^
OSTask_flags            equ 0x0004 // see note below                     |
OSTask_ucode_boot       equ 0x0008 //                                    |
OSTask_ucode_boot_size  equ 0x000C //                                    v
OSTask_ucode            equ 0x0010 // used in F3D, S2D, and boot
OSTask_ucode_size       equ 0x0014 //                      EX3: startCounterTime (CFG_PROFILING_A and C only)
OSTask_ucode_data       equ 0x0018 // used in boot only.   EX3: xfrmLookatDirs ^
OSTask_ucode_data_size  equ 0x001C // used in boot only                        v
OSTask_dram_stack       equ 0x0020 // used in F3D and S2D
OSTask_dram_stack_size  equ 0x0024
OSTask_output_buff      equ 0x0028 // used in F3D and S2D
OSTask_output_buff_size equ 0x002C // used in F3D and S2D; actually end pointer not size
OSTask_data_ptr         equ 0x0030 // used in F3D and S2D
OSTask_data_size        equ 0x0034 //                      EX3: 2 bytes: savedOrigV1Addr
OSTask_yield_data_ptr   equ 0x0038 // used in F3D and S2D
OSTask_yield_data_size  equ 0x003C //                      EX3: dumpDmemBuffer (CFG_PROFILING_B only), startFifoStallTime (CFG_PROFILING_A only)
// Unlabeled members are never used. In particular, boot does NOT use OSTask_ucode_size,
// it always fills all of IMEM after start.
// A hypothetical other microcode could use OSTask_dram_stack_size or OSTask_data_size
// for bounds checking.
// OSTask_flags is used:
// - In F3D and S2D only once at startup to check if resuming from yield, then zeroed
// - In boot to check if the task should wait until the RDP is finished with its
//   previous command buffer
// F3DEX3 now zeroes OSTask_flags when loading another ucode. As a result, the first
// 0x10 bytes of OSTask are unused temp memory (not kept at yield), so we put
// clipPoly there.

// flags
OS_TASK_YIELDED equ 0x0001
OS_TASK_DP_WAIT equ 0x0002
