`include "i2c_master_defines.v"

`define REG_CLK_PRESCALER 3'b000
`define REG_CTRL          3'b001
`define REG_RX            3'b010
`define REG_STATUS        3'b011
`define REG_TX            3'b100
`define REG_CMD           3'b101

module apb_i2c
#(
    parameter APB_ADDR_WIDTH = 12
)
(
    input  PCLK,
    input  PRESETn,
    input  [APB_ADDR_WIDTH-1:0] PADDR,
    input  [31:0] PWDATA,
    input  PWRITE,
    input  PSEL,
    input  PENABLE,

    output [31:0] PRDATA,
    output PREADY,
    output PSLVERR,
    output interrupt_o,

    input  scl_pad_i,
    output scl_pad_o,
    output scl_padoen_o,
    input  sda_pad_i,
    output sda_pad_o,
    output sda_padoen_o
);

    wire [3:0] s_apb_addr;

    reg [15:0] r_pre;
    reg [7:0]  r_ctrl;
    reg [7:0]  r_tx;
    wire [7:0] s_rx;
    reg [7:0]  r_cmd;
    wire [7:0] s_status;

    wire s_done;
    wire s_core_en;
    wire s_ien;

    wire s_irxack;
    reg rxack;
    reg tip;
    reg irq_flag;
    wire i2c_busy;
    wire i2c_al;
    reg al;

    assign s_apb_addr = PADDR[5:2];

    always @(posedge PCLK or negedge PRESETn)
    begin
        if(!PRESETn)
        begin
            r_pre  <= 0;
            r_ctrl <= 0;
            r_tx   <= 0;
            r_cmd  <= 0;
        end
        else if (PSEL && PENABLE && PWRITE)
        begin
            if (s_done | i2c_al)
                r_cmd[7:4] <= 0;

            r_cmd[2:1] <= 0;
            r_cmd[0]   <= 0;

            case (s_apb_addr)
                `REG_CLK_PRESCALER: r_pre  <= PWDATA[15:0];
                `REG_CTRL:          r_ctrl <= PWDATA[7:0];
                `REG_TX:            r_tx   <= PWDATA[7:0];
                `REG_CMD:
                    if(s_core_en)
                        r_cmd <= PWDATA[7:0];
                default: ;
            endcase
        end
        else
        begin
            if (s_done | i2c_al)
                r_cmd[7:4] <= 0;

            r_cmd[2:1] <= 0;
            r_cmd[0]   <= 0;
        end
    end

    assign PRDATA =
        (s_apb_addr == `REG_CLK_PRESCALER) ? {16'h0,r_pre}  :
        (s_apb_addr == `REG_CTRL)          ? {24'h0,r_ctrl} :
        (s_apb_addr == `REG_RX)            ? {24'h0,s_rx}   :
        (s_apb_addr == `REG_STATUS)        ? {24'h0,s_status}:
        (s_apb_addr == `REG_TX)            ? {24'h0,r_tx}   :
        (s_apb_addr == `REG_CMD)           ? {24'h0,r_cmd}  : 32'h0;

    wire sta  = r_cmd[7];
    wire sto  = r_cmd[6];
    wire rd   = r_cmd[5];
    wire wr   = r_cmd[4];
    wire ack  = r_cmd[3];
    wire iack = r_cmd[0];

    assign s_core_en = r_ctrl[7];
    assign s_ien     = r_ctrl[6];

    i2c_master_byte_ctrl byte_controller (
        .clk(PCLK),
        .nReset(PRESETn),
        .ena(s_core_en),
        .clk_cnt(r_pre),
        .start(sta),
        .stop(sto),
        .read(rd),
        .write(wr),
        .ack_in(ack),
        .din(r_tx),
        .cmd_ack(s_done),
        .ack_out(s_irxack),
        .dout(s_rx),
        .i2c_busy(i2c_busy),
        .i2c_al(i2c_al),
        .scl_i(scl_pad_i),
        .scl_o(scl_pad_o),
        .scl_oen(scl_padoen_o),
        .sda_i(sda_pad_i),
        .sda_o(sda_pad_o),
        .sda_oen(sda_padoen_o)
    );

    always @(posedge PCLK or negedge PRESETn)
    begin
        if(!PRESETn)
        begin
            al <= 0;
            rxack <= 0;
            tip <= 0;
            irq_flag <= 0;
        end
        else
        begin
            al       <= i2c_al | (al & ~sta);
            rxack    <= s_irxack;
            tip      <= (rd | wr);
            irq_flag <= (s_done | i2c_al | irq_flag) & ~iack;
        end
    end

    assign interrupt_o = irq_flag && s_ien;
    assign PREADY  = 1'b1;
    assign PSLVERR = 1'b0;

    assign s_status[7]   = rxack;
    assign s_status[6]   = i2c_busy;
    assign s_status[5]   = al;
    assign s_status[4:2] = 0;
    assign s_status[1]   = tip;
    assign s_status[0]   = irq_flag;

endmodule
