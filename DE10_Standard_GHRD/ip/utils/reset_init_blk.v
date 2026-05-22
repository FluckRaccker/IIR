module reset_init_blk 
	(
		input clk,
		
		output rst_out
	);
	
	reg [7:0] reset_count;
	reg rst_reg;
	always @(posedge clk)
		if (reset_count == 8'hffff)
			rst_reg <= 0;
		else
		begin
			rst_reg	<= 1;
			reset_count <= reset_count + 8'd1;
		end
	
	assign rst_out = rst_reg;
	
endmodule 