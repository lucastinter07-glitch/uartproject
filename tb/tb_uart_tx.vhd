--------------------------------------------------------------------------------
-- tb_uart_tx.vhd
-- Self-checking testbench for uart_tx.
--
-- Drives a synthetic sample_tick (faster than the real baud_gen so the sim runs
-- quickly) and verifies that each transmitted byte produces the correct 8N1
-- frame on serial_out: start(0), 8 data bits LSB-first, stop(1). It samples each
-- bit at the interior of its 16-tick window, where serial_out is stable.
--
-- This is a UNIT test: the transmitter is checked in isolation. The real
-- baud_gen + TX + RX path is exercised together in the Phase 4 loopback test.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;                 -- finish (VHDL-2008)

entity tb_uart_tx is
end entity tb_uart_tx;

architecture sim of tb_uart_tx is
    constant C_CLK_PERIOD : time     := 20 ns;   -- 50 MHz
    constant C_OVERSAMPLE : positive := 16;
    constant C_TICK_DIV   : positive := 4;       -- clocks per synthetic tick

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal sample_tick : std_logic := '0';
    signal tx_start    : std_logic := '0';
    signal tx_data     : std_logic_vector(7 downto 0) := (others => '0');
    signal serial_out  : std_logic;
    signal tx_busy     : std_logic;
begin
    ----------------------------------------------------------------------------
    -- 50 MHz clock
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Synthetic oversample tick: a 1-clock pulse every C_TICK_DIV clocks
    ----------------------------------------------------------------------------
    tick_gen : process(clk)
        variable cnt : integer range 0 to C_TICK_DIV - 1 := 0;
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cnt         := 0;
                sample_tick <= '0';
            elsif cnt = C_TICK_DIV - 1 then
                cnt         := 0;
                sample_tick <= '1';
            else
                cnt         := cnt + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- DUT
    ----------------------------------------------------------------------------
    dut : entity work.uart_tx
        generic map ( g_oversample => C_OVERSAMPLE )
        port map (
            clk         => clk,
            rst         => rst,
            sample_tick => sample_tick,
            tx_start    => tx_start,
            tx_data     => tx_data,
            serial_out  => serial_out,
            tx_busy     => tx_busy
        );

    ----------------------------------------------------------------------------
    -- Stimulus + checking
    ----------------------------------------------------------------------------
    stim : process

        procedure wait_ticks(n : in integer) is
        begin
            for i in 1 to n loop
                wait until sample_tick = '1';
            end loop;
        end procedure;

        procedure send_and_check(b : in std_logic_vector(7 downto 0)) is
            variable frame : std_logic_vector(0 to 9);
        begin
            frame(0) := '0';                    -- start bit
            for i in 0 to 7 loop
                frame(i + 1) := b(i);           -- data, LSB first
            end loop;
            frame(9) := '1';                    -- stop bit

            if tx_busy = '1' then
                wait until tx_busy = '0';
            end if;
            wait until rising_edge(clk);
            tx_data  <= b;
            tx_start <= '1';
            wait until rising_edge(clk);
            tx_start <= '0';

            wait until serial_out = '0';        -- catch the start-bit edge
            wait_ticks(C_OVERSAMPLE / 2);       -- move into the start-bit interior
            for i in 0 to 9 loop
                assert serial_out = frame(i)
                    report "Byte " & to_hstring(b) & " bit " & integer'image(i) &
                           ": expected " & std_logic'image(frame(i)) &
                           " got " & std_logic'image(serial_out)
                    severity error;
                if i < 9 then
                    wait_ticks(C_OVERSAMPLE);   -- advance to next bit interior
                end if;
            end loop;
        end procedure;

    begin
        rst <= '1';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst <= '0';

        send_and_check(x"55");
        send_and_check(x"AA");
        send_and_check(x"00");
        send_and_check(x"FF");
        send_and_check(x"41");   -- 'A'
        send_and_check(x"61");   -- 'a'

        if tx_busy = '1' then
            wait until tx_busy = '0';
        end if;

        report "ALL TX FRAME TESTS PASSED" severity note;
        finish;
    end process;
end architecture sim;