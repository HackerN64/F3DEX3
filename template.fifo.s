.macro glabel label
    .global \label
    .balign 4
    \label:
.endm

.section .text

.balign 16
glabel gspXXX_fifoTextStart
    .incbin "build/XXX/XXX.code"
.balign 16
glabel gspXXX_fifoTextEnd

.section .data

.balign 16
glabel gspXXX_fifoDataStart
    .incbin "build/XXX/XXX.data"
.balign 16
glabel gspXXX_fifoDataEnd
