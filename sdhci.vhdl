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
         width : in std_ulogic_vector(1 downto 0); -- 0 = byte, 1, = word, 2 - dword
         data_tx : out std_ulogic_vector(31 downto 0) := (others => '0');
         data_rx : in std_ulogic_vector(31 downto 0);

         pci_clk : in std_ulogic
       );
end sdhci_pci_interface;

architecture behavioral of sdhci_pci_interface is
  type t_pci_config is array (0 to 120) of std_ulogic_vector(7 downto 0);
  type t_membar is array (0 to 120) of std_ulogic_vector(7 downto 0);
  signal pci_config : t_pci_config := (others => (others => '0'));
  signal membar : t_membar := (36 => X"AA", 37 => X"AB", 38 => X"CC", 39 => X"DD",others => (others => '0'));

  signal cycle_complete : std_ulogic := '0';
begin

  process (pci_clk) is
  begin
    if rising_edge (pci_clk) then

      if cycle_req = '1' and cycle_complete = '0' then
        cycle_active <= '1';

        if mem_cycl_en = '1' then
          if wr_en = '1' then
            if width = X"0" then -- byte
              membar(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
            elsif width = X"1" then -- word
              membar(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
              membar(to_integer(unsigned(addr) + 1)) <= data_rx(15 downto 8);
            else -- dword and default case
              membar(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
              membar(to_integer(unsigned(addr) + 1)) <= data_rx(15 downto 8);
              membar(to_integer(unsigned(addr) + 2)) <= data_rx (23 downto 16);
              membar(to_integer(unsigned(addr) + 3)) <= data_rx (31 downto 24);
            end if;
          else
            if width = X"0" then -- byte
              data_tx(7 downto 0) <= membar(to_integer(unsigned(addr)));
            elsif width = X"1" then -- word
              data_tx(7 downto 0) <= membar(to_integer(unsigned(addr)));
              data_tx(15 downto 8) <= membar(to_integer(unsigned(addr) + 1));
            else -- dword and default case
              data_tx(7 downto 0) <= membar(to_integer(unsigned(addr)));
              data_tx(15 downto 8) <= membar(to_integer(unsigned(addr) + 1));
              data_tx(23 downto 16) <= membar(to_integer(unsigned(addr) + 2));
              data_tx(31 downto 24) <= membar(to_integer(unsigned(addr) + 3));
            end if;
          end if;
        else
          if wr_en = '1' then
            if width = X"0" then -- byte
              pci_config(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
            elsif width = X"1" then -- word
              pci_config(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
              pci_config(to_integer(unsigned(addr) + 1)) <= data_rx(15 downto 8);
            else -- dword and default case
              pci_config(to_integer(unsigned(addr))) <= data_rx(7 downto 0);
              pci_config(to_integer(unsigned(addr) + 1)) <= data_rx(15 downto 8);
              pci_config(to_integer(unsigned(addr) + 2)) <= data_rx (23 downto 16);
              pci_config(to_integer(unsigned(addr) + 3)) <= data_rx (31 downto 24);
            end if;
          else
            if width = X"0" then -- byte
              data_tx(7 downto 0) <= pci_config(to_integer(unsigned(addr)));
            elsif width = X"1" then -- word
              data_tx(7 downto 0) <= pci_config(to_integer(unsigned(addr)));
              data_tx(15 downto 8) <= pci_config(to_integer(unsigned(addr) + 1));
            else -- dword and default case
              data_tx(7 downto 0) <= pci_config(to_integer(unsigned(addr)));
              data_tx(15 downto 8) <= pci_config(to_integer(unsigned(addr) + 1));
              data_tx(23 downto 16) <= pci_config(to_integer(unsigned(addr) + 2));
              data_tx(31 downto 24) <= pci_config(to_integer(unsigned(addr) + 3));
            end if;
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
