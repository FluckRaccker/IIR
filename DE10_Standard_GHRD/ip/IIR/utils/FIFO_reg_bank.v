module FIFO_reg_bank #(	parameter LENGTH_DATA = 32,
				 		parameter LENGTH_DELAY = 2
						)
	(
		input clk,
		
		input [LENGTH_DATA-1:0] in_bank,
		
		output [LENGTH_DATA-1:0] out_bank
		
	);
	
	reg [LENGTH_DATA-1:0] reg_bank [0:LENGTH_DELAY-1];
	
	integer i;
	always @(posedge clk)
	begin
		reg_bank[0] <= in_bank;
		for (i = 1; i <= LENGTH_DELAY-1; i=i+1)
			reg_bank[i] <= reg_bank[i-1];
	end	
	
	assign out_bank = reg_bank[LENGTH_DELAY-1];
	
endmodule 