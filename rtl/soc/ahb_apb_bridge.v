`timescale 1ns/1ps
// ============================================================
// ahb_apb_bridge.v  Simplified AHB-Lite to APB Bridge
// Single master, no burst, no wait states on APB side
// APB clock = AHB clock (same domain)
// ============================================================
module ahb_apb_bridge (
    input         clk,
    input         rst,

    // AHB-Lite slave interface
    input  [31:0] HADDR,
    input  [31:0] HWDATA,
    input         HWRITE,
    input  [2:0]  HSIZE,
    input         HSEL,
    input         HREADY,
    output [31:0] HRDATA,
    output        HREADYOUT,
    output        xfer_done,   // 1 in the cycle the APB transfer completes (ENABLE & PREADY)

    // APB master interface
    output [31:0] PADDR,
    output [31:0] PWDATA,
    output        PWRITE,
    output        PENABLE,
    output        PSEL,
    input  [31:0] PRDATA,
    input         PREADY,
    input         PSLVERR
);

//  State machine 
// IDLE  SETUP  ENABLE  IDLE
localparam IDLE   = 2'b00;
localparam SETUP  = 2'b01;
localparam ENABLE = 2'b10;

reg [1:0]  state;
reg [31:0] addr_reg;
reg [31:0] wdata_reg;
reg        write_reg;

always @(posedge clk or posedge rst) begin
    if (rst) begin
        state     <= IDLE;
        addr_reg  <= 32'b0;
        wdata_reg <= 32'b0;
        write_reg <= 1'b0;
    end
    else begin
        case (state)
            IDLE: begin
                if (HSEL && HREADY) begin
                    addr_reg  <= HADDR;
                    wdata_reg <= HWDATA;
                    write_reg <= HWRITE;
                    state     <= SETUP;
                end
            end
            SETUP: begin
                state <= ENABLE;
            end
            ENABLE: begin
                if (PREADY) begin
                    if (HSEL && HREADY) begin
                        addr_reg  <= HADDR;
                        wdata_reg <= HWDATA;
                        write_reg <= HWRITE;
                        state     <= SETUP;
                    end
                    else state <= IDLE;
                end
            end
            default: state <= IDLE;
        endcase
    end
end

//  APB outputs 
assign PADDR   = addr_reg;
assign PWDATA  = wdata_reg;
assign PWRITE  = write_reg;
assign PSEL    = (state == SETUP) || (state == ENABLE);
assign PENABLE = (state == ENABLE);

//  AHB outputs 
assign HRDATA    = PRDATA;
assign HREADYOUT = (state == ENABLE) ? PREADY : 1'b1;
assign xfer_done = (state == ENABLE) & PREADY;

endmodule
