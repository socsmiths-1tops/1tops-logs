`timescale 1ns/1ps

module main_decoder(
    input  [6:0] opcode,
    output [1:0] ResultSrc,
    output MemWrite, Branch, ALUSrcA,
    output [1:0] ALUSrcB,
    output RegWrite, Jump,
    output [2:0] ImmSrc,
    output [1:0] ALUOp,
    output        IsCSR,    // NEW: this is a CSR instruction
    output        IsMret    // NEW: this is mret instruction
);

reg [15:0] controls;

always @(*) begin
    case (opcode)
        // RegWrite_ImmSrc_ALUSrcA_ALUSrcB_MemWrite_ResultSrc_Branch_ALUOp_Jump_IsCSR_IsMret
        7'b0000011: controls = 16'b1_000_0_01_0_01_0_00_0_0_0; // lw
        7'b0100011: controls = 16'b0_001_0_01_1_00_0_00_0_0_0; // sw
        7'b0110011: controls = 16'b1_000_0_00_0_00_0_10_0_0_0; // R-type, m-ext
        7'b1100011: controls = 16'b0_010_0_00_0_00_1_00_0_0_0; // B-Type
        7'b0010011: controls = 16'b1_000_0_01_0_00_0_10_0_0_0; // I-type ALU
        7'b1101111: controls = 16'b1_011_1_10_0_10_0_00_1_0_0; // jal
        7'b0110111: controls = 16'b1_100_0_01_0_11_0_00_0_0_0; // lui
        7'b0010111: controls = 16'b1_100_1_01_0_00_0_00_0_0_0; // auipc
        7'b1100111: controls = 16'b1_000_0_01_0_10_0_00_1_0_0; // jalr
        7'b1110011: begin // SYSTEM — CSR or mret
            // mret: instr = 32'h30200073 (funct3=000, rs2=00010)
            // CSR:  funct3 != 000
            // We decode IsCSR and IsMret in controller using funct3
            controls = 16'b1_000_0_00_0_11_0_00_0_1_0; // CSR default
                       // ResultSrc=11 means CSR read result
        end
        default:    controls = 16'b0_000_0_00_0_00_0_00_0_0_0;
    endcase
end

assign {RegWrite, ImmSrc, ALUSrcA, ALUSrcB, MemWrite,
        ResultSrc, Branch, ALUOp, Jump, IsCSR, IsMret} = controls;

endmodule
