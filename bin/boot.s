ADDI 1,0,64
ADDI 2,0,0
ADDI 3,0,0
ADDI 4,0,0
ADDI 5,0,7
ESET 5
IN 6
IN 7
IN 8
IN 9
SLLI 6,6,24
SLLI 7,7,16
SLLI 8,8,8
ADD 6,6,7
ADD 6,6,8
ADD 6,6,9
BEQ 6,0,4
ISW 1,6
ADDI 1,1,1
J -13
ECLR
CMU
