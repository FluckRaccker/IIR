module simple_cmd_storage
(
    input  logic        clk,
    input  logic        reset,       // reset ativo em 0

    input  logic [63:0] in_a,        // comando
    input  logic [63:0] in_b,        // dados

    output logic [63:0] out_export,
    output logic [2:0]  led,

    output logic signed [15:0] sample_to_iir,
    output logic               sample_tick,

    input  logic signed [15:0] iir_out,
    input  logic               iir_valid,

    output logic               clear_iir_state,

    output logic signed [15:0] coeff0,
    output logic signed [15:0] coeff1,
    output logic signed [15:0] coeff2,
    output logic signed [15:0] coeff3,
    output logic signed [15:0] coeff4
);

    // ============================================================
    // Protocolo de comandos
    // ============================================================

    localparam logic [7:0] CMD_NOP         = 8'h00;
    localparam logic [7:0] CMD_SAMPLE      = 8'h01;
    localparam logic [7:0] CMD_WRITE_COEFF = 8'h02;
    localparam logic [7:0] CMD_READ_COEFF  = 8'h03;
    localparam logic [7:0] CMD_CLEAR_IIR   = 8'h04;

    localparam int COEFF_DEPTH = 5;

    // Formato de in_a
    wire [7:0]  cmd       = in_a[7:0];
    wire [2:0]  coeff_idx = in_a[10:8];
    wire [15:0] seq       = in_a[47:32];

    logic [63:0] in_a_prev;
    wire cmd_tick = (in_a != in_a_prev) && (cmd != CMD_NOP);

    // ============================================================
    // Memória de coeficientes
    // Ordem:
    // coeff_mem[0] = a1
    // coeff_mem[1] = a2
    // coeff_mem[2] = b0
    // coeff_mem[3] = b1
    // coeff_mem[4] = b2
    // ============================================================

    logic signed [15:0] coeff_mem [0:COEFF_DEPTH-1];

    assign coeff0 = coeff_mem[0];
    assign coeff1 = coeff_mem[1];
    assign coeff2 = coeff_mem[2];
    assign coeff3 = coeff_mem[3];
    assign coeff4 = coeff_mem[4];

    logic signed [15:0] last_sample;
    logic [15:0]        last_seq;
    logic               waiting_iir;

    integer i;

    // LED visual de clock dentro do bloco
    blink blk_cmd
    (
        .clk (clk),
        .led (led[0])
    );

    // ============================================================
    // Máquina principal de comandos
    // ============================================================

    always_ff @(posedge clk) begin
        if (!reset) begin
            in_a_prev       <= 64'd0;
            out_export      <= 64'd0;

            sample_to_iir   <= 16'sd0;
            sample_tick     <= 1'b0;
            clear_iir_state <= 1'b0;

            last_sample     <= 16'sd0;
            last_seq        <= 16'd0;
            waiting_iir     <= 1'b0;

            led[1]          <= 1'b0;
            led[2]          <= 1'b0;

            // Coeficientes padrão: passa-baixa trivial / pass-through
            // y[n] = x[n]
            // Q2.14: 1.0 = 16384
            coeff_mem[0] <= 16'sd0;      // a1
            coeff_mem[1] <= 16'sd0;      // a2
            coeff_mem[2] <= 16'sd16384;  // b0
            coeff_mem[3] <= 16'sd0;      // b1
            coeff_mem[4] <= 16'sd0;      // b2
        end
        else begin
            // Pulsos de um clock
            sample_tick     <= 1'b0;
            clear_iir_state <= 1'b0;

            // LED indica FPGA rodando
            led[2] <= 1'b1;

            // ----------------------------------------------------
            // Recebe novo comando pelo HPS
            // ----------------------------------------------------
            if (cmd_tick) begin
                in_a_prev <= in_a;

                // Toggle para indicar que um comando chegou
                led[1] <= ~led[1];

                case (cmd)

                    // --------------------------------------------
                    // Envia uma amostra para o IIR
                    // in_b[15:0] = amostra signed 16 bits
                    // --------------------------------------------
                    CMD_SAMPLE: begin
                        sample_to_iir <= in_b[15:0];
                        sample_tick   <= 1'b1;

                        last_sample   <= in_b[15:0];
                        last_seq      <= seq;
                        waiting_iir   <= 1'b1;

                        // ACK de recebido, ainda não é o resultado
                        out_export <= {
                            8'h10,          // status: sample recebido
                            CMD_SAMPLE,
                            seq,
                            16'd0,
                            in_b[15:0]
                        };
                    end

                    // --------------------------------------------
                    // Escreve coeficiente
                    // in_a[10:8] = índice 0..4
                    // in_b[15:0] = valor signed Q2.14
                    // --------------------------------------------
                    CMD_WRITE_COEFF: begin
                        if (coeff_idx < COEFF_DEPTH) begin
                            coeff_mem[coeff_idx] <= in_b[15:0];

                            out_export <= {
                                8'hB0,          // status: coeficiente escrito
                                5'd0,
                                coeff_idx,
                                seq,
                                16'd0,
                                in_b[15:0]
                            };
                        end
                        else begin
                            out_export <= {
                                8'hE1,          // erro: índice inválido
                                5'd0,
                                coeff_idx,
                                seq,
                                32'd0
                            };
                        end
                    end

                    // --------------------------------------------
                    // Lê coeficiente
                    // in_a[10:8] = índice 0..4
                    // out_export[15:0] = coeficiente
                    // --------------------------------------------
                    CMD_READ_COEFF: begin
                        if (coeff_idx < COEFF_DEPTH) begin
                            out_export <= {
                                8'hC0,          // status: coeficiente lido
                                5'd0,
                                coeff_idx,
                                seq,
                                16'd0,
                                coeff_mem[coeff_idx]
                            };
                        end
                        else begin
                            out_export <= {
                                8'hE1,          // erro: índice inválido
                                5'd0,
                                coeff_idx,
                                seq,
                                32'd0
                            };
                        end
                    end

                    // --------------------------------------------
                    // Limpa estados internos do IIR
                    // Não apaga coeficientes
                    // --------------------------------------------
                    CMD_CLEAR_IIR: begin
                        clear_iir_state <= 1'b1;
                        waiting_iir     <= 1'b0;

                        out_export <= {
                            8'hD0,          // status: estado do IIR limpo
                            CMD_CLEAR_IIR,
                            seq,
                            32'd0
                        };
                    end

                    default: begin
                        out_export <= {
                            8'hEE,          // comando desconhecido
                            cmd,
                            seq,
                            32'd0
                        };
                    end
                endcase
            end

            // ----------------------------------------------------
            // Quando o IIR termina, devolve o resultado para o HPS
            // ----------------------------------------------------
            if (iir_valid && waiting_iir) begin
                waiting_iir <= 1'b0;

                out_export <= {
                    8'hA0,          // status: resultado pronto
                    CMD_SAMPLE,
                    last_seq,
                    last_sample,
                    iir_out
                };
            end
        end
    end

endmodule