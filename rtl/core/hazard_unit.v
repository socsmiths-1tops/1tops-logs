`timescale 1ns/1ps
module hazard_unit(
    rst, Rs1E, Rs2E, RdM, RdW,
    RegWriteM, RegWriteW,
    ResultSrcE0, ResultSrcE1, IsMretE, Rs1D, Rs2D, RdE, PCSrcE, trap_taken,
    MemStall, DivStall,
    ForwardAE, ForwardBE,
    lwStall, StallF, StallD, StallE, StallM, FlushD, FlushE
);
input rst, RegWriteM, RegWriteW, ResultSrcE0, ResultSrcE1, IsMretE, PCSrcE, trap_taken;
input [4:0] Rs1E, Rs2E, RdM, RdW, Rs1D, Rs2D, RdE;
// NEW: asserted by the interconnect while a slow APB read in the Memory
// stage hasn't completed yet. Takes ABSOLUTE priority over every other
// stall/flush decision below -- while MemStall=1 the ENTIRE pipeline
// (PC, F/D, D/E, E/M, M/W) is held frozen with zero exceptions, so no
// partially-resolved branch/load-use condition can ever corrupt a held
// instruction mid-freeze.
input MemStall;
// DivStall: iterative divide busy in Execute -> hold F/D/E (M/W keep
// draining; execute sends bubbles). A trap on the divide overrides it.
input DivStall;
wire  div_hold = DivStall & ~trap_taken;
output [1:0] ForwardAE, ForwardBE;
output lwStall, StallF, StallD, StallE, StallM, FlushD, FlushE;

assign ForwardAE = (!rst) ?
    (((Rs1E == RdM) && RegWriteM) && (Rs1E != 5'b0)) ? 2'b10 :
    (((Rs1E == RdW) && RegWriteW) && (Rs1E != 5'b0)) ? 2'b01 : 2'b00
    : 2'b00;

assign ForwardBE = (!rst) ?
    (((Rs2E == RdM) && RegWriteM) && (Rs2E != 5'b0)) ? 2'b10 :
    (((Rs2E == RdW) && RegWriteW) && (Rs2E != 5'b0)) ? 2'b01 : 2'b00
    : 2'b00;

assign lwStall = ResultSrcE0 & ((Rs1D == RdE) | (Rs2D == RdE));

// CRITICAL FIX (kept from before): a trap/interrupt must never be
// swallowed by a load-use stall.
assign StallF  = MemStall | ((lwStall & ~IsMretE) & ~trap_taken) | div_hold;
assign StallD  = MemStall | (lwStall & ~trap_taken) | div_hold;

// NEW: freeze D/E and (E/M + M/W) respectively while MemStall is active.
assign StallE  = MemStall | div_hold;
assign StallM  = MemStall;

// MemStall overrides FlushD/FlushE entirely -- a held instruction must
// be held, never flushed, while waiting on a slow APB read.
assign FlushD  = (~MemStall) & (PCSrcE | trap_taken | IsMretE);
assign FlushE  = (~MemStall) & (lwStall | PCSrcE | trap_taken | IsMretE);

endmodule
