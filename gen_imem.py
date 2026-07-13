# Week03 Task2: ARM find-max -> RV32I. Branch/jump imm = BYTE offset (target_PC - cur_PC).
prog = [
 ("addi","x4","x0",0),    # 0x00  x4 = &RESULT (=0)
 ("lw","x5",4,"x4"),      # 0x04  x5 = N
 ("addi","x6","x4",8),    # 0x08  x6 = &NUMBERS[0]
 ("lw","x7",0,"x6"),      # 0x0C  x7 = first number (max so far)
 ("addi","x5","x5",-1),   # 0x10  LOOP: x5--
 ("beq","x5","x0",24),    # 0x14  if x5==0 -> DONE (0x2C), +24
 ("addi","x6","x6",4),    # 0x18  x6 += 4
 ("lw","x8",0,"x6"),      # 0x1C  x8 = next number
 ("bge","x7","x8",-16),   # 0x20  if x7>=x8 -> LOOP (0x10), -16
 ("add","x7","x8","x0"),  # 0x24  x7 = x8 (update max)
 ("beq","x0","x0",-24),   # 0x28  jump -> LOOP (0x10), -24
 ("sw","x7",0,"x4"),      # 0x2C  DONE: RESULT = x7
 ("beq","x0","x0",0),     # 0x30  END: self-loop (halt)
]

# ---------------- encoding helpers ----------------
def reg(r):
    assert r[0] == 'x', f"bad register {r}"
    n = int(r[1:])
    assert 0 <= n < 32, f"reg out of range {r}"
    return n

def u2(val, bits):
    """two's-complement mask to 'bits' width"""
    return val & ((1 << bits) - 1)

# opcode/funct tables
R = {  # mnemonic: (funct7, funct3)
    "add": (0b0000000, 0b000), "sub": (0b0100000, 0b000),
    "sll": (0b0000000, 0b001), "slt": (0b0000000, 0b010),
    "sltu":(0b0000000, 0b011), "xor": (0b0000000, 0b100),
    "srl": (0b0000000, 0b101), "sra": (0b0100000, 0b101),
    "or":  (0b0000000, 0b110), "and": (0b0000000, 0b111),
}
I = {  # mnemonic: funct3   (opcode 0010011)
    "addi": 0b000, "slti": 0b010, "sltiu": 0b011, "xori": 0b100,
    "ori": 0b110, "andi": 0b111,
}
SH = {  # shift-immediate: funct3, funct7
    "slli": (0b001, 0b0000000), "srli": (0b101, 0b0000000),
    "srai": (0b101, 0b0100000),
}
LOAD = {"lb": 0b000, "lh": 0b001, "lw": 0b010, "lbu": 0b100, "lhu": 0b101}
STORE = {"sb": 0b000, "sh": 0b001, "sw": 0b010}
BR = {"beq": 0b000, "bne": 0b001, "blt": 0b100, "bge": 0b101,
      "bltu": 0b110, "bgeu": 0b111}

def enc_r(rd, rs1, rs2, funct7, funct3):
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0b0110011

def enc_i(rd, rs1, imm, funct3, opcode):
    return (u2(imm, 12) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode

def enc_sh(rd, rs1, shamt, funct3, funct7):
    return (funct7 << 25) | (u2(shamt, 5) << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | 0b0010011

def enc_s(rs2, rs1, imm, funct3):
    imm = u2(imm, 12)
    hi = (imm >> 5) & 0x7f
    lo = imm & 0x1f
    return (hi << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (lo << 7) | 0b0100011

def enc_b(rs1, rs2, imm, funct3):
    imm = u2(imm, 13)  # imm[12:0], bit0 = 0
    b12 = (imm >> 12) & 1
    b11 = (imm >> 11) & 1
    b10_5 = (imm >> 5) & 0x3f
    b4_1 = (imm >> 1) & 0xf
    return (b12 << 31) | (b10_5 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (b4_1 << 8) | (b11 << 7) | 0b1100011

def enc_u(rd, imm20, opcode):
    return ((imm20 & 0xfffff) << 12) | (rd << 7) | opcode

def enc_j(rd, imm):
    imm = u2(imm, 21)  # imm[20:0], bit0 = 0
    b20 = (imm >> 20) & 1
    b19_12 = (imm >> 12) & 0xff
    b11 = (imm >> 11) & 1
    b10_1 = (imm >> 1) & 0x3ff
    return (b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | (rd << 7) | 0b1101111

def encode(instr):
    op = instr[0]
    if op in R:
        f7, f3 = R[op]
        return enc_r(reg(instr[1]), reg(instr[2]), reg(instr[3]), f7, f3)
    if op in I:
        return enc_i(reg(instr[1]), reg(instr[2]), instr[3], I[op], 0b0010011)
    if op in SH:
        f3, f7 = SH[op]
        return enc_sh(reg(instr[1]), reg(instr[2]), instr[3], f3, f7)
    if op in LOAD:
        # (op, rd, offset, base)
        return enc_i(reg(instr[1]), reg(instr[3]), instr[2], LOAD[op], 0b0000011)
    if op in STORE:
        # (op, rs2, offset, base)
        return enc_s(reg(instr[1]), reg(instr[3]), instr[2], STORE[op])
    if op in BR:
        return enc_b(reg(instr[1]), reg(instr[2]), instr[3], BR[op])
    if op == "lui":
        return enc_u(reg(instr[1]), instr[2], 0b0110111)
    if op == "auipc":
        return enc_u(reg(instr[1]), instr[2], 0b0010111)
    if op == "jal":
        return enc_j(reg(instr[1]), instr[2])
    if op == "jalr":
        return enc_i(reg(instr[1]), reg(instr[2]), instr[3], 0b000, 0b1100111)
    raise ValueError(f"unknown instruction: {op}")

# ---------------- main ----------------
lines = []
for idx, instr in enumerate(prog):
    word = encode(instr) & 0xffffffff
    bits = format(word, "032b")
    lines.append(bits)
    asm = instr[0] + " " + ", ".join(str(a) for a in instr[1:])
    print(f"{idx:02d}  0x{word:08x}  {bits}  # {asm}")

with open("imem.mem", "w", newline="\n") as f:
    f.write("\n".join(lines) + "\n")

print(f"\nWrote imem.mem ({len(lines)} instructions).")
