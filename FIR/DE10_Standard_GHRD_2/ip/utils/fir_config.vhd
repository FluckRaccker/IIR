library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.MATH_REAL.ALL;

package TYPES is

  constant taps         : integer := 300;                                                         -- number of FIR coefficients
  constant coeff_width  : integer := 16;                                                          -- width of each FIR coefficient
  constant data_width   : integer := 16;                                                          -- width of input/output data
  constant result_width : integer := data_width + coeff_width + integer(ceil(log2(real(taps)))); -- width of FIR filter result
  
  type coeff_array   is array (0 to taps-1) of std_logic_vector(coeff_width-1 downto 0);         -- array of FIR coefficients
  type data_array    is array (0 to taps-1) of signed(data_width-1 downto 0);                    -- array of data
  type product_array is array (0 to taps-1) of signed((data_width + coeff_width)-1 downto 0);    -- array of (coefficient * data) products
  
end package TYPES;