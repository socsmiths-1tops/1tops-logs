`timescale 1ns/1ps
// ============================================================
// csr_unit.v  Minimal Machine-mode CSR for RV32IM SoC
// Implements: mstatus, mie, mtvec, mepc, mcause, mip
// Supports:   csrrw, csrrs, csrrc, csrrwi, csrrsi, csrrci, mret
// ============================================================
module csr_unit (
    input         clk,
    input         rst,

    // CSR instruction interface (from Execute stage)
    input  [31:0] instr_execute,  // instruction in Execute (NOP=bubble, suppress trap)
    input         csr_wen,       // CSR write enable
    input  [11:0] csr_addr,      // CSR address (from instr[31:20])
    input  [31:0] csr_wdata,     // data to write into CSR
    input  [2:0]  csr_op,        // funct3: 001=rw 010=rs 011=rc 101=rwi 110=rsi 111=rci
    output [31:0] csr_rdata,     // CSR read data (to result mux)

    // Interrupt inputs
    input         irq_extern,    // from PLIC (external interrupt)
    input         irq_timer,     // from CLINT (timer interrupt)
    input         irq_software,  // from CLINT (software interrupt)

    // Trap control outputs (to fetch stage)
    input  [31:0] pc_execute,    // current PC in execute stage
    output [31:0] mtvec_out,     // interrupt vector address
    output [31:0] mepc_out,      // return address for mret
    output        trap_taken,    // 1 = redirect PC to mtvec
    output        mret_taken,    // 1 = redirect PC to mepc

    // mret instruction signal (from decode)
    input         mret_instr,

    // Pipeline frozen by an outstanding APB/AHB read (MemStall). While
    // held, the Execute instruction is not flushed and the PC register
    // is frozen, so no trap, mret or CSR write may take effect.
    input         hold
);

//  CSR Registers 
// mstatus [3]=MIE (machine interrupt enable global)
reg [31:0] mstatus;
// mie [11]=MEIE (external) [7]=MTIE (timer) [3]=MSIE (software)
reg [31:0] mie;
// mtvec  interrupt vector base address (mode=0: direct)
reg [31:0] mtvec;
// mepc  saved PC on trap
reg [31:0] mepc;
// mcause  trap cause
reg [31:0] mcause;
// mip  interrupt pending (read-only, set by hardware)
wire [31:0] mip;

// MIE bit (global interrupt enable) from mstatus
wire mstatus_mie = mstatus[3];

//  mip  Interrupt Pending (hardware sets these) 
assign mip[31:12] = 20'b0;
assign mip[11]    = irq_extern;    // MEIP  machine external interrupt pending
assign mip[10:8]  = 3'b0;
assign mip[7]     = irq_timer;     // MTIP  machine timer interrupt pending
assign mip[6:4]   = 3'b0;
assign mip[3]     = irq_software;  // MSIP  machine software interrupt pending
assign mip[2:0]   = 3'b0;

//  Interrupt Detection 
// An interrupt is taken when:
// 1. MIE=1 (global enable in mstatus)
// 2. Individual enable bit is set in mie
// 3. Pending bit is set in mip
wire irq_external_active = mstatus_mie && mie[11] && mip[11];
wire irq_timer_active    = mstatus_mie && mie[7]  && mip[7];
wire irq_software_active = mstatus_mie && mie[3]  && mip[3];

wire interrupt_pending = irq_external_active | irq_timer_active | irq_software_active;
// CRITICAL FIX: do not take a trap while Execute holds a bubble (NOP from FlushE).
// Otherwise mepc captures pc_execute=0 (the flushed PCE), corrupting the return address.
wire execute_is_bubble = (instr_execute == 32'h00000013);

//  Trap and mret outputs 
// Bug #17 fix: trap/mret gated by hold. Previously a trap during MemStall
// saved mepc=PCE but could not flush E (StallE wins over FlushE), so that
// instruction executed twice; an mret held in E re-fired every stall cycle
// and, once MIE was restored, a trap could land on the mret itself
// (mepc = mret PC -> runaway return loop, seen as VG03 failure).
assign trap_taken = interrupt_pending & ~execute_is_bubble & ~hold;
assign mret_taken = mret_instr & ~hold;
assign mtvec_out  = mtvec;
assign mepc_out   = mepc;

//  mcause value encoding (RISC-V spec) 
// bit[31]=1 means interrupt (not exception)
wire [31:0] mcause_next =
    irq_external_active ? 32'h8000_000B :  // machine external interrupt
    irq_timer_active    ? 32'h8000_0007 :  // machine timer interrupt
    irq_software_active ? 32'h8000_0003 :  // machine software interrupt
                          32'h0000_0000;

//  CSR Read 
reg [31:0] csr_rdata_r;
always @(*) begin
    case (csr_addr)
        12'h300: csr_rdata_r = mstatus;
        12'h304: csr_rdata_r = mie;
        12'h305: csr_rdata_r = mtvec;
        12'h341: csr_rdata_r = mepc;
        12'h342: csr_rdata_r = mcause;
        12'h344: csr_rdata_r = mip;
        default: csr_rdata_r = 32'b0;
    endcase
end
assign csr_rdata = csr_rdata_r;

//  CSR Write Data (based on operation) 
// op[2]=0: register source, op[2]=1: immediate source
// op[1:0]: 01=write, 10=set, 11=clear
wire [31:0] wdata_final =
    (csr_op[1:0] == 2'b01) ? csr_wdata :                    // CSRRW/CSRRWI
    (csr_op[1:0] == 2'b10) ? csr_rdata_r | csr_wdata :      // CSRRS/CSRRSI
    (csr_op[1:0] == 2'b11) ? csr_rdata_r & ~csr_wdata :     // CSRRC/CSRRCI
                              csr_rdata_r;

//  CSR Register Write + Trap/mret Logic 
always @(posedge clk or posedge rst) begin
    if (rst) begin
        mstatus <= 32'h0000_1800; // MPP=11 (machine mode), MIE=0
        mie     <= 32'b0;
        mtvec   <= 32'b0;
        mepc    <= 32'b0;
        mcause  <= 32'b0;
    end
    else begin
        //  Trap taken: save state, jump to mtvec 
        if (trap_taken) begin
            mepc          <= pc_execute;      // save current PC
            mcause        <= mcause_next;     // record cause
            mstatus[3]    <= 1'b0;           // clear MIE (disable interrupts)
            mstatus[7]    <= mstatus[3];     // save old MIE to MPIE
        end
        //  mret: restore state, return from handler 
        else if (mret_taken) begin
            mstatus[3]    <= mstatus[7];     // restore MIE from MPIE
            mstatus[7]    <= 1'b1;           // set MPIE=1
        end
        //  Normal CSR write instruction 
        else if (csr_wen && !hold) begin
            case (csr_addr)
                12'h300: mstatus <= wdata_final;
                12'h304: mie     <= wdata_final;
                12'h305: mtvec   <= wdata_final;
                12'h341: mepc    <= wdata_final;
                12'h342: mcause  <= wdata_final;
                // mip is read-only  writes ignored
                default: ;
            endcase
        end
    end
end

endmodule
