#!/bin/bash
# Create object files

UCODES=(
    F3DEX3_BrW
    F3DEX3_BrW_PA
    F3DEX3_BrW_PB
    F3DEX3_BrW_PC
    F3DEX3_BrW_NOC
    F3DEX3_BrW_NOC_PA
    F3DEX3_BrW_NOC_PB
    F3DEX3_BrW_NOC_PC
    F3DEX3_BrW_LVP
    F3DEX3_BrW_LVP_PA
    F3DEX3_BrW_LVP_PB
    F3DEX3_BrW_LVP_PC
    F3DEX3_BrW_LVP_NOC
    F3DEX3_BrW_LVP_NOC_PA
    F3DEX3_BrW_LVP_NOC_PB
    F3DEX3_BrW_LVP_NOC_PC
)

mkdir -p build/objects

for ucode in "${UCODES[@]}"; do
    make $ucode
    echo .macro glabel label > object.s
    echo     .global \\label >> object.s
    echo     .balign 4 >> object.s
    echo     \\label: >> object.s
    echo .endm >> object.s
    echo  >> object.s
    echo .section .text >> object.s
    echo  >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$ucode\_fifoTextStart >> object.s
    echo     .incbin \"build/$ucode/$ucode.code\" >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$ucode\_fifoTextEnd >> object.s
    echo  >> object.s
    echo .section .data >> object.s
    echo  >> object.s
    echo .balign 16 >> object.s >> object.s
    echo glabel gsp$ucode\_fifoDataStart >> object.s
    echo     .incbin \"build/$ucode/$ucode.data\" >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$ucode\_fifoDataEnd >> object.s
    echo >> object.s

    OUTNAME=${ucode//_/.}
    mips64-linux-gnu-as -march=vr4300 -mabi=32 -I . object.s -o build/objects/gsp$OUTNAME.fifo.o
done

rm object.s
