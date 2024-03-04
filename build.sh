#!/bin/bash
# Note: This is a convenience script for Sauraen to build the microcode, build
# HackerOoT, and upload the ROM to the SummerCart64. You do NOT need to run this
# script to build the microcode. To build the microcode, just run make F3DEX3_BrZ
# or make F3DEX3_BrW.
set -e
make all
cp build/F3DEX3_BrW/F3DEX3_BrW.code ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW.code
cp build/F3DEX3_BrW/F3DEX3_BrW.data ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW.data
cp build/F3DEX3_BrW_PA/F3DEX3_BrW_PA.code ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PA.code
cp build/F3DEX3_BrW_PA/F3DEX3_BrW_PA.data ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PA.data
cp build/F3DEX3_BrW_PB/F3DEX3_BrW_PB.code ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PB.code
cp build/F3DEX3_BrW_PB/F3DEX3_BrW_PB.data ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PB.data
cp build/F3DEX3_BrW_PC/F3DEX3_BrW_PC.code ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PC.code
cp build/F3DEX3_BrW_PC/F3DEX3_BrW_PC.data ../../Mods/HackerOoT/data/F3DEX3/F3DEX3_BrW_PC.data
make -C ../../Mods/HackerOoT -j12
#cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
../../Flashcarts/SummerCart64/sw/deployer/target/release/sc64deployer upload ../../Mods/HackerOoT/HackerOoT.z64
printf "\n====\nDone\n====\n"
