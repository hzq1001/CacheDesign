LIBRARY ieee, work;
USE ieee.std_logic_1164.all;
USE work.all;

entity counter is
generic (hi : natural);
port (
   in1, in2: in std_logic_vector (hi downto 0);  --input the  bits.
   sum : out std_logic_vector (hi downto 0)  --output sum.
   );
end entity;


ARCHITECTURE STRUCTURE OF counter IS
signal carry : std_logic_vector(hi DOWNTO 0);
BEGIN

--initialize
sum(0) <= in1(0) xor in2(0);
carry(0) <= (in1(0) and in2(0));

add_bits: for i in 1 to hi generate
	sum(i) <= in1(i) xor in2(i) xor carry(i-1);
	carry(i) <= (in1(i) and in2(i)) or ((in1(i) or in2(i)) and carry(i-1));
end generate add_bits;

END STRUCTURE;