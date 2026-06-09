--------------------------------------------------------------------------------
-- uart_rx.vhd
-- UART receiver. Recovers an 8N1 byte from an asynchronous serial line using
-- 16x oversampling and midpoint sampling.
--
-- Two-process FSM (matching uart_tx):
--   * next_state_logic (combinational) decides the next state.
--   * seq (clocked)     runs the 2-FF input synchronizer, the datapath
--                       (tick/bit counters, receive shift register), and the
--                       registered outputs.
--
-- Timing: anchor at the MIDDLE of the start bit (8 ticks after the falling
-- edge), then sample every data bit a full 16 ticks later -- i.e. at its own
-- midpoint, where the line is stable.
--------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;          -- ceil, log2 (elaboration-time only)

entity uart_rx is
    generic (
        g_oversample : positive := 16    -- sample_ticks per bit period
    );
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;                    -- synchronous, active high
        sample_tick   : in  std_logic;                    -- 16x oversample tick
        serial_in     : in  std_logic;                    -- asynchronous UART line
        rx_data       : out std_logic_vector(7 downto 0); -- recovered byte
        data_valid    : out std_logic;                    -- 1-cycle strobe when rx_data is valid
        framing_error : out std_logic                     -- high if stop bit was not '1'
    );
end entity uart_rx;

architecture rtl of uart_rx is

    type state_t is (IDLE, START, DATA, STOP);
    signal state, next_state : state_t := IDLE;

    -- Sample counter sized to hold (g_oversample - 1).
    constant C_CNT_W : positive := integer(ceil(log2(real(g_oversample))));
    constant C_MID   : integer  := g_oversample / 2 - 1;   -- start-bit midpoint (7)
    constant C_END   : integer  := g_oversample - 1;       -- full bit period (15)

    signal sample_count : unsigned(C_CNT_W - 1 downto 0) := (others => '0');
    signal bit_index    : unsigned(2 downto 0)           := (others => '0'); -- 0..7
    signal rx_shift     : std_logic_vector(7 downto 0)   := (others => '0');

    -- 2-FF synchronizer for the asynchronous input. rx_sync is the clean,
    -- in-domain version of serial_in; the FSM never reads serial_in directly.
    signal sync_ff : std_logic_vector(1 downto 0) := (others => '1');
    signal rx_sync : std_logic;

begin

    rx_sync <= sync_ff(1);

    ----------------------------------------------------------------------------
    -- Combinational next-state logic
    ----------------------------------------------------------------------------
    next_state_logic : process(all)
    begin
        next_state <= state;                 -- default: hold current state
        case state is
            when IDLE =>
                if rx_sync = '0' then                       -- possible start bit
                    next_state <= START;
                end if;
            when START =>
                if sample_tick = '1' and sample_count = C_MID then
                    if rx_sync = '0' then                   -- still low at midpoint: real start
                        next_state <= DATA;
                    else                                    -- bounced high: false start
                        next_state <= IDLE;
                    end if;
                end if;
            when DATA =>
                if sample_tick = '1' and sample_count = C_END and bit_index = 7 then
                    next_state <= STOP;                     -- 8th data bit sampled
                end if;
            when STOP =>
                if sample_tick = '1' and sample_count = C_END then
                    next_state <= IDLE;
                end if;
        end case;
    end process;

    ----------------------------------------------------------------------------
    -- Sequential: synchronizer, datapath, registered outputs
    ----------------------------------------------------------------------------
    seq : process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state         <= IDLE;
                sync_ff       <= (others => '1');           -- idle high
                sample_count  <= (others => '0');
                bit_index     <= (others => '0');
                rx_shift      <= (others => '0');
                rx_data       <= (others => '0');
                data_valid    <= '0';
                framing_error <= '0';
            else
                -- 2-FF synchronizer runs every clock, ungated by sample_tick
                sync_ff(0) <= serial_in;
                sync_ff(1) <= sync_ff(0);

                state      <= next_state;
                data_valid <= '0';                          -- default: 1-cycle pulse

                case state is
                    when IDLE =>
                        sample_count <= (others => '0');
                        bit_index    <= (others => '0');

                    when START =>
                        if sample_tick = '1' then
                            if sample_count = C_MID then
                                sample_count <= (others => '0');  -- re-anchor at midpoint
                            else
                                sample_count <= sample_count + 1;
                            end if;
                        end if;

                    when DATA =>
                        if sample_tick = '1' then
                            if sample_count = C_END then
                                sample_count <= (others => '0');
                                -- sample at the bit midpoint, assemble LSB-first
                                rx_shift <= rx_sync & rx_shift(7 downto 1);
                                if bit_index /= 7 then
                                    bit_index <= bit_index + 1;
                                end if;
                            else
                                sample_count <= sample_count + 1;
                            end if;
                        end if;

                    when STOP =>
                        if sample_tick = '1' then
                            if sample_count = C_END then
                                sample_count  <= (others => '0');
                                rx_data       <= rx_shift;        -- present recovered byte
                                data_valid    <= '1';             -- strobe
                                framing_error <= not rx_sync;     -- stop bit should be '1'
                            else
                                sample_count <= sample_count + 1;
                            end if;
                        end if;
                end case;
            end if;
        end if;
    end process;

end architecture rtl;