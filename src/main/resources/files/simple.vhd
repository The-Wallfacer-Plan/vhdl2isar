entity div32 is
generic (scantest  : integer := 0);
port (
    rst     : in  std_ulogic;
    clk     : in  std_ulogic;
    holdn   : in  std_ulogic;
    divi    : in  div32_in_type;
    divo    : out div32_out_type;
    testen  : in  std_ulogic := '0';
    testrst : in  std_ulogic := '1'
);
end;

architecture rtl of div32 is

type div_regtype is record
  x      : std_logic_vector(64 downto 0);
  state  : std_logic_vector(2 downto 0);
  zero   : std_logic;
  zero2  : std_logic;
  qcorr  : std_logic;
  zcorr  : std_logic;
  qzero  : std_logic;
  qmsb   : std_logic;
  ovf    : std_logic;
  neg    : std_logic;
  cnt    : std_logic_vector(4 downto 0);
end record;

-- constant definition
-- constant RESET_ALL : boolean := GRLIB_CONFIG_ARRAY(grlib_sync_reset_enable_all) = 1;
constant RESET_ALL : boolean := true;
-- constant ASYNC_RESET : boolean := GRLIB_CONFIG_ARRAY(grlib_async_reset_enable) = 1;
constant ASYNC_RESET : boolean := true;
constant RRES : div_regtype := (
  x      => (others => '0'),
  state  => (others => '0'),
  zero   => '0',
  zero2  => '0',
  qcorr  => '0',
  zcorr  => '0',
  qzero  => '0',
  qmsb   => '0',
  ovf    => '0',
  neg    => '0',
  cnt    => (others => '0'));


signal arst   : std_ulogic;
signal r, rin : div_regtype;
signal addin1, addin2, addout: std_logic_vector(32 downto 0);
signal addsub : std_logic;

-------------------------------------------------------------------------
-------------------------------------------------------------------------

begin

  --- concurrent_signal_assignment_statement
  arst <= testrst when (ASYNC_RESET and scantest/=0 and testen/='0') else
          rst when ASYNC_RESET else
          '1';
  -----------------------------------------------------------------------

  --- process_statement
  divcomb : process (r, rst, divi, addout)

  variable v : div_regtype;
  variable vready, vnready : std_logic;
  variable vaddin1, vaddin2 : std_logic_vector(32 downto 0);
  variable vaddsub, ymsb : std_logic;
  constant zero33: std_logic_vector(32 downto 0) := "000000000000000000000000000000000";
  begin

    vready := '0'; vnready := '0'; v := r;
    if addout = zero33 then v.zero := '1'; else v.zero := '0'; end if;

    vaddin1 := r.x(63 downto 31); vaddin2 := divi.op2;
    vaddsub := not (divi.op2(32) xor r.x(64));
    v.zero2 := r.zero;

    case r.state is
    when "000" =>
      v.cnt := "00000";
      if (divi.start = '1') then
	v.x(64) := divi.y(32); v.state := "001";
      end if;
    when "001" =>
      v.x := divi.y & divi.op1(31 downto 0);
      v.neg := divi.op2(32) xor divi.y(32);
      if divi.signed = '1' then
        vaddin1 := divi.y(31 downto 0) & divi.op1(31);
        v.ovf := not (addout(32) xor divi.y(32));
      else
        vaddin1 := divi.y; vaddsub := '1';
        v.ovf := not addout(32);
      end if;
      v.state := "010";
    when "010" =>
      if ((divi.signed and r.neg and r.zero) = '1') and (divi.op1 = zero33) then v.ovf := '0'; end if;
      v.qmsb := vaddsub; v.qzero := '1';
      v.x(64 downto 32) := addout;
      v.x(31 downto 0) := r.x(30 downto 0) & vaddsub;
      v.state := "011"; v.zcorr := v.zero;
      v.cnt := r.cnt + 1;
    when "011" =>
      v.qzero := r.qzero and (vaddsub xor r.qmsb);
      v.zcorr := r.zcorr or v.zero;
      v.x(64 downto 32) := addout;
      v.x(31 downto 0) := r.x(30 downto 0) & vaddsub;
      if (r.cnt = "11111") then v.state := "100"; vnready := '1';
      else v.cnt := r.cnt + 1; end if;
      v.qcorr := v.x(64) xor divi.y(32);
    when "100" =>
      vaddin1 := r.x(64 downto 32);
      v.state := "101";
    when others =>
      vaddin1 := ((not r.x(31)) & r.x(30 downto 0) & '1');
      vaddin2 := (others => '0'); vaddin2(0) := '1';
      vaddsub := (not r.neg);-- or (r.zcorr and not r.qcorr);
      if ((r.qcorr = '1')  or (r.zero = '1')) and (r.zero2 = '0') then
        if (r.zero = '1') and ((r.qcorr = '0') and (r.zcorr = '1')) then
	   vaddsub := r.neg; v.qzero := '0';
	end if;
        v.x(64 downto 32) := addout;
      else
        v.x(64 downto 32) := vaddin1; v.qzero := '0';
      end if;
      if (r.ovf = '1') then
	v.qzero := '0';
        v.x(63 downto 32) := (others => '1');
        if divi.signed = '1' then
          if r.neg = '1' then v.x(62 downto 32) := (others => '0');
	  else v.x(63) := '0'; end if;
	end if;
      end if;
      vready := '1';
      v.state := "000";
    end case;

    divo.icc <= r.x(63) & r.qzero & r.ovf & '0';
    if (divi.flush = '1') then v.state := "000"; end if;
    if (not ASYNC_RESET) and (not RESET_ALL) and (rst = '0') then
      v.state := RRES.state; v.cnt := RRES.cnt;
    end if;
    rin <= v;
    divo.ready <= vready; divo.nready <= vnready;
    divo.result(31 downto 0) <= r.x(63 downto 32);
    addin1 <= vaddin1; addin2 <= vaddin2; addsub <= vaddsub;

  end process;
  -----------------------------------------------------------------------

  --- process_statement
  divadd : process(addin1, addin2, addsub)
  variable b : std_logic_vector(32 downto 0);
  begin
    if addsub = '1' then b := not addin2; else b := addin2; end if;
    addout <= addin1 + b + addsub;
  end process;
  -----------------------------------------------------------------------

  --- generate_statement
  syncrregs : if not ASYNC_RESET generate
    reg : process(clk)
    begin
      -- if rising_edge(clk) then
      if (clk = '0') then
        if (holdn = '1') then r <= rin; end if;
        if (rst = '0') then
          if RESET_ALL then
            r <= RRES;
          else
            r.state <= RRES.state; r.cnt <= RRES.cnt;
          end if;
        end if;
      end if;
    end process;
  end generate syncrregs;
  -----------------------------------------------------------------------

  --- generate_statement
  asyncrregs : if ASYNC_RESET generate
    reg : process(clk, arst)
    begin
      if (arst = '0') then
        r <= RRES;
--      elsif rising_edge(clk) then
      elsif (clk = '0') then
        if (holdn = '1') then r <= rin; end if;
      end if;
    end process;
  end generate asyncrregs;
  -----------------------------------------------------------------------

end;
-------------------------------------------------------------------------
-------------------------------------------------------------------------
