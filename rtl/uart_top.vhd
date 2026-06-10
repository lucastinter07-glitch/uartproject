--------------------------------------------------------------------------------
-- uart_top.vhd
-- Structural top level: instantiates the baud generator, transmitter, and
-- receiver and wires them together. No logic of its own.
--
-- A single sample_tick (16x baud) is generated once and shared by TX and RX,
-- so the two paths are guaranteed to agree on bit timing.
--
-- serial_out and serial_in are exposed as separate pins (as a real device would
-- drive a TX pin and sense an RX pin). The loopback connection serial_out ->
-- serial_in is made in the testbench, not here.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity uart_top is
    generic (
        g_clk_freq_hz : positive := 50_000_000;
        g_baud_rate   : positive := 9_600;
        g_oversample  : positive := 16
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;
        -- transmit side
        tx_data       : in  std_logic_vector(7 downto 0);
        tx_start      : in  std_logic;
        tx_busy       : out std_logic;
        serial_out    : out std_logic;
        -- receive side
        serial_in     : in  std_logic;
        rx_data       : out std_logic_vector(7 downto 0);
        data_valid    : out std_logic;
        framing_error : out std_logic
    );
end entity uart_top;

architecture rtl of uart_top is
    signal sample_tick : std_logic;
begin

    baud_inst : entity work.baud_gen
        generic map (
            g_clk_freq_hz => g_clk_freq_hz,
            g_baud_rate   => g_baud_rate,
            g_oversample  => g_oversample
        )
        port map (
            clk         => clk,
            rst         => rst,
            sample_tick => sample_tick
        );

    tx_inst : entity work.uart_tx
        generic map ( g_oversample => g_oversample )
        port map (
            clk         => clk,
            rst         => rst,
            sample_tick => sample_tick,
            tx_start    => tx_start,
            tx_data     => tx_data,
            serial_out  => serial_out,
            tx_busy     => tx_busy
        );

    rx_inst : entity work.uart_rx
        generic map ( g_oversample => g_oversample )
        port map (
            clk           => clk,
            rst           => rst,
            sample_tick   => sample_tick,
            serial_in     => serial_in,
            rx_data       => rx_data,
            data_valid    => data_valid,
            framing_error => framing_error
        );

end architecture rtl;