`timescale 1ns/1ps
module execute(
    input clk,
    input rst,

    input [1:0]  ForwardAE,
    input [1:0]  ForwardBE,

    input [31:0] RD1E,
    input [31:0] RD2E,
    input [31:0] ResultW,
    input [31:0] InstrE,
    input [31:0] ImmExtE,
    input [31:0] PCE,
    input [31:0] PCPlus4E,
    input [4:0]  RdE,
    input [4:0]  ALUControlE,
    input        RegWriteE,
    input        MemWriteE,
    input        BranchE,
    input        ALUSrcAE,
    input [1:0]  ALUSrcBE,
    input [1:0]  ResultSrcE,
    input        is_m_instrE,

    input        IsCSRE,
    input        IsMretE,

    input        irq_extern,
    input        irq_timer,
    input        irq_software,

    input        StallM,     // NEW: freeze E/M register during MemStall
    output       DivStallE,  // iterative divide in progress (stall F/D/E)

    output reg [31:0] ALUResultM,
    output reg [31:0] WriteDataM,
    output reg [31:0] PCPlus4M,
    output reg [31:0] m_resultM,
    output reg [31:0] InstrM,
    output reg [4:0]  RdM,
    output reg        RegWriteM,
    output reg        MemWriteM,
    output reg [1:0]  ResultSrcM,
    output reg        is_m_instrM,
    output reg [31:0] ImmExtM,
    output reg [31:0] CSRDataM,
    output reg        IsCSRM,

    output [31:0] PCTargetE,
    output [31:0] ALUResultE,
    output [1:0]  PCSrcE,
    output        zero, nzero, lt, gt,

    output [31:0] mtvec_out,
    output [31:0] mepc_out,
    output        trap_taken,
    output        mret_taken
);

wire [31:0] tempA, tempB;
wire [31:0] SrcA, SrcB;

wire [31:0] ForwardResultM;
assign ForwardResultM = is_m_instrM ? m_resultM : ALUResultM;

mux3 #(32) fwdA(
    RD1E, ResultW, ForwardResultM, ForwardAE, tempA
);
mux2 #(32) muxA(
    tempA, PCE, ALUSrcAE, SrcA
);
mux3 #(32) fwdB(
    RD2E, ResultW, ForwardResultM, ForwardBE, tempB
);
mux3 #(32) muxB(
    tempB, ImmExtE, 32'd4, ALUSrcBE, SrcB
);

wire [31:0] ALUResult;
wire [31:0] m_result;

alu_unit alu(
    SrcA, SrcB, ALUControlE,
    ALUResult, zero, nzero, lt, gt
);

mdu_wrapper MDU(
    .clk       (clk),
    .rst       (rst),
    .rs1       (SrcA),
    .rs2       (SrcB),
    .funct3    (InstrE[14:12]),
    .func7     (InstrE[31:25]),
    .op        (InstrE[6:0]),
    .hold      (StallM),
    .kill      (trap_taken),
    .m_result  (m_result),
    .div_stall (DivStallE)
);

assign ALUResultE = ALUResult;

adder pc_adder(PCE, ImmExtE, PCTargetE);

assign PCSrcE[0] = (BranchE & zero)  |
                   (BranchE & nzero) |
                   (BranchE & lt)    |
                   (BranchE & gt)    |
                   (InstrE[6:0] == 7'b1101111);
assign PCSrcE[1] = (InstrE[6:0] == 7'b1100111);

wire [31:0] csr_wdata = InstrE[14] ? {27'b0, InstrE[19:15]}
                                    : SrcA;

wire csr_wen = IsCSRE && !IsMretE;

wire [31:0] csr_rdata;

csr_unit csr(
    .instr_execute (InstrE),
    .clk         (clk),
    .rst         (rst),
    .csr_wen     (csr_wen),
    .csr_addr    (InstrE[31:20]),
    .csr_wdata   (csr_wdata),
    .csr_op      (InstrE[14:12]),
    .csr_rdata   (csr_rdata),
    .irq_extern  (irq_extern),
    .irq_timer   (irq_timer),
    .irq_software(irq_software),
    .pc_execute  (PCE),
    .mtvec_out   (mtvec_out),
    .mepc_out    (mepc_out),
    .trap_taken  (trap_taken),
    .mret_taken  (mret_taken),
    .mret_instr  (IsMretE),
    .hold        (StallM)
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        RegWriteM  <= 1'b0;
        MemWriteM  <= 1'b0;
        ResultSrcM <= 2'b00;
        RdM        <= 5'd0;
        ALUResultM <= 32'd0;
        WriteDataM <= 32'd0;
        PCPlus4M   <= 32'd0;
        m_resultM  <= 32'd0;
        is_m_instrM<= 1'b0;
        InstrM     <= 32'd0;
        ImmExtM    <= 32'd0;
        CSRDataM   <= 32'd0;
        IsCSRM     <= 1'b0;
    end
    else if (StallM) begin
        // Hold everything -- a slow APB read is in flight. Freeze the
        // EX/MEM register exactly in place so the Memory stage keeps
        // presenting the same address until the read completes.
    end
    else if (trap_taken || mret_taken || DivStallE) begin
        // trap/mret kill the E instruction; a divide in progress sends a bubble
        RegWriteM  <= 1'b0;
        MemWriteM  <= 1'b0;
        ResultSrcM <= 2'b00;
        RdM        <= 5'd0;
        ALUResultM <= 32'd0;
        WriteDataM <= 32'd0;
        PCPlus4M   <= 32'd0;
        m_resultM  <= 32'd0;
        is_m_instrM<= 1'b0;
        InstrM     <= 32'd0;
        ImmExtM    <= 32'd0;
        CSRDataM   <= 32'd0;
        IsCSRM     <= 1'b0;
    end
    else begin
        RegWriteM  <= RegWriteE;
        MemWriteM  <= MemWriteE;
        ResultSrcM <= ResultSrcE;
        RdM        <= RdE;
        ALUResultM <= ALUResult;
        WriteDataM <= tempB;
        PCPlus4M   <= PCPlus4E;
        m_resultM  <= m_result;
        is_m_instrM<= is_m_instrE;
        InstrM     <= InstrE;
        ImmExtM    <= ImmExtE;
        CSRDataM   <= csr_rdata;
        IsCSRM     <= IsCSRE;
    end
end

endmodule
