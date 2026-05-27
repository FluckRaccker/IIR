// ============================================================
// simple_cmd_storage_fir1.sv
// Interface HPS <-> 1 FIR reconfiguravel
//
// Protocolo HPS:
//   in_a[63:0]  = dado/payload
//   in_b[7:0]   = opcode
//   in_b[63:8]  = seq. O HPS deve mudar esse campo a cada comando.
//
// Opcodes:
//   0x00 CMD_NOP
//   0x20 CMD_SET_COEFF    in_a = {c3,c2,c1,c0}, signed Q15, 4x16 bits
//   0x22 CMD_CLEAR_PENDING
//   0x23 CMD_CLEAR_OVERRUN
//   0x40 CMD_SET_SAMPLE   in_a[DATA_WIDTH-1:0] = amostra signed
//   0x41 CMD_CLEAR_RESULT
//
// out_data:
//   [63:56] command_counter
//   [55:48] last_opcode
//   [47:36] coeff_count
//   [35:28] status_flags
//   [27:0]  sample_counter[27:0]
//
// status_flags:
//   [0] fir_ready
//   [1] coeff_pending
//   [2] sample_pending
//   [3] coeff_overrun
//   [4] sample_overrun
//   [5] coeff_ok
//   [6] result_valid_sticky
//   [7] fir_en_last
//
// out_export:
//   [63:48] last_output signed16
//   [47:32] last_input  signed16
//   [31:16] result_counter[15:0]
//   [15:0]  sample_counter[15:0]
// ============================================================

module simple_cmd_storage_fir1 #(
    parameter int DATA_WIDTH  = 16,
    parameter int COEFF_WIDTH = 16
)(
    input  logic                          clk,
    input  logic                          reset_n,

    input  logic [63:0]                   in_a,
    input  logic [63:0]                   in_b,

    output logic [63:0]                   out_export,
    output logic [63:0]                   out_data,

    // Interface com o FIR
    output logic signed [DATA_WIDTH-1:0]  fir_data_in,
    output logic [4*COEFF_WIDTH-1:0]      fir_coeff_in,
    output logic                          fir_en,
    output logic                          fir_mode,       // 0 = carrega coef, 1 = filtra amostra

    input  logic                          fir_ready,      // use ~busy do feedsecondary_fir
    input  logic                          fir_coeff_ok,
    input  logic [11:0]                   fir_coeff_count,
    input  logic signed [DATA_WIDTH-1:0]  fir_data_out,
    input  logic                          fir_valid_out
);

    // -----------------------------
    // Opcodes
    // -----------------------------
    localparam logic [7:0] CMD_NOP           = 8'h00;
    localparam logic [7:0] CMD_SET_COEFF     = 8'h20;
    localparam logic [7:0] CMD_CLEAR_PENDING = 8'h22;
    localparam logic [7:0] CMD_CLEAR_OVERRUN = 8'h23;
    localparam logic [7:0] CMD_SET_SAMPLE    = 8'h40;
    localparam logic [7:0] CMD_CLEAR_RESULT  = 8'h41;

    logic [7:0]  opcode;
    logic [63:0] in_b_prev;

    assign opcode = in_b[7:0];

    // -----------------------------
    // Buffers e status
    // -----------------------------
    logic [4*COEFF_WIDTH-1:0] coeff_buf;
    logic signed [DATA_WIDTH-1:0] sample_buf;

    logic coeff_pending;
    logic sample_pending;
    logic coeff_overrun;
    logic sample_overrun;

    logic [7:0]  command_counter;
    logic [7:0]  last_opcode;
    logic [31:0] sample_counter;
    logic [31:0] result_counter;

    logic signed [DATA_WIDTH-1:0] last_input;
    logic signed [DATA_WIDTH-1:0] last_output;

    logic result_valid_sticky;
    logic fir_en_last;

    logic [7:0] status_flags;

    assign status_flags = {
        fir_en_last,
        result_valid_sticky,
        fir_coeff_ok,
        sample_overrun,
        coeff_overrun,
        sample_pending,
        coeff_pending,
        fir_ready
    };

    assign out_data = {
        command_counter,
        last_opcode,
        fir_coeff_count,
        status_flags,
        sample_counter[27:0]
    };

    assign out_export = {
        last_output[15:0],
        last_input[15:0],
        result_counter[15:0],
        sample_counter[15:0]
    };

    // -----------------------------
    // Processo principal
    // -----------------------------
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            in_b_prev           <= 64'd0;

            fir_en              <= 1'b0;
            fir_mode            <= 1'b0;
            fir_data_in         <= '0;
            fir_coeff_in        <= '0;

            coeff_buf           <= '0;
            sample_buf          <= '0;

            coeff_pending       <= 1'b0;
            sample_pending      <= 1'b0;
            coeff_overrun       <= 1'b0;
            sample_overrun      <= 1'b0;

            command_counter     <= 8'd0;
            last_opcode         <= CMD_NOP;
            sample_counter      <= 32'd0;
            result_counter      <= 32'd0;

            last_input          <= '0;
            last_output         <= '0;

            result_valid_sticky <= 1'b0;
            fir_en_last         <= 1'b0;
        end
        else begin
            // Pulsos de 1 ciclo
            fir_en      <= 1'b0;
            fir_en_last <= 1'b0;

            // Captura resultado do FIR. O valid_out do FIR e pulso de 1 ciclo.
            if (fir_valid_out) begin
                last_output         <= fir_data_out;
                result_counter      <= result_counter + 32'd1;
                result_valid_sticky <= 1'b1;
            end

            // Entrega pendencias para o FIR quando ele estiver pronto.
            // Prioridade: coeficientes antes das amostras.
            if (fir_ready) begin
                if (coeff_pending) begin
                    fir_coeff_in   <= coeff_buf;
                    fir_mode       <= 1'b0;       // carregar coeficientes
                    fir_en         <= 1'b1;
                    fir_en_last    <= 1'b1;
                    coeff_pending  <= 1'b0;
                end
                else if (sample_pending) begin
                    fir_data_in       <= sample_buf;
                    last_input        <= sample_buf;
                    fir_mode          <= 1'b1;    // filtrar amostra
                    fir_en            <= 1'b1;
                    fir_en_last       <= 1'b1;
                    sample_pending    <= 1'b0;
                    sample_counter    <= sample_counter + 32'd1;
                    result_valid_sticky <= 1'b0;  // novo resultado ainda nao chegou
                end
            end

            // Processa comando novo do HPS.
            if (in_b != in_b_prev) begin
                in_b_prev <= in_b;

                if (opcode != CMD_NOP) begin
                    command_counter <= command_counter + 8'd1;
                    last_opcode     <= opcode;

                    case (opcode)
                        CMD_SET_COEFF: begin
                            if (!coeff_pending) begin
                                coeff_buf     <= in_a[4*COEFF_WIDTH-1:0];
                                coeff_pending <= 1'b1;
                            end
                            else begin
                                coeff_overrun <= 1'b1;
                            end
                        end

                        CMD_SET_SAMPLE: begin
                            if (!sample_pending) begin
                                sample_buf     <= $signed(in_a[DATA_WIDTH-1:0]);
                                sample_pending <= 1'b1;
                            end
                            else begin
                                sample_overrun <= 1'b1;
                            end
                        end

                        CMD_CLEAR_PENDING: begin
                            coeff_pending  <= 1'b0;
                            sample_pending <= 1'b0;
                        end

                        CMD_CLEAR_OVERRUN: begin
                            coeff_overrun  <= 1'b0;
                            sample_overrun <= 1'b0;
                        end

                        CMD_CLEAR_RESULT: begin
                            result_valid_sticky <= 1'b0;
                        end

                        default: begin
                            // Comando desconhecido: ignora.
                        end
                    endcase
                end
            end
        end
    end

endmodule
