`timescale 1ns/1ps
// ============================================================
// mdu_wrapper.v  RV32M multiply/divide unit (Execute stage)
//
// MUL/MULH/MULHSU/MULHU: one shared 33x33 signed multiplier, 2 cycles:
//   operands are registered on the start cycle and the product is computed
//   from those registers in the next cycle, straight into the E/M register
//   (timing: reg -> multiplier -> reg, no forwarding mux in the path).
// DIV/DIVU/REM/REMU: iterative restoring divider, 32 iterations + 1 start
// cycle. While an M operation is in progress `div_stall` freezes F/D/E and
// the Execute stage feeds bubbles into Memory (see hazard_unit / execute).
//   - operands are latched on the start cycle (forwarded values)
//   - `hold` (MemStall): the divider keeps iterating, the result is held
//     until the pipeline advances
//   - `kill` (trap taken on this instruction): divider aborts; the
//     instruction is re-executed after mret
// Spec corner cases: x/0 -> quotient all ones, remainder = dividend;
// (-2^31)/(-1) -> quotient -2^31, remainder 0 (falls out naturally).
// ============================================================
module mdu_wrapper(
    input         clk,
    input         rst,
    input  [31:0] rs1,
    input  [31:0] rs2,
    input  [2:0]  funct3,
    input  [6:0]  func7,
    input  [6:0]  op,
    input         hold,
    input         kill,
    output [31:0] m_result,
    output        div_stall
);

wire is_m_instr = (op == 7'b0110011) && (func7 == 7'b0000001);
wire is_div     = is_m_instr & funct3[2];

//  Multiply (operands registered at start, product in the following cycle)
reg  [31:0] ma, mb;
reg  [1:0]  mf;                                   // funct3[1:0]
reg         m_is_mul;                             // result source: multiplier
// rs1 signed for MUL/MULH/MULHSU, rs2 signed for MUL/MULH
wire a_sgn = (mf != 2'b11) & ma[31];
wire b_sgn = (mf[1] == 1'b0) & mb[31];
wire signed [65:0] prod = $signed({a_sgn, ma}) * $signed({b_sgn, mb});
wire [31:0] mul_res = (mf == 2'b00) ? prod[31:0] : prod[63:32];

//  Divide
wire        d_signed = ~funct3[0];                 // DIV, REM
wire        a_neg    = d_signed & rs1[31];
wire        b_neg    = d_signed & rs2[31];
wire [31:0] a_mag    = a_neg ? (~rs1 + 32'd1) : rs1;
wire [31:0] b_mag    = b_neg ? (~rs2 + 32'd1) : rs2;

reg        busy, done;
reg [4:0]  cnt;
reg [31:0] quo, rem, dvsr, dividend;
reg        neg_q, neg_r, dz, want_rem;
reg [31:0] div_res;

wire        start = is_m_instr & ~busy & ~done & ~kill & ~hold;
wire [32:0] trial = {rem, quo[31]} - {1'b0, dvsr};   // 33-bit
wire        fits  = ~trial[32];
wire [31:0] rem_n = fits ? trial[31:0] : {rem[30:0], quo[31]};
wire [31:0] quo_n = {quo[30:0], fits};

wire [31:0] q_fix = dz ? 32'hFFFFFFFF : (neg_q ? (~quo_n + 32'd1) : quo_n);
wire [31:0] r_fix = dz ? dividend     : (neg_r ? (~rem_n + 32'd1) : rem_n);

always @(posedge clk or posedge rst) begin
    if (rst) begin
        busy <= 1'b0; done <= 1'b0; cnt <= 5'd0;
        quo <= 32'd0; rem <= 32'd0; dvsr <= 32'd0; dividend <= 32'd0;
        neg_q <= 1'b0; neg_r <= 1'b0; dz <= 1'b0; want_rem <= 1'b0;
        div_res <= 32'd0;
        ma <= 32'd0; mb <= 32'd0; mf <= 2'd0; m_is_mul <= 1'b0;
    end else if (kill) begin
        busy <= 1'b0;
        done <= 1'b0;
    end else if (start) begin
        ma       <= rs1;
        mb       <= rs2;
        mf       <= funct3[1:0];
        m_is_mul <= ~funct3[2];
        busy     <= funct3[2];          // divide iterates; multiply result
        done     <= ~funct3[2];         // is ready next cycle (from ma/mb)
        cnt      <= 5'd0;
        quo      <= a_mag;
        rem      <= 32'd0;
        dvsr     <= b_mag;
        dividend <= rs1;
        dz       <= (rs2 == 32'd0);
        neg_q    <= a_neg ^ b_neg;
        neg_r    <= a_neg;
        want_rem <= funct3[1];
    end else if (busy) begin
        quo <= quo_n;
        rem <= rem_n;
        cnt <= cnt + 5'd1;
        if (cnt == 5'd31) begin
            busy    <= 1'b0;
            done    <= 1'b1;
            div_res <= want_rem ? r_fix : q_fix;
        end
    end else if (done && !hold) begin
        done <= 1'b0;          // result consumed: E advanced this cycle
    end
end

assign div_stall = is_m_instr & ~done;
assign m_result  = (!is_m_instr) ? 32'd0 : (m_is_mul ? mul_res : div_res);

endmodule
