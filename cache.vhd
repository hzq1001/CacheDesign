library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_misc.all;
library altera;
use altera.altera_primitives_components.all;

entity cache is
  port (
    clk      :  in std_logic;
    rst      :  in std_logic;
    
    ready    : out std_logic;
	 
    --request interface---
    addr     : in std_logic_vector (31 downto 3);
    req_vld  : in std_logic;
    req_st   : in std_logic;
    
    
    resp_hit  : out std_logic;
    resp_miss : out std_logic;
    resp_dirty: out std_logic;
    
    
    --cast_out data--
    co_vld   : out std_logic;
    co_addr  : out std_logic_vector(31 downto 4);
    --reload interface --
    rld_vld  : in std_logic;
    
    ---data interface --
    -- used for store write data (63 downto 0)
    -- and for reload data
    data_in : in std_logic_vector(127 downto 0); 
    -- used for load read data (63 downto 0)
    -- and cast out data
    data_out : out std_logic_vector(127 downto 0);
    --debug interface
    debug_sel : in std_logic_vector (3 downto 0);
    debug_info: out std_logic_vector (7 downto 0));
    

end cache;


architecture basic of cache is

signal tag_address, data_address,dffe_out,counter_out : std_logic_vector (6 downto 0);
signal tag_in, tag_out,tag_data : std_logic_vector (20 downto 0);
signal data_input, data_output : std_logic_vector (511 downto 0);
signal data_byteena,reg2_in,reg2_out : std_logic_vector (63 downto 0);
signal reg_in, reg_out : std_logic_vector (31 downto 0);
signal tag_wren,data_wren,is_hit,is_dirty,dffe_ena: std_logic;
signal state_d, state_q : std_logic_vector (3 downto 0);
signal test_hit,test_miss : std_logic;




 constant ST_INIT : std_logic_vector (3 downto 0)     := "0000"; -- 0
 constant ST_SEND : std_logic_vector (3 downto 0)     := "0001"; -- 1
 constant ST_WAIT : std_logic_vector (3 downto 0)     := "0010"; -- 2
 constant ST_CMP : std_logic_vector (3 downto 0)      := "0011"; -- 3
 --constant ST_ERR : std_logic_vector (3 downto 0)      := "0100"; -- 4
 --constant ST_FIN : std_logic_vector (3 downto 0)      := "0101"; -- 5
 constant ST_RLD_WAIT : std_logic_vector (3 downto 0) := "0110"; -- 6
 constant ST_NEXT: std_logic_vector (3 downto 0)      := "0111"; -- 7

  ---note: code relies on CO/RLD starting with 1
  --and RLD starting with 11
 constant ST_CO_0 : std_logic_vector (3 downto 0)  := "1000"; -- 8 
 constant ST_CO_1 : std_logic_vector (3 downto 0)  := "1001"; -- 9
 constant ST_CO_2 : std_logic_vector (3 downto 0)  := "1010"; -- A
 constant ST_CO_3 : std_logic_vector (3 downto 0)  := "1011"; -- B
 constant ST_RL_0 : std_logic_vector (3 downto 0)  := "1100"; -- C
 constant ST_RL_1 : std_logic_vector (3 downto 0)  := "1101"; -- D
 constant ST_RL_2 : std_logic_vector (3 downto 0)  := "1110"; -- E
 constant ST_RL_3 : std_logic_vector (3 downto 0)  := "1111"; -- F

 
constant      zero16  : std_logic_vector(15 downto 0):= (others => '0');
constant       zero8  : std_logic_vector(7 downto 0):= (others => '0');
constant        one8  : std_logic_vector(7 downto 0):= (others => '1');
constant       one16  : std_logic_vector(15 downto 0):= (others => '1');
constant      zero128 : std_logic_vector(127 downto 0):= (others => '0');
constant      zero64  : std_logic_vector(63 downto 0):= (others => '0');

  -- for the tag array
  component tags is
    port (
      address  : in std_logic_vector(6 downto 0);
      clock    : in std_logic;
      clken    : in std_logic := '1';
      data     : in std_logic_vector (20 DOWNTO 0);
      wren     : in std_logic ;
      q        : out std_logic_vector (20 DOWNTO 0));
  end component;

  -- for the data array
  component data is
    port (
      
      address  : in std_logic_vector(6 downto 0);
      byteena  : in std_logic_vector(63 downto 0);
      clock    : in std_logic;
      data     : in std_logic_vector (511 DOWNTO 0);
      wren     : in std_logic ;
      q	       : out std_logic_vector (511 DOWNTO 0));
  end component;

  -- a register (multiple DFFs together)
  component reg is
    generic (lo : integer := 0;
             hi : integer := 31);
    port (
      clk: in std_logic;
      rst: in std_logic;
      
      d : in std_logic_vector (hi downto lo);
      q : out std_logic_vector (hi downto lo);
      en : in std_logic);
  end component;
  
  -- counter --
  component counter is
    generic (hi : natural);
    port (
       in1, in2: in std_logic_vector (hi downto 0);  
       sum : out std_logic_vector (hi downto 0) );
  end component;
   


begin

  my_tag : tags port map(
                          address  => tag_address,
                          clock    => clk,
                          clken    => '1',
                          data     => tag_data,
                          wren     => tag_wren,
                          q        => tag_out);
  
  my_data : data port map(
                          address  => data_address,
                          byteena  => data_byteena,
                          clock    => clk,
                          data     => data_input,
                          wren     => data_wren ,
                          q	       => data_output);
   
   -- latch address --                       
   my_reg : reg generic map (lo => 0,hi => 31)
                        port map (
                        clk  => clk,
                        rst  => rst,
                        d    => reg_in,
                        q    => reg_out,
                        en   => '1');
                        
   -- latch data_in --
   
   my_reg2 : reg generic map (lo => 0,hi => 63)
                        port map (
                        clk  => clk,
                        rst  => rst,
                        d    => reg2_in,
                        q    => reg2_out,
                        en   => '1');
                        
   my_counter: counter generic map (hi=>6)  
                          port map (
                                   in1 => dffe_out,
                                   in2 => "0000001",
                                   sum => counter_out);
                 
    g1: for i in 6 downto 0 generate
    my_dffe : dffe port map(
                            d=> counter_out(i), 
                            clk=> clk, 
                            clrn=> not rst,
                            prn=>'1',
                            ena=> dffe_ena , 
                            q=> dffe_out(i));
    end generate g1;
    
    g2: for i in 3 downto 0 generate
    my_fsm : dffe port map(
                            d=> state_d(i), 
                            clk=> clk, 
                            clrn=> not rst,
                            prn=>'1',
                            ena=>'1', 
                            q=> state_q(i));
    end generate g2;
    
    --implement FSM
    
    state_d <= ST_INIT when rst = '1' else
               ST_NEXT when (state_q = ST_INIT  and dffe_out = "1111111") or
                            (state_q = ST_CMP and is_hit = '1') or 
                             state_q = ST_RLD_WAIT else
               ST_SEND when state_q = ST_NEXT and req_vld = '1' else
               ST_WAIT when state_q = ST_SEND else
                 
               
               ST_CO_0  when state_q = ST_WAIT  and is_hit = '0' and is_dirty = '1' else
               ST_CO_1  when state_q = ST_CO_0 else
               ST_CO_2  when state_q = ST_CO_1 else
               ST_CO_3  when state_q = ST_CO_2 else
               
               ST_CMP when (state_q = ST_WAIT and is_hit = '1') or 
                           (state_q = ST_WAIT and is_hit = '0' and is_dirty = '0') else
                       
               ST_RL_0 when (state_q = ST_CMP and is_hit = '0' and is_dirty = '0') or
                             state_q = ST_CO_3 else
               ST_RL_1 when state_q = ST_RL_0 else
               ST_RL_2 when state_q = ST_RL_1 else
               ST_RL_3 when state_q = ST_RL_2 else
               
               ST_RLD_WAIT when state_q = ST_RL_3 else
               
               state_q;
               
   ---determine hit/miss, dirty/clean
   
   is_hit  <= '1' when tag_out(20) = '1' and reg_out(31 downto 13) = tag_out(18 downto 0) else
              '0';
   is_dirty <= '1' when tag_out(19) = '1' else
               '0';
              
   
   --- implement tag array        
   tag_address <= dffe_out when state_q = ST_INIT else
                  addr(12 downto 6) when req_vld = '1' else
                  reg_out(12 downto 6);
   
   tag_data    <= '1'& tag_out(19) & reg_out(31 downto 13) when state_q = ST_RL_3 else
                  '1'&'1'& reg_out(31 downto 13) when state_q = ST_CMP and is_hit = '1' and req_st = '1' else
                  '1'&'1'& reg_out(31 downto 13) when state_q = ST_RLD_WAIT and req_st = '1' else
                  (others => '0');
   
   tag_wren    <= '1' when state_q = ST_INIT else
                  '1' when state_q = ST_RL_3 else
                  '1' when state_q = ST_CMP and is_hit = '1' and req_st = '1' else
                  '1' when state_q = ST_RLD_WAIT and req_st = '1' else
                  '0';
                  
   --- implement data array
   data_address <= addr(12 downto 6) when req_vld = '1' else
                   reg_out(12 downto 6);
   
   data_byteena <= zero16 & zero16 & zero16 & one16 when state_q = ST_RL_0 else
                   zero16 & zero16 & one16 & zero16 when state_q = ST_RL_1 else
                   zero16 & one16 & zero16 & zero16 when state_q = ST_RL_2 else
                   one16 & zero16 & zero16 & zero16 when state_q = ST_RL_3 else
                   
                   zero16 & zero16 & zero16 & zero8 & one8 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "000" else
                   zero16 & zero16 & zero16 & one8 & zero8 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "001" else
                   zero16 & zero16 & zero8 & one8 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "010" else
                   zero16 & zero16 & one8 & zero8 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "011" else
                   zero16 & zero8 & one8 & zero16 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "100" else
                   zero16 & one8 & zero8 & zero16 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "101" else
                   zero8 & one8 & zero16 & zero16 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "110" else
                   one8 & zero8 & zero16 & zero16 & zero16 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "111" else
                   
                   zero16 & zero16 & zero16 & zero8 & one8 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "000" else
                   zero16 & zero16 & zero16 & one8 & zero8 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "001" else
                   zero16 & zero16 & zero8 & one8 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "010" else
                   zero16 & zero16 & one8 & zero8 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "011" else
                   zero16 & zero8 & one8 & zero16 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "100" else
                   zero16 & one8 & zero8 & zero16 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "101" else
                   zero8 & one8 & zero16 & zero16 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "110" else
                   one8 & zero8 & zero16 & zero16 & zero16 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "111" else
                   (others => '0');
                   
   data_input   <= zero128 & zero128 & zero128 & data_in when state_q = ST_RL_0 else
                   zero128 & zero128 & data_in & zero128 when state_q = ST_RL_1 else
                   zero128 & data_in & zero128 & zero128 when state_q = ST_RL_2 else
                   data_in & zero128 & zero128 & zero128 when state_q = ST_RL_3 else
                   
                   zero128 & zero128 & zero128 & zero64 & reg2_out when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "000" else
                   zero128 & zero128 & zero128 & reg2_out & zero64 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "001" else
                   zero128 & zero128 & zero64 & reg2_out & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "010" else
                   zero128 & zero128 & reg2_out & zero64 & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "011" else
                   zero128 & zero64 & reg2_out & zero128 & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "100" else
                   zero128 & reg2_out & zero64 & zero128 & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "101" else
                   zero64 & reg2_out & zero128 & zero128 & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "110" else
                   reg2_out & zero64 & zero128 & zero128 & zero128 when state_q = ST_CMP and is_hit = '1' and req_st = '1' and reg_out(5 downto 3) = "111" else
                   
                   zero128 & zero128 & zero128 & zero64 & reg2_out when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "000" else
                   zero128 & zero128 & zero128 & reg2_out & zero64 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "001" else
                   zero128 & zero128 & zero64 & reg2_out & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "010" else
                   zero128 & zero128 & reg2_out & zero64 & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "011" else
                   zero128 & zero64 & reg2_out & zero128 & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "100" else
                   zero128 & reg2_out & zero64 & zero128 & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "101" else
                   zero64 & reg2_out & zero128 & zero128 & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "110" else
                   reg2_out & zero64 & zero128 & zero128 & zero128 when state_q = ST_RLD_WAIT and req_st = '1' and reg_out(5 downto 3) = "111" else
                   (others => '0');
                   
   data_wren    <= '1' when state_q = ST_RL_0 else
                   '1' when state_q = ST_RL_1 else
                   '1' when state_q = ST_RL_2 else
                   '1' when state_q = ST_RL_3 else
                   '1' when state_q = ST_CMP and is_hit = '1' and req_st = '1'else
                   '1' when state_q = ST_RLD_WAIT and req_st = '1' else
                   '0';
                   
   --- implement reg
   
   reg_in <=  addr & "000" when req_vld = '1' else
              reg_out;
              
   --- latch data_to_store
   
   reg2_in <= data_in(63 downto 0) when req_vld = '1' and req_st = '1' else
              reg2_out;

                 
   
   -- stop the counter 
   dffe_ena <= '0' when dffe_out = "1111111" else
               '1';
   
   
   ---implement cache output
   ready     <= '1' when dffe_out = "1111111" else
                '0';
                
   resp_hit  <= '1' when (state_q = ST_WAIT and is_hit = '1') or state_q = ST_RLD_WAIT else
                '0';
   
   test_hit  <= '1' when (state_q = ST_WAIT and is_hit = '1') or state_q = ST_RLD_WAIT else
                '0';           
  
                
   resp_miss <= '1' when state_q = ST_WAIT and is_hit = '0' else
                '0';
   
   test_miss <= '1' when state_q = ST_WAIT and is_hit = '0' else
                '0';
                
   resp_dirty <= '1' when state_q = ST_WAIT and is_hit = '0' and is_dirty = '1' else
                 '0';
                 

                 
   data_out   <= data_output(127 downto 0)   when state_q = ST_CO_0 else
                 data_output(255 downto 128) when state_q = ST_CO_1 else
                 data_output(383 downto 256) when state_q = ST_CO_2 else
                 data_output(511 downto 384) when state_q = ST_CO_3 else  
                 
                 zero64 & data_output(63 downto 0)    when reg_out(5 downto 3) = "000" else
                 zero64 & data_output(127 downto 64)  when reg_out(5 downto 3) = "001" else
                 zero64 & data_output(191 downto 128) when reg_out(5 downto 3) = "010" else
                 zero64 & data_output(255 downto 192) when reg_out(5 downto 3) = "011" else
                 zero64 & data_output(319 downto 256) when reg_out(5 downto 3) = "100" else
                 zero64 & data_output(383 downto 320) when reg_out(5 downto 3) = "101" else
                 zero64 & data_output(447 downto 384) when reg_out(5 downto 3) = "110" else
                 zero64 & data_output(511 downto 448) when reg_out(5 downto 3) = "111" else
                       
                 (others => '0');
   
 
  co_vld <= '1' when state_q = ST_CO_0 else
            '1' when state_q = ST_CO_1 else
            '1' when state_q = ST_CO_2 else
            '1' when state_q = ST_CO_3 else
            '0';
            

            
  co_addr <= tag_out(18 downto 0) & reg_out(12 downto 6) & "00" when state_q = ST_CO_0 else
             tag_out(18 downto 0) & reg_out(12 downto 6) & "01" when state_q = ST_CO_1 else
             tag_out(18 downto 0) & reg_out(12 downto 6) & "10" when state_q = ST_CO_2 else
             tag_out(18 downto 0) & reg_out(12 downto 6) & "11" when state_q = ST_CO_3 else
             (others => '0');
             
  debug_info <= "0000000" & test_hit when debug_sel = "0001" else
                "0000000" & test_miss when debug_sel = "0010" else
                "0000000" & req_vld when debug_sel = "0011" else
                "0000" & state_q;


end basic;	 

