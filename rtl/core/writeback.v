`timescale 1ns/1ps
module writeback(
    input        RegWriteW,
    input        is_m_instrW,
    input [1:0]  ResultSrcW,
    input [31:0] ImmExtW,
    input [31:0] ALUResultW,
    input [31:0] m_resultW,
    input [31:0] ReadDataW,
    input [31:0] PCPlus4W,
    input [31:0] CSRDataW,
    input        IsCSRW,      // NEW: is this a CSR instruction?
    output [31:0] ResultW
);

wire [31:0] Op_ResultW;
wire [31:0] MuxOut;

mux2 #(32) mux_IvsM(
    ALUResultW,
    m_resultW,
    is_m_instrW,
    Op_ResultW
);

// ResultSrc=11: ImmExt for LUI, CSRData for CSR
// Distinguish using IsCSRW flag
wire [31:0] Src11 = IsCSRW ? CSRDataW : ImmExtW;

mux4 #(32) result_mux(
    Op_ResultW,
    ReadDataW,
    PCPlus4W,
    Src11,
    ResultSrcW,
    ResultW
);

endmodule
