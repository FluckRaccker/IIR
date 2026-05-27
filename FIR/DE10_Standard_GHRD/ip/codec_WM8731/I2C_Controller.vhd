-- Major Functions:i2c controller
-- Edson Manoel da Silva

LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.STD_LOGIC_UNSIGNED.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY I2C_Controller IS
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
		--TEST
			SD_COUNTER 	: OUT STD_LOGIC_VECTOR(5 DOWNTO 0) ;
			SDO		   	: OUT STD_LOGIC		
		);
END ENTITY;


ARCHITECTURE FUNCIONAMENTO OF I2C_Controller IS

SIGNAL SDO_REG	  : STD_LOGIC;
SIGNAL SCLK		  : STD_LOGIC;
SIGNAL ENDS_REG	  : STD_LOGIC;
SIGNAL SD  		  : STD_LOGIC_VECTOR(23 DOWNTO 0);
SIGNAL SD_COUNTER_REG : STD_LOGIC_VECTOR(5 DOWNTO 0);
SIGNAL ACK1,ACK2,ACK3 : STD_LOGIC;
SIGNAL DELAY : STD_LOGIC_VECTOR(5 DOWNTO 0);





BEGIN
	SDO  <= SDO_REG;
	ENDS <= ENDS_REG;
	SD_COUNTER <= SD_COUNTER_REG;
	ACK <= ACK1 OR ACK2 OR ACK3; --WIRE ACK=ACK1 | ACK2 |ACK3;

--I2C COUNTER
PROCESS(RESET,CLOCK)
BEGIN

	
	IF((SD_COUNTER_REG >= "000100") AND (SD_COUNTER_REG <= "011110")) THEN 
		I2C_SCLK <= NOT(CLOCK); -- See i2c bus specification. The SCL need to be low while SDA changes its value
	ELSE
		I2C_SCLK <= SCLK;
	END IF;
	
	IF (SDO_REG = '1') THEN 
		I2C_SDAT <= '1';
	ELSE
		I2C_SDAT <= '0';
	END IF;
	
	IF (RESET='1') THEN
		SD_COUNTER_REG <= "000000";
		DELAY <= (OTHERS => '0');
	ELSIF(CLOCK'EVENT AND CLOCK = '1') THEN
		IF (GO = '0') THEN 
			SD_COUNTER_REG <= (OTHERS => '0');
		ELSIF(SD_COUNTER_REG < "111111") THEN
--			IF ((DELAY < 5) AND (SD_COUNTER_REG = "000001")) THEN
--				DELAY <= DELAY + '1';
--			ELSE	
--				DELAY <= (OTHERS => '0');
				SD_COUNTER_REG <= SD_COUNTER_REG + '1';
--			END IF;
		END IF;
	END IF;
END PROCESS;
----

PROCESS(RESET,CLOCK)
BEGIN
	IF (RESET = '1') THEN
		SCLK <= '1';
		SDO_REG  <= '1'; 
		ACK1 <= '1';
		ACK2 <= '1';
		ACK3 <= '1'; 
		ENDS_REG <= '0';
		SD <= I2C_DATA;
	ELSIF(CLOCK'EVENT AND CLOCK = '1') THEN
		CASE (SD_COUNTER_REG) IS
			WHEN "000000" => 
				ACK1 <= '1';
				ACK2 <= '1';
				ACK3 <= '1';
				ENDS_REG <= '0';
				SDO_REG  <= '1';
				SCLK <= '1';
				
				--start
			WHEN "000001" =>
				SD   	<= I2C_DATA;
				SCLK 	<= '1';
				SDO_REG <= '0';	
					
			WHEN "000010" =>
				SDO_REG <= '0';	
				SCLK <= '0';
				
				--SLAVE ADDR
			WHEN "000011" =>
				SDO_REG <= SD(23);
			WHEN "000100" =>
			    SDO_REG <= SD(22);
			WHEN "000101" =>
				SDO_REG <= SD(21);
			WHEN "000110" =>
				SDO_REG <= SD(20);
			WHEN "000111" =>
				SDO_REG <= SD(19);
			WHEN "001000" =>
				SDO_REG <= SD(18);
			WHEN "001001" =>
				SDO_REG <= SD(17);
			WHEN "001010" =>
				SDO_REG <= SD(16);	
			WHEN "001011" =>
				ACK1    <= I2C_SDAT; 
			
			--SUB ADDR
			WHEN "001100" =>
				SDO_REG <= SD(15);
			WHEN "001101" =>
				SDO_REG <= SD(14);
			WHEN "001110" => 
				SDO_REG <= SD(13);
			WHEN "001111" =>
				SDO_REG <= SD(12);
			WHEN "010000" =>
				SDO_REG <= SD(11);
			WHEN "010001" =>
				SDO_REG <= SD(10);
			WHEN "010010" =>
				SDO_REG <= SD(9);
			WHEN "010011" =>
				SDO_REG <= SD(8);
			WHEN "010100" =>
				ACK2	<= I2C_SDAT; 
				
			--//DATA
			WHEN "010101" =>
				SDO_REG <= SD(7); 
			WHEN "010110" =>
				SDO_REG <= SD(6);
			WHEN "010111" =>
				SDO_REG <= SD(5);
			WHEN "011000" =>
				SDO_REG <= SD(4);
			WHEN "011001" =>
				SDO_REG <= SD(3);
			WHEN "011010" =>
				SDO_REG <= SD(2);
			WHEN "011011" =>
				SDO_REG <= SD(1);
			WHEN "011100" =>
				SDO_REG <= SD(0);
			WHEN "011101" =>
				ACK3	 <= I2C_SDAT;
			
			--//stop
			WHEN "011110" =>
				SDO_REG  <= '0';
			WHEN "011111" => 
				SCLK	 <= '1'; 
			WHEN "100000" =>
				SDO_REG  <= '1'; 
				ENDS_REG <= '1'; 
			WHEN OTHERS => 
				ACK1 <= '0';
				ACK2 <= '0';
				ACK3 <= '0'; 
				ENDS_REG <= '1';
				SCLK	 <= '1';
		END CASE;
	END IF;
END PROCESS;

END ARCHITECTURE;