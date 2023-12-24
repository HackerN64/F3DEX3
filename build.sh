#!/bin/bash
# Note: This is a convenience script for Sauraen to build the microcode, build
# HackerOoT, and upload the ROM to the SummerCart64. You do NOT need to run this
# script to build the microcode. To build the microcode, just run make F3DEX3_BrZ
# or make F3DEX3_BrW.
set -e
make F3DEX3_BrW
cp build/F3DEX3_BrW/F3DEX3_BrW.code ../../Mods/HackerOoT/data/F3DEX3_BrW.code
cp build/F3DEX3_BrW/F3DEX3_BrW.data ../../Mods/HackerOoT/data/F3DEX3_BrW.data
make -C ../../Mods/HackerOoT -j12
#cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
../../Flashcarts/SummerCart64/sw/deployer/target/debug/sc64deployer upload ../../Mods/HackerOoT/HackerOoT.z64
printf "\n====\nDone\n====\n"
