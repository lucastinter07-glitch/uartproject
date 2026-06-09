--------------------------------------------------------------------------------
-- tb_uart_rx.vhd
-- Self-checking testbench for uart_rx.
--
-- Drives a synthetic sample_tick (fast, for sim speed) and a hand-built serial
-- line. For each byte it drives a full 8N1 frame (start, 8 data LSB-first, stop)
-- one bit period per bit, then checks that rx_data matches and data_valid pulses
-- with no framing error. Also includes two directed error tests:
--   * a sub-half-bit glitch in IDLE, which must be rejected (no data_valid)
--   * a frame with a corrupted (low) stop bit, which must raise framing_error
--
-- Unit test: the receiver in isolation. TX + RX together come in Phase 4.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;                 -- finish (VHDL-2008)

entity tb_uart_rx is
end entity tb_uart_rx;

architecture sim of tb_uart_rx is
    constant C_CLK_PERIOD : time     := 20 ns;   -- 50 MHz
    constant C_OVERSAMPLE : positive := 16;
    constant C_TICK_DIV   : positive := 4;       -- clocks per synthetic tick

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal sample_tick   : std_logic := '0';
    signal serial_in     : std_logic := '1';     -- line idles high
    signal rx_data       : std_logic_vector(7 downto 0);
    signal data_valid    : std_logic;
    signal framing_error : std_logic;
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
    dut : entity work.uart_rx
        generic map ( g_oversample => C_OVERSAMPLE )
        port map (
            clk           => clk,
            rst           => rst,
            sample_tick   => sample_tick,
            serial_in     => serial_in,
            rx_data       => rx_data,
            data_valid    => data_valid,
            framing_error => framing_error
        );

    ----------------------------------------------------------------------------
    -- Stimulus + checking
    ----------------------------------------------------------------------------
    stim : process

        constant C_ERR_BYTE : std_logic_vector(7 downto 0) := x"3C";

        procedure wait_ticks(n : in integer) is
        begin
            for i in 1 to n loop
                wait until sample_tick = '1';
            end loop;
        end procedure;

        -- Drive one bit value for a full bit period.
        procedure drive_bit(v : in std_logic) is
        begin
            serial_in <= v;
            wait_ticks(C_OVERSAMPLE);
        end procedure;

        -- Drive a full frame and check the recovered byte.
        procedure send_and_check(b : in std_logic_vector(7 downto 0)) is
        begin
            drive_bit('0');                         -- start bit
            for i in 0 to 7 loop
                drive_bit(b(i));                    -- data, LSB first
            end loop;
            serial_in <= '1';                       -- stop bit / idle
            wait until data_valid = '1' for 2 ms;   -- RX strobes at stop midpoint
            assert data_valid = '1'
                report "Timeout: no data_valid for byte " & to_hstring(b)
                severity error;
            assert rx_data = b
                report "RX mismatch: sent " & to_hstring(b) &
                       " got " & to_hstring(rx_data)
                severity error;
            assert framing_error = '0'
                report "Unexpected framing error on " & to_hstring(b)
                severity error;
            wait_ticks(C_OVERSAMPLE);               -- finish stop bit / idle gap
        end procedure;

    begin
        rst <= '1';
        wait for 200 ns;
        wait until rising_edge(clk);
        rst <= '0';
        wait_ticks(C_OVERSAMPLE);                   -- settle in idle

        -- Good bytes
        send_and_check(x"55");
        send_and_check(x"AA");
        send_and_check(x"00");
        send_and_check(x"FF");
        send_and_check(x"41");   -- 'A'
        send_and_check(x"61");   -- 'a'

        -- Error test 1: glitch shorter than half a bit must be rejected
        serial_in <= '0';
        wait_ticks(C_OVERSAMPLE / 4);               -- 4 ticks < 8-tick midpoint
        serial_in <= '1';
        wait until data_valid = '1' for 300 us;
        assert data_valid = '0'
            report "Glitch was NOT rejected (spurious data_valid)"
            severity error;
        report "Glitch correctly rejected" severity note;

        -- Error test 2: corrupted (low) stop bit must raise framing_error
        drive_bit('0');                             -- start
        for i in 0 to 7 loop
            drive_bit(C_ERR_BYTE(i));               -- data
        end loop;
        serial_in <= '0';                           -- BAD stop bit (should be '1')
        wait until data_valid = '1' for 2 ms;
        assert data_valid = '1'
            report "No data_valid on framing-error frame" severity error;
        assert framing_error = '1'
            report "Framing error NOT detected on bad stop bit" severity error;
        report "Framing error correctly detected" severity note;
        serial_in <= '1';
        wait_ticks(C_OVERSAMPLE);

        report "ALL RX TESTS PASSED" severity note;
        finish;
    end process;
end architecture sim;