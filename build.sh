#!/bin/bash
# Note: This is a convenience script for Sauraen to build the microcode, build
# HackerOoT, and upload the ROM to the SummerCart64. You do NOT need to run this
# script to build the microcode. To build the microcode, just run make F3DEX3_BrZ
# or make F3DEX3_BrW (or many other options).
set -e

mkdir -p ../../Mods/HackerOoT/data/F3DEX3

UCODES=(
    F3DEX3_BrW
    F3DEX3_BrW_PA
    F3DEX3_BrW_PB
    F3DEX3_BrW_PC
    F3DEX3_BrW_NOC
    F3DEX3_BrW_NOC_PA
    F3DEX3_BrW_NOC_PB
    F3DEX3_BrW_NOC_PC
)
for ucode in "${UCODES[@]}"; do
    make $ucode
    cp build/$ucode/$ucode.code ../../Mods/HackerOoT/data/F3DEX3/$ucode.code
    cp build/$ucode/$ucode.data ../../Mods/HackerOoT/data/F3DEX3/$ucode.data
done

make -C ../../Mods/HackerOoT -j12
#cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
../../Flashcarts/SummerCart64/sw/deployer/target/release/sc64deployer upload ../../Mods/HackerOoT/HackerOoT.z64
printf "\n====\nDone\n====\n"
