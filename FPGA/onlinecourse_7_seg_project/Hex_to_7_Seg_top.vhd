-------------------------------------------------------------------------------
-- Lab 4 Udemy
-- 
-- Utilize the 7 segment displays on the board
--
-- Note:
-- 
-------------------------------------------------------------------------------
-- Librarys
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.numeric_std.all;

-- Entity
entity Hex_to_7_Seg_top is
port (
	seg_out		: out std_logic_vector(6 downto 0);
	enable0		: out std_logic;
	enable1		: out std_logic;
	enable2		: out std_logic;
	enable3		: out std_logic;
	hex_in_0		: in std_logic_vector(3 downto 0);
	hex_in_1		: in std_logic_vector(3 downto 0);
	clk 			: in std_logic;
	reset			: in std_logic);
end Hex_to_7_Seg_top;

architecture behavior of Hex_to_7_Seg_top is
-- Component Instantiations
-- 7 segment display
component Hex_to_7_Seg
port (
	seven_seg 		: out std_logic_vector( 6 downto 0);
	hex 			: in std_logic_vector(3 downto 0));
end component;

-- Signals for holding 7 seg values
signal Seg_0	: std_logic_vector(6 downto 0);
signal Seg_1	: std_logic_vector(6 downto 0);

-- signals for toggling

-- a 28-bit counter is required to count to 100000000 (100 million/ 100 MHz)
-- we will be counting to 200,000 to achieve a 500Hz refresh rate (21 bit counter) 
signal counter				: unsigned(20 downto 0) := to_unsigned(0, 21);
constant maxcount			: integer := 200000;

signal toggle				: std_logic_vector(1 downto 0) := "10";

--signal second_counter		: unsigned(7 downto 0);
--constant max_second_count	: integer := 255;


begin
		-- instantiate 2 instances of the 7 segment converter
		seg1 : Hex_to_7_Seg
			port map (Seg_1, hex_in_1);
		seg0 : Hex_to_7_Seg
			port map (Seg_0, hex_in_0);
			
		-- Signal assignments	
		enable0 <= toggle(0);
		enable1 <= toggle(1);
		enable2 <= '1';
		enable3 <= '1';
			
		-- Counter to create 60Hz
		counter_proc: process(clk)
		begin
			if(rising_edge(clk)) then
				if(reset = '1' or counter = maxcount) then
					counter <= (others => '0');
				else
					counter <= counter + 1;
				end if;
			end if;
		end process counter_proc;
		
		-- Process that flags seven segs to toggle at 60Hz
		toggle_count_proc: process(clk)
		begin
			if(rising_edge(clk)) then
				if(reset = '1') then
					toggle <= toggle;
				elsif(counter = maxcount) then
					toggle <= not toggle;
				end if;
			end if;
		end process toggle_count_proc;
		
		-- Toggle the seven segment displays
		toggle_proc: process(toggle, Seg_1, Seg_0)
		begin
			if(toggle(1) = '1') then
				seg_out <= Seg_1;
			else
				seg_out <= Seg_0;
			end if;
		end process toggle_proc;
end behavior;
