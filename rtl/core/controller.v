`timescale 1ns/1ps

module controller(
    input  [6:0] opcode,
    input  [2:0] func3,
    input  [6:0] func7,
    input  [4:0] rs2,        // NEW: instr[24:20], distinguishes mret/ecall/ebreak
    input  zero, nzero, lt, gt,

    output RegWrite, MemWrite, ALUSrcA, Branch, Jump,
    output [1:0] ALUSrcB,
    output [1:0] ResultSrc,
    output [2:0] ImmSrc,
    output [4:0] ALUControl,
    output       is_m_instr,
    output       IsCSR,
    output       IsMret
);

wire [1:0] ALUOp;
wire IsCSR_raw;

main_decoder md(
    .opcode    (opcode),
    .ResultSrc (ResultSrc),
    .MemWrite  (MemWrite),
    .Branch    (Branch),
    .ALUSrcA   (ALUSrcA),
    .ALUSrcB   (ALUSrcB),
    .RegWrite  (RegWrite),
    .Jump      (Jump),
    .ImmSrc    (ImmSrc),
    .ALUOp     (ALUOp),
    .IsCSR     (IsCSR_raw),
    .IsMret    ()
);

alu_decoder ad(
    .opcode     (opcode),
    .ALUOp      (ALUOp),
    .func3      (func3),
    .func7      (func7),
    .ALUControl (ALUControl)
);

// is_m_instr: M-extension instruction (opcode=R-type, func7=0000001)
assign is_m_instr = (opcode == 7'b0110011) && (func7 == 7'b0000001);

// CSR: opcode=SYSTEM and funct3 != 000
// mret: opcode=SYSTEM, funct3 == 000, AND rs2==00010 specifically.
// ecall (rs2=00000) and ebreak (rs2=00001) ALSO have func3==000 and the
// same opcode -- without checking rs2, they were being silently decoded
// as mret, causing the core to jump to mepc (0 right after reset) on any
// ecall/ebreak in the instruction stream. This core has no illegal-
// instruction/ecall exception path, so ecall/ebreak still won't trap
// properly after this fix -- but they will no longer masquerade as mret.
assign IsCSR  = IsCSR_raw && (func3 != 3'b000);
assign IsMret = IsCSR_raw && (func3 == 3'b000) && (rs2 == 5'b00010);

endmodule
