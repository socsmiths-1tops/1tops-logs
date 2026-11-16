`timescale 1ns/1ps
module decode(
    input clk,
    input rst,
    input RegWriteW,
    input [31:0] InstrD,
    input [31:0] PCD,
    input [31:0] PCPlus4D,
    input [31:0] ResultW,
    input [4:0]  RdW,
    input zero, nzero, lt, gt,
    input FlushE,
    input StallE,     // NEW: freeze D/E register during MemStall

    output reg RegWriteE,
    output reg MemWriteE,
    output reg ALUSrcAE,
    output reg [1:0]  ALUSrcBE,
    output reg [1:0]  ResultSrcE,
    output reg [4:0]  ALUControlE,
    output reg [31:0] RD1E,
    output reg [31:0] RD2E,
    output reg [31:0] ImmExtE,
    output reg [31:0] PCE,
    output reg [31:0] PCPlus4E,
    output reg [31:0] InstrE,
    output reg [4:0]  RdE,
    output reg [4:0]  Rs1E,
    output reg [4:0]  Rs2E,
    output reg        is_m_instrE,
    output reg        BranchE,
    output reg        JumpE,
    output reg        IsCSRE,
    output reg        IsMretE
);

wire RegWriteD, MemWriteD;
wire ALUSrcAD;
wire [1:0]  ALUSrcBD;
wire [1:0]  ResultSrcD;
wire [4:0]  ALUControlD;
wire [2:0]  ImmSrcD;
wire [31:0] RD1, RD2;
wire [31:0] ImmExtD;
wire is_m_instr, JumpD, BranchD;
wire IsCSRD, IsMretD;

controller ctrl(
    .opcode      (InstrD[6:0]),
    .func3       (InstrD[14:12]),
    .func7       (InstrD[31:25]),
    .rs2         (InstrD[24:20]),
    .zero        (zero),
    .nzero       (nzero),
    .lt          (lt),
    .gt          (gt),
    .RegWrite    (RegWriteD),
    .MemWrite    (MemWriteD),
    .ALUSrcA     (ALUSrcAD),
    .ALUSrcB     (ALUSrcBD),
    .ResultSrc   (ResultSrcD),
    .ImmSrc      (ImmSrcD),
    .ALUControl  (ALUControlD),
    .is_m_instr  (is_m_instr),
    .Branch      (BranchD),
    .Jump        (JumpD),
    .IsCSR       (IsCSRD),
    .IsMret      (IsMretD)
);

reg_file rf(
    .clk      (clk),
    .rst      (rst),
    .wr_en    (RegWriteW),
    .rd_addr1 (InstrD[19:15]),
    .rd_addr2 (InstrD[24:20]),
    .wr_addr  (RdW),
    .wr_data  (ResultW),
    .rd_data1 (RD1),
    .rd_data2 (RD2)
);

ImmExt imm_ext(
    .imm_in (InstrD[31:7]),
    .ImmSrc (ImmSrcD),
    .ImmExt (ImmExtD)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        RegWriteE   <= 1'b0;
        MemWriteE   <= 1'b0;
        ALUSrcAE    <= 1'b0;
        ALUSrcBE    <= 2'b00;
        ResultSrcE  <= 2'b00;
        ALUControlE <= 5'b00000;
        RD1E        <= 32'b0;
        RD2E        <= 32'b0;
        ImmExtE     <= 32'b0;
        PCE         <= 32'b0;
        PCPlus4E    <= 32'b0;
        InstrE      <= 32'h00000013;
        RdE         <= 5'b0;
        Rs1E        <= 5'b0;
        Rs2E        <= 5'b0;
        is_m_instrE <= 1'b0;
        BranchE     <= 1'b0;
        JumpE       <= 1'b0;
        IsCSRE      <= 1'b0;
        IsMretE     <= 1'b0;
    end
    else if (StallE) begin
        // Hold everything -- a slow APB read is in flight in the
        // Memory stage. Do not advance, do not flush; just freeze.
    end
    else if (FlushE) begin
        RegWriteE   <= 1'b0;
        MemWriteE   <= 1'b0;
        ALUSrcAE    <= 1'b0;
        ALUSrcBE    <= 2'b00;
        ResultSrcE  <= 2'b00;
        ALUControlE <= 5'b00000;
        RD1E        <= 32'b0;
        RD2E        <= 32'b0;
        ImmExtE     <= 32'b0;
        PCE         <= 32'b0;
        PCPlus4E    <= 32'b0;
        InstrE      <= 32'h00000013;
        RdE         <= 5'b0;
        Rs1E        <= 5'b0;
        Rs2E        <= 5'b0;
        is_m_instrE <= 1'b0;
        BranchE     <= 1'b0;
        JumpE       <= 1'b0;
        IsCSRE      <= 1'b0;
        IsMretE     <= 1'b0;
    end
    else begin
        RegWriteE   <= RegWriteD;
        MemWriteE   <= MemWriteD;
        ALUSrcAE    <= ALUSrcAD;
        ALUSrcBE    <= ALUSrcBD;
        ResultSrcE  <= ResultSrcD;
        ALUControlE <= ALUControlD;
        RD1E        <= RD1;
        RD2E        <= RD2;
        ImmExtE     <= ImmExtD;
        PCE         <= PCD;
        PCPlus4E    <= PCPlus4D;
        InstrE      <= InstrD;
        RdE         <= InstrD[11:7];
        Rs1E        <= ((InstrD[6:0] == 7'b0110111) || (InstrD[6:0] == 7'b0010111) ||
                         (InstrD[6:0] == 7'b1101111)) ? 5'b0 : InstrD[19:15];
        Rs2E        <= ((InstrD[6:0] == 7'b0110111) || (InstrD[6:0] == 7'b0010111) ||
                         (InstrD[6:0] == 7'b1101111)) ? 5'b0 : InstrD[24:20];
        is_m_instrE <= is_m_instr;
        BranchE     <= BranchD;
        JumpE       <= JumpD;
        IsCSRE      <= IsCSRD;
        IsMretE     <= IsMretD;
    end
end

endmodule
