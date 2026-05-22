module IIR 
(
	/******* clock input *******/
	input CLOCK_50,
	
	/****** LEDs *******/
	output [4:0] LEDR,

	/******** Audio-Port WM8731LS ********/
	input 	AUD_ADCDAT,
	inout 	AUD_ADCLRCK,
	inout 	AUD_BCLK,	
	output 	AUD_DACDAT,	
	inout 	AUD_DACLRCK,
	output 	AUD_XCK,	

	/******* I2C for Audio Tv-Decoder *******/
	output 	I2C_SCLK,
	inout 	I2C_SDAT,
	// General purpose signals
	
	input  reset,
	input  [63:0] in_a,
	input  [63:0] in_b,
	output [63:0] out_export
	
	
);


	// send out the clocks
	assign I2C_SCLK = SCL_SIG;
	assign AUD_BCLK = ~clk_12;
	assign AUD_XCK  = ~clk_12;

	assign AUD_ADCLRCK = adcLRC;
	assign AUD_DACLRCK = dacLRC;
	assign AUD_DACDAT = rst_50 ? 0 : dacDat;
	
	


	wire clk_50 = CLOCK_50;
	
	
	/******** initial reset ********/
	wire rst_initial_50;
	reset_init_blk reset_init_blk_50
	(
		.clk(clk_50),
		
		.rst_out(rst_initial_50)
	);
	
	wire rst_50 = rst_initial_50;
	wire rst = rst_50;
	/*******************************/
	
	wire clk_12;
	PLL12M288 PLL50to12288MHz (
		.refclk(clk_50),
		.outclk_0(clk_12),
		.locked()
	);

	

	wire clk_20k;			
	clock_divisor #(
		.LOG_MIN(13),
		.RATE_DIVISOR(2500)) clock_divisor_20k
	(
		.clk_in(clk_50),
		.rst(rst_50),		
		.clk_out(clk_20k)
	);
	
	
	wire clk_48k;			
	clock_divisor #(
		.LOG_MIN(12),
		.RATE_DIVISOR(1040)) clock_divisor_48k
	(
		.clk_in(clk_50),
		.rst(rst_50),		
		.clk_out(clk_48k)
	);
	/**************************/
	

	

	/****************** Audio CODEC Controller - 48kHz - 16-bit - Stereo ******************/
	wire adcDat = rst_50 ? 0 : AUD_ADCDAT;
	wire dacDat;
	
	wire [15:0] adcLOUT_SIG, adcROUT_SIG;
	
	wire [15:0] data_in_L;
	wire [15:0] data_in_R;
	wire adcLRC, dacLRC, SCL_SIG;
	
	wire clk_data_48k;
	audio_codec_controller audio_codec_controller	
	(
		.RESET(rst_50),			
		.CLOCK(clk_50),			
		
		.i2cClock20KHz(clk_20k),
		.SCL(SCL_SIG),				
		.SDA(I2C_SDAT),				
		
//		// write to codec
		.dacLIN(data_in_R),			
		.dacRIN(data_in_R),

		// write to codec
//		.dacLIN(16'd0),			
//		.dacRIN(16'd0),				

		// read from codec
		.adcLOUT(adcLOUT_SIG),		
		.adcROUT(adcROUT_SIG),		
		
		.adcData(adcDat),				
		.dacData(dacDat),				
		
		.RL_DATA_OUT_VALID(clk_data_48k),	
		
		.audioClock(clk_12),			
		
		.adcLRSelect(adcLRC),		
		.dacLRSelect(dacLRC),		
		
		.dacLRSelect_ACK()

	);
	
/****************** IIR biquad - low pass filter ******************/

	wire signed [15:0] coeff0, coeff1, coeff2, coeff3, coeff4;

	simple_IIR_biquad_DF1 s_iir_r
	(
		.clk(clk_data_48k),
		.din(adcROUT_SIG),
		.a1_fixed(coeff0),
		.a2_fixed(coeff1),
		.b0_fixed(coeff2),
		.b1_fixed(coeff3),
		.b2_fixed(coeff4),
		.dout(data_in_R)
	);
	
/****************** Storage ******************/

simple_cmd_storage uut(
	.clk(clk_50),
	.reset(reset),
	.in_a(in_a),
	.in_b(in_b),
	.out_export(out_export),
	.led(LEDR[4:2]),
	.coeff0(coeff0),
	.coeff1(coeff1),
	.coeff2(coeff2),
	.coeff3(coeff3),
	.coeff4(coeff4)
);

	

	
/****************** blink confirmation ******************/
	
	blink blk1(
	.clk(clk_12),
	.led(LEDR[0])
	);
	
	blink blk2(
	.clk(clk_50),
	.led(LEDR[1])
	);

endmodule 