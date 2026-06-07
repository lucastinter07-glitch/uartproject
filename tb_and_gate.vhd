library ieee;
use ieee.std_logic_1164.all;

entity tb_and_gate is
end entity tb_and_gate;

architecture sim of tb_and_gate is
    signal a, b, y : std_logic;
begin
    -- instantiate the gate under test
    dut : entity work.and_gate
        port map (a => a, b => b, y => y);

    -- drive all four input combinations and check each
    process
    begin
        a <= '0'; b <= '0'; wait for 100 ns;
        assert y = '0' report "FAIL: 0 and 0 should be 0" severity error;

        a <= '0'; b <= '1'; wait for 100 ns;
        assert y = '0' report "FAIL: 0 and 1 should be 0" severity error;

        a <= '1'; b <= '0'; wait for 100 ns;
        assert y = '0' report "FAIL: 1 and 0 should be 0" severity error;

        a <= '1'; b <= '1'; wait for 100 ns;
        assert y = '1' report "FAIL: 1 and 1 should be 1" severity error;

        wait for 100 ns;

        report "ALL AND-GATE TESTS PASSED" severity note;
        wait;
    end process;
end architecture sim;