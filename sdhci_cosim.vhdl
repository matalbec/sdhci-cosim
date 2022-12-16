library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdhci_cosim is
end;

architecture behavioral of sdhci_cosim is
  constant clock_period : time := 1 ns;

  signal clk : std_ulogic := '0';

  signal wr_en : std_ulogic := '0';
  signal addr : std_ulogic_vector(31 downto 0) := X"00000000";
  signal data_rx : std_ulogic_vector(31 downto 0) := (others => 'Z');
  signal data_tx : std_ulogic_vector(31 downto 0) := (others => '0');

  signal mem_cycl_en : std_ulogic := '0';
  signal cycle_req : std_ulogic := '0';
  signal cycle_active : std_ulogic;

  component sdhci_pci_interface is
    port (
         cycle_req : in std_ulogic;
         cycle_active : out std_ulogic;
         mem_cycl_en : in std_ulogic;
         wr_en : in std_ulogic;

         addr : in std_ulogic_vector(31 downto 0);
         data_tx : out std_ulogic_vector(31 downto 0);
         data_rx : in std_ulogic_vector(31 downto 0);

         pci_clk : in std_ulogic
    );
  end component;
begin

  UUT : sdhci_pci_interface
  port map (
    cycle_req => cycle_req,
    cycle_active => cycle_active,
    mem_cycl_en => mem_cycl_en,
    wr_en => wr_en,

    addr => addr,
    data_tx => data_rx,
    data_rx => data_tx,

    pci_clk => clk
  );

  process is
  begin
    wait for clock_period/2;
    clk <= not clk;
  end process;
end;
