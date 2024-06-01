#!python3

import glob

dirs = glob.glob("build/F3DEX3_*")
if len(dirs) == 0:
    raise RuntimeError("Please build one or more microcode versions in build/ first")

smallestDmemAvail = 1000000
smallestImemAvail = 1000000
for dir in dirs:
    toks = dir.split("/")
    assert len(toks) == 2
    ucodename = toks[1]
    dmemAvail = None
    imemAvail = None
    with open(dir + "/" + ucodename + ".sym", "r") as f:
        for l in f:
            toks = l.strip().split(" ")
            if len(toks) != 2:
                continue
            addr = int(toks[0], 16)
            sym = toks[1]
            if sym == "endVariableDmemUse":
                dmemAvail = addr
            elif sym == "rdpCmdBuffer1":
                dmemAvail = addr - dmemAvail
            elif sym == "totalImemUseUpTo1FC8":
                imemAvail = addr
            elif sym == "while_wait_dma_busy":
                imemAvail = addr - imemAvail
        if dmemAvail == None or imemAvail == None:
            raise RuntimeError("Failed to extract addresses from sym file for " + ucodename)
        print(f"{ucodename:<22}: DMEM avail: {dmemAvail:2d} bytes | IMEM avail: {imemAvail//4:2d} instr")
        if dmemAvail < smallestDmemAvail:
            smallestDmemAvail = dmemAvail
        if imemAvail < smallestImemAvail:
            smallestImemAvail = imemAvail

print(f"Minimum               : DMEM avail: {smallestDmemAvail:2d} bytes | IMEM avail: {smallestImemAvail//4:2d} instr")
