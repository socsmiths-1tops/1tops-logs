`timescale 1ns/1ps

// Simple GPIO
//-------------------------------------
// Programmer's Model
// 0x00 RO  Data In
// 0x04 RW  Data Output
// 0x08 RW  Output Enable
// 0x0C RW  Interrupt Enable
// 0x10 RW  Interrupt Type
// 0x14 RW  Interrupt Polarity (1 = rising edge / high level, 0 = falling / low)
// 0x18 RWc Interrupt State
//-------------------------------------

module apb_gpio #(
    parameter PortWidth = 8
)(
    input  wire                 PCLK,
    input  wire                 PRESETn,

    // APB Interface
    input  wire                 PSEL,
    input  wire [7:2]           PADDR,
    input  wire                 PENABLE,
    input  wire                 PWRITE,
    input  wire [31:0]          PWDATA,

    output wire [31:0]          PRDATA,
    output wire                 PREADY,
    output wire                 PSLVERR,

    // GPIO Interface
    input  wire [PortWidth-1:0] PORTIN,
    output wire [PortWidth-1:0] PORTOUT,
    output wire [PortWidth-1:0] PORTEN,

    // Interrupt Outputs
    output wire [PortWidth-1:0] GPIOINT,
    output wire                 COMBINT
);

    // Read/Write Control Signals
    wire ReadEnable;
    wire WriteEnable;

    wire WriteEnable04;
    wire WriteEnable08;
    wire WriteEnable0C;
    wire WriteEnable10;
    wire WriteEnable14;
    wire WriteEnable18;

    reg [PortWidth-1:0] ReadMux;
    reg [PortWidth-1:0] ReadMuxReg;

    // Control Registers
    reg [PortWidth-1:0] RegDOUT;
    reg [PortWidth-1:0] RegDOUTEN;
    reg [PortWidth-1:0] RegINTEN;
    reg [PortWidth-1:0] RegINTTYPE;
    reg [PortWidth-1:0] RegINTPOL;
    reg [PortWidth-1:0] RegINTState;

    // Input Synchronization
    reg  [PortWidth-1:0] DataInSync1;
    reg  [PortWidth-1:0] DataInSync2;
    wire [PortWidth-1:0] DataInPolAdjusted;
    reg  [PortWidth-1:0] LastDataInPol;

    wire [PortWidth-1:0] EdgeDetect;
    wire [PortWidth-1:0] RawInt;
    wire [PortWidth-1:0] MaskedInt;

    //--------------------------------------------------
    // Read/Write Control
    //--------------------------------------------------

    assign ReadEnable  = PSEL & (~PWRITE);
    assign WriteEnable = PSEL & (~PENABLE) & PWRITE;

    assign WriteEnable04 = WriteEnable & (PADDR[7:2] == 6'b000001);
    assign WriteEnable08 = WriteEnable & (PADDR[7:2] == 6'b000010);
    assign WriteEnable0C = WriteEnable & (PADDR[7:2] == 6'b000011);
    assign WriteEnable10 = WriteEnable & (PADDR[7:2] == 6'b000100);
    assign WriteEnable14 = WriteEnable & (PADDR[7:2] == 6'b000101);
    assign WriteEnable18 = WriteEnable & (PADDR[7:2] == 6'b000110);

    //--------------------------------------------------
    // Data Output Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegDOUT <= {PortWidth{1'b0}};
        else if (WriteEnable04)
            RegDOUT <= PWDATA[PortWidth-1:0];
    end

    //--------------------------------------------------
    // Output Enable Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegDOUTEN <= {PortWidth{1'b0}};
        else if (WriteEnable08)
            RegDOUTEN <= PWDATA[PortWidth-1:0];
    end

    //--------------------------------------------------
    // Interrupt Enable Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegINTEN <= {PortWidth{1'b0}};
        else if (WriteEnable0C)
            RegINTEN <= PWDATA[PortWidth-1:0];
    end

    //--------------------------------------------------
    // Interrupt Type Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegINTTYPE <= {PortWidth{1'b0}};
        else if (WriteEnable10)
            RegINTTYPE <= PWDATA[PortWidth-1:0];
    end

    //--------------------------------------------------
    // Interrupt Polarity Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegINTPOL <= {PortWidth{1'b0}};
        else if (WriteEnable14)
            RegINTPOL <= PWDATA[PortWidth-1:0];
    end

    //--------------------------------------------------
    // Read Mux
    //--------------------------------------------------

    always @(*) begin
        case (PADDR[7:2])
            0: ReadMux = DataInSync2;
            1: ReadMux = RegDOUT;
            2: ReadMux = RegDOUTEN;
            3: ReadMux = RegINTEN;
            4: ReadMux = RegINTTYPE;
            5: ReadMux = RegINTPOL;
            6: ReadMux = RegINTState;
            default: ReadMux = {PortWidth{1'b0}};
        endcase
    end

    //--------------------------------------------------
    // Read Data Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            ReadMuxReg <= {PortWidth{1'b0}};
        else
            ReadMuxReg <= ReadMux;
    end

    assign PRDATA  = ReadEnable ?
                     {{(32-PortWidth){1'b0}}, ReadMuxReg} :
                     32'b0;

    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    //--------------------------------------------------
    // GPIO Outputs
    //--------------------------------------------------

    assign PORTEN  = RegDOUTEN;
    assign PORTOUT = RegDOUT;

    //--------------------------------------------------
    // Input Synchronizer
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn) begin
            DataInSync1 <= {PortWidth{1'b0}};
            DataInSync2 <= {PortWidth{1'b0}};
        end
        else begin
            DataInSync1 <= PORTIN;
            DataInSync2 <= DataInSync1;
        end
    end

    //--------------------------------------------------
    // Interrupt Logic
    //--------------------------------------------------

    // Bug #20: was DataInSync2 ^ RegINTPOL (1 = active-low), contradicting
    // the firmware convention; masked earlier by the bridge dropping writes.
    assign DataInPolAdjusted = DataInSync2 ^ ~RegINTPOL;

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            LastDataInPol <= {PortWidth{1'b0}};
        else
            LastDataInPol <= DataInPolAdjusted;
    end

    assign EdgeDetect = ~LastDataInPol & DataInPolAdjusted;

    assign RawInt =
            ( RegINTTYPE & EdgeDetect ) |
            (~RegINTTYPE & DataInPolAdjusted);

    assign MaskedInt = RawInt & RegINTEN;

    //--------------------------------------------------
    // Interrupt State Register
    //--------------------------------------------------

    always @(posedge PCLK or negedge PRESETn) begin
        if (!PRESETn)
            RegINTState <= {PortWidth{1'b0}};
        else begin
            RegINTState <=
                MaskedInt |
                (RegINTState &
                ~(PWDATA[PortWidth-1:0] &
                  {PortWidth{WriteEnable18}}));
        end
    end

    //--------------------------------------------------
    // Interrupt Outputs
    //--------------------------------------------------

    assign GPIOINT = RegINTState;
    assign COMBINT = |RegINTState;

endmodule
