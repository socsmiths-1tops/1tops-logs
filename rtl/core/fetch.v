`timescale 1ns/1ps

module fetch(
    input clk,
    input rst,
    input FlushD,
    input StallD,
    input StallF,

    input [1:0]  PCSrcE,
    input [31:0] PCTargetE,
    input [31:0] ALUResultE,

    // Interrupt/trap PC sources (from csr_unit)
    input [31:0] mtvec,       // trap vector address
    input [31:0] mepc,        // return address for mret
    input        trap_taken,  // redirect to mtvec
    input        mret_taken,  // redirect to mepc

    input [31:0] InstrF,

    output [31:0] PCF,
    // PC value PCF will hold after the next edge: address for the
    // synchronous-read IMEM macro (data valid while PCF holds it)
    output [31:0] PCFetchNext,

    output reg [31:0] InstrD,
    output reg [31:0] PCD,
    output reg [31:0] PCPlus4D
);

wire [31:0] PC;
wire [31:0] PCNext;
wire [31:0] PCPlus4;
wire [31:0] PCFromPipeline;
reg trap_redirect_q;

assign PCF = PC;

// Original 3-way PC mux (pipeline: PC+4, branch target, JALR)
mux3 #(32) pc_mux(
    PCPlus4,
    PCTargetE,
    ALUResultE,
    PCSrcE,
    PCFromPipeline
);

// Interrupt/mret override — highest priority
// trap_taken overrides everything → jump to mtvec
// mret_taken overrides pipeline   → jump to mepc
// Normal → use pipeline result
// DEBUG: disable trap/mret temporarily
// trap_redirect_q masks stale branch/jump PCSrcE for one cycle after trap/mret.
always @(posedge clk or posedge rst) begin
    if (rst)
        trap_redirect_q <= 1'b0;
    else
        trap_redirect_q <= trap_taken | mret_taken;
end

assign PCNext = trap_taken      ? mtvec :
                mret_taken      ? mepc  :
                trap_redirect_q ? PCPlus4 :
                                  PCFromPipeline;

wire pc_hold = StallF & ~trap_taken & ~mret_taken;
assign PCFetchNext = pc_hold ? PC : PCNext;

reset_ff #(32) pcreg(
    clk,
    rst,
    pc_hold,
    PCNext,
    PC
);

adder add1(
    PC,
    32'd4,
    PCPlus4
);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        InstrD   <= 32'h00000013;
        PCD      <= 32'b0;
        PCPlus4D <= 32'b0;
    end
    else if (FlushD || trap_taken || mret_taken) begin
        InstrD   <= 32'h00000013; // NOP
        PCD      <= 32'b0;
        PCPlus4D <= 32'b0;
    end
    else if (!StallD) begin
        InstrD   <= InstrF;
        PCD      <= PC;
        PCPlus4D <= PCPlus4;
    end
end

endmodule
