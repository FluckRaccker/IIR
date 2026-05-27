-- LINSE - UFSC property
-- A code wrote by Edson Manoel da Silva. Electronic Engineering, UFSC - Brasil
-- This module is for controlling the codec via i2c
-- References:  
-- 1.  Audio codec datasheet  


LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
--USE IEEE.STD_LOGIC_SIGNED.ALL;
USE ieee.std_logic_arith.ALL;



ENTITY audio_codec_controller IS 
PORT
	(
		RESET 		 : IN  STD_LOGIC;
		CLOCK		 : IN  STD_LOGIC;
		i2cClock20KHz: IN  STD_LOGIC;
		SCL   		 : OUT STD_LOGIC;
		SDA   		 : INOUT STD_LOGIC;
		dacLIN		 : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		dacRIN		 : IN STD_LOGIC_VECTOR(15 DOWNTO 0);
		adcLOUT		 : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		adcROUT		 : OUT STD_LOGIC_VECTOR(15 DOWNTO 0);
		adcData 	 : IN  STD_LOGIC;
		dacData 	 : OUT STD_LOGIC;
		RL_DATA_OUT_VALID	: OUT STD_LOGIC;
		audioClock 	 : IN  STD_LOGIC; 
		adcLRSelect  : OUT STD_LOGIC;
		dacLRSelect  : OUT STD_LOGIC;
		dacLRSelect_ACK		: OUT STD_LOGIC

	);
END ENTITY;

ARCHITECTURE funcionamento OF audio_codec_controller IS



----------------------------------------- Component Declarations ---------------------------------------

COMPONENT I2C_Controller
	PORT
	(
		CLOCK		:	 IN STD_LOGIC;
		I2C_SCLK	:	 OUT STD_LOGIC;
		I2C_SDAT	:	 INOUT STD_LOGIC;
		I2C_DATA	:	 IN STD_LOGIC_VECTOR(23 DOWNTO 0);
		RESET		:	 IN STD_LOGIC;
		GO			:	 IN STD_LOGIC;
		ENDS		:	 OUT STD_LOGIC;
		W_R			:	 IN STD_LOGIC;
		ACK			:	 OUT STD_LOGIC;
		SD_COUNTER	:	 OUT STD_LOGIC_VECTOR(5 DOWNTO 0);
		SDO			:	 OUT STD_LOGIC
	);
END COMPONENT;


COMPONENT delayCounter
	PORT
	(
		reset		:	 IN STD_LOGIC;
		clock		:	 IN STD_LOGIC;
		resetAdc	:	 OUT STD_LOGIC
	);
END COMPONENT;

---------------------------------------------------------------------------------------------------------
	TYPE LEFT_MODE_TYPE IS (right_channel, left_channel);
	SIGNAL LEFT_MODE_SM		: LEFT_MODE_TYPE;
	
	TYPE states IS (resetState,transmit,checkAcknowledge,turnOffi2cControl,incrementMuxSelectBits,stop);
	SIGNAL currentState,nextState : states;
	
	SIGNAL cont2			: STD_LOGIC_VECTOR(23 DOWNTO 0);
	SIGNAL R_DATA_IN_temp	: STD_LOGIC_VECTOR(15 DOWNTO 0);
	SIGNAL AUDIO_buffer_in	: STD_LOGIC_VECTOR(15 DOWNTO 0);
	SIGNAL AUDIO_buffer_out	: STD_LOGIC_VECTOR(15 DOWNTO 0);


	SIGNAL i2cControllerData  : STD_LOGIC_VECTOR(23 DOWNTO 0);
	SIGNAL i2cRun,done,ACK    : STD_LOGIC;	
	SIGNAL muxSelect 		  : INTEGER RANGE 0 TO 15;
	SIGNAL incrementMuxSelect : STD_LOGIC := '0';
	SIGNAL i2cData 			  : STD_LOGIC_VECTOR(15 DOWNTO 0) := X"001B";
	signal resetAdcDac : std_logic := '0';
	

---------------------------------------------------------------------------------------------------	


	
BEGIN


--------------------------------------------------------------------------------------------------
-- instantiate i2c controller
i2cController : I2C_Controller 
	PORT MAP 
		(
			i2cClock20KHz,
			SCL,
			SDA,
			i2cControllerData,
			RESET,
			i2cRun,
			done,
			'0',
			ACK,
			open,
			open
		);
		
		
adcDacControllerStartDelay : delayCounter 
	PORT MAP 
		(
			RESET,
			CLOCK,
			resetAdcDac
		);

--------------------------------------------------------------------------------------------------

	
		-- mini FSM to send out right data to audio codec via i2c
		PROCESS(i2cClock20KHz)
		BEGIN
			IF (i2cClock20KHz'EVENT AND i2cClock20Khz = '1') THEN
				currentState <= nextState;
			END IF;
		END PROCESS;
				
		PROCESS(currentState,reset,muxSelect,done,ACK)
		BEGIN
			CASE currentState IS
				WHEN resetState =>										
					IF (reset = '1') THEN
						nextState <= resetState;
					ELSE
						nextState <= transmit;
					END IF;
					incrementMuxSelect <= '0';
					i2cRun <= '0';
					 
				WHEN transmit =>
					IF (muxSelect > 10) THEN					
						i2cRun <= '0';
						nextState <= stop;	
					ELSE
						i2cRun <= '1';
						nextState <= checkAcknowledge;
					END IF;		
					incrementMuxSelect <= '0';
					 
				WHEN checkAcknowledge =>					
					IF (done = '1') THEN
						IF (ACK = '0') THEN -- all the ACKs from codec need to be low (i2c Bus specification)
							i2cRun <= '0';
							nextState <= turnOffi2cControl;
						ELSE
							i2cRun <= '0';
							nextState <= transmit;
						END IF;
					ELSE					
						nextState <= checkAcknowledge;
					END IF;					
					i2cRun <= '1';
					incrementMuxSelect <= '0';
					
				WHEN turnOffi2cControl =>
					incrementMuxSelect <= '0';
					nextState <= incrementMuxSelectBits; 
					i2cRun <= '0';
 
				WHEN incrementMuxSelectBits =>
						incrementMuxSelect <= '1';
						nextState <= transmit; 
						i2cRun <= '0';
					
				WHEN stop =>
					nextState <= stop; 
					i2cRun <= '0';
					incrementMuxSelect <= '0';	
					
				WHEN OTHERS =>
					nextState <= resetState;
 
			END CASE;
		END PROCESS;
		
		PROCESS(incrementMuxSelect,reset)
		BEGIN
			IF (reset = '1') THEN
				muxSelect <= 0;
			ELSE
				IF (incrementMuxSelect'EVENT AND incrementMuxSelect='1') THEN
					muxSelect <= muxSelect + 1;
				END IF;				
			END IF;
		END PROCESS;
		
		-- 0x1A is the base address of your device
		-- Refer to page 43 of the audio codec datasheet and the schematic
		-- on p. 38 of DE1 User's manual.  CSB is tied to ground so the 8-bit base address is
		-- b00110100 = 0x1A(0011010) and 0 bit write comand.  		
		i2cControllerData <= "00110100"&i2cData; 		
		-- data to be sent to audio code obtained via a MUX
		-- the select bits for the MUX are obtained by the mini FSM above

		WITH muxSelect SELECT
			i2cData <= 
				-- IMPORTANTE, Descriçao dos bits nos comentários: 1(msb) -> 9(lsb)
				"0001111" & "000000000" WHEN 0, -- reset
				-- Left Line input channel volume control --
				
				"0000000" & "010011111" WHEN 1,  -- --"0000000" & "010011111" WHEN 1,  --Mudanca feita por M.A --"0000000" & "000011111" mutar left 
				-- 010010111 : Default - Mute e 0dB
				-- Volume � dado pelos �ltimos 5 bits
				---- 11111 : 12 dB
				---- 11101 : 9 dB
				---- 11011 : 6 dB
				---- 10111 : 0 dB
				---- 00000 : -34.5 dB
				---- Varia em escala de 1.5 dB
				-- Primeiro bit: Volume/Mute Simult�neo dos dois canais 
				-- Segundo bit: Mute - 0 = Normal; 1 = Muted -> Line Mute
				--------------------------------------------  
				-- Right Line input channel volume control --
				"0000001" & "000011111" WHEN 2,
				-- 010010111 : Default - Mute e 0 dB
				-- Volume � dado pelos �ltimos 5 bits
				---- 11111 : 12 dB
				---- 11101 : 9 dB
				---- 11011 : 6 dB
				---- 10111 : 0 dB
				---- 00000 : -34.5 dB
				---- Varia em escala de 1.5 dB
				-- Primeiro bit: Volume/Mute Simult�neo dos dois canais
				-- Segundo bit: Mute - 0 = Normal; 1 = Muted -> Line Mute
				---------------------------------------------  
				-- Left Channel Headphone Volume Control --
--				"0000010" & "011011101" WHEN 3,
				"0000010" & "011111001" WHEN 3,
				-- 011111001 : Default - Zero-cross e 0 dB
				-- Volume � dado pelos �ltimos 7 bits
				---- 1111111 : 6 dB
				---- 1111001 : 0 dB
				---- 0110000 : -73 dB (Mute)
				---- Varia em escala de 1 dB
				---- Valores abaixo de -73 dB -> Mute.
				-- Primeiro bit: LR Headphone channel simultaneous Volume/Mute - 0 = Off; 1 = On.
				-- Segundo bit: Left-channel zero-cross detect - 0 = Off; 1 = On.
				------------------------------------------- 
				-- Right Channel Headphone Volume Control --
--				"0000011" & "011011101" WHEN 4,
				"0000011" & "011111001" WHEN 4,
				-- 011111001 : Default - Zero-cross e 0 dB
				-- Volume � dado pelos �ltimos 7 bits
				---- 1111111 : 6 dB
				---- 1111001 : 0 dB
				---- 0110000 : -73 dB (Mute)
				---- Varia em escala de 1 dB
				---- Valores abaixo de -73 dB -> Mute.
				-- Primeiro bit: LR Headphone channel simultaneous Volume/Mute - 0 = Off; 1 = On.
				-- Segundo bit: Right-channel zero-cross detect - 0 = Off; 1 = On.
				-------------------------------------------- 
				-- Analog Audio Path Control --
--				"0000100" & "000011010" WHEN 5, -- Bypass enabled
				"0000100" & "000010010" WHEN 5,
				-- 000001010 : Default
				-- Quatro primeiros bits: Added Sidetone
				---- 1XX1 : 0 dB
				---- 0001 : -6 dB
				---- 0011 : -9 dB
				---- 0101 : -12 dB
				---- 0111 : -18 dB
				---- XXX0 : Disabled
				-- Quinto bit: DAC Select - 0 = DAC Off; 1 = DAC Selected.
				-- Sexto bit: Bypass - 0 Disabled; 1 Enabled.
				-- S�timo bit: Input Select for ADC - 0 = Line; 1 = Microphone.
				-- Oitavo bit: Microphone Mute - 0 Normal; 1 Muted.
				-- Nono bit: Microphone Boost - 0 = 0 dB; 1 = 20 dB.
				-------------------------------  
				-- Digital Audio Path Control --
				"0000101" & "000000001" WHEN 6,
--				"0000101" & "000000111" WHEN 6,
				-- 000000000 : Default 
				-- Sexto bit: DAC Soft Mute - 0 = Disabled; 1 = Enabled.
				-- S�timo e oitavo bits: De-emphasis Control
				---- 00 : Disabled
				---- 01 : 32 kHz
				---- 10 : 44.1 kHz
				---- 11 : 48 kHz
				-- Nono bit: ADC High-Pass filter: 0 = Enabled; 1 = Disabled.
				--------------------------------  -- deemphasis to 48 KHz, enable high pass filter on ADC
				-- Power Down Control --110 000000000
				"0000110" & "000000010" WHEN 7,
				-- 000000111 - Default
				-- Segundo bit: Device Power	- 0 = On; 1 = Off.
				-- Terceiro bit: Clock			- 0 = On; 1 = OFF.
				-- Quarto bit: Oscillator		- 0 = On; 1 = OFF.
				-- Quinto bit: Outputs			- 0 = On; 1 = OFF.
				-- Sexto bit: DAC				- 0 = On; 1 = OFF.
				-- S�timo bit: ADC				- 0 = On; 1 = OFF.
				-- Oitavo bit: Microphone Input	- 0 = On; 1 = OFF.
				-- Nono bit: Line Input			- 0 = On; 1 = OFF.
				------------------------  
				-- Digital Audio Interface Format --
				"0000111" & "000000001" WHEN 8,
				-- 000000001 - Default
				-- Terceiro bit: Master/Slave Mode - 0 = Slave; 1 = Master.
				-- Quarto bit: DAC Left/Right Swap - 0 = Disabled; 1 = Enabled.
				-- Quinto bit: DAC Left/Right Phase
				---- 0 = Right channel on, LRCIN high
				---- 1 = Right channel on, LRCIN low
				---- DSP mode
				---- 1 = MSB is available on 2nd BCLK rising edge after LRCIN rising edge
				---- 0 = MSB is available on 1st BCLK rising edge after LRCIN rising edge
				-- Sexto e S�timo bits: Input bit lenght
				---- 00 : 16 bits
				---- 01 : 20 bits
				---- 10 : 24 bits
				---- 11 : 32 bits
				-- Oitavo e Nono bits: Data Format
				---- 00 : MSB first, right aligned
				---- 01 : MSB first, left aligned
				---- 10 : I2S format, MSB first, left � 1 aligned
				---- 11 : DSP format, frame sync followed by two data words
				------------------------------------  
				-- Sample Rate Control --
				"0001000" & "000000000" WHEN 9,
				-- "0001000" & "000000001" WHEN 9,
				-- 000100000 - Default
				-- Segundo bit: Clock output divider - 0 = MCLK; 1 = MCLK/2.
				-- Terceiro bit: Clock input divider - 0 = MCLK; 1 = MCLK/2.
				-- Quarto a S�timo bits: Sampling rate control
				----
				-- Oitavo bit: Base oversampling rate
				---- Normal MODE:
				---- 0 : 256 fs
				---- 1 : 384 fs
				---- USB MODE:
				---- 0 : 250 fs
				---- 1 : 272 fs
				-- Nono bit: Clock mode select - 0 = Normal; 1 = USB.
				-------------------------  
				-- Digital Interface Activation 
				"0001001" & "000000001" WHEN 10, 
				-- 000000000 - Default
				-- Nono bit: Activate interface - 0 = Inactive; 1 = Active.
				---------------------------------- -- activate
				X"ABCD" WHEN OTHERS; -- should never occur
				
				
				

	--entrada de dados fornecidos pelo ADC
	PROCESS(resetAdcDac, audioClock)
	BEGIN
		IF resetAdcDac = '0' THEN
			AUDIO_buffer_out<= (others => '0');
			adcROUT			<= (others => '0');
			adcLOUT			<= (others => '0');
			
		ELSIF FALLING_EDGE(audioClock) THEN
			CASE LEFT_MODE_SM IS
				WHEN right_channel =>
					IF cont2 <= 16 THEN -- Armazena os 16 primeiro bits, fornecidos pelo AD, durante a leitura do canal direito
						AUDIO_buffer_out 	<= AUDIO_buffer_out(14 DOWNTO 0) & adcData; 
						adcROUT				<= AUDIO_buffer_out(14 DOWNTO 0) & adcData;
					END IF;
					
				WHEN left_channel =>
					IF cont2 <= 16 THEN -- Armazena os 16 primeiro bits, fornecidos pelo AD, durante a leitura do canal esquerdo
						AUDIO_buffer_out	<= AUDIO_buffer_out(14 DOWNTO 0) & adcData;
						adcLOUT				<= AUDIO_buffer_out(14 DOWNTO 0) & adcData;
					END IF;
					
			END CASE;
		END IF;
	END PROCESS;
	
	--saida de dados para o DAC
	PROCESS(resetAdcDac, audioClock)
	BEGIN
		IF resetAdcDac = '0' THEN
			LEFT_MODE_SM	<= right_channel;
			cont2			<= (others => '0');
			adcLRSelect		<= '0';
			dacLRSelect		<= '0';
			dacData			<= '0';
			AUDIO_buffer_in	<= (others => '0');
			R_DATA_IN_temp	<= (others => '0');
			dacLRSelect_ACK	<= '0';
			
		ELSIF RISING_EDGE(audioClock) THEN
			CASE LEFT_MODE_SM IS
				WHEN right_channel =>
					adcLRSelect					<= '0';
					dacLRSelect					<= '0';
					dacData						<= AUDIO_buffer_in(15);
					
					IF cont2 >= 127 THEN	-- 48 kHz ([12MHz/2(canais)*fs]-1)
					-- IF cont2 >= 124 THEN	-- 48 kHz ([12MHz/2(canais)*fs]-1)
						cont2 				<= (others => '0');
						LEFT_MODE_SM		<= left_channel;
						AUDIO_buffer_in		<= dacLIN;
						R_DATA_IN_temp		<= dacRIN;
						dacLRSelect_ACK		<= '0';
					ELSE
						cont2 <= cont2 + 1; -- divide o MCLK na frequência em que os conversores foram configurados para trabalhar
						AUDIO_buffer_in(15 downto 1) 	<= AUDIO_buffer_in(14 downto 0);
						AUDIO_buffer_in(0)				<= '0';
					END IF;
					
					
				WHEN left_channel =>
					adcLRSelect				<= '1';
					dacLRSelect				<= '1';
					dacData					<= AUDIO_buffer_in(15);
					dacLRSelect_ACK			<= '1';
					
					IF cont2 >= 127 THEN	-- 48 kHz ([12MHz/2(canais)*fs]-1)
					-- IF cont2 >= 124 THEN	-- 48 kHz ([12MHz/2(canais)*fs]-1)
						cont2 				<= (others => '0');
						LEFT_MODE_SM		<= right_channel;
						AUDIO_buffer_in		<= R_DATA_IN_temp;
					ELSE
						cont2 <= cont2 + 1;
						AUDIO_buffer_in(15 downto 1)	<= AUDIO_buffer_in(14 downto 0);
						AUDIO_buffer_in(0)				<= '0';
					END IF;
			END CASE;
		END IF;
	END PROCESS;


	PROCESS(resetAdcDac, audioClock)
	BEGIN
		IF resetAdcDac = '0' THEN
			RL_DATA_OUT_VALID	<= '0';
			
		ELSIF RISING_EDGE(audioClock) THEN
			IF cont2 = 16 AND LEFT_MODE_SM = right_channel THEN
				RL_DATA_OUT_VALID	<= '1'; -- sinal com frequência de 48Khz (pode ser usado como referência da frequência de amostragem)
			ELSE
				RL_DATA_OUT_VALID	<= '0';
			END IF;
		END IF;
	END PROCESS;


END ARCHITECTURE;