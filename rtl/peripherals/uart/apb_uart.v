`timescale 1ns/1ps

module apb_uart (
    input wire PCLK,
    input wire PRESETn,

    input wire PSEL,
    input wire [7:2] PADDR,
    input wire PENABLE,
    input wire PWRITE,
    input wire [31:0] PWDATA,

    output wire [31:0] PRDATA,
    output wire PREADY,
    output wire PSLVERR,

    input wire RXD,
    output wire TXD,
    output wire TXEN,
    output wire BAUDTICK,
    output wire TXINT,
    output wire RXINT
);

wire ReadEnable;
wire ReadEnable10;
wire WriteEnable;
wire WriteEnable00;
wire WriteEnable04;
wire WriteEnable08;
wire WriteEnable10;
wire WriteEnable14;

reg [7:0] ReadMux;
reg [7:0] ReadMuxReg;
reg ReadEnable10Reg;

reg [3:0] RegCTRL;
reg [7:0] RegTxBuf;
reg [7:0] RegRxBuf;
reg [19:0] RegBaudDiv;

reg [15:0] RegBaudCntrI;
wire [15:0] NxtBaudCntrI;
reg [3:0] RegBaudCntrF;
wire [3:0] NxtBaudCntrF;
wire [3:0] MappedCntrF;
reg RegBaudTick;
reg BaudUpdated;
wire ReloadI;
wire ReloadF;
wire BaudDivEn;

wire [3:0] UartStatus;
reg RegRxOverrun;
wire RxOverrun;
reg RegTxOverrun;
wire TxOverrun;
wire NxtRxOverrun;
wire NxtTxOverrun;

reg RegTXINT;
wire NxtTXINT;
reg RegRXINT;
wire NxtRXINT;

reg [3:0] TxState;
reg [3:0] NxtTxState;
wire TxStateInc;
reg [3:0] TxTickCnt;
wire [3:0] NxtTxTickCnt;
reg [7:0] TxShiftBuf;
wire [7:0] NxtTxShiftBuf;
reg TxBufFull;
wire NxtTxBufFull;
reg RegTxD;
wire NxtTxD;
wire TxBufClear;

reg RxDSync1;
reg RxDSync2;
reg [2:0] RxDLPF;
wire RxShiftIn;

reg [3:0] RxState;
reg [3:0] NxtRxState;
reg [3:0] RxTickCnt;
wire [3:0] NxtRxTickCnt;
wire RxStateInc;
reg [6:0] RxShiftBuf;
wire [6:0] NxtRxShiftBuf;
reg RxBufFull;
wire NxtRxBufFull;
wire RxBufSample;
wire RxDataRead;
wire [7:0] NxtRxBuf;

assign ReadEnable  = PSEL & (~PWRITE);
assign WriteEnable = PSEL & (~PENABLE) & PWRITE;

assign WriteEnable00 = WriteEnable & (PADDR[7:2] == 6'b000000);
assign WriteEnable04 = WriteEnable & (PADDR[7:2] == 6'b000001);
assign WriteEnable08 = WriteEnable & (PADDR[7:2] == 6'b000010);
assign WriteEnable10 = WriteEnable & (PADDR[7:2] == 6'b000100);
assign WriteEnable14 = WriteEnable & (PADDR[7:2] == 6'b000101);

assign ReadEnable10 = PSEL & (~PWRITE) & (~PENABLE) & (PADDR[7:2] == 6'b000100);

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
        RegCTRL <= 4'b0000;
    else if (WriteEnable00)
        RegCTRL <= PWDATA[3:0];
end

assign NxtRxOverrun = (RegRxOverrun & ~(WriteEnable04 & PWDATA[3])) | RxOverrun;
assign NxtTxOverrun = (RegTxOverrun & ~(WriteEnable04 & PWDATA[2])) | TxOverrun;

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        RegRxOverrun <= 1'b0;
        RegTxOverrun <= 1'b0;
    end
    else
    begin
        RegRxOverrun <= NxtRxOverrun;
        RegTxOverrun <= NxtTxOverrun;
    end
end

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
        RegTxBuf <= 8'b00000000;
    else if (WriteEnable08)
        RegTxBuf <= PWDATA[7:0];
end

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
        RegBaudDiv <= 20'b00000000000000000000;
    else if (WriteEnable10)
        RegBaudDiv <= PWDATA[19:0];
end

assign UartStatus = {RegRxOverrun, RegTxOverrun, RxBufFull, TxBufFull};

always @(PADDR or RegCTRL or UartStatus or RegBaudDiv or TxBufFull or RegRxBuf or RegTXINT or RegRXINT)
begin
    case (PADDR[7:2])
        6'd0:    ReadMux = {4'b0000, RegCTRL};
        6'd1:    ReadMux = {4'b0000, UartStatus};
        6'd2:    ReadMux = {7'b0000000, TxBufFull};
        6'd3:    ReadMux = RegRxBuf;
        6'd4:    ReadMux = RegBaudDiv[7:0];
        6'd5:    ReadMux = {6'b000000, RegTXINT, RegRXINT};
        default: ReadMux = 8'b00000000;
    endcase
end

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        ReadMuxReg <= 8'b00000000;
        ReadEnable10Reg <= 1'b0;
    end
    else
    begin
        ReadMuxReg <= ReadMux;
        ReadEnable10Reg <= ReadEnable10;
    end
end

assign PRDATA[7:0]   = (ReadEnable) ? ReadMuxReg : 8'b00000000;
assign PRDATA[19:8]  = (ReadEnable10Reg) ? RegBaudDiv[19:8] : 12'b000000000000;
assign PRDATA[31:20] = 12'b000000000000;

assign PREADY  = 1'b1;
assign PSLVERR = 1'b0;

assign BaudDivEn = (RegCTRL[1:0] != 2'b00);

assign MappedCntrF = {RegBaudCntrF[0], RegBaudCntrF[1], RegBaudCntrF[2], RegBaudCntrF[3]};

assign ReloadI = BaudDivEn &
                 ((((MappedCntrF >= RegBaudDiv[3:0]) &&
                 (RegBaudCntrI[15:1] == 15'b000000000000000)) ||
                 (RegBaudCntrI[15:0] == 16'b0000000000000000)));

assign NxtBaudCntrI = (BaudUpdated | ReloadI) ? RegBaudDiv[19:4] :
                      (RegBaudCntrI - {15'b000000000000000, BaudDivEn});

assign ReloadF = BaudDivEn & (RegBaudCntrF == 4'h0) & ReloadI;

assign NxtBaudCntrF = (BaudUpdated) ? RegBaudDiv[3:0] :
                      (ReloadF) ? 4'b1111 :
                      (RegBaudCntrF - {3'b000, ReloadI});

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        RegBaudCntrI <= 16'b0000000000000000;
        RegBaudCntrF <= 4'b0000;
        BaudUpdated  <= 1'b0;
        RegBaudTick  <= 1'b0;
    end
    else
    begin
        RegBaudCntrI <= NxtBaudCntrI;
        RegBaudCntrF <= NxtBaudCntrF;
        BaudUpdated  <= WriteEnable10;
        RegBaudTick  <= ReloadI;
    end
end

assign BAUDTICK = RegBaudTick;

assign NxtTxTickCnt = ((TxState == 4'h1) & RegBaudTick) ? 4'h0 :
                      TxTickCnt + {3'b000, RegBaudTick};

assign TxStateInc = (((&TxTickCnt) | (TxState == 4'h1)) & RegBaudTick);

assign NxtTxBufFull = (WriteEnable08) | (TxBufFull & ~TxBufClear);

assign TxBufClear = ((TxState == 4'h0) & TxBufFull) |
                    ((TxState == 4'hB) & TxBufFull & TxStateInc);

always @(TxState or TxBufFull or TxTickCnt or TxStateInc or RegCTRL)
begin
    case (TxState)
        4'h0:
        begin
            NxtTxState = (TxBufFull & RegCTRL[0]) ? 4'h1 : 4'h0;
        end

        4'h1:
        begin
            NxtTxState = TxState + {3'b000, TxStateInc};
        end

        4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9, 4'hA:
        begin
            NxtTxState = TxState + {3'b000, TxStateInc};
        end

        4'hB:
        begin
            NxtTxState = (TxStateInc) ? (TxBufFull ? 4'h2 : 4'h0) : TxState;
        end

        default:
        begin
            NxtTxState = 4'h0;
        end
    endcase
end

assign NxtTxShiftBuf = (((TxState == 4'h0) & TxBufFull) |
                       ((TxState == 4'hB) & TxBufFull & TxStateInc)) ? RegTxBuf :
                       (((TxState > 4'h2) & TxStateInc) ?
                       {1'b1, TxShiftBuf[7:1]} : TxShiftBuf[7:0]);

assign NxtTxD = (TxState == 4'h2) ? 1'b0 :
                (TxState > 4'h2) ? TxShiftBuf[0] : 1'b1;

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        TxBufFull  <= 1'b0;
        TxShiftBuf <= 8'b00000000;
        TxState    <= 4'b0000;
        TxTickCnt  <= 4'b0000;
        RegTxD     <= 1'b1;
    end
    else
    begin
        TxBufFull  <= NxtTxBufFull;
        TxShiftBuf <= NxtTxShiftBuf;
        TxState    <= NxtTxState;
        TxTickCnt  <= NxtTxTickCnt;
        RegTxD     <= NxtTxD;
    end
end

assign TxOverrun = TxBufFull & ~TxBufClear & WriteEnable08;

assign TXD  = RegTxD;
assign TXEN = RegCTRL[0];

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        RxDSync1 <= 1'b1;
        RxDSync2 <= 1'b1;
    end
    else
    begin
        RxDSync1 <= RXD;
        RxDSync2 <= RxDSync1;
    end
end

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
        RxDLPF <= 3'b111;
    else if (RegBaudTick)
        RxDLPF <= {RxDLPF[1:0], RxDSync2};
end

assign RxShiftIn = (RxDLPF[1] & RxDLPF[0]) |
                   (RxDLPF[1] & RxDLPF[2]) |
                   (RxDLPF[0] & RxDLPF[2]);

assign NxtRxTickCnt = ((RxState == 4'h0) & ~RxShiftIn) ? 4'h8 :
                      RxTickCnt + {3'b000, RegBaudTick};

assign RxStateInc = ((&RxTickCnt) & RegBaudTick);

assign NxtRxShiftBuf = (RxStateInc) ? {RxShiftIn, RxShiftBuf[6:1]} : RxShiftBuf;

assign NxtRxBufFull = RxBufSample | (RxBufFull & ~RxDataRead);

assign RxBufSample = ((RxState == 4'h9) & RxStateInc);

assign NxtRxBuf = (RxBufSample) ? {RxShiftIn, RxShiftBuf} : RegRxBuf;

assign RxDataRead = (PSEL & ~PENABLE & (PADDR[7:2] == 6'd3) & ~PWRITE);

assign RxOverrun = RxBufFull & RxBufSample & ~RxDataRead;

always @(RxState or RxShiftIn or RxTickCnt or RxStateInc or RegCTRL)
begin
    case (RxState)
        4'h0:
        begin
            NxtRxState = ((~RxShiftIn) & RegCTRL[1]) ? 4'h1 : 4'h0;
        end

        4'h1:
        begin
            NxtRxState = RxState + {3'b000, RxStateInc};
        end

        4'h2, 4'h3, 4'h4, 4'h5, 4'h6, 4'h7, 4'h8, 4'h9:
        begin
            NxtRxState = RxState + {3'b000, RxStateInc};
        end

        4'hA:
        begin
            NxtRxState = (RxStateInc) ? 4'h0 : 4'hA;
        end

        default:
        begin
            NxtRxState = 4'h0;
        end
    endcase
end

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        RxBufFull  <= 1'b0;
        RxShiftBuf <= 7'b0000000;
        RxState    <= 4'b0000;
        RxTickCnt  <= 4'b0000;
        RegRxBuf   <= 8'b00000000;
    end
    else
    begin
        RxBufFull  <= NxtRxBufFull;
        RxShiftBuf <= NxtRxShiftBuf;
        RxState    <= NxtRxState;
        RxTickCnt  <= NxtRxTickCnt;
        RegRxBuf   <= NxtRxBuf;
    end
end

assign NxtTXINT = RegCTRL[2] & TxBufFull & TxBufClear;
assign NxtRXINT = RegCTRL[3] & RxBufSample;

always @(posedge PCLK or negedge PRESETn)
begin
    if (~PRESETn)
    begin
        RegTXINT <= 1'b0;
        RegRXINT <= 1'b0;
    end
    else
    begin
        RegTXINT <= NxtTXINT | (RegTXINT & ~(WriteEnable14 & PWDATA[1]));
        RegRXINT <= NxtRXINT | (RegRXINT & ~(WriteEnable14 & PWDATA[0]));
    end
end

assign TXINT = RegTXINT;
assign RXINT = RegRXINT;

endmodule
