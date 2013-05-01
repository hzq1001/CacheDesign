library IEEE;
use IEEE.std_logic_misc.all;
use IEEE.std_logic_1164.all;

entity led is
  
  port (
    din  : in  std_logic_vector (15 downto 0);  -- one hot hex number
    dout : out std_logic_vector (6 downto 0));  -- one bit per segment

end led;

architecture basic of led is

begin  -- basic

  dout(0) <= not (not din(1) and
                  not din(4) and
                  not din(11) and
                  not din(13));
  dout(5) <= not (not din(1) and
                  not din(2) and
                  not din(3) and
                  not din(13));
  dout(1) <= not (not din(5) and
                  not din(6) and
                  not din(11) and
                  not din(12) and
                  not din(14) and
                  not din(15));
  dout(6) <= not (not din(0) and
                  not din(1) and
                  not din(7) and
                  not din(12));
  dout(4) <= not (not din(1) and
                  not din(3) and
                  not din(4) and
                  not din(5) and
                  not din(7) and
                  not din(9));
  dout(2) <= not (not din(2) and
                  not din(12) and
                  not din(14) and
                  not din(15));
  dout(3) <=not (not din(1) and
                 not din(4) and
                 not din(7) and
                 not din(9) and
                 not din(10) and
                 not din(15));
  
end basic;
