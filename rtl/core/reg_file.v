`timescale 1ns/1ps

module reg_file #(parameter DATA_WIDTH = 32) (
    input clk,
    input rst,
    input wr_en,
    input [4:0] rd_addr1, rd_addr2, wr_addr,
    input [DATA_WIDTH-1:0] wr_data,
    output [DATA_WIDTH-1:0] rd_data1, rd_data2
);

reg [DATA_WIDTH-1:0] reg_file_arr [0:31];

integer i;

// write
always @(posedge clk or posedge rst) begin
    if (rst) begin
        for (i = 0; i < 32; i = i + 1)
            reg_file_arr[i] <= 32'b0;
    end
    else if (wr_en && wr_addr != 5'b0)
        reg_file_arr[wr_addr] <= wr_data;
end

// read with bypass
assign rd_data1 =
        (rd_addr1 == 5'b0) ? 32'b0 :
        (wr_en && wr_addr == rd_addr1) ? wr_data :
        reg_file_arr[rd_addr1];

assign rd_data2 =
        (rd_addr2 == 5'b0) ? 32'b0 :
        (wr_en && wr_addr == rd_addr2) ? wr_data :
        reg_file_arr[rd_addr2];

endmodule
