library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.TYPES.ALL;

entity fir_reconfig_top is
  port (
    clk     : in  std_logic;
    reset_n : in  std_logic;

    in_a : in std_logic_vector(63 downto 0);
    in_b : in std_logic_vector(63 downto 0);

    out_export : out std_logic_vector(63 downto 0);
    out_data   : out std_logic_vector(63 downto 0);

    LEDR : out std_logic_vector(4 downto 0)
  );
end entity fir_reconfig_top;

architecture rtl of fir_reconfig_top is

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

  signal fir_data_in  : signed(data_width-1 downto 0);
  signal fir_coeff_in : std_logic_vector(4*coeff_width-1 downto 0);
  signal fir_en       : std_logic;
  signal fir_mode     : std_logic;

  signal fir_data_out    : signed(data_width-1 downto 0);
  signal fir_valid_out   : std_logic;
  signal fir_busy        : std_logic;
  signal fir_ready       : std_logic;
  signal fir_coeff_ok    : std_logic;
  signal fir_coeff_count : std_logic_vector(11 downto 0);

begin

  reset <= not reset_n;

  -- No feedsecondary_fir usado aqui, busy='0' significa pronto.
  fir_ready <= not fir_busy;

  LEDR(0) <= fir_coeff_ok;
  LEDR(1) <= fir_ready;
  LEDR(2) <= fir_en;
  LEDR(3) <= fir_mode;
  LEDR(4) <= reset_n;


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

end architecture rtl;
