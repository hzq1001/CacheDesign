library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_misc.all;
library altera;
use altera.altera_primitives_components.all;

entity cache_sim is
  port (inclk :in std_logic;
        rstn : in std_logic;
        led7s : out std_logic_vector (55 downto 0);
        ledg  : out std_logic_vector (7 downto 0);
        ledr  : out std_logic_vector (17 downto 0);
        cache_debug_sel: in std_logic_vector (3 downto 0);
        sstep : in std_logic;
        step_button_n : in std_logic;
        sw    : in std_logic_vector (3 downto 0));
  
  
end cache_sim;

architecture basic of cache_sim is
  component pll is
    port (inclk0: in std_logic;
          c0: out std_logic);
  end component;
  component  clkctrl_altclkctrl_lei is
    port 
      ( 
        clkselect	:	in std_logic_vector (1 downto 0);
        ena	:	in std_logic;
        inclk	:	in std_logic_vector( 3 downto 0);
        outclk	:	out std_logic
        ); 
  end component;

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


  component cache is
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
  end component;
  component testrom is
    port (
      address  : in std_logic_vector(10 downto 0);
      clock		: in std_logic;
      q	      : out std_logic_vector (129 downto 0));
  end component;
  component led is
    port (
      din  : in  std_logic_vector (15 downto 0);  -- one hot hex number
      dout : out std_logic_vector (6 downto 0));  -- one bit per segment
  end component;
  component encoder is
    
    generic (
      bits : natural := 4);               -- input bits

    port (
      din  : in  std_logic_vector (bits -1 downto 0);
      dout : out std_logic_vector (2**bits -1 downto 0));

  end component;

  component rcaddr is
    generic (  
      hi: natural :=3);
    port (
      a   : in std_logic_vector (hi downto 0);  
      b   : in std_logic_vector (hi downto 0);   
      ci  : in std_logic;                               
      sum : out std_logic_vector (hi downto 0)); 
  end component;
  signal err_q : std_logic_vector (17 downto 0);
  signal err_d : std_logic_vector (17 downto 0);

  signal addr_q : std_logic_vector (31 downto 3);
--expected values from trace
  signal update_rom_addr : std_logic;

  signal ex_st_q : std_logic;
  signal ex_hit_q : std_logic;
  signal ex_miss_q: std_logic;
  signal ex_dirty_q : std_logic;
  signal ex_data_q : std_logic_vector (63 downto 0);
  signal ex_co_tag_q : std_logic_vector (18 downto 0);

  constant ST_INIT : std_logic_vector (3 downto 0)  := "0000";
  constant ST_SEND : std_logic_vector (3 downto 0)  := "0001";
  constant ST_WAIT : std_logic_vector (3 downto 0)  := "0010";
  constant ST_CMP : std_logic_vector (3 downto 0)  := "0011";
  constant ST_ERR : std_logic_vector (3 downto 0)  := "0100";
  constant ST_FIN : std_logic_vector (3 downto 0)  := "0101";
  constant ST_RLD_WAIT : std_logic_vector (3 downto 0) := "0110";
  constant ST_NEXT: std_logic_vector (3 downto 0) := "0111";

  ---note: code relies on CO/RLD starting with 1
  --and RLD starting with 11
  constant ST_CO_0 : std_logic_vector (3 downto 0)  := "1000";
  constant ST_CO_1 : std_logic_vector (3 downto 0)  := "1001";
  constant ST_CO_2 : std_logic_vector (3 downto 0)  := "1010";
  constant ST_CO_3 : std_logic_vector (3 downto 0)  := "1011";
  constant ST_RL_0 : std_logic_vector (3 downto 0)  := "1100";
  constant ST_RL_1 : std_logic_vector (3 downto 0)  := "1101";
  constant ST_RL_2 : std_logic_vector (3 downto 0)  := "1110";
  constant ST_RL_3 : std_logic_vector (3 downto 0)  := "1111";

  signal state_q : std_logic_vector (3 downto 0);
  signal state_d : std_logic_vector (3 downto 0);

  signal test_rom_rd_addr_d : std_logic_vector (10 downto 0);
  signal test_rom_rd_addr_q : std_logic_vector (10 downto 0);
  signal test_rom_rd_addr_temp: std_logic_vector (10 downto 0);
  signal test_rom_rd_data : std_logic_vector(129 downto 0);


  signal watch_dog_d : std_logic_vector (9 downto 0);
  signal watch_dog_q : std_logic_vector (9 downto 0);
  signal watch_dog_q_plus_1 : std_logic_vector (9 downto 0);
  signal prev_state: std_logic_vector (3 downto 0);
  signal watchdog_timeout : std_logic;

  signal cache_resp_hit : std_logic;
  signal cache_resp_miss : std_logic;
  signal cache_resp_dirty : std_logic;
  signal cache_co_vld : std_logic;
  signal cache_co_vld_q : std_logic;
  signal cache_co_addr : std_logic_vector (31 downto 4);
  signal cache_data_in : std_logic_vector (127 downto 0);
  signal cache_data_out: std_logic_vector (127 downto 0);
  signal rst: std_logic;
  signal latch_rom_data : std_logic;
  signal clk: std_logic;
  attribute keep: boolean;
  attribute keep of clk: signal is true;

  signal outnum: std_logic_vector (31 downto 0);
  signal led7s_temp  : std_logic_vector (55 downto 0);
  signal cache_data_out_q : std_logic_vector ( 127 downto 0);
  signal cache_co_addr_q : std_logic_vector (31 downto 0);
  signal ex_co_addr_off_d: std_logic_vector (1 downto 0);
  signal ex_co_addr_off_q: std_logic_vector (1 downto 0);
  signal ex_info_co_addr: std_logic_vector (31 downto 0);
  signal ex_info: std_logic_vector(31 downto 0);

  signal non_err_state_q : std_logic_vector (3 downto 0);

  signal step_pulse : std_logic;

  signal step_button_q:std_logic;
  signal etype_q : std_logic_vector(1 downto 0);
  signal cache_debug_info: std_logic_vector (7 downto 0);
  signal cache_ready : std_logic;
  signal clk_temp : std_logic;
  signal step_button_2_q: std_logic;

  signal clk_ena_q : std_logic;
begin  -- basic

  pll0: pll port map (
    inclk0 => inclk,
    c0 => clk_temp);

  cbuff: clkctrl_altclkctrl_lei	 
    port map (clkselect => "00",
              ena => clk_ena_q,
              inclk(0) => clk_temp,
              inclk(1) => '0',
              inclk(2) => '0',
              inclk(3) => '0',
              outclk => clk);
  step_p: dff port map (clk => clk_temp,
                        d=> not step_button_n,
                        q=> step_button_q,
                        clrn => not rst,
                        prn => '1');

  clk_ena: dff port map (clk => clk_temp,
                         d=> (not sstep) or step_pulse,
                         q => clk_ena_q,
                         prn => '1',
                         clrn => '1');		  
  step_p2: dff port map(clk => clk_temp,
                        d=> step_button_q,
                        q=> step_button_2_q,
                        clrn => not rst,
                        prn => '1');
  
  step_pulse <= (step_button_q and not step_button_2_q) or (not or_reduce (state_q xor ST_INIT) and not cache_ready);		  
  
 reset_dff : dff port map (
   clk  => clk,
   d    => not rstn,
   q    => rst,
   prn  => '1',
   clrn => '1'); 


  state_d <= ST_INIT when rst /= '0' else
             ST_NEXT when state_q = ST_INIT and cache_ready /= '0' else
             ST_ERR when or_reduce(err_d) /= '0' else 
             ST_FIN when state_q = ST_NEXT and test_rom_rd_data(129 downto 128) = "00" else
             ST_SEND when state_q = ST_NEXT else
             ST_WAIT when state_q = ST_SEND else
             ST_CO_0 when state_q = ST_WAIT and (cache_resp_miss and not ex_hit_q and ex_dirty_q and cache_resp_dirty) /= '0' else
             ST_CMP when state_q = ST_WAIT and (cache_resp_hit or cache_resp_miss) /= '0' else
             ST_NEXT when state_q = ST_CMP and ex_hit_q /= '0' else
--             ST_CO_0 when state_q = ST_CMP and ex_dirty_q /= '0' else
             ST_RL_0 when state_q = ST_CMP else
             ST_CO_1 when state_q = ST_CO_0 and cache_co_vld /= '0' else
             ST_CO_2 when state_q = ST_CO_1 and cache_co_vld /= '0' else
             ST_CO_3 when state_q = ST_CO_2 and cache_co_vld /= '0' else
             ST_RL_0 when state_q = ST_CO_3 and cache_co_vld /= '0' else
             ST_RL_1 when state_q = ST_RL_0 else
             ST_RL_2 when state_q = ST_RL_1 else
             ST_RL_3 when state_q = ST_RL_2 else
             ST_RLD_WAIT when state_q = ST_RL_3 else
             --ST_RLD_CMP when state_q = ST_RLD_WAIT and cache_resp_hit /= '0' else
             ST_NEXT when state_q = ST_RLD_WAIT and cache_resp_hit /= '0' else
             state_q;

  
  
--run_sim <= (not sstep) or
--           step_pulse or
--           cache_resp_hit or cache_resp_miss or cache_co_vld or not or_reduce(state_q xor ST_SEND) or
--			  (state_q(3) and state_q(2)) or not or_reduce(state_q xor ST_INIT);
  
  
  state: reg generic map (hi => 3)
    port map (clk=>clk, rst=> rst, d=> state_d, q=>state_q, en=>'1');			  
  
  non_err_state: reg generic map (hi => 3)
    port map (clk=>clk, rst=>rst, d=>state_q, q=>non_err_state_q, en=>or_reduce(state_q xor ST_ERR));			  
  
--the cache---

  c : cache port map (
    clk       => clk,
    rst       => rst,
    ready     => cache_ready,
    addr      => addr_q,
    req_vld   => not(or_reduce(state_q xor ST_SEND)),
    req_st    => ex_st_q,
    resp_hit   => cache_resp_hit,
    resp_miss  => cache_resp_miss,
    resp_dirty => cache_resp_dirty,
    co_vld    => cache_co_vld,
    co_addr   => cache_co_addr,
    rld_vld   => state_q(3) and state_q(2),
    data_in   => cache_data_in,
    data_out  => cache_data_out,
    debug_sel => cache_debug_sel,
    debug_info => cache_debug_info);

  cache_data_in (63 downto 0) <= test_rom_rd_data (63 downto 0);
  cache_data_in (127 downto 64) <= (others => '0') when state_q = ST_SEND else test_rom_rd_data(127 downto 64);

  cdata_reg: reg generic map (hi => 127)
    port map (clk => clk, rst => rst, en=>cache_resp_hit or cache_co_vld , d=>cache_data_out, q=> cache_data_out_q);

  coaddr_reg: reg 
    port map (clk => clk, rst => rst, en=>cache_co_vld,d=>cache_co_addr &"0000", q=> cache_co_addr_q);

  co_vld_dff : dff port map (
    clk  => clk,
    d    => cache_co_vld,
    q    => cache_co_vld_q,
    prn  => '1',
    clrn => not rst);
  
-------------------------------------------------------------------------------
-- Error checking --
-------------------------------------------------------------------------------

-- 0: hit, should be miss
-- 1: miss, should be hit
-- 2: dirty miss, should be clean
-- 3: clean miss, should be dirty
-- 4: wrong co tag
-- 5: wrong co ind
-- 6: wrong co offset
-- 7: wrong load data
-- 8: signaled hit and miss, or signaled hit/miss at unexpected time
-- 9: signaled co_vld unexpectedly (not dirty miss)
-- A: wrong co data (dword 0)
-- B: wrong co data (dword 1)
-- C: wrong co data (dword 2)
-- D: wrong co data (dword 3)
-- E,F,10 : stuck waiting for...
-- ====
-- 001  hit
-- 010  miss
-- 011  hit after reload
-- 100  co0
-- 101  co1
-- 110  co2
-- 111  co3  (or anything else?)
-- =====
-- 11: internal/trace error

--watch dog timer

  wd_add: rcaddr generic map (hi => 9)
    port map (a => watch_dog_q,
              b => "0000000001",
              ci => '0',
              sum => watch_dog_q_plus_1);

  watch_dog_d <= (others => '0') when rst /= '0' else
                 (others => '0') when state_q = ST_FIN else
                 (others => '0') when prev_state /= state_q else
                 watch_dog_q_plus_1 ;
  
  ps: reg generic map (hi => 3)
    port map (clk => clk, rst => rst, d => state_q, q=> prev_state, en =>'1' );					
  
  wd_reg : reg generic map (hi => 9)
    port map (clk => clk,
              rst => rst,
              d => watch_dog_d,
              q => watch_dog_q,
              en => '1')	;				
  
  
  watchdog_timeout <= and_reduce(watch_dog_q);
  err_d (0) <= (cache_resp_hit and not ex_hit_q) and not or_reduce (state_q xor ST_WAIT);
  err_d (1) <= ((cache_resp_miss and ex_hit_q) and not or_reduce (state_q xor ST_WAIT)) or
               (cache_resp_miss and not or_reduce(state_q xor ST_RLD_WAIT));
  err_d(2) <= cache_resp_miss and (cache_resp_dirty and not ex_dirty_q);
  err_d(3) <= cache_resp_miss and (not cache_resp_dirty and  ex_dirty_q);
  err_d(4) <= cache_co_vld and or_reduce(ex_co_tag_q xor cache_co_addr(31 downto 13));
  err_d(5) <= cache_co_vld and or_reduce(addr_q(12 downto 6) xor cache_co_addr(12 downto 6));
  err_d(6) <= '0' when cache_co_vld = '0' else
              '1' when state_q = ST_CO_0 and cache_co_addr(5 downto 4) /= "00" else
              '1' when state_q = ST_CO_1 and cache_co_addr(5 downto 4) /= "01" else
              '1' when state_q = ST_CO_2 and cache_co_addr(5 downto 4) /= "10" else
              '1' when state_q = ST_CO_3 and cache_co_addr(5 downto 4) /= "11" else
              '0';
  err_d(7) <= cache_resp_hit and not ex_st_q and or_reduce(cache_data_out(63 downto 0) xor ex_data_q);
  err_d(8) <= (cache_resp_hit or cache_resp_miss) and
              not or_reduce(state_q xor ST_WAIT) and 
              not or_reduce(state_q xor ST_RLD_WAIT);
  err_d(9) <= cache_co_vld and (not state_q(3) or state_q(2));
  co_chk: for i in 3 downto 0 generate
    err_d(10 + i) <= cache_co_vld and or_reduce(cache_data_out(31+32*i downto 32*i) xor test_rom_rd_data(31+32*i downto 32*i));
  end generate co_chk;

  ex_co_addr_off_d <= "00" when state_q = ST_CO_0 else
                      "01" when state_q = ST_CO_1 else
                      "10" when state_q = ST_CO_2 else
                      "11" ;
  ex_co_addr: reg generic map (hi => 1)
    port map (clk=> clk, rst=> rst, en => state_q(3) and not state_q(2), d=> ex_co_addr_off_d, q=>ex_co_addr_off_q);						  
  
  err_d (16 downto 14) <= "000" when watchdog_timeout = '0' else
                          "001" when state_q = ST_WAIT and ex_hit_q /= '0' else
                          "010" when state_q = ST_WAIT else
                          "011" when state_q = ST_RLD_WAIT else
                          "100" when state_q = ST_CO_0 else
                          "101" when state_q = ST_CO_1 else
                          "110" when state_q = ST_CO_2 else
                          "111";	
  err_d (17) <= (state_q (3) and state_q(2) and not (test_rom_rd_data(129) and test_rom_rd_data(128))) or
                (state_q (3) and not state_q(2) and not (test_rom_rd_data(129) and not test_rom_rd_data(128))) or
                (etype_q(1) and not or_reduce(state_q xor ST_SEND));
  
  err: reg generic map (hi => 17)
    port map (clk => clk, rst => rst, d => err_d, q=> err_q, en =>  or_reduce(state_q xor ST_ERR));

  
-----
-- Test rom and trace processing
---


  tr: testrom port map (
    address => test_rom_rd_addr_d,
    clock => clk,
    q => test_rom_rd_data);
  
  update_rom_addr <= ((not or_reduce(state_q xor ST_SEND)) or 
                      (state_q(3) and (state_q(2) or cache_co_vld)));    --all rld states (and co states when co_vld)						  
  
  latch_rom_data <=     not or_reduce(state_q xor ST_NEXT);

  tr_addr: reg generic map (hi => 10)
    port map (clk => clk, 
              rst => rst,
              d => test_rom_rd_addr_d,
              q => test_rom_rd_addr_q,
              en => update_rom_addr);
  
  addr_adder: rcaddr generic map (hi => 10)
    port map (a => test_rom_rd_addr_q, b=> "00000000001", sum=> test_rom_rd_addr_temp, ci => '0');

  test_rom_rd_addr_d <= (others => '0') when rst /= '0' else
                        test_rom_rd_addr_q when update_rom_addr = '0' else
                        test_rom_rd_addr_temp;

  etype: reg  generic map (hi => 1)
    port map (clk => clk,
              d => test_rom_rd_data (129 downto 128),
              q => etype_q,
              rst => rst,
              en => latch_rom_data);
  
  ex_st: dffe port map (
    clk=> clk,
    d=> test_rom_rd_data(42+64),
    q=>ex_st_q,
    ena => latch_rom_data,
    clrn => not rst,
    prn => '1');	
  ex_miss: dffe port map (
    clk=> clk,
    d=> test_rom_rd_data(43+64),
    q=>ex_miss_q,
    ena => latch_rom_data,
    clrn => not rst,
    prn => '1');				
  
  ex_hit_q <= not ex_miss_q;

  ex_dirty :  dffe port map (
    clk=> clk,
    d=> test_rom_rd_data(44+64),
    q=>ex_dirty_q,
    ena => latch_rom_data,
    clrn => not rst,
    prn => '1');	
  ex_data: reg generic map (hi => 63)
    port map (clk => clk,
              d => test_rom_rd_data (63 downto 0),
              q => ex_data_q,
              rst => rst,
              en => latch_rom_data);
  ex_co_tag: reg generic map (hi => 18)
    port map (clk => clk,
              d => test_rom_rd_data (127 downto 45+64),
              q => ex_co_tag_q,
              rst => rst,
              en => latch_rom_data);			
  
  addr: reg generic map (hi => 31, lo => 3)
    port map (clk => clk,
              d => test_rom_rd_data (95 downto 64+3),
              q => addr_q,
              rst => rst,
              en => latch_rom_data);							  

  outnum (10 downto 0) <= test_rom_rd_addr_q;
  outnum (15 downto 11) <= (others=> '0');
  outnum (19 downto 16) <= non_err_state_q;
  outnum (20) <= ex_hit_q;
  outnum (21) <= ex_st_q;
  outnum (22) <= ex_dirty_q;
  outnum (23) <= '0';
  outnum (31 downto 24) <= cache_debug_info;


  ex_info_co_addr(31 downto 13) <= ex_co_tag_q;
  ex_info_co_addr(12 downto 6) <= addr_q(12 downto 6);
  ex_info_co_addr(5 downto 4) <= ex_co_addr_off_q;
  ex_info_co_addr(3 downto 0) <= "0000";
  
  ex_info <= cache_co_addr_q when sw ="0001" else	
             ex_info_co_addr when sw="1001" else
             cache_data_out_q(31 downto 0) when sw = "0010" else  
             cache_data_out_q(63 downto 32) when sw = "0011" else
             ex_data_q (31 downto 0) when sw ="1010" else
             ex_data_q (63 downto 32) when sw="1011" else
             cache_data_out_q(31 downto 0) when sw = "0100" else  
             cache_data_out_q(63 downto 32) when sw = "0101" else  
             cache_data_out_q(95 downto 64) when sw = "0110" else
             cache_data_out_q(127 downto 96) when sw = "0111" else
             test_rom_rd_data(31 downto 0) when sw = "1100" else  
             test_rom_rd_data(63 downto 32) when sw = "1101" else  
             test_rom_rd_data(95 downto 64) when sw = "1110" else
             test_rom_rd_data(127 downto 96) when sw = "1111" else
             
             outnum;
  
  

  
  led7out: for i in 7 downto 0 generate
    signal temp: std_logic_vector (15 downto 0);
  begin
    e: encoder port map (
      din => ex_info(4*i + 3 downto 4*i),
      dout => temp);
    l: led port map (
      din => temp,
      dout => led7s_temp(7*i +6 downto 7*i));
  end generate led7out;				
  
  
  led7s <= led7s_temp when state_q = ST_FIN or state_q = ST_ERR or sstep = '1' else (others => '1');
  
  
  
  ledg <= "11111111" when state_q = ST_FIN else 
          "00000000" when state_q = ST_ERR else 
          etype_q & "001010" when sstep = '1' else
          "00000001";
  ledr <= err_q;
end basic;
