module DE10_Standard_GHRD(


      ///////// CLOCK /////////
      input              CLOCK2_50,
      input              CLOCK3_50,
      input              CLOCK4_50,
      input              CLOCK_50,

      ///////// KEY /////////
      input    [ 3: 0]   KEY,

      ///////// SW /////////
      input    [ 9: 0]   SW,

      ///////// LED /////////
      output   [ 9: 0]   LEDR,

      ///////// GPIO /////////
      inout    [35: 0]   GPIO,

      output      [14:0] HPS_DDR3_ADDR,
      output      [2:0]  HPS_DDR3_BA,
      output             HPS_DDR3_CAS_N,	
      output             HPS_DDR3_CKE,
      output             HPS_DDR3_CK_N,
      output             HPS_DDR3_CK_P,
      output             HPS_DDR3_CS_N,
      output      [3:0]  HPS_DDR3_DM,
      inout       [31:0] HPS_DDR3_DQ,
      inout       [3:0]  HPS_DDR3_DQS_N,
      inout       [3:0]  HPS_DDR3_DQS_P,
      output             HPS_DDR3_ODT,
      output             HPS_DDR3_RAS_N,
      output             HPS_DDR3_RESET_N,
      input              HPS_DDR3_RZQ,
      output             HPS_DDR3_WE_N

);



//=======================================================
//  REG/WIRE declarations
//=======================================================
  wire  hps_fpga_reset_n;
  wire [3:0] fpga_debounced_buttons;
  wire [8:0]  fpga_led_internal;
  wire        fpga_clk_50;
  wire [63:0] input_a_export;
  wire [63:0] input_b_export;
  wire [63:0] output_mm_export;
  wire [63:0] out_data_export;
// connection of internal logics
  assign LEDR[1] = fpga_led_internal;
  assign stm_hw_events    = {{4{1'b0}}, SW, fpga_led_internal, fpga_debounced_buttons};
  assign fpga_clk_50=CLOCK_50;
  
//=======================================================
//  Components declarations
//=======================================================

  
   fir_reconfig_top dut (
    .clk    (fpga_clk_50),
    .LEDR        (LEDR[6:2]),
	 .reset_n(SW[0]),
	 .in_a(input_a_export),
	 .in_b(input_b_export),
	 .out_data(out_data_export),
	 .out_export(output_mm_export)
  );
  
  
//=======================================================
//  Structural coding
//=======================================================
soc_system u0 (
			// Adder
		  .input_a_export(input_a_export),
		  .input_b_export(input_b_export),
		  .output_mm_export(output_mm_export),
		  .out_data_export(out_data_export),
         //Clock&Reset		  
		  .clk_clk                               (CLOCK_50),                             //                clk.clk
		  .reset_reset_n                         (1'b1),                                 //                reset.reset_n
		  //HPS ddr3
		  .memory_mem_a                          ( HPS_DDR3_ADDR),                       //                memory.mem_a
        .memory_mem_ba                         ( HPS_DDR3_BA),                         //                .mem_ba
        .memory_mem_ck                         ( HPS_DDR3_CK_P),                       //                .mem_ck
        .memory_mem_ck_n                       ( HPS_DDR3_CK_N),                       //                .mem_ck_n
        .memory_mem_cke                        ( HPS_DDR3_CKE),                        //                .mem_cke
        .memory_mem_cs_n                       ( HPS_DDR3_CS_N),                       //                .mem_cs_n
        .memory_mem_ras_n                      ( HPS_DDR3_RAS_N),                      //                .mem_ras_n
        .memory_mem_cas_n                      ( HPS_DDR3_CAS_N),                      //                .mem_cas_n
        .memory_mem_we_n                       ( HPS_DDR3_WE_N),                       //                .mem_we_n
        .memory_mem_reset_n                    ( HPS_DDR3_RESET_N),                    //                .mem_reset_n
        .memory_mem_dq                         ( HPS_DDR3_DQ),                         //                .mem_dq
        .memory_mem_dqs                        ( HPS_DDR3_DQS_P),                      //                .mem_dqs
        .memory_mem_dqs_n                      ( HPS_DDR3_DQS_N),                      //                .mem_dqs_n
        .memory_mem_odt                        ( HPS_DDR3_ODT),                        //                .mem_odt
        .memory_mem_dm                         ( HPS_DDR3_DM),                         //                .mem_dm
        .memory_oct_rzqin                      ( HPS_DDR3_RZQ),                        //                .oct_rzqin
 
		  .hps_0_h2f_reset_reset_n               ( hps_fpga_reset_n ),                //                hps_0_h2f_reset.reset_n
    );


reg [25:0] counter; 
reg  led_level;
always @(posedge fpga_clk_50 or negedge hps_fpga_reset_n)
begin
if(~hps_fpga_reset_n)
begin
                counter<=0;
                led_level<=0;
end

else if(counter==24999999)
        begin
                counter<=0;
                led_level<=~led_level;
        end
else
                counter<=counter+1'b1;
end

assign LEDR[0]=led_level;
endmodule

  