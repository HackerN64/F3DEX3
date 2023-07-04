#!/bin/bash
set -e
cp ../../Mods/HackerOOT/origucode_text.bin ../../Mods/HackerOOT/moducode_text.bin
cp ../../Mods/HackerOOT/origucode_data.bin ../../Mods/HackerOOT/moducode_data.bin
touch ../../Mods/HackerOOT/data/rsp.rodata.s
make -C ../../Mods/HackerOOT -j12
cp ../../Mods/HackerOOT/HackerOoT.z64 /media/`whoami`/SOME2/
printf "\n====\nDone\n====\n"
