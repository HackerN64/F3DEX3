#!/bin/bash
set -e
make F3DEX3_BrW
cp build/F3DEX3_BrW/F3DEX3_BrW.code ../../Mods/HackerOoT/data/F3DEX3_BrW.code
cp build/F3DEX3_BrW/F3DEX3_BrW.data ../../Mods/HackerOoT/data/F3DEX3_BrW.data
make -C ../../Mods/HackerOoT -j12
#cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
../../Flashcarts/SummerCart64/sw/deployer/target/debug/sc64deployer upload ../../Mods/HackerOoT/HackerOoT.z64
printf "\n====\nDone\n====\n"
