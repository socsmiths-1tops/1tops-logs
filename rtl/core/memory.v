`timescale 1ns/1ps
module memory(
    input clk,
    input rst,
    input [31:0] ImmExtM,
    input        RegWriteM,
    input        MemWriteM,
    input [1:0]  ResultSrcM,
    input [4:0]  RdM,
    input        is_m_instrM,
    input [31:0] InstrM,
    input [31:0] ALUResultM,
    input [31:0] WriteDataM,
    input [31:0] PCPlus4M,
    input [31:0] m_resultM,
    input [31:0] ReadDataMem,
    input [31:0] CSRDataM,
    input        IsCSRM,

    input        StallM,    // NEW: freeze M/W register during MemStall

    output        MemWriteOut,
    output [31:0] DataAddr,
    output [31:0] DataWrite,

    output reg        RegWriteW,
    output reg [1:0]  ResultSrcW,
    output reg [4:0]  RdW,
    output reg [31:0] ALUResultW,
    output reg [31:0] ReadDataW,
    output reg [31:0] PCPlus4W,
    output reg [31:0] m_resultW,
    output reg        is_m_instrW,
    output reg [31:0] ImmExtW,
    output reg [31:0] CSRDataW,
    output reg        IsCSRW
);

wire [31:0] ParsedData;

assign MemWriteOut = MemWriteM;
assign DataAddr    = ALUResultM;
// Bug #25: store data must sit on the byte lanes being written. It was
// passed unshifted, so SB/SH to a non-zero offset wrote the wrong byte
// (hidden in core compliance: that TB's memory model shifted it itself).
// Replicate per size (standard RISC-V bus convention; lanes via byte enables).
assign DataWrite   = (InstrM[13:12] == 2'b00) ? {4{WriteDataM[7:0]}}  :
                     (InstrM[13:12] == 2'b01) ? {2{WriteDataM[15:0]}} :
                                                WriteDataM;

data_parser parser(
    .func3    (InstrM[14:12]),
    .byte_off (ALUResultM[1:0]),
    .mem_word (ReadDataMem),
    .data_out (ParsedData)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        RegWriteW   <= 1'b0;
        ResultSrcW  <= 2'b0;
        RdW         <= 5'b0;
        ALUResultW  <= 32'b0;
        ReadDataW   <= 32'b0;
        PCPlus4W    <= 32'b0;
        m_resultW   <= 32'b0;
        is_m_instrW <= 1'b0;
        ImmExtW     <= 32'b0;
        CSRDataW    <= 32'b0;
        IsCSRW      <= 1'b0;
    end
    else if (StallM) begin
        // Hold everything -- ReadDataMem/ParsedData may not be valid
        // yet this cycle. Do NOT let it land in Writeback; wait for
        // the real data, captured on the cycle StallM finally drops.
    end
    else begin
        RegWriteW   <= RegWriteM;
        ResultSrcW  <= ResultSrcM;
        RdW         <= RdM;
        ALUResultW  <= ALUResultM;
        ReadDataW   <= ParsedData;
        PCPlus4W    <= PCPlus4M;
        m_resultW   <= m_resultM;
        is_m_instrW <= is_m_instrM;
        ImmExtW     <= ImmExtM;
        CSRDataW    <= CSRDataM;
        IsCSRW      <= IsCSRM;
    end
end

endmodule
