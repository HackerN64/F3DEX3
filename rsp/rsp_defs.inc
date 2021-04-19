// RSP definitions

// OSTask placed at end of DMEM (IMEM_START - sizeof(OSTask))
.definelabel OSTask_addr, 0xFC0
// OSTask data member offsets
OSTask_type             equ 0x0000
OSTask_flags            equ 0x0004
OSTask_ucode_boot       equ 0x0008
OSTask_ucode_boot_size  equ 0x000C
OSTask_ucode            equ 0x0010
OSTask_ucode_size       equ 0x0014
OSTask_ucode_data       equ 0x0018
OSTask_ucode_data_size  equ 0x001C
OSTask_dram_stack       equ 0x0020
OSTask_dram_stack_size  equ 0x0024
OSTask_output_buff      equ 0x0028
OSTask_output_buff_size equ 0x002C
OSTask_data_ptr         equ 0x0030
OSTask_data_size        equ 0x0034
OSTask_yield_data_ptr   equ 0x0038
OSTask_yield_data_size  equ 0x003C

// flags
OS_TASK_YIELDED equ 0x0001
OS_TASK_DP_WAIT equ 0x0002


// RSP Status flags
SPSTATUS_HALT        equ 0x0001
SPSTATUS_BROKE       equ 0x0002
SPSTATUS_DMA_BUSY    equ 0x0004
SPSTATUS_DMA_FULL    equ 0x0008
SPSTATUS_IO_FULL     equ 0x0010
SPSTATUS_SSTEP       equ 0x0020
SPSTATUS_INTR_BREAK  equ 0x0040
SPSTATUS_SIGNAL0_SET equ 0x0080
SPSTATUS_SIGNAL1_SET equ 0x0100
SPSTATUS_SIGNAL2_SET equ 0x0200
SPSTATUS_SIGNAL3_SET equ 0x0400
SPSTATUS_SIGNAL4_SET equ 0x0800
SPSTATUS_SIGNAL5_SET equ 0x1000
SPSTATUS_SIGNAL6_SET equ 0x2000
SPSTATUS_SIGNAL7_SET equ 0x4000

// RDP Status read flags
DPC_STATUS_XBUS_DMA    equ 0x0001
DPC_STATUS_DMA_BUSY    equ 0x0100
DPC_STATUS_START_VALID equ 0x0400

// RDP Status write flags
DPC_STATUS_CLR_XBUS    equ 0x0001


// Types
TYPE_F3DEX2 equ 0
TYPE_F3DZEX equ 1

UCODE_HAS_POINT_LIGHTING equ ((UCODE_TYPE == TYPE_F3DZEX && UCODE_ID >= 1) || (UCODE_TYPE == TYPE_F3DEX2 && UCODE_ID == 3))
UCODE_IS_206_OR_OLDER equ ((UCODE_TYPE == TYPE_F3DZEX && UCODE_ID < 1) || (UCODE_TYPE == TYPE_F3DEX2 && UCODE_ID < 1))
UCODE_IS_207_OR_OLDER equ ((UCODE_TYPE == TYPE_F3DZEX && UCODE_ID < 1) || (UCODE_TYPE == TYPE_F3DEX2 && UCODE_ID < 2))
UCODE_IS_F3DEX2_204H equ (UCODE_TYPE == TYPE_F3DEX2 && UCODE_ID == 0)