-- ============================================================
-- fir_reconfig_top.vhd
-- Top simples em VHDL:
-- HPS bridge -> simple_cmd_storage_fir1 -> 1 feedsecondary_fir
--
-- Use este arquivo como TOP_LEVEL_ENTITY no Quartus.
-- Adicione tambem no projeto:
--   - simple_cmd_storage_fir1.vhd
--   - feedsecondary_fir.vhd
--   - package TYPES com data_width=16 e coeff_width=16
--   - IP/modulo ram usado pelo feedsecondary_fir
--
-- LEDR(0) acende quando os coeficientes terminaram de carregar.
-- LEDR(1) pisca/pulsa quando sai resultado valido do FIR.
-- LEDR(9 downto 2) ficam apagados.
-- ============================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.TYPES.ALL;

entity fir_reconfig_top is
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;

    -- Registradores vindos da HPS-to-FPGA bridge
    in_a : in std_logic_vector(63 downto 0);
    in_b : in std_logic_vector(63 downto 0);

    -- Registradores lidos pelo HPS
    out_export : out std_logic_vector(63 downto 0);
    out_data   : out std_logic_vector(63 downto 0);

    -- LEDs de debug
    -- LEDR(0) = coeficientes carregados
    -- LEDR(1) = pulso de resultado valido
    -- LEDR(9 downto 2) = 0
    LEDR : out std_logic_vector(2 downto 0)
  );
end entity fir_reconfig_top;

architecture rtl of fir_reconfig_top is

	component blink is 
	port(
		clk              : in  std_logic;
		 led          : out  std_logic
	);
	end component;

	component simple_cmd_storage_fir1 is
	  generic (
		 DATA_WIDTH  : integer := data_width;
		 COEFF_WIDTH : integer := coeff_width
	  );
	  port (
		 clk              : in  std_logic;
		 reset_n          : in  std_logic;

		 in_a             : in  std_logic_vector(63 downto 0);
		 in_b             : in  std_logic_vector(63 downto 0);

		 out_export       : out std_logic_vector(63 downto 0);
		 out_data         : out std_logic_vector(63 downto 0);

		 fir_data_in      : out signed(data_width-1 downto 0);
		 fir_coeff_in     : out std_logic_vector(4*coeff_width-1 downto 0);
		 fir_en           : out std_logic;
		 fir_mode         : out std_logic;

		 fir_ready        : in  std_logic;
		 fir_coeff_ok     : in  std_logic;
		 fir_coeff_count  : in  std_logic_vector(11 downto 0);
		 fir_data_out     : in  signed(data_width-1 downto 0);
		 fir_valid_out    : in  std_logic
	  );
	end component;

  signal reset : std_logic;

  -- Interface simple_cmd_storage -> FIR
  signal fir_data_in  : signed(data_width-1 downto 0);
  signal fir_coeff_in : std_logic_vector(4*coeff_width-1 downto 0);
  signal fir_en       : std_logic;
  signal fir_mode     : std_logic;

  -- Interface FIR -> simple_cmd_storage
  signal fir_data_out    : signed(data_width-1 downto 0);
  signal fir_valid_out   : std_logic;
  signal fir_busy        : std_logic;
  signal fir_ready       : std_logic;
  signal fir_coeff_ok    : std_logic;
  signal fir_coeff_count : std_logic_vector(11 downto 0);

begin

  -- reset_n externo ativo em 0; FIR usa reset ativo em 1.
  reset <= not reset_n;

  -- No feedsecondary_fir enviado, busy = '0' significa pronto.
  fir_ready <= not fir_busy;

  -- LEDs de debug
  LEDR(0) <= fir_coeff_ok;
  LEDR(1) <= fir_valid_out;

	u_cmd : simple_cmd_storage_fir1
	  generic map (
		 DATA_WIDTH  => data_width,
		 COEFF_WIDTH => coeff_width
	  )
	  port map (
		 clk             => clk,
		 reset_n         => reset_n,

		 in_a            => in_a,
		 in_b            => in_b,

		 out_export      => out_export,
		 out_data        => out_data,

		 fir_data_in     => fir_data_in,
		 fir_coeff_in    => fir_coeff_in,
		 fir_en          => fir_en,
		 fir_mode        => fir_mode,

		 fir_ready       => fir_ready,
		 fir_coeff_ok    => fir_coeff_ok,
		 fir_coeff_count => fir_coeff_count,
		 fir_data_out    => fir_data_out,
		 fir_valid_out   => fir_valid_out
  );

  u_fir : entity work.feedsecondary_fir
    generic map (
      FIR_TAPS => taps
    )
    port map (
      clock       => clk,
      reset       => reset,
      data_in     => fir_data_in,
      coeff_in    => fir_coeff_in,
      en          => fir_en,
      mode        => fir_mode,
      data_out    => fir_data_out,
      valid_out   => fir_valid_out,
      busy        => fir_busy,
      coeff_ok    => fir_coeff_ok,
      coeff_count => fir_coeff_count
    );
	 
	 blk : blink
		port map (
		clk       => clk,
      led       => LEDR(2)
		);

end architecture rtl;
