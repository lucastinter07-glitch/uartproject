--------------------------------------------------------------------------------
-- uart_tx.vhd
-- UART transmitter. Accepts a parallel byte and serializes it as an 8N1 frame
-- (idle high -> start bit low -> 8 data bits LSB-first -> stop bit high).
--
-- Two-process FSM:
--   * next_state_logic (combinational) decides the next state.
--   * seq (clocked)     holds the state register, runs the datapath
--                       (tick/bit counters, shift register), and drives the
--                       registered outputs.
--
-- Bit timing is derived purely by counting sample_ticks: one bit period =
-- g_oversample ticks. This block never sees the clock divisor, so it stays in
-- lockstep with the receiver, which counts the same ticks.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;          -- ceil, log2 (elaboration-time only)

entity uart_tx is
    generic (
        g_oversample : positive := 16    -- sample_ticks per bit period
    );
    port (
        clk         : in  std_logic;
        rst         : in  std_logic;                      -- synchronous, active high
        sample_tick : in  std_logic;                      -- 16x oversample tick
        tx_start    : in  std_logic;                      -- pulse to begin a send
        tx_data     : in  std_logic_vector(7 downto 0);   -- byte to transmit
        serial_out  : out std_logic;                      -- UART line (idles high)
        tx_busy     : out std_logic                       -- high while transmitting
    );
end entity uart_tx;

architecture rtl of uart_tx is

    type state_t is (IDLE, START, DATA, STOP);
    signal state, next_state : state_t := IDLE;

    -- Counter width sized to hold (g_oversample - 1).
    constant C_TICK_W : positive := integer(ceil(log2(real(g_oversample))));

    signal tick_count : unsigned(C_TICK_W - 1 downto 0) := (others => '0'); -- 0..15
    signal bit_index  : unsigned(2 downto 0)            := (others => '0'); -- 0..7
    signal shift_reg  : std_logic_vector(7 downto 0)    := (others => '1');

    -- High on the final oversample tick of the current bit period.
    signal bit_done   : std_logic;

begin

    bit_done <= '1' when (sample_tick = '1' and tick_count = g_oversample - 1)
                else '0';

    ----------------------------------------------------------------------------
    -- Combinational next-state logic
    ----------------------------------------------------------------------------
    next_state_logic : process(all)
    begin
        next_state <= state;                 -- default: hold current state
        case state is
            when IDLE =>
                if tx_start = '1' then
                    next_state <= START;
                end if;
            when START =>
                if bit_done = '1' then
                    next_state <= DATA;
                end if;
            when DATA =>
                if bit_done = '1' and bit_index = 7 then
                    next_state <= STOP;      -- 8th data bit just finished
                end if;
            when STOP =>
                if bit_done = '1' then
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    ----------------------------------------------------------------------------
    -- Sequential: state register, datapath, registered outputs
    ----------------------------------------------------------------------------
    seq : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state      <= IDLE;
                tick_count <= (others => '0');
                bit_index  <= (others => '0');
                shift_reg  <= (others => '1');
                serial_out <= '1';
                tx_busy    <= '0';
            else
                state   <= next_state;
                tx_busy <= '1';              -- default; IDLE overrides below

                case state is
                    when IDLE =>
                        serial_out <= '1';                 -- line idles high
                        tx_busy    <= '0';
                        tick_count <= (others => '0');
                        bit_index  <= (others => '0');
                        if tx_start = '1' then
                            shift_reg <= tx_data;          -- latch byte to send
                        end if;

                    when START =>
                        serial_out <= '0';                 -- start bit
                        if sample_tick = '1' then
                            if tick_count = g_oversample - 1 then
                                tick_count <= (others => '0');
                            else
                                tick_count <= tick_count + 1;
                            end if;
                        end if;

                    when DATA =>
                        serial_out <= shift_reg(0);        -- LSB first
                        if sample_tick = '1' then
                            if tick_count = g_oversample - 1 then
                                tick_count <= (others => '0');
                                if bit_index /= 7 then
                                    shift_reg <= '1' & shift_reg(7 downto 1);
                                    bit_index <= bit_index + 1;
                                end if;
                            else
                                tick_count <= tick_count + 1;
                            end if;
                        end if;

                    when STOP =>
                        serial_out <= '1';                 -- stop bit
                        if sample_tick = '1' then
                            if tick_count = g_oversample - 1 then
                                tick_count <= (others => '0');
                            else
                                tick_count <= tick_count + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;