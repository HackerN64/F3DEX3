.macro glabel label
    .global \label
    .balign 4
    \label:
.endm

.section .text

.balign 16
glabel gspXXXTextStart
    .incbin "build/XXX/XXX.code"
.balign 16
glabel gspXXXTextEnd

.section .data

.balign 16
glabel gspXXXDataStart
    .incbin "build/XXX/XXX.data"
.balign 16
glabel gspXXXDataEnd
