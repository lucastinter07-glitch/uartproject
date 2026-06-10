--------------------------------------------------------------------------------
-- tb_uart_loopback.vhd
-- Headline test: drives bytes into the transmitter and checks the receiver
-- hands back the same bytes, through the REAL baud generator (full 326-cycle
-- tick spacing, no synthetic tick). serial_out is wired to serial_in.
--
-- Two tests:
--   1. Per-byte round trip  - send one byte, wait for data_valid, check it.
--   2. Back-to-back burst    - send the next byte the moment TX is free; a
--                              monitor captures each received byte and the
--                              whole sequence is checked at the end.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;                 -- finish (VHDL-2008)

entity tb_uart_loopback is
end entity tb_uart_loopback;

architecture sim of tb_uart_loopback is
    constant C_CLK_PERIOD : time := 20 ns;   -- 50 MHz

    signal clk           : std_logic := '0';
    signal rst           : std_logic := '1';
    signal tx_data       : std_logic_vector(7 downto 0) := (others => '0');
    signal tx_start      : std_logic := '0';
    signal tx_busy       : std_logic;
    signal serial_line   : std_logic;        -- the loopback wire (TX out -> RX in)
    signal rx_data       : std_logic_vector(7 downto 0);
    signal data_valid    : std_logic;
    signal framing_error : std_logic;

    type byte_array is array (natural range <>) of std_logic_vector(7 downto 0);
    constant TESTS : byte_array(0 to 5) := (x"55", x"AA", x"00", x"FF", x"41", x"61");
    constant BURST : byte_array(0 to 5) := (x"DE", x"AD", x"BE", x"EF", x"12", x"34");

    -- Burst capture (driven only by the monitor process)
    signal capture_en : std_logic := '0';
    signal rx_count   : integer := 0;
    signal rx_capture : byte_array(0 to 5) := (others => (others => '0'));
begin
    ----------------------------------------------------------------------------
    -- 50 MHz clock
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- DUT: baud_gen + uart_tx + uart_rx, with the loopback wire tied here
    ----------------------------------------------------------------------------
    dut : entity work.uart_top
        generic map (
            g_clk_freq_hz => 50_000_000,
            g_baud_rate   => 9_600,
            g_oversample  => 16
        )
        port map (
            clk           => clk,
            rst           => rst,
            tx_data       => tx_data,
            tx_start      => tx_start,
            tx_busy       => tx_busy,
            serial_out    => serial_line,    -- TX drives the wire
            serial_in     => serial_line,    -- RX senses the same wire
            rx_data       => rx_data,
            data_valid    => data_valid,
            framing_error => framing_error
        );

    ----------------------------------------------------------------------------
    -- Monitor: record received bytes while capture is enabled
    ----------------------------------------------------------------------------
    monitor : process(clk)
    begin
        if rising_edge(clk) then
            if capture_en = '0' then
                rx_count <= 0;
            elsif data_valid = '1' then
                if rx_count <= 5 then
                    rx_capture(rx_count) <= rx_data;
                end if;
                rx_count <= rx_count + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus + checking
    ----------------------------------------------------------------------------
    stim : process

        -- Begin transmitting a byte; returns once the TX has accepted it.
        procedure start_tx(b : in std_logic_vector(7 downto 0)) is
        begin
            if tx_busy = '1' then
                wait until tx_busy = '0';
            end if;
            wait until rising_edge(clk);
            tx_data  <= b;
            tx_start <= '1';
            wait until rising_edge(clk);
            tx_start <= '0';
            wait until tx_busy = '1';        -- TX has accepted and begun
        end procedure;

        -- Send one byte and verify the full round trip.
        procedure send_and_check(b : in std_logic_vector(7 downto 0)) is
        begin
            start_tx(b);
            wait until data_valid = '1' for 50 ms;
            assert data_valid = '1'
                report "Timeout: no loopback for byte " & to_hstring(b)
                severity error;
            assert rx_data = b
                report "Loopback mismatch: sent " & to_hstring(b) &
                       " got " & to_hstring(rx_data) severity error;
            assert framing_error = '0'
                report "Unexpected framing error on " & to_hstring(b)
                severity error;
        end procedure;

    begin
        rst <= '1';
        wait for 500 ns;
        wait until rising_edge(clk);
        rst <= '0';

        -- Test 1: one byte fully round-trips at a time
        for i in TESTS'range loop
            send_and_check(TESTS(i));
        end loop;
        report "Per-byte loopback PASSED" severity note;

        -- Let Test 1's final data_valid pulse fully clear and the line settle
        -- back to idle before arming the burst capture (avoids capturing the
        -- trailing byte into the burst).
        wait until tx_busy = '0';
        wait for 200 us;

        -- Test 2: back-to-back burst
        capture_en <= '1';
        wait until rising_edge(clk);
        for i in BURST'range loop
            start_tx(BURST(i));
        end loop;
        wait until rx_count = BURST'length for 50 ms;
        assert rx_count = BURST'length
            report "Burst: expected " & integer'image(BURST'length) &
                   " bytes, got " & integer'image(rx_count) severity error;
        for i in BURST'range loop
            assert rx_capture(i) = BURST(i)
                report "Burst byte " & integer'image(i) & " mismatch: expected " &
                       to_hstring(BURST(i)) & " got " & to_hstring(rx_capture(i))
                severity error;
        end loop;
        report "Back-to-back burst PASSED" severity note;
        capture_en <= '0';

        report "ALL LOOPBACK TESTS PASSED" severity note;
        finish;
    end process;
end architecture sim;