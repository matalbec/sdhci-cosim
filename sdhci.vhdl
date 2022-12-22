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
         byte_enable : in std_ulogic_vector(3 downto 0);
         data_tx : out std_ulogic_vector(31 downto 0) := (others => '0');
         data_rx : in std_ulogic_vector(31 downto 0);

         pci_clk : in std_ulogic
       );
end sdhci_pci_interface;

architecture behavioral of sdhci_pci_interface is

  type mem_cycle_state is (idle, cycle_begin, write_hold, cycle_done);
  signal current_state : mem_cycle_state := idle;
  signal clock_count : integer := 0;

  signal present_state : std_ulogic_vector(31 downto 0) := (others => '0');
  constant present_state_addr : natural := 36;

  signal interrupt_reg : std_ulogic_vector(31 downto 0) := (others => '0');
  signal interrupt_reg_upd : std_ulogic_vector(31 downto 0) := (others => '0');
  signal interrupt_reg_int : std_ulogic_vector(31 downto 0) := (others => '0');
  signal int_upd : std_ulogic := '0';
  constant interrupt_reg_addr : natural := 48;

  signal host_ctl1_reg : std_ulogic_vector(7 downto 0) := (others => '0');
  signal host_ctl1_reg_upd : std_ulogic_vector(7 downto 0) := (others => '0');
  signal ctl_upd : std_ulogic := '0';
  constant host_ctl1_addr : natural := 40;

  signal block_size_reg : std_ulogic_vector(15 downto 0) := (others => '0');
  signal block_size_reg_upd : std_ulogic_vector(15 downto 0) := (others => '0');
  signal block_count_reg : std_ulogic_vector(15 downto 0) := (others => '0');
  signal block_count_reg_upd : std_ulogic_vector(15 downto 0) := (others => '0');
  signal block_size_upd : std_ulogic := '0';
  signal block_count_upd : std_ulogic := '0';
  constant block_size_addr : natural := 4;

  signal argument_reg : std_ulogic_vector(31 downto 0) := (others => '0');
  signal argument_reg_upd : std_ulogic_vector(31 downto 0) := (others => '0');
  signal argument_upd : std_ulogic := '0';
  constant argument_addr : natural := 8;

  signal transfer_mode_reg : std_ulogic_vector(15 downto 0) := (others => '0');
  signal transfer_mode_reg_upd : std_ulogic_vector(15 downto 0) := (others => '0');
  signal transfer_mode_upd : std_ulogic := '0';
  constant transfer_mode_addr : natural := 12;

  signal command_reg : std_ulogic_vector(15 downto 0) := (others => '0');
  signal command_reg_upd : std_ulogic_vector(15 downto 0) := (others => '0');
  signal command_upd : std_ulogic := '0';
  signal cmd_upd_clock : integer := 0;
  signal cmd_start : std_ulogic := '0';

  type t_response_reg is array(3 downto 0) of std_ulogic_vector(31 downto 0);
  signal response_reg : t_response_reg := (others => (others => '0'));
  constant response_reg_addr : natural := 16;

  signal cmd_done_int : std_ulogic := '0';
  signal wrt_buf_rdy_int : std_ulogic := '0';
  signal rd_buf_rdy_int : std_ulogic := '0';
  signal buffer_size : integer := 0;
  signal direction : std_ulogic := '0';
  signal cmd_clock : integer := 0;

  signal transfer_start : std_ulogic := '0';
  signal buf_data_port_reg_upd : std_ulogic_vector(31 downto 0) := (others => '0');
  signal buf_data_port_upd : std_ulogic := '0';
  signal buf_data_port_rd : std_ulogic := '0';
  constant buf_data_port_addr : natural := 32;

  type t_data_block is array(127 downto 0) of std_ulogic_vector(31 downto 0);
  signal data_block : t_data_block := (others => (others => '0'));

  type t_command_process_state is (idle, start, wait_for_transfer_start, done);
  signal command_state : t_command_process_state := idle;

  type t_transfer_process_state is (idle, start, in_progress, done);
  signal transfer_state : t_transfer_process_state := idle;
  signal transfer_rdy : std_ulogic := '0';
  signal transfer_complete : std_ulogic := '0';
  signal transfer_clock : integer := 0;
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
        if mem_cycl_en = '1' then
          if wr_en = '1' then
            case to_integer(unsigned(addr)) is
              when block_size_addr =>
                if byte_enable(1 downto 0) = b"11" then
                  block_size_reg_upd <= data_rx(15 downto 0);
                  block_size_upd <= '1';
                else
                  block_size_reg_upd <= (others => '0');
                  block_size_upd <= '0';
                end if;
                if byte_enable (3 downto 2) = b"11" then
                  block_count_reg_upd <= data_rx (31 downto 16);
                  block_count_upd <= '1';
                else
                  block_count_reg_upd <= (others => '0');
                  block_count_upd <= '0';
                end if;
              when argument_addr =>
                argument_reg_upd <= data_rx(31 downto 0);
                argument_upd <= '1';
              when transfer_mode_addr =>
                if byte_enable(1 downto 0) = b"11" then
                  transfer_mode_reg_upd <= data_rx(15 downto 0);
                  transfer_mode_upd <= '1';
                else
                  transfer_mode_reg_upd <= (others => '0');
                  transfer_mode_upd <= '0';
                end if;
                if byte_enable(3 downto 2) = b"11" then
                  command_reg_upd <= data_rx(31 downto 16);
                  command_upd <= '1';
                else
                  command_reg_upd <= (others => '0');
                  command_upd <= '0';
                end if;
              when buf_data_port_addr =>
                buf_data_port_reg_upd <= data_rx(31 downto 0);
                buf_data_port_upd <= '1';
              when host_ctl1_addr =>
                host_ctl1_reg_upd <= data_rx(7 downto 0);
                ctl_upd <= '1';
              when interrupt_reg_addr =>
                if byte_enable(1 downto 0) = b"11" then
                  interrupt_reg_upd(15 downto 0) <= data_rx(15 downto 0);
                else
                  interrupt_reg_upd(15 downto 0) <= (others => '0');
                end if;
                if byte_enable(3 downto 2) = b"11" then
                  interrupt_reg_upd(31 downto 16) <= data_rx(31 downto 16);
                else
                  interrupt_reg_upd(31 downto 16) <= (others => '0');
                end if;
                interrupt_reg_upd <= data_rx;
                int_upd <= '1';
              when others =>
                report "invalid address" severity warning;
            end case;
            current_state <= write_hold;
            clock_count <= 2;
          else
            case to_integer(unsigned(addr)) is
              when block_size_addr =>
                if byte_enable(1 downto 0) = b"11" then
                  data_tx(15 downto 0) <= block_size_reg;
                else
                  data_tx(15 downto 0) <= (others => '1');
                end if;
                if byte_enable(3 downto 2) = b"11" then
                  data_tx(31 downto 16) <= block_count_reg;
                else
                  data_tx(31 downto 16) <= (others => '1');
                end if;
              when argument_addr =>
                data_tx (31 downto 0) <= argument_reg;
              when transfer_mode_addr =>
                data_tx (15 downto 0) <= transfer_mode_reg;
                data_tx (31 downto 16) <= command_reg;
              when response_reg_addr =>
                data_tx (31 downto 0) <= response_reg(0);
              when response_reg_addr + 4 =>
                data_tx (31 downto 0) <= response_reg(1);
              when response_reg_addr + 8 =>
                data_tx(31 downto 0) <= response_reg(2);
              when response_reg_addr + 12 =>
                data_tx(31 downto 0) <= response_reg(3);
              when buf_data_port_addr =>
                data_tx(31 downto 0) <= data_block(buffer_size);
                buf_data_port_rd <= '1';
                clock_count <= 2;
              when host_ctl1_addr =>
                data_tx(7 downto 0) <= host_ctl1_reg;
                data_tx(31 downto 8) <= (others => '1');
              when present_state_addr =>
                data_tx <= (others => '0');
              when interrupt_reg_addr =>
                data_tx <= interrupt_reg;
              when others =>
                report "invalid address" severity warning;
                data_tx <= (others => '1'); -- return all FF for invalid addresses
            end case;
            current_state <= write_hold when to_integer(unsigned(addr)) = buf_data_port_addr else cycle_done;
          end if;
        else -- pci config not implemented yet
          data_tx <= (others => '1');
          current_state <= cycle_done;
        end if;
      when write_hold =>
        if clock_count = 0 then
          current_state <= cycle_done;
        else
          clock_count <= clock_count - 1;
        end if;
      when cycle_done =>
        cycle_active <= '0';
        clock_count <= 0;
        int_upd <= '0';
        ctl_upd <= '0';
        block_size_upd <= '0';
        block_count_upd <= '0';
        argument_upd <= '0';
        command_upd <= '0';
        transfer_mode_upd <= '0';
        buf_data_port_upd <= '0';
        buf_data_port_rd <= '0';
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

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if int_upd = '1' then
        interrupt_reg <= interrupt_reg and (not (interrupt_reg or interrupt_reg_upd));
      elsif cmd_done_int = '1' then
        if rd_buf_rdy_int = '1' then
          interrupt_reg <= interrupt_reg or X"00000021";
        elsif wrt_buf_rdy_int = '1' then
          interrupt_reg <= interrupt_reg or X"00000011";
        else
          interrupt_reg <= interrupt_reg or X"00000001";
        end if;
      elsif transfer_complete = '1' then
        interrupt_reg <= interrupt_reg or X"00000002";
      else
        interrupt_reg <= interrupt_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if ctl_upd = '1' then
        host_ctl1_reg <= host_ctl1_reg_upd;
      else
        host_ctl1_reg <= host_ctl1_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if block_size_upd = '1' then
        block_size_reg <= block_size_reg_upd;
      else
        block_size_reg <= block_size_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if block_count_upd = '1' then
        block_count_reg <= block_count_reg_upd;
      else
        block_count_reg <= block_count_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if argument_upd = '1' then
        argument_reg <= argument_reg_upd;
      else
        argument_reg <= argument_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if transfer_mode_upd = '1' then
        transfer_mode_reg <= transfer_mode_reg_upd;
      else
        transfer_mode_reg <= transfer_mode_reg;
      end if;
    end if;
  end process;

  process (pci_clk) is
  begin
    if rising_edge(pci_clk) then
      if command_upd = '1' then
        command_reg <= command_reg_upd;
        cmd_start <= '1';
        cmd_upd_clock <= 2;
      else
        if cmd_upd_clock = 0 then
          cmd_start <= '0';
        else
          cmd_upd_clock <= cmd_upd_clock - 1;
        end if;
        command_reg <= command_reg;
      end if;
    end if;
  end process;

  cmd_process: process (pci_clk) is
  begin

   if rising_edge(pci_clk) then
     case command_state is
       when idle =>
         if cmd_start = '1' then
           command_state <= start;
          else
            command_state <= idle;
         end if;
       when start =>
         if transfer_mode_reg(4) = '1' then
           rd_buf_rdy_int <= '1';
         else
           wrt_buf_rdy_int <= '1';
         end if;
         transfer_start <= '1';
         command_state <= wait_for_transfer_start;
         cmd_clock <= 2;
       when wait_for_transfer_start =>
         if transfer_state = in_progress then
           command_state <= done;
         else
           command_state <= wait_for_transfer_start;
         end if;
       when done =>
         transfer_start <= '0';
         if cmd_clock = 0 then
           command_state <= idle;
           cmd_done_int <= '0';
           rd_buf_rdy_int <= '0';
           wrt_buf_rdy_int <= '0';
         else
           command_state <= done;
           cmd_done_int <= '1';
           cmd_clock <= cmd_clock - 1;
         end if;
     end case;
   end if;
  end process;

  transfer_process: process (pci_clk) is
  begin
    if rising_edge (pci_clk) then
      case transfer_state is
        when idle =>
          transfer_complete <= '0';
          if transfer_start = '1' then
            transfer_state <= start;
          else
            transfer_state <= idle;
          end if;
        when start =>
          transfer_state <= in_progress;
          buffer_size <= 127;
          transfer_clock <= 2;
          if wrt_buf_rdy_int = '1' then
            direction <= '1';
          elsif rd_buf_rdy_int = '1' then
            direction <= '0';
          end if;
        when in_progress =>
          if buffer_size = 0 then
            transfer_state <= done;
          end if;
          if buf_data_port_upd = '1' and direction = '1' then
            data_block(buffer_size) <= buf_data_port_reg_upd;
            buffer_size <= buffer_size - 1;
          elsif buf_data_port_rd = '1' and direction = '0' then
            buffer_size <= buffer_size - 1;
          end if;
        when done =>
          direction <= '0';
          buffer_size <= 0;
          transfer_complete <= '1';
          if transfer_clock = 0 then
            transfer_state <= idle;
          else
            transfer_state <= done;
            transfer_clock <= transfer_clock - 1;
          end if;
      end case;
    end if;
  end process;

end architecture behavioral;
