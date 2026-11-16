`timescale 1ns/1ps
module data_parser(
    input  [2:0]  func3,
    input  [1:0]  byte_off,   // DataAdr[1:0]
    input  [31:0] mem_word,
    output reg [31:0] data_out
);
// Select the correct byte/halfword based on address offset
wire [7:0]  byte_sel  = (byte_off == 2'b00) ? mem_word[ 7: 0] :
                        (byte_off == 2'b01) ? mem_word[15: 8] :
                        (byte_off == 2'b10) ? mem_word[23:16] :
                                              mem_word[31:24];
wire [15:0] half_sel  = (byte_off[1] == 1'b0) ? mem_word[15: 0] :
                                                  mem_word[31:16];
always @(*) begin
    case(func3)
        3'b000: data_out = {{24{byte_sel[7]}},  byte_sel};        // LB
        3'b001: data_out = {{16{half_sel[15]}}, half_sel};        // LH
        3'b010: data_out = mem_word;                               // LW
        3'b100: data_out = {24'b0, byte_sel};                     // LBU
        3'b101: data_out = {16'b0, half_sel};                     // LHU
        default: data_out = mem_word;
    endcase
end
endmodule
