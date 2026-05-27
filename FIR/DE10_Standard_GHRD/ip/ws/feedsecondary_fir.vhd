library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.TYPES.ALL;

-- ============================================================
-- feedsecondary_fir.vhd
-- FIR transposto reconfiguravel, sem RAM.
-- Usa coeff_array definido em WORK.TYPES.
--
-- Interface mantida igual a versao anterior:
--   mode = '0' -> carrega 4 coeficientes por pulso de en
--   mode = '1' -> filtra 1 amostra por pulso de en
--
-- Coeficientes Q1.15 quando coeff_width = 16.
-- busy = '0' significa pronto para receber novo en.
-- ============================================================

entity feedsecondary_fir is
  generic (
    FIR_TAPS : positive := taps
  );
  port (
    clock       : in  std_logic;
    reset       : in  std_logic;

    data_in     : in  signed(data_width-1 downto 0);
    coeff_in    : in  std_logic_vector(4*coeff_width-1 downto 0);

    en          : in  std_logic;
    mode        : in  std_logic;

    data_out    : out signed(data_width-1 downto 0);
    valid_out   : out std_logic;

    busy        : out std_logic;
    coeff_ok    : out std_logic;
    coeff_count : out std_logic_vector(11 downto 0)
  );
end entity feedsecondary_fir;

architecture Transposed of feedsecondary_fir is

  constant NTAPS         : natural := taps;
  constant PRODUCT_WIDTH : natural := data_width + coeff_width;

  -- Esta versao foi feita para taps >= 2.
  type acc_array_t is array (0 to NTAPS-2) of signed(result_width-1 downto 0);

  signal coeffs : coeff_array := (others => (others => '0'));
  signal z      : acc_array_t := (others => (others => '0'));

  signal n_coeffs_set : natural range 0 to NTAPS := 0;
  signal coeff_loaded : std_logic := '0';

  -- Cuidado: "block" e palavra reservada em VHDL.
  -- Por isso o argumento se chama coeff_block.
  function get_coeff_from_block(
    coeff_block : std_logic_vector(4*coeff_width-1 downto 0);
    idx         : natural
  ) return std_logic_vector is
    variable r : std_logic_vector(coeff_width-1 downto 0);
  begin
    r := coeff_block((idx+1)*coeff_width-1 downto idx*coeff_width);
    return r;
  end function;

begin

  assert FIR_TAPS = taps
    report "FIR_TAPS diferente de TYPES.taps. Esta versao usa TYPES.taps."
    severity warning;

  -- Mantem a mesma semantica da sua versao antiga:
  -- busy='0' significa pronto para novo en.
  busy <= '0' when (mode = '0' or coeff_loaded = '1') else '1';

  coeff_ok    <= coeff_loaded;
  coeff_count <= std_logic_vector(to_unsigned(n_coeffs_set, 12));

  main : process(clock, reset)
    variable base_v      : natural range 0 to NTAPS;
    variable new_count_v : natural range 0 to NTAPS;

    variable p_v      : signed(PRODUCT_WIDTH-1 downto 0);
    variable y_v      : signed(result_width-1 downto 0);
    variable z_next_v : acc_array_t;
  begin
    if reset = '1' then
      coeffs        <= (others => (others => '0'));
      z             <= (others => (others => '0'));
      n_coeffs_set  <= 0;
      coeff_loaded  <= '0';
      data_out      <= (others => '0');
      valid_out     <= '0';

    elsif rising_edge(clock) then
      valid_out <= '0';

      if en = '1' then

        ------------------------------------------------------------
        -- mode = 0: carrega 4 coeficientes por pulso de en
        ------------------------------------------------------------
        if mode = '0' then

          if n_coeffs_set = NTAPS then
            base_v := 0;
          else
            base_v := n_coeffs_set;
          end if;

          new_count_v := base_v;

          for k in 0 to 3 loop
            if base_v + k < NTAPS then
              coeffs(base_v + k) <= get_coeff_from_block(coeff_in, k);
              new_count_v := base_v + k + 1;
            end if;
          end loop;

          n_coeffs_set <= new_count_v;

          if new_count_v >= NTAPS then
            coeff_loaded <= '1';
          else
            coeff_loaded <= '0';
          end if;

          -- Ao iniciar uma nova carga, limpa os estados internos.
          if base_v = 0 then
            z <= (others => (others => '0'));
          end if;

        ------------------------------------------------------------
        -- mode = 1: filtra uma amostra usando FIR transposto
        ------------------------------------------------------------
        else
          if coeff_loaded = '1' then

            -- y[n] = b0*x[n] + z0[n]
            p_v := signed(coeffs(0)) * data_in;
            y_v := resize(p_v, result_width) + z(0);

            -- z_i[n+1] = b_{i+1}*x[n] + z_{i+1}[n]
            for i in 0 to NTAPS-3 loop
              p_v := signed(coeffs(i+1)) * data_in;
              z_next_v(i) := resize(p_v, result_width) + z(i+1);
            end loop;

            -- ultimo estado
            p_v := signed(coeffs(NTAPS-1)) * data_in;
            z_next_v(NTAPS-2) := resize(p_v, result_width);

            z <= z_next_v;

            -- Coeficientes Q1.15: divide por 2^(coeff_width-1)
            data_out  <= resize(shift_right(y_v, coeff_width-1), data_width);
            valid_out <= '1';

          end if;
        end if;
      end if;
    end if;
  end process main;

end architecture Transposed;
