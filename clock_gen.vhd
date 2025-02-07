library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity clock_gen is
  generic(N: integer := 8);
  port(clk, xrst: in std_logic;
       enable: in std_logic;
       cnt_max: in std_logic_vector (N-1 downto 0);
       clk_tx: out std_logic);
end clock_gen;

architecture rtl of clock_gen is
  type state_type is (s0, s1);
  signal state: state_type;
  signal clk_cnt: std_logic_vector (N-1 downto 0);
begin
  process(clk, xrst)
  begin
    if(xrst = '0') then
      state <= s0;
      clk_tx <= '0';
      clk_cnt <= (others => '0');
    elsif(clk'event and clk = '1') then
      case state is
        when s0 =>
          if(enable = '1') then
            state <= s1;
            clk_tx <= '1';
          end if;
          clk_cnt <= (others => '0');
        when s1 =>
          if(enable = '1') then
            if(clk_cnt < cnt_max) then
              clk_cnt <= clk_cnt + 1;
              clk_tx <= '0';
            else
              clk_cnt <= (others => '0');
              clk_tx <= '1';
            end if;
          else
            state <= s0;
          end if;
      end case;
    end if;
  end process;
end rtl;

