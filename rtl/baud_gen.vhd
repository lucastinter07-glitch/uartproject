--------------------------------------------------------------------------------
-- baud_gen.vhd
-- Oversample tick generator for the UART transceiver.
--
-- Emits a single-clock-wide pulse on sample_tick at a rate of
--     (g_baud_rate * g_oversample) Hz.
--
-- DESIGN DECISION: this block produces ONLY the 16x oversample tick. Both the
-- transmitter and the receiver derive all of their bit timing by counting these
-- ticks (g_oversample ticks = one bit period). Generating a separate, independent
-- "baud tick" would let the two divisors drift relative to each other
-- (16 * 326 = 5216 clocks != 5208 clocks per bit), so we derive everything from
-- one divisor instead. This keeps TX and RX timing perfectly coherent.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;          -- round, log2, ceil (elaboration-time only)

entity baud_gen is
    generic (
        g_clk_freq_hz : positive := 50_000_000;  -- system clock frequency
        g_baud_rate   : positive := 9_600;       -- target UART baud rate
        g_oversample  : positive := 16            -- RX oversampling factor
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;   -- synchronous, active high
        sample_tick : out std_logic    -- 1-cycle pulse at g_oversample x g_baud_rate
    );
end entity baud_gen;

architecture rtl of baud_gen is
    -- Clock cycles per oversample tick, rounded to the nearest integer.
    --   50e6 / (9600 * 16) = 325.52  ->  326   (effective baud 9586, 0.15% error)
    constant C_OS_DIV : positive :=
        integer(round(real(g_clk_freq_hz) / real(g_baud_rate * g_oversample)));

    -- Counter width sized to exactly hold the value (C_OS_DIV - 1).
    constant C_CNT_W  : positive := integer(ceil(log2(real(C_OS_DIV))));

    signal count : unsigned(C_CNT_W - 1 downto 0) := (others => '0');
begin
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                count       <= (others => '0');
                sample_tick <= '0';
            elsif count = C_OS_DIV - 1 then
                count       <= (others => '0');
                sample_tick <= '1';        -- assert for exactly one clock cycle
            else
                count       <= count + 1;
                sample_tick <= '0';
            end if;
        end if;
    end process;
end architecture rtl;