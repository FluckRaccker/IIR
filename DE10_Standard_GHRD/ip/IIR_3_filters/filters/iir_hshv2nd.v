
module iir_hshv2nd (
  input clk,
  input signed [15:0] din,
  output signed [15:0] dout
);


//
	reg signed [15:0] a1_fixed = -18778;
	reg signed [15:0] a2_fixed = 6786;
	reg signed [15:0] b0_fixed = 2283;
	reg signed [15:0] b1_fixed = 1533;
	reg signed [15:0] b2_fixed = 576;

//	reg signed [15:0] a1_fixed = 441;
//	reg signed [15:0] a2_fixed = 2813;
//	reg signed [15:0] b0_fixed = 31804;
//	reg signed [15:0] b1_fixed = -19837;
//	reg signed [15:0] b2_fixed = 7671;

	
  // input register
  reg signed [15:0] r_x = 0;

  // output register
  reg signed [15:0] r_y = 0;

  // delay registers
  reg signed [15:0] r_x_z1 = 0;
  reg signed [15:0] r_x_z2 = 0;
  reg signed [15:0] r_y_z1 = 0;
  reg signed [15:0] r_y_z2 = 0;

  // multiplication wires
  wire signed [31:0] w_product_a1;
  wire signed [31:0] w_product_a2;
  wire signed [31:0] w_product_b0;
  wire signed [31:0] w_product_b1;
  wire signed [31:0] w_product_b2;

  wire signed [31:0] w_sum; 

  always @ (posedge clk)
    begin
      r_x <= din;
      r_x_z1 <= r_x;
      r_x_z2 <= r_x_z1;
      r_y_z1 <= w_sum >>> 14;  // divide by the same 2^14 value the coefficients were multiplied by
      r_y_z2 <= r_y_z1;
    end

  // multiply
  assign w_product_a1 = r_y_z1 * -a1_fixed;
  assign w_product_a2 = r_y_z2 * -a2_fixed;
  assign w_product_b0 = r_x * b0_fixed;
  assign w_product_b1 = r_x_z1 * b1_fixed;
  assign w_product_b2 = r_x_z2 * b2_fixed;

  assign w_sum = w_product_b0 + w_product_b1 + w_product_b2 + w_product_a1 + w_product_a2;

  assign dout = r_y_z1;

endmodule