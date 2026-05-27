module simple_adder(	
  input logic clk,
  input logic [63:0] a,
  input logic [63:0] b,
  output logic [63:0] sum,
  output led
);
assign sum = a + b;

reg [26:0] counter;

always @(posedge clk) counter <= counter + 1'b1;

assign led = counter[26];

endmodule