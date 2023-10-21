#!/bin/bash
set -e
make F3DEX3_BrW
cp build/F3DEX3_BrW/F3DEX3_BrW.code ../../Mods/HackerOoT/data/F3DEX3_BrW.code
cp build/F3DEX3_BrW/F3DEX3_BrW.data ../../Mods/HackerOoT/data/F3DEX3_BrW.data
make -C ../../Mods/HackerOoT -j12
cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
printf "\n====\nDone\n====\n"
