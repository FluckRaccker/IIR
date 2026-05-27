module strobe_relative 
	(
		input clk,
		
		input in_relative,
		
		output stb_out
	);
	// gera um strobe em relacao ao sinal clk e frequencia relativa a in_relative
	
	reg stb_reg;
	reg stb_in_reg;
	always @(posedge clk)
	begin
		stb_in_reg <= in_relative;
		
		if ((stb_in_reg == 0) && (in_relative == 1))
			stb_reg <= 1;
		else
			stb_reg <= 0;
		
	end
	
	assign stb_out = stb_reg;
	
endmodule 