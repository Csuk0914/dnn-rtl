-- Hex to 7-segment conversion 
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity Hex_to_7_Seg is
port (
	seven_seg		: out std_logic_vector(6 downto 0);
	hex				: in std_logic_vector(3 downto 0));
end hex_to_7_seg;

architecture behavior of Hex_to_7_Seg is
  
signal seg_out 		: std_logic_vector(6 downto 0);
begin  
	--  7 segs are active low
	seven_seg <= not seg_out;  

	seg_proc : process(hex)
	begin	
		case hex is
			when x"0" => seg_out <= "0111111";
			when x"1" => seg_out <= "0000110";
			when x"2" => seg_out <= "1011011";
			when x"3" => seg_out <= "1001111";
			when x"4" => seg_out <= "1100110";
			when x"5" => seg_out <= "1101101";
			when x"6" => seg_out <= "1111101";
			when x"7" => seg_out <= "0000111";
			when x"8" => seg_out <= "1111111";
			when x"9" => seg_out <= "1101111";
			when x"A" => seg_out <= "1110111";
			when x"B" => seg_out <= "1111100";
			when x"C" => seg_out <= "0111001";
			when x"D" => seg_out <= "1011110";
			when x"E" => seg_out <= "1111001";
			when x"F" => seg_out <= "1110001";
			when others =>
				seg_out <= (others => 'X');
		end case;
	end process seg_proc;			
end behavior;
