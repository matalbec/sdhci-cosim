library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdhci_pci_interface is
  port (
         cycle_req : in std_ulogic;
         cycle_done : out std_ulogic := '0';
         mem_cycl_en : in std_ulogic;
         wr_en : in std_ulogic;

         addr : in std_ulogic_vector(31 downto 0);
         data : inout std_ulogic_vector(31 downto 0) := (others => 'Z');

         pci_clk : in std_ulogic
       );
end sdhci_pci_interface;

architecture behavioral of sdhci_pci_interface is
  type t_pci_config is array (0 to 30) of std_ulogic_vector(31 downto 0);
  type t_membar is array (0 to 30) of std_ulogic_vector(31 downto 0);
  signal pci_config : t_pci_config := (X"80811112", others => X"00000000");
  signal membar : t_membar := (X"11223344" ,others => X"00000000");

  signal cycle_complete : std_ulogic := '0';
  signal tx_data_internal : std_ulogic_vector(31 downto 0) := (others => '0');
  signal tx_enable : std_ulogic := '0';

begin

  process (pci_clk) is
  begin
    if rising_edge (pci_clk) then
      if cycle_req = '1' and cycle_complete = '0' then
        if mem_cycl_en = '1' then
          if wr_en = '1' then
            membar(to_integer(unsigned(addr))) <= data;
          else
            tx_data_internal <= membar(to_integer(unsigned(addr)));
            tx_enable <= '1';
          end if;
        else
          if wr_en = '1' then
            pci_config(to_integer (unsigned(addr))) <= data;
          else
            tx_data_internal <= pci_config(to_integer (unsigned(addr)));
            tx_enable <= '1';
          end if;
        end if;
        cycle_complete <= '1';
        cycle_done <= '1';
        tx_enable <= '0';
        data <= tx_data_internal when tx_enable = '0' else (others => 'Z');
      elsif cycle_req = '0' and cycle_complete = '1' then
        cycle_done <= '0';
        cycle_complete <= '0';
      end if;
    end if;
  end process;

end architecture behavioral;
