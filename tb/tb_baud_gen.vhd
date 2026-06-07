--------------------------------------------------------------------------------
-- tb_baud_gen.vhd
-- Self-checking testbench for baud_gen.
--
-- Verifies that sample_tick pulses exactly C_EXPECTED clock cycles apart in
-- steady state. Uses std.env.finish so no --stop-time argument is required:
--   ghdl -r --std=08 tb_baud_gen --vcd=baud_gen.vcd
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;                 -- finish (VHDL-2008)

entity tb_baud_gen is
end entity tb_baud_gen;

architecture sim of tb_baud_gen is
    constant C_CLK_PERIOD : time     := 20 ns;   -- 50 MHz
    constant C_EXPECTED   : positive := 326;     -- expected clocks between ticks

    signal clk         : std_logic := '0';
    signal rst         : std_logic := '1';
    signal sample_tick : std_logic;

    signal gap        : integer := 0;   -- clocks since the last tick
    signal tick_count : integer := 0;   -- total ticks observed
    signal checks     : integer := 0;   -- spacing checks performed
begin
    ----------------------------------------------------------------------------
    -- 50 MHz free-running clock
    ----------------------------------------------------------------------------
    clk <= not clk after C_CLK_PERIOD / 2;

    ----------------------------------------------------------------------------
    -- Device under test
    ----------------------------------------------------------------------------
    dut : entity work.baud_gen
        generic map (
            g_clk_freq_hz => 50_000_000,
            g_baud_rate   => 9_600,
            g_oversample  => 16
        )
        port map (
            clk         => clk,
            rst         => rst,
            sample_tick => sample_tick
        );

    ----------------------------------------------------------------------------
    -- Monitor: measure the spacing between consecutive ticks
    ----------------------------------------------------------------------------
    monitor : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                gap        <= 0;
                tick_count <= 0;
                checks     <= 0;
            elsif sample_tick = '1' then
                tick_count <= tick_count + 1;
                if tick_count > 0 then          -- skip the first partial interval
                    assert gap = C_EXPECTED
                        report "Bad tick spacing: expected " &
                               integer'image(C_EXPECTED) & " got " &
                               integer'image(gap)
                        severity error;
                    checks <= checks + 1;
                end if;
                gap <= 1;
            else
                gap <= gap + 1;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------------------
    -- Stimulus
    ----------------------------------------------------------------------------
    stim : process
    begin
        rst <= '1';
        wait for 200 ns;
        rst <= '0';

        -- Run long enough to observe ~50 ticks.
        wait for 50 * C_EXPECTED * C_CLK_PERIOD;

        assert tick_count >= 45
            report "Too few ticks observed: " & integer'image(tick_count)
            severity error;

        report "baud_gen PASS: " & integer'image(tick_count) &
               " ticks, " & integer'image(checks) & " spacing checks OK"
            severity note;
        finish;                                 -- clean end of simulation
    end process;
end architecture sim;