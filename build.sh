#!/bin/bash
set -e
make F3DEX3
cp build/F3DEX3/F3DEX3.code ../../Mods/HackerOOT/moducode_text.bin
cp build/F3DEX3/F3DEX3.data ../../Mods/HackerOOT/moducode_data.bin
touch ../../Mods/HackerOOT/data/rsp.rodata.s
make -C ../../Mods/HackerOOT -j12
cp ../../Mods/HackerOOT/HackerOoT.z64 /media/`whoami`/SOME2/
printf "\n====\nDone\n====\n"
