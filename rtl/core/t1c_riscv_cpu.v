`timescale 1ns/1ps

module t1c_riscv_cpu (

    input clk,
    input reset,

    output [31:0] InstrAddr,
    output [31:0] InstrAddrNext,   // next fetch address (sync-read IMEM)
    input  [31:0] InstrF,

    output        MemWrite,
    output        MemRead,     // load in Memory stage (qualifies data-bus reads)
    output [31:0] WriteData,
    output [31:0] DataAdr,
    output [31:0] DataAdrNext,     // next Memory-stage address (sync-read DMEM)
    input  [31:0] ReadData,

    input         irq_extern,
    input         irq_timer,
    input         irq_software,

    // NEW: asserted by the SoC interconnect while a slow APB read issued
    // from the Memory stage hasn't completed yet. Freezes the entire
    // pipeline until the real data is available.
    input         MemStall,

    output [1:0]  MemSize,
    output        MemUnsigned,

    output [31:0] PCD,
    output [31:0] ResultW,
    output [31:0] InstrD

);

wire [31:0] PCPlus4D;

wire        RegWriteE, MemWriteE;
wire        ALUSrcAE;
wire [1:0]  ALUSrcBE;
wire [1:0]  ResultSrcE;
wire [4:0]  ALUControlE;
wire [31:0] RD1E, RD2E, ImmExtE, PCE, PCPlus4E, InstrE;
wire [4:0]  RdE, Rs1E, Rs2E;
wire        is_m_instrE;
wire        BranchE, JumpE;
wire        IsCSRE, IsMretE;

wire [1:0]  PCSrcE;
wire [31:0] ImmExtM;
wire        RegWriteM, MemWriteM;
wire [1:0]  ResultSrcM;
wire [31:0] ALUResultM;
wire [31:0] ALUResultE;
wire [31:0] WriteDataM;
wire [31:0] PCPlus4M;
wire [31:0] m_resultM;
wire [31:0] InstrM;
wire [4:0]  RdM;
wire        is_m_instrM;
wire [31:0] CSRDataM;
wire        IsCSRM;

wire        RegWriteW;
wire [1:0]  ResultSrcW;
wire [4:0]  RdW;
wire [31:0] ALUResultW;
wire [31:0] ReadDataW;
wire [31:0] PCPlus4W;
wire [31:0] m_resultW;
wire        is_m_instrW;
wire [31:0] ImmExtW;
wire [31:0] CSRDataW;
wire        IsCSRW;

wire [1:0]  ForwardAE, ForwardBE;
wire        StallF, StallD, StallE, StallM, FlushD, FlushE, lwStall;
wire        DivStallE;

wire [31:0] mtvec_out;
wire [31:0] mepc_out;
wire        trap_taken;
wire        mret_taken;

wire [31:0] PCTargetE;
wire        zero, lt, gt, nzero;

assign MemSize     = InstrM[13:12];
// E/M register holds on StallM, else loads the Execute result
assign DataAdrNext = StallM ? ALUResultM : ALUResultE;
assign MemRead     = (ResultSrcM == 2'b01);
assign MemUnsigned = InstrM[14];

fetch fetch_stage(
    .clk        (clk),
    .rst        (reset),
    .FlushD     (FlushD),
    .StallD     (StallD),
    .StallF     (StallF),
    .PCSrcE     (PCSrcE),
    .PCTargetE  (PCTargetE),
    .ALUResultE (ALUResultE),
    .mtvec      (mtvec_out),
    .mepc       (mepc_out),
    .trap_taken (trap_taken),
    .mret_taken (mret_taken),
    .InstrF     (InstrF),
    .PCF        (InstrAddr),
    .PCFetchNext(InstrAddrNext),
    .InstrD     (InstrD),
    .PCD        (PCD),
    .PCPlus4D   (PCPlus4D)
);

decode decode_stage(
    .clk        (clk),
    .rst        (reset),
    .RegWriteW  (RegWriteW),
    .InstrD     (InstrD),
    .PCD        (PCD),
    .PCPlus4D   (PCPlus4D),
    .ResultW    (ResultW),
    .zero       (zero),
    .nzero      (nzero),
    .lt         (lt),
    .gt         (gt),
    .RdW        (RdW),
    .FlushE     (FlushE),
    .StallE     (StallE),
    .RegWriteE  (RegWriteE),
    .MemWriteE  (MemWriteE),
    .ALUSrcAE   (ALUSrcAE),
    .ALUSrcBE   (ALUSrcBE),
    .ResultSrcE (ResultSrcE),
    .ALUControlE(ALUControlE),
    .RD1E       (RD1E),
    .RD2E       (RD2E),
    .ImmExtE    (ImmExtE),
    .PCE        (PCE),
    .PCPlus4E   (PCPlus4E),
    .InstrE     (InstrE),
    .RdE        (RdE),
    .Rs1E       (Rs1E),
    .Rs2E       (Rs2E),
    .is_m_instrE(is_m_instrE),
    .BranchE    (BranchE),
    .JumpE      (JumpE),
    .IsCSRE     (IsCSRE),
    .IsMretE    (IsMretE)
);

execute execute_stage(
    .clk          (clk),
    .rst          (reset),
    .ForwardAE    (ForwardAE),
    .ForwardBE    (ForwardBE),
    .RD1E         (RD1E),
    .RD2E         (RD2E),
    .ResultW      (ResultW),
    .InstrE       (InstrE),
    .ImmExtE      (ImmExtE),
    .PCE          (PCE),
    .PCPlus4E     (PCPlus4E),
    .RdE          (RdE),
    .ALUControlE  (ALUControlE),
    .RegWriteE    (RegWriteE),
    .MemWriteE    (MemWriteE),
    .BranchE      (BranchE),
    .ALUSrcAE     (ALUSrcAE),
    .ALUSrcBE     (ALUSrcBE),
    .ResultSrcE   (ResultSrcE),
    .is_m_instrE  (is_m_instrE),
    .IsCSRE       (IsCSRE),
    .IsMretE      (IsMretE),
    .irq_extern   (irq_extern),
    .irq_timer    (irq_timer),
    .irq_software (irq_software),
    .StallM       (StallM),
    .DivStallE    (DivStallE),
    .ALUResultM   (ALUResultM),
    .WriteDataM   (WriteDataM),
    .PCPlus4M     (PCPlus4M),
    .m_resultM    (m_resultM),
    .InstrM       (InstrM),
    .RdM          (RdM),
    .RegWriteM    (RegWriteM),
    .MemWriteM    (MemWriteM),
    .ResultSrcM   (ResultSrcM),
    .is_m_instrM  (is_m_instrM),
    .ImmExtM      (ImmExtM),
    .CSRDataM     (CSRDataM),
    .IsCSRM       (IsCSRM),
    .PCTargetE    (PCTargetE),
    .ALUResultE   (ALUResultE),
    .PCSrcE       (PCSrcE),
    .zero         (zero),
    .nzero        (nzero),
    .lt           (lt),
    .gt           (gt),
    .mtvec_out    (mtvec_out),
    .mepc_out     (mepc_out),
    .trap_taken   (trap_taken),
    .mret_taken   (mret_taken)
);

memory memory_stage(
    .clk          (clk),
    .rst          (reset),
    .ImmExtM      (ImmExtM),
    .RegWriteM    (RegWriteM),
    .MemWriteM    (MemWriteM),
    .ResultSrcM   (ResultSrcM),
    .RdM          (RdM),
    .is_m_instrM  (is_m_instrM),
    .InstrM       (InstrM),
    .ALUResultM   (ALUResultM),
    .WriteDataM   (WriteDataM),
    .PCPlus4M     (PCPlus4M),
    .m_resultM    (m_resultM),
    .ReadDataMem  (ReadData),
    .CSRDataM     (CSRDataM),
    .IsCSRM       (IsCSRM),
    .StallM       (StallM),
    .MemWriteOut  (MemWrite),
    .DataAddr     (DataAdr),
    .DataWrite    (WriteData),
    .RegWriteW    (RegWriteW),
    .ResultSrcW   (ResultSrcW),
    .RdW          (RdW),
    .ALUResultW   (ALUResultW),
    .ReadDataW    (ReadDataW),
    .PCPlus4W     (PCPlus4W),
    .m_resultW    (m_resultW),
    .is_m_instrW  (is_m_instrW),
    .ImmExtW      (ImmExtW),
    .CSRDataW     (CSRDataW),
    .IsCSRW       (IsCSRW)
);

writeback writeback_stage(
    .RegWriteW   (RegWriteW),
    .is_m_instrW (is_m_instrW),
    .ResultSrcW  (ResultSrcW),
    .ALUResultW  (ALUResultW),
    .m_resultW   (m_resultW),
    .ReadDataW   (ReadDataW),
    .PCPlus4W    (PCPlus4W),
    .CSRDataW    (CSRDataW),
    .IsCSRW      (IsCSRW),
    .ResultW     (ResultW),
    .ImmExtW     (ImmExtW)
);

hazard_unit hazard(
    .rst          (reset),
    .Rs1E         (Rs1E),
    .Rs2E         (Rs2E),
    .RdM          (RdM),
    .RdW          (RdW),
    .RegWriteM    (RegWriteM),
    .RegWriteW    (RegWriteW),
    .ResultSrcE0  (ResultSrcE[0]),
    .ResultSrcE1  (ResultSrcE[1]),
    .IsMretE      (IsMretE),
    .trap_taken   (trap_taken),
    .MemStall     (MemStall),
    .DivStall     (DivStallE),
    .Rs1D         (((InstrD[6:0] == 7'b0110111) || (InstrD[6:0] == 7'b0010111) ||
                     (InstrD[6:0] == 7'b1101111)) ? 5'b0 : InstrD[19:15]),
    .Rs2D         (((InstrD[6:0] == 7'b0110111) || (InstrD[6:0] == 7'b0010111) ||
                     (InstrD[6:0] == 7'b1101111)) ? 5'b0 : InstrD[24:20]),
    .RdE          (RdE),
    .PCSrcE       (|PCSrcE),
    .ForwardAE    (ForwardAE),
    .ForwardBE    (ForwardBE),
    .lwStall      (lwStall),
    .StallF       (StallF),
    .StallD       (StallD),
    .StallE       (StallE),
    .StallM       (StallM),
    .FlushD       (FlushD),
    .FlushE       (FlushE)
);

endmodule
