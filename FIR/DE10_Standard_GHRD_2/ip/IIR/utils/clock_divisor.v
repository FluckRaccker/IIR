module clock_divisor #(
	parameter LOG_MIN = 13,
	parameter RATE_DIVISOR = 2500
				)
(
	input clk_in,
	input rst,
	
	output clk_out
);
	
	localparam RATE_DIVISOR_HALF = RATE_DIVISOR/2;
	
	reg [LOG_MIN-1:0] clk_count;
	reg clk_out_reg;
	always @(posedge clk_in, posedge rst)
		if (rst)
		begin
			clk_count <= 0;
			clk_out_reg <= 0;
		end else
		begin
			if (clk_count == RATE_DIVISOR-1)
				clk_count <= 0;
			else	
				clk_count <= clk_count + 1;
				
			if (clk_count == RATE_DIVISOR-1)
				clk_out_reg <= 0;
			else if (clk_count == RATE_DIVISOR_HALF-1)
				clk_out_reg <= 1;
		end
		
	assign clk_out = clk_out_reg;
	
endmodule
