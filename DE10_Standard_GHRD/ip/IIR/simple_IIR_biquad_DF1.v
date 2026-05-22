
module simple_IIR_biquad_DF1 (
	input clk,
	input signed [15:0] din,

	input signed [15:0] a1_fixed,
	input signed [15:0] a2_fixed,
	input signed [15:0] b0_fixed,
	input signed [15:0] b1_fixed,
	input signed [15:0] b2_fixed,

	output signed [15:0] dout
);



//	reg signed [15:0] a1_fixed = 1360;
//	reg signed [15:0] a2_fixed = 2831;
//	reg signed [15:0] b0_fixed = 5193;
//	reg signed [15:0] b1_fixed = -8825;
//	reg signed [15:0] b2_fixed = 3838;

  // filter coefficients (multiplied floating point coefficients by 2^14)
  // sos = {1.0000   -1.8057    1.0000    1.0000   -1.9459    0.9480}
  //         b0         b1        b2        a0        a1        a2
  //   g = 0.0102 
//  reg signed [15:0] a1_fixed = -31881;
//  reg signed [15:0] a2_fixed = 15531;
//  reg signed [15:0] b0_fixed = 167;    // g * b0 * 2^14  (multiply denom coeffs by gain for DF1 [source 1])
//  reg signed [15:0] b1_fixed = -302;   // g * b1 * 2^14 
//  reg signed [15:0] b2_fixed = 167;    // g * b2 * 2^14
	
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