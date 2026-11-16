`timescale 1ns/1ps
// ============================================================
// reset_sync.v  Active-high reset synchronizer: asynchronous assert,
// synchronous (2-flop) de-assert, so every flop leaves reset on the
// same clock edge regardless of when the external pin is released.
// ============================================================
module reset_sync (
    input  clk,
    input  rst_async,   // external reset pin (active high, async)
    output rst_sync     // to all SoC logic
);
reg [1:0] sync_q;
always @(posedge clk or posedge rst_async)
    if (rst_async) sync_q <= 2'b11;
    else           sync_q <= {sync_q[0], 1'b0};
assign rst_sync = sync_q[1];
endmodule
