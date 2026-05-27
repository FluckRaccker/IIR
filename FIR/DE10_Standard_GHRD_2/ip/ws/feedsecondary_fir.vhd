library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use WORK.TYPES.ALL;

entity feedsecondary_fir is
  generic (
    FIR_TAPS : positive := 3000
  );
  port (
    clock       : in  std_logic;
    reset     : in  std_logic;

    data_in   : in  signed(data_width-1 downto 0);

    -- 4 coeficientes empacotados.
    -- Para coeff_width = 16, isso dá 64 bits.
    coeff_in  : in  std_logic_vector(4*coeff_width-1 downto 0);

    en        : in  std_logic;

    -- mode = 0 -> carregar coeficientes
    -- mode = 1 -> filtrar amostra
    mode      : in  std_logic;

    data_out  : out signed(data_width-1 downto 0);
    valid_out : out std_logic;

    -- busy = 1 significa que o bloco pode aceitar um novo pulso de en
    busy     : out std_logic;
	 coeff_ok : out std_logic;
	 
	 coeff_count : out std_logic_vector(11 downto 0)
  );
end feedsecondary_fir;

architecture Behavioral of feedsecondary_fir is

  --------------------------------------------------------------------
  -- Configuração da RAM IP
  --------------------------------------------------------------------
  constant RAM_DEPTH      : positive := 4096;
  constant RAM_ADDR_WIDTH : positive := 12;

  --------------------------------------------------------------------
  -- Função para calcular ceil(log2(n)) sem usar MATH_REAL
  --------------------------------------------------------------------
  function clog2(n : positive) return natural is
    variable v : natural := n - 1;
    variable r : natural := 0;
  begin
    while v > 0 loop
      v := v / 2;
      r := r + 1;
    end loop;

    return r;
  end function;

  --------------------------------------------------------------------
  -- Largura do acumulador
  --
  -- produto: data_width + coeff_width
  -- soma de FIR_TAPS produtos: + ceil(log2(FIR_TAPS))
  --------------------------------------------------------------------
  constant FIR_RESULT_WIDTH : natural :=
    data_width + coeff_width + clog2(FIR_TAPS);

  --------------------------------------------------------------------
  -- Tipos internos
  --------------------------------------------------------------------
  type sample_array_t is array (0 to FIR_TAPS-1) of signed(data_width-1 downto 0);

  type state_t is (
    IDLE,
    LOAD_WRITE,
    MAC_ADDR,
    MAC_ACC
  );

  --------------------------------------------------------------------
  -- Sinais de controle
  --------------------------------------------------------------------
  signal state : state_t := IDLE;

  signal samples : sample_array_t := (others => (others => '0'));

  signal n_coeffs_set : natural range 0 to FIR_TAPS := 0;
  signal coeff_loaded : std_logic := '0';

  signal coeff_buf : std_logic_vector(4*coeff_width-1 downto 0) := (others => '0');

  signal load_base : natural range 0 to RAM_DEPTH-1 := 0;
  signal load_idx  : natural range 0 to 3 := 0;

  signal tap_idx : natural range 0 to FIR_TAPS-1 := 0;

  signal acc : signed(FIR_RESULT_WIDTH-1 downto 0) := (others => '0');

  --------------------------------------------------------------------
  -- Sinais da RAM de coeficientes
  --------------------------------------------------------------------
  signal ram_address : std_logic_vector(RAM_ADDR_WIDTH-1 downto 0) := (others => '0');
  signal ram_data    : std_logic_vector(15 downto 0) := (others => '0');
  signal ram_wren    : std_logic := '0';
  signal ram_q       : std_logic_vector(15 downto 0);

  --------------------------------------------------------------------
  -- IP RAM: 32 palavras x 16 bits
  --------------------------------------------------------------------
  component ram is
    port (
      address : in  std_logic_vector(11 downto 0);
      clock   : in  std_logic := '1';
      data    : in  std_logic_vector(15 downto 0);
      wren    : in  std_logic;
      q       : out std_logic_vector(15 downto 0)
    );
  end component;

 begin 


  --------------------------------------------------------------------
  -- Instância da RAM de coeficientes
  --------------------------------------------------------------------
  coeff_ram_inst : ram
    port map (
      address => ram_address,
      clock   => clock,
      data    => ram_data,
      wren    => ram_wren,
      q       => ram_q
    );

  --------------------------------------------------------------------
  -- Seleção do endereço da RAM
  --------------------------------------------------------------------
  ram_address <= std_logic_vector(to_unsigned(load_base + load_idx, RAM_ADDR_WIDTH))
                 when state = LOAD_WRITE else
                 std_logic_vector(to_unsigned(tap_idx, RAM_ADDR_WIDTH));

  --------------------------------------------------------------------
  -- Dado escrito na RAM durante o carregamento
  --------------------------------------------------------------------
  ram_data <= coeff_buf(15 downto 0) when state = LOAD_WRITE and load_idx = 0 else
            coeff_buf(31 downto 16) when state = LOAD_WRITE and load_idx = 1 else
            coeff_buf(47 downto 32) when state = LOAD_WRITE and load_idx = 2 else
            coeff_buf(63 downto 48) when state = LOAD_WRITE and load_idx = 3 else
            (others => '0');

  --------------------------------------------------------------------
  -- Habilita escrita somente no estado LOAD_WRITE
  --------------------------------------------------------------------
  ram_wren <= '1' when state = LOAD_WRITE else '0';

  --------------------------------------------------------------------
  -- busy indica se o bloco pode receber um novo comando en
  --------------------------------------------------------------------
  busy <= '0' when state = IDLE and (mode = '0' or coeff_loaded = '1') else '1';
  
  --------------------------------------------------------------------
  -- Coeficiente Count
  --------------------------------------------------------------------
  
  coeff_count <= std_logic_vector(to_unsigned(n_coeffs_set, 12));

  --------------------------------------------------------------------
  -- Processo principal
  --------------------------------------------------------------------
  main : process(clock, reset)

    variable prod_v : signed(data_width + coeff_width - 1 downto 0);
    variable acc_v  : signed(FIR_RESULT_WIDTH-1 downto 0);

  begin

    if reset = '1' then

      state <= IDLE;

      samples <= (others => (others => '0'));

      n_coeffs_set <= 0;
      coeff_loaded <= '0';
		coeff_ok     <= '0';

      coeff_buf <= (others => '0');

      load_base <= 0;
      load_idx  <= 0;

      tap_idx <= 0;

      acc <= (others => '0');

      data_out  <= (others => '0');
      valid_out <= '0';

    elsif rising_edge(clock) then

      -- valid_out é pulso de 1 ciclo
      valid_out <= '0';

      case state is

        ----------------------------------------------------------------
        -- Estado IDLE
        -- Espera um pulso de en
        ----------------------------------------------------------------
        when IDLE =>

          if en = '1' then

            ------------------------------------------------------------
            -- mode = 0: carregar coeficientes
            ------------------------------------------------------------
            if mode = '0' then

              coeff_buf <= coeff_in;

              -- Se já tinha carregado todos os coeficientes antes,
              -- uma nova carga começa do endereço zero.
              if n_coeffs_set = FIR_TAPS then
                load_base    <= 0;
                n_coeffs_set <= 0;
                coeff_loaded <= '0';
					 coeff_ok     <= '0';
              else
                load_base    <= n_coeffs_set;
                coeff_loaded <= '0';
					 coeff_ok     <= '0';
              end if;

              load_idx <= 0;
              state    <= LOAD_WRITE;

            ------------------------------------------------------------
            -- mode = 1: filtrar uma nova amostra
            ------------------------------------------------------------
            else

              if coeff_loaded = '1' then

                -- Atualiza linha de atraso das amostras
                samples(0) <= data_in;

                for i in 1 to FIR_TAPS-1 loop
                  samples(i) <= samples(i-1);
                end loop;

                acc     <= (others => '0');
                tap_idx <= 0;

                state <= MAC_ADDR;

              end if;

            end if;

          end if;

        ----------------------------------------------------------------
        -- Estado LOAD_WRITE
        --
        -- A RAM tem largura de 16 bits, então grava 1 coeficiente
        -- por ciclo de clock.
        --
        -- Cada pacote coeff_in possui 4 coeficientes.
        ----------------------------------------------------------------
        when LOAD_WRITE =>

          -- A escrita na RAM acontece neste ciclo de clock.
          -- O endereço e o dado vêm de:
          --
          -- ram_address = load_base + load_idx
          -- ram_data    = coeff_buf correspondente a load_idx
          -- ram_wren    = 1

          if load_base + load_idx + 1 >= FIR_TAPS then

            n_coeffs_set <= FIR_TAPS;
            coeff_loaded <= '1';
				coeff_ok     <= '1';
            state        <= IDLE;

          elsif load_idx = 3 then

            n_coeffs_set <= load_base + 4;
            state        <= IDLE;

          else

            load_idx <= load_idx + 1;

          end if;

        ----------------------------------------------------------------
        -- Estado MAC_ADDR
        --
        -- Coloca o endereço do coeficiente na RAM.
        -- Como a RAM IP normalmente é síncrona, o dado q aparece
        -- no próximo ciclo.
        ----------------------------------------------------------------
        when MAC_ADDR =>

          state <= MAC_ACC;

        ----------------------------------------------------------------
        -- Estado MAC_ACC
        --
        -- Usa ram_q, multiplica pela amostra correspondente
        -- e acumula.
        ----------------------------------------------------------------
        when MAC_ACC =>

          prod_v := signed(ram_q) * samples(tap_idx);

          acc_v := acc + resize(prod_v, FIR_RESULT_WIDTH);

          if tap_idx = FIR_TAPS-1 then

            acc <= acc_v;

            -- Coeficientes em Q15:
            -- divide o resultado por 2^15
            data_out <= (resize(shift_right(acc_v, coeff_width-1), data_width));

            valid_out <= '1';

            state <= IDLE;

          else

            acc <= acc_v;

            tap_idx <= tap_idx + 1;

            state <= MAC_ADDR;

          end if;

      end case;

    end if;

  end process main;

end Behavioral;