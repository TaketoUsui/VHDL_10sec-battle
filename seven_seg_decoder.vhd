library ieee;
use ieee.std_logic_1164.all;

entity seven_seg_decoder is
  port(clk: in std_logic;
       xrst: in std_logic;
       din: in std_logic_vector(3 downto 0);
       dout: out std_logic_vector(6 downto 0));
end seven_seg_decoder;

architecture rtl of seven_seg_decoder is
begin
  process(clk, xrst)
  begin
    if(xrst = '0') then
      dout <= "0000000";
    elsif(clk'event and clk = '1') then
      case din is
        when "0000" => dout <= "1000000";
        when "0001" => dout <= "1111001";
        when "0010" => dout <= "0100100";
        when "0011" => dout <= "0110000";
        when "0100" => dout <= "0011001";
        when "0101" => dout <= "0010010";
        when "0110" => dout <= "0000010";
        when "0111" => dout <= "1111000";
        when "1000" => dout <= "0000000";
        when "1001" => dout <= "0011000";
        when "1010" => dout <= "0001000";
        when "1011" => dout <= "0000011";
        when "1100" => dout <= "1000110";
        when "1101" => dout <= "0100001";
        when "1110" => dout <= "0000110";
        when "1111" => dout <= "0001110";
        when others => dout <= "0000000";
      end case;
    end if;
  end process;
end rtl;
