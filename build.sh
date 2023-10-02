#!/bin/bash
set -e
make F3DEX3
cp build/F3DEX3/F3DEX3.code ../../Mods/HackerOoT/data/F3DEX3.code
cp build/F3DEX3/F3DEX3.data ../../Mods/HackerOoT/data/F3DEX3.data
make -C ../../Mods/HackerOoT -j12
cp ../../Mods/HackerOoT/HackerOoT.z64 /media/`whoami`/SOME2/
printf "\n====\nDone\n====\n"
