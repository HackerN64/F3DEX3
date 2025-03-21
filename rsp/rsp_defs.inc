// RSP definitions

OS_YIELD_DATA_SIZE equ 0xC00
YIELD_DATA_FOOTER_SIZE equ 0x18
yieldDataFooter equ OS_YIELD_DATA_SIZE - YIELD_DATA_FOOTER_SIZE
YDF_OFFSET_PERFCOUNTERA equ 0x00
YDF_OFFSET_PERFCOUNTERB equ 0x04
YDF_OFFSET_PERFCOUNTERC equ 0x08
YDF_OFFSET_PERFCOUNTERD equ 0x0C
YDF_OFFSET_TASKDATAPTR  equ 0x10
YDF_OFFSET_UCODE        equ 0x14

// OSTask data member offsets
OSTask_type             equ 0x0000 //                      EX3: end of      ^
OSTask_flags            equ 0x0004 // see note below            inputBuffer |
OSTask_ucode_boot       equ 0x0008 //                                       |
OSTask_ucode_boot_size  equ 0x000C //                                       v
OSTask_ucode            equ 0x0010 // used in F3D, S2D, and boot
OSTask_ucode_size       equ 0x0014 //                      EX3: startCounterTime
OSTask_ucode_data       equ 0x0018 // used in boot only.   EX3: xfrmLookatDirs ^
OSTask_ucode_data_size  equ 0x001C // used in boot only                        v
OSTask_dram_stack       equ 0x0020 // used in F3D and S2D at first startup
OSTask_dram_stack_size  equ 0x0024
OSTask_output_buff      equ 0x0028 // used in F3D and S2D
OSTask_output_buff_size equ 0x002C // used in F3D and S2D; actually end pointer not size
OSTask_data_ptr         equ 0x0030 // used in F3D and S2D
OSTask_data_size        equ 0x0034
OSTask_yield_data_ptr   equ 0x0038 // used in F3D and S2D
OSTask_yield_data_size  equ 0x003C
// Unlabeled members are never used. In particular, boot does NOT use OSTask_ucode_size,
// it always fills all of IMEM after start.
// A hypothetical other microcode could use OSTask_dram_stack_size or OSTask_data_size
// for bounds checking.
// OSTask_flags is used:
// - In F3D and S2D only once at startup to check if resuming from yield, then zeroed
// - In boot to check if the task should wait until the RDP is finished with its
//   previous command buffer
// F3DEX3 now zeroes OSTask_flags when loading another ucode. As a result, the first
// 0x10 bytes of OSTask are unused temp memory (not kept at yield), so we overlap
// the end of inputBuffer into this space.

// flags
OS_TASK_YIELDED equ 0x0001
OS_TASK_DP_WAIT equ 0x0002

// RSP Status flags (write)
SP_CLR_HALT       equ 0x00000001
SP_SET_HALT       equ 0x00000002
SP_CLR_BROKE      equ 0x00000004
SP_CLR_INTR       equ 0x00000008
SP_SET_INTR       equ 0x00000010
SP_CLR_SSTEP      equ 0x00000020
SP_SET_SSTEP      equ 0x00000040
SP_CLR_INTR_BREAK equ 0x00000080
SP_SET_INTR_BREAK equ 0x00000100
SP_CLR_SIG0       equ 0x00000200 // yield
SP_SET_SIG0       equ 0x00000400
SP_CLR_SIG1       equ 0x00000800 // yielded
SP_SET_SIG1       equ 0x00001000
SP_CLR_SIG2       equ 0x00002000 // task done
SP_SET_SIG2       equ 0x00004000
SP_CLR_SIG3       equ 0x00008000 // rsp signal
SP_SET_SIG3       equ 0x00010000
SP_CLR_SIG4       equ 0x00020000 // cpu signal
SP_SET_SIG4       equ 0x00040000
SP_CLR_SIG5       equ 0x00080000
SP_SET_SIG5       equ 0x00100000
SP_CLR_SIG6       equ 0x00200000
SP_SET_SIG6       equ 0x00400000
SP_CLR_SIG7       equ 0x00800000
SP_SET_SIG7       equ 0x01000000

// RSP Status flags (read)
SP_STATUS_HALT       equ 0x0001
SP_STATUS_BROKE      equ 0x0002
SP_STATUS_DMA_BUSY   equ 0x0004
SP_STATUS_DMA_FULL   equ 0x0008
SP_STATUS_IO_FULL    equ 0x0010
SP_STATUS_SSTEP      equ 0x0020
SP_STATUS_INTR_BREAK equ 0x0040
SP_STATUS_SIG0       equ 0x0080
SP_STATUS_SIG1       equ 0x0100
SP_STATUS_SIG2       equ 0x0200
SP_STATUS_SIG3       equ 0x0400
SP_STATUS_SIG4       equ 0x0800
SP_STATUS_SIG5       equ 0x1000
SP_STATUS_SIG6       equ 0x2000
SP_STATUS_SIG7       equ 0x4000

// RDP Status read flags
DPC_STATUS_XBUS_DMA    equ 0x0001
DPC_STATUS_GCLK_ALIVE  equ 0x0008
DPC_STATUS_DMA_BUSY    equ 0x0100
DPC_STATUS_END_VALID   equ 0x0200
DPC_STATUS_START_VALID equ 0x0400

// RDP Status write flags
DPC_STATUS_CLR_XBUS    equ 0x0001
DPC_STATUS_SET_XBUS    equ 0x0002
