    # Create object files

    echo .macro glabel label > object.s
    echo     .global \\label >> object.s
    echo     .balign 4 >> object.s
    echo     \\label: >> object.s
    echo .endm >> object.s
    echo  >> object.s
    echo .section .text >> object.s
    echo  >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$1\_fifoTextStart >> object.s
    echo     .incbin \"build/$1/$1.code\" >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$1\_fifoTextEnd >> object.s
    echo  >> object.s
    echo .section .data >> object.s
    echo  >> object.s
    echo .balign 16 >> object.s >> object.s
    echo glabel gsp$1\_fifoDataStart >> object.s
    echo     .incbin \"build/$1/$1.data\" >> object.s
    echo .balign 16 >> object.s
    echo glabel gsp$1\_fifoDataEnd >> object.s
    echo >> object.s
    
    mips64-linux-gnu-as -march=vr4300 -mabi=32 -I . object.s -o build/$1/gsp$1.fifo.o
