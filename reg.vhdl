library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_misc.all;
library altera;
use altera.altera_primitives_components.all;

entity reg is
 generic (lo : integer := 0;
          hi : integer := 31);
 port (
   clk: in std_logic;
	rst: in std_logic;
	
	d : in std_logic_vector (hi downto lo);
	q : out std_logic_vector (hi downto lo);
	en : in std_logic);
end reg;

architecture basic of reg is

begin

bits: for i in hi downto lo generate
  b: dffe port map (
      clk => clk,
		d => d(i),
		q => q(i),
		ena => en,
		clrn => not rst,
		prn => '1');
end generate bits;

end basic;
