library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdhci_test is
end;

architecture behavioral of sdhci_test is
  constant clock_period : time := 1 ns;

  signal clk : std_ulogic := '0';

  signal wr_en : std_ulogic := '0';
  signal addr : std_ulogic_vector(31 downto 0) := X"00000000";
  signal data : std_ulogic_vector(31 downto 0) := (others => 'Z');

  signal mem_cycl_en : std_ulogic := '0';
  signal cycle_req : std_ulogic := '0';
  signal cycle_done : std_ulogic;

  component sdhci_pci_interface is
    port (
         cycle_req : in std_ulogic;
         cycle_done : out std_ulogic;
         mem_cycl_en : in std_ulogic;
         wr_en : in std_ulogic;

         addr : in std_ulogic_vector(31 downto 0);
         data : inout std_ulogic_vector(31 downto 0);

         pci_clk : in std_ulogic
    );
  end component;
begin

  UUT : sdhci_pci_interface
  port map (
    cycle_req => cycle_req,
    cycle_done => cycle_done,
    mem_cycl_en => mem_cycl_en,
    wr_en => wr_en,

    addr => addr,
    data => data,

    pci_clk => clk

  );

  process is
  begin
    wait for clock_period/2;
    clk <= not clk;
  end process;

  process is
  begin
    wait for clock_period;
    addr <= X"00000000";
    cycle_req <= '1';
    wait for clock_period;
    if cycle_done = '1' then
      cycle_req <= '0';
    end if;
    wait for clock_period * 2;

    addr <= X"00000001";
    --data <= X"AAAAAAAB";
    wr_en <= '1';
    cycle_req <= '1';
    wait for clock_period * 3;
    if cycle_done = '1' then
      cycle_req <= '0';
      --data <= (others => 'Z');
      wr_en <= '0';
    end if;
    wait for clock_period;

    mem_cycl_en <= '1';
    addr <= X"00000000";
    cycle_req <= '1';
    wait for clock_period;
    if cycle_done = '1' then
      cycle_req <= '0';
    end if;
    wait for clock_period;

    --addr <= X"00000001";
    --data <= X"AAAABBBB";
    --wr_en <= '1';
    --cycle_req <= '1';
    --wait for clock_period;
    --if cycle_done = '1' then
     -- cycle_req <= '0';
     -- data <= (others => 'Z');
     -- wr_en <= '0';
    --end if;
  end process;
end;
