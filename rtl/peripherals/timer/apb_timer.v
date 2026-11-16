`timescale 1ns/1ps

module apb_timer (
    input  wire        PCLK,
    input  wire        PRESETn,

    // APB interface inputs
    input  wire        PSEL,
    input  wire [7:2]  PADDR,
    input  wire        PENABLE,
    input  wire        PWRITE,
    input  wire [31:0] PWDATA,

    // APB interface outputs
    output wire [31:0] PRDATA,
    output wire        PREADY,
    output wire        PSLVERR,

    input  wire        EXTIN,
    output wire        TIMERINT
);

    // Read/Write controls
    wire ReadEnable;
    wire WriteEnable;

    wire WriteEnable00;
    wire WriteEnable04;
    wire WriteEnable08;
    wire WriteEnable0C;

    reg [31:0] ReadMux;
    reg [31:0] ReadMuxReg;

    // Registers
    reg [3:0]  RegCTRL;
    reg [31:0] RegCurrVal;
    reg [31:0] RegReloadVal;
    reg [31:0] NxtCurrVal;

    // External input synchronization
    reg ExtInSync1;
    reg ExtInSync2;
    reg ExtInDelay;

    wire DecCtrl;
    wire ClkCtrl;
    wire EnCtrl;
    wire EdgeDetect;

    reg  RegTimerInt;
    wire NxtTimerInt;

    //---------------------------------------------------------
    // APB Read/Write Controls
    //---------------------------------------------------------

    assign ReadEnable  = PSEL & (~PWRITE);
    assign WriteEnable = PSEL & (~PENABLE) & PWRITE;

    assign WriteEnable00 = WriteEnable & (PADDR[7:2] == 6'b000000);
    assign WriteEnable04 = WriteEnable & (PADDR[7:2] == 6'b000001);
    assign WriteEnable08 = WriteEnable & (PADDR[7:2] == 6'b000010);
    assign WriteEnable0C = WriteEnable & (PADDR[7:2] == 6'b000011);

    //---------------------------------------------------------
    // CTRL Register
    //---------------------------------------------------------

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
            RegCTRL <= 4'b0000;
        else if (WriteEnable00)
            RegCTRL <= PWDATA[3:0];
    end

    //---------------------------------------------------------
    // Current Value Register
    //---------------------------------------------------------

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
            RegCurrVal <= 32'b0;
        else
            RegCurrVal <= NxtCurrVal;
    end

    //---------------------------------------------------------
    // Reload Value Register
    //---------------------------------------------------------

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
            RegReloadVal <= 32'b0;
        else if (WriteEnable08)
            RegReloadVal <= PWDATA;
    end

    //---------------------------------------------------------
    // Read Mux
    //---------------------------------------------------------

    always @(*)
    begin
        case (PADDR[7:2])
            6'd0: ReadMux = {28'b0, RegCTRL};
            6'd1: ReadMux = RegCurrVal;
            6'd2: ReadMux = RegReloadVal;
            6'd3: ReadMux = {31'b0, RegTimerInt};
            default: ReadMux = 32'b0;
        endcase
    end

    //---------------------------------------------------------
    // Read Data Register
    //---------------------------------------------------------

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
            ReadMuxReg <= 32'b0;
        else
            ReadMuxReg <= ReadMux;
    end

    assign PRDATA  = (ReadEnable) ? ReadMuxReg : 32'b0;
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    //---------------------------------------------------------
    // Synchronizer
    //---------------------------------------------------------

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
        begin
            ExtInSync1 <= 1'b0;
            ExtInSync2 <= 1'b0;
            ExtInDelay <= 1'b0;
        end
        else
        begin
            ExtInSync1 <= EXTIN;
            ExtInSync2 <= ExtInSync1;
            ExtInDelay <= ExtInSync2;
        end
    end

    //---------------------------------------------------------
    // Edge Detect
    //---------------------------------------------------------

    assign EdgeDetect = ExtInSync2 & ~ExtInDelay;

    //---------------------------------------------------------
    // Clock / Enable Selection
    //---------------------------------------------------------

    assign ClkCtrl = RegCTRL[2] ? EdgeDetect : 1'b1;
    assign EnCtrl  = RegCTRL[1] ? ExtInSync2 : 1'b1;

    assign DecCtrl = RegCTRL[0] & EnCtrl & ClkCtrl;

    //---------------------------------------------------------
    // Next Counter Value Logic
    //---------------------------------------------------------

    always @(*)
    begin
        if (WriteEnable04)
            NxtCurrVal = PWDATA;

        else if (DecCtrl)
        begin
            if (RegCurrVal == 32'h00000000)
                NxtCurrVal = RegReloadVal;
            else
                NxtCurrVal = RegCurrVal - 1;
        end
        else
            NxtCurrVal = RegCurrVal;
    end

    //---------------------------------------------------------
    // Interrupt Logic
    //---------------------------------------------------------

    assign NxtTimerInt =
           DecCtrl &
           RegCTRL[3] &
           (RegCurrVal == 32'h00000001);

    always @(posedge PCLK or negedge PRESETn)
    begin
        if (~PRESETn)
            RegTimerInt <= 1'b0;
        else
            RegTimerInt <=
                NxtTimerInt |
                (RegTimerInt & ~(WriteEnable0C & PWDATA[0]));
    end

    //---------------------------------------------------------
    // Output
    //---------------------------------------------------------

    assign TIMERINT = RegTimerInt;

endmodule
