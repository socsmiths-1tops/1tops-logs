`timescale 1ns/1ps

module spi_fifo (
    input  wire        clk,
    input  wire        resetn,
    input  wire        wr_en,
    input  wire        rd_en,
    input  wire [31:0] wr_data,
    output wire [31:0] rd_data,
    output wire        full,
    output wire        empty,
    output wire [4:0]  level
);

    reg [31:0] mem [0:15];
    reg [3:0]  wr_ptr;
    reg [3:0]  rd_ptr;
    reg [4:0]  count;

    integer j;

    assign full    = (count == 5'd16);
    assign empty   = (count == 5'd0);
    assign level   = count;
    assign rd_data = mem[rd_ptr];

    always @(posedge clk or negedge resetn)
    begin
        if (!resetn)
        begin
            wr_ptr <= 4'd0;
            rd_ptr <= 4'd0;
            count  <= 5'd0;

            for (j = 0; j < 16; j = j + 1)
                mem[j] <= 32'd0;
        end
        else
        begin
            if (wr_en && !full)
            begin
                mem[wr_ptr] <= wr_data;
                wr_ptr <= wr_ptr + 4'd1;
            end

            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 4'd1;

            case ({wr_en && !full, rd_en && !empty})
                2'b10: count <= count + 5'd1;
                2'b01: count <= count - 5'd1;
                default: count <= count;
            endcase
        end
    end

endmodule
