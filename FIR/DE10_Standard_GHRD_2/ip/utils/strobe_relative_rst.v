module strobe_relative_rst
	(
		input clk,
		input rst,
		
		input in_relative,
		
		output stb_out
	);
	// gera um strobe em relacao ao sinal clk e frequencia relativa a in_relative
	
	reg stb_reg;
	reg stb_in_reg;
	always @(posedge clk, posedge rst)
	if (rst)
	begin
		stb_reg <= 0;
		stb_in_reg <= 0;
	end
	else begin
		stb_in_reg <= in_relative;
		
		if ((stb_in_reg == 0) && (in_relative == 1))
			stb_reg <= 1;
		else
			stb_reg <= 0;
		
	end
	
	assign stb_out = stb_reg;
	
endmodule 