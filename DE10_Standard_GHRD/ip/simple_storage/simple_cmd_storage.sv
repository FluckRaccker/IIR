module simple_cmd_storage
(
    input  logic        clk,
    input  logic        reset,
    input  logic [63:0] in_a,
    input  logic [63:0] in_b,
    output logic [63:0] out_export,
    output logic [2:0]  led,
	 output logic [15:0] coeff0,
    output logic [15:0] coeff1,
    output logic [15:0] coeff2,
    output logic [15:0] coeff3,
    output logic [15:0] coeff4
);

    localparam ADDR_WIDTH  = 4;
    localparam DATA_WIDTH  = 16;
    localparam DEPTH       = 16;
    localparam COEFF_DEPTH = 5;

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    wire [4:0] cmd;
    wire [ADDR_WIDTH-1:0] addr;

    reg [63:0] in_b_prev;
    reg [$clog2(COEFF_DEPTH)-1:0] wptr;
    reg [$clog2(COEFF_DEPTH)-1:0] rptr;

    integer i;

    assign cmd    = in_b[4:0];
    assign addr   = in_b[8:5];
    assign led[1] = reset;
	 
	 assign coeff0 = mem[0];
    assign coeff1 = mem[1];
    assign coeff2 = mem[2];
    assign coeff3 = mem[3];
    assign coeff4 = mem[4];

    always @(posedge clk) begin
        if (!reset) begin
            out_export <= 64'd0;
            in_b_prev  <= 64'd0;
            led[2]     <= 1'b0;
            wptr       <= 0;
            rptr       <= 0;

            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
        end
        else begin
            led[2] <= 1'b1;

            if (in_b != in_b_prev) begin
                in_b_prev <= in_b;
                led[2]    <= 1'b0;

                if (cmd == 5'b00001) begin
                    // WRITE DATA
                    mem[addr] <= in_a[DATA_WIDTH-1:0];
                end
                else if (cmd == 5'b00010) begin
                    // READ ADDRESS
                    out_export <= {{(64-DATA_WIDTH){1'b0}}, mem[addr]};
                end
                else if (cmd[1:0] == 2'b11) begin
                    // WRITE BATCH: até 4 palavras de 16 bits a partir de in_a

                    for (i = 0; i < 4; i = i + 1) begin
                        if (i < cmd[4:2]) begin
                            if ((wptr + i) <= COEFF_DEPTH) begin
                                mem[wptr + i] <= in_a[i*DATA_WIDTH +: DATA_WIDTH];
                            end
                        end
                    end

                    if ((wptr + cmd[4:2]) >= COEFF_DEPTH)
                        wptr <= 0;
                    else
                        wptr <= wptr + cmd[4:2];
                end
            end
        end
    end

	blink blk2(
	.clk(clk),
	.led(led[0])
	);

endmodule