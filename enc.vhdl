library IEEE;
use IEEE.std_logic_misc.all;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity encoder is
  
  generic (
    bits : natural := 4);               -- input bits

  port (
    din  : in  std_logic_vector (bits -1 downto 0);
    dout : out std_logic_vector (2**bits -1 downto 0));

end encoder;

architecture basic of encoder is
  
begin  -- basic

  out_bits: for i in 0 to 2**bits - 1 generate
    dout(i) <= not or_reduce(std_logic_vector(to_unsigned(i,bits)) xor
                          din);    
  end generate out_bits;

end basic;
