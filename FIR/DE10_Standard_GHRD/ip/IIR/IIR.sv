module IIR 
(
    input  logic        CLOCK_50,

    output logic [4:0]  LEDR,

    input  logic        reset,      // reset ativo em 0
    input  logic [63:0] in_a,       // comando
    input  logic [63:0] in_b,       // dados
    output logic [63:0] out_export
);

    logic clk_50;
    assign clk_50 = CLOCK_50;

    // ============================================================
    // Sinais entre command storage e IIR
    // ============================================================

    logic signed [15:0] sample_to_iir;
    logic               sample_tick;

    logic signed [15:0] iir_out;
    logic               iir_valid;

    logic               clear_iir_state;

    logic signed [15:0] coeff0;
    logic signed [15:0] coeff1;
    logic signed [15:0] coeff2;
    logic signed [15:0] coeff3;
    logic signed [15:0] coeff4;

    // ============================================================
    // IIR biquad
    // coeff0 = a1
    // coeff1 = a2
    // coeff2 = b0
    // coeff3 = b1
    // coeff4 = b2
    // ============================================================

    simple_IIR_biquad_DF1 s_iir_r
    (
        .clk          (clk_50),
        .reset        (reset),
        .clear_state  (clear_iir_state),

        .sample_tick  (sample_tick),
        .din          (sample_to_iir),

        .a1_fixed     (coeff0),
        .a2_fixed     (coeff1),
        .b0_fixed     (coeff2),
        .b1_fixed     (coeff3),
        .b2_fixed     (coeff4),

        .dout         (iir_out),
        .dout_valid   (iir_valid)
    );

    // ============================================================
    // Bloco de comando HPS -> FPGA
    // ============================================================

    simple_cmd_storage cmd_block
    (
        .clk             (clk_50),
        .reset           (reset),

        .in_a            (in_a),
        .in_b            (in_b),
        .out_export      (out_export),

        .led             (LEDR[4:2]),

        .sample_to_iir   (sample_to_iir),
        .sample_tick     (sample_tick),

        .iir_out         (iir_out),
        .iir_valid       (iir_valid),

        .clear_iir_state (clear_iir_state),

        .coeff0          (coeff0),
        .coeff1          (coeff1),
        .coeff2          (coeff2),
        .coeff3          (coeff3),
        .coeff4          (coeff4)
    );

    // LEDR[0] pisca muito rápido, mas serve para debug em SignalTap
    assign LEDR[0] = sample_tick;

    // LEDR[1] confirmação visual de clock
    blink blk2
    (
        .clk (clk_50),
        .led (LEDR[1])
    );

endmodule