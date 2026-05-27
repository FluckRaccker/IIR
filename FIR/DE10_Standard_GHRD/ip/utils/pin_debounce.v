module pin_debounce #(parameter LENGTH = 500)
(
  input clk,
  input rst,

  input sig_in,

  output wire sig_out
);

  reg [10:0] counter;
  reg SM;
  reg sig_reg;
  always @(posedge clk)
    if (rst)
    begin
      counter <= 0;
      SM <= 0;
      sig_reg <= 0;
    end else begin
      case (SM)
        0:
        begin
          if (sig_reg != sig_in)
            SM <= 1;

          sig_reg <= sig_in;
          counter <= 0; 
        end 
        
        1:
        begin
          if (counter == LENGTH-1)
            SM <= 0;
          else 
            counter <= counter + 1; 
        end
      endcase
    end

    assign sig_out = sig_reg;
  
endmodule 