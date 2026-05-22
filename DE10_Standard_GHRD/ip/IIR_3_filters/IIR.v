module IIR 
(
	/******* clock input *******/
	input CLOCK_50,
	
	/****** Switches ******/
	input [2:0] SW,
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
	inout 	I2C_SDAT
	// General purpose signals
	
	
);

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
	wire [15:0] data_in_R, data_in_mux, data_in_peq, data_in_lshv, data_in_hshv;
	wire [15:0] data_in_cascode, data_in_peq_2, data_in_lshv_2, data_in_hshv_2;
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
	
/****************** IIR filters ******************/
//	simple_IIR_biquad_DF1 s_iir_r
//	(
//		.clk(clk_data_48k),
//		.din(adcROUT_SIG),
//		.dout(data_in_lshv)
//	);

	iir_peq2nd peq_1
	(
		.clk(clk_data_48k),
		.din(adcROUT_SIG),
		.dout(data_in_peq)
 	);
	
	iir_lshv2nd low_1
	(
		.clk(clk_data_48k),
		.din(adcROUT_SIG),
		.dout(data_in_lshv)
 	);
	
	iir_hshv2nd high_1
	(
		.clk(clk_data_48k),
		.din(adcROUT_SIG),
		.dout(data_in_hshv)
 	);
	
/****************** IIR CASCODE ******************/

	iir_peq2nd peq_2
	(
		.clk(clk_data_48k),
		.din(adcROUT_SIG),
		.dout(data_in_peq_2)
 	);
	
	iir_lshv2nd low_2
	(
		.clk(clk_data_48k),
		.din(data_in_peq_2),
		.dout(data_in_lshv_2)
 	);
	
	iir_hshv2nd high_2
	(
		.clk(clk_data_48k),
		.din(data_in_lshv_2),
		.dout(data_in_hshv_2)
 	);
	
	
	// send out the clocks
	assign I2C_SCLK = SCL_SIG;
	assign AUD_BCLK = ~clk_12;
	assign AUD_XCK  = ~clk_12;

	assign AUD_ADCLRCK = adcLRC;
	assign AUD_DACLRCK = dacLRC;
	assign AUD_DACDAT = rst_50 ? 0 : dacDat;
	
/****************** Debounce ******************/	
	
	wire SW0_debounced;
	pin_debounce #(.LENGTH(1000)) SW0_debounce (
		.clk(clk_50), .rst(rst),
		.sig_in(SW[0]), .sig_out(SW0_debounced) );


//  /*******************************/
	
	
	wire SW1_debounced;
	pin_debounce #(.LENGTH(1000)) SW1_debounce (
		.clk(clk_50), .rst(rst),
		.sig_in(SW[1]), .sig_out(SW1_debounced) );


//  /*******************************/	
	
	wire SW2_debounced;
	pin_debounce #(.LENGTH(1000)) SW2_debounce (
		.clk(clk_50), .rst(rst),
		.sig_in(SW[2]), .sig_out(SW2_debounced) );


//  /*******************************/

	
	/****************** MUX ******************/	
	
	mux41 (
	.A(adcROUT_SIG),
	.B(data_in_peq),
	.C(data_in_lshv),
	.D(data_in_hshv),
	.S({SW2_debounced, SW1_debounced}),
	.F(data_in_mux)
	);
	
	mux2_1 (
	.A(data_in_mux),
	.B(data_in_hshv_2),
	.S(SW0_debounced),
	.F(data_in_R)
	);
	
	
	/****************** blink confirmation ******************/
	
	blink blk1(
	.clk(clk_12),
	.led(LEDR[4])
	);

	blink blk2(
	.clk(clk_50),
	.led(LEDR[3])
	);
	
	assign LEDR[1] = SW1_debounced;
	assign LEDR[2] = SW2_debounced;
	assign LEDR[0] = SW0_debounced;

endmodule 