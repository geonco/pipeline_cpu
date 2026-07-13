_start: addi x4, x0, 0
        lw   x5, 4(x4)
        addi x6, x4, 8
        lw   x7, 0(x6)
LOOP:   addi x5, x5, -1
        beq  x5, x0, DONE
        addi x6, x6, 4
        lw   x8, 0(x6)
        bge  x7, x8, LOOP
        add  x7, x8, x0
        beq  x0, x0, LOOP
DONE:   sw   x7, 0(x4)
END:    beq  x0, x0, END