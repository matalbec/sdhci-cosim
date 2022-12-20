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

  type mem_cycle_state is (idle, cycle_begin, cycle_done);
  signal current_state : mem_cycle_state := idle;

begin

  process (pci_clk) is
  begin
    case current_state is
      when idle =>
        cycle_active <= '0';
        data_tx <= (others => '0');
        if cycle_req = '1' then
          current_state <= cycle_begin;
        else
          current_state <= idle;
        end if;
      when cycle_begin =>
        cycle_active <= '1';
        if wr_en = '1' then
          case addr is
            when others =>
              report "invalid address" severity warning;
          end case;
        else
          case addr is
            when others =>
              report "invalid address" severity warning;
              data_tx <= (others => '1'); -- return all FF for invalid addresses
          end case;
        end if;
        current_state <= cycle_done;
      when cycle_done =>
        cycle_active <= '0';
        if cycle_req = '0' then
          data_tx <= (others => '0');
          current_state <= idle;
        else
          data_tx <= data_tx;
          current_state <= cycle_done;
        end if;
      when others =>
        report "invalid state" severity error;
        current_state <= idle;
    end case;
  end process;

end architecture behavioral;
