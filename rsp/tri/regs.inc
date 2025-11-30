// Tri write vector regs:

// H = highest on screen = lowest Y value; then M = mid, L = low

tHPos equ $v14
tMPos equ $v2
tLPos equ $v10

tPosMmH equ $v6
tPosLmH equ $v8
tPosHmM equ $v11

tSubPxHF equ $v4
tSubPxHI equ $v26

tPosCatF equ $v25
tPosCatI equ $v15

tXPF equ $v16
tXPI equ $v17
tXPRcpF equ $v23
tXPRcpI equ $v24

t1WF equ $v14 
t1WI equ $v13
tMx1W equ $v25
tMnWF equ $v10
tMnWI equ $v25

tSTWHMF equ $v25
tSTWHMI equ $v22
tSTWLF equ $v13
tSTWLI equ $v10

tHAtF equ $v5
tMAtF equ $v27
tLAtF equ $v9
tHAtI equ $v18
tMAtI equ $v19
tLAtI equ $v21

tAtLmHF equ $v10
tAtLmHI equ $v9
tAtMmHF equ $v13
tAtMmHI equ $v27

tDaDxF equ $v2
tDaDxI equ $v3
tDaDyF equ $v6
tDaDyI equ $v27
tDaDeF equ $v8
tDaDeI equ $v9
