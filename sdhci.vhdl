library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity sdhci_pci_interface is
  port (
         cycle_req : in std_ulogic;
         cycle_active : out std_ulogic := '0';
         mem_cycl_en : in std_ulogic;
         wr_en : in std_ulogic;

         addr : in std_ulogic_vector(31 downto 0);
         data_tx : out std_ulogic_vector(31 downto 0) := (others => '0');
         data_rx : in std_ulogic_vector(31 downto 0);

         pci_clk : in std_ulogic
       );
end sdhci_pci_interface;

architecture behavioral of sdhci_pci_interface is
  type t_pci_config is array (0 to 30) of std_ulogic_vector(31 downto 0);
  type t_membar is array (0 to 30) of std_ulogic_vector(31 downto 0);
  signal pci_config : t_pci_config := (X"80811112", X"12345678", others => (others => '0'));
  signal membar : t_membar := (X"11223344" ,others => (others => '0'));

  signal cycle_complete : std_ulogic := '0';
begin

  process (pci_clk) is
  begin
    if rising_edge (pci_clk) then

      if cycle_req = '1' and cycle_complete = '0' then
        cycle_active <= '1';

        if mem_cycl_en = '1' then
          if wr_en = '1' then
            membar(to_integer(unsigned(addr))) <= data_rx;
          else
            data_tx <= membar(to_integer(unsigned(addr)));
          end if;
        else
          if wr_en = '1' then
            pci_config(to_integer (unsigned(addr))) <= data_rx;
          else
            data_tx <= pci_config(to_integer (unsigned(addr)));
          end if;
        end if;

        cycle_complete <= '1';

      elsif cycle_req = '0' and cycle_complete = '1' then
        cycle_active <= '0';
        cycle_complete <= '0';
        data_tx <= (others => '0');
      end if;
    end if;
  end process;

end architecture behavioral;
