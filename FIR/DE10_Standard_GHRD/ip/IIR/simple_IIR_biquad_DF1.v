module simple_IIR_biquad_DF1 
#(
    parameter int Q_SHIFT = 14
)
(
    input  logic clk,
    input  logic reset,        // reset ativo em 0
    input  logic clear_state,

    input  logic sample_tick,
    input  logic signed [15:0] din,

    input  logic signed [15:0] a1_fixed,
    input  logic signed [15:0] a2_fixed,
    input  logic signed [15:0] b0_fixed,
    input  logic signed [15:0] b1_fixed,
    input  logic signed [15:0] b2_fixed,

    output logic signed [15:0] dout,
    output logic               dout_valid
);

    logic signed [15:0] x_z1;
    logic signed [15:0] x_z2;
    logic signed [15:0] y_z1;
    logic signed [15:0] y_z2;

    wire signed [31:0] product_b0 = din  * b0_fixed;
    wire signed [31:0] product_b1 = x_z1 * b1_fixed;
    wire signed [31:0] product_b2 = x_z2 * b2_fixed;

    wire signed [31:0] product_a1 = -(y_z1 * a1_fixed);
    wire signed [31:0] product_a2 = -(y_z2 * a2_fixed);

    wire signed [35:0] acc =
        {{4{product_b0[31]}}, product_b0} +
        {{4{product_b1[31]}}, product_b1} +
        {{4{product_b2[31]}}, product_b2} +
        {{4{product_a1[31]}}, product_a1} +
        {{4{product_a2[31]}}, product_a2};

    wire signed [35:0] y_scaled = acc >>> Q_SHIFT;

    function automatic logic signed [15:0] sat16;
        input logic signed [35:0] value;
        begin
            if (value > 36'sd32767)
                sat16 = 16'sh7FFF;
            else if (value < -36'sd32768)
                sat16 = 16'sh8000;
            else
                sat16 = value[15:0];
        end
    endfunction

    wire signed [15:0] y_next = sat16(y_scaled);

    always_ff @(posedge clk) begin
        if (!reset) begin
            x_z1       <= 16'sd0;
            x_z2       <= 16'sd0;
            y_z1       <= 16'sd0;
            y_z2       <= 16'sd0;
            dout       <= 16'sd0;
            dout_valid <= 1'b0;
        end
        else begin
            dout_valid <= 1'b0;

            if (clear_state) begin
                x_z1       <= 16'sd0;
                x_z2       <= 16'sd0;
                y_z1       <= 16'sd0;
                y_z2       <= 16'sd0;
                dout       <= 16'sd0;
                dout_valid <= 1'b0;
            end
            else if (sample_tick) begin
                dout       <= y_next;
                dout_valid <= 1'b1;

                x_z2 <= x_z1;
                x_z1 <= din;

                y_z2 <= y_z1;
                y_z1 <= y_next;
            end
        end
    end

endmodule