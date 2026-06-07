Library ieee;
USE ieee.std_logic_1164.all;

Entity SevenSegment IS
	Port
	(
		X7 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X6 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X5 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X4 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X3 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X2 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X1 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		X0 : IN STD_LOGIC_VECTOR (1 DOWNTO 0);
		H7 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H6 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H5 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H4 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H3 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H2 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H1 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0);
		H0 : OUT STD_LOGIC_VECTOR (6 DOWNTO 0)
	);
END SevenSegment;

ARCHITECTURE Behavioral OF SevenSegment IS

constant zero : STD_LOGIC_VECTOR := "1000000";
constant one : STD_LOGIC_VECTOR := "1111001";
constant two : STD_LOGIC_VECTOR := "0100100";
constant three : STD_LOGIC_VECTOR := "0110000";
constant none : STD_LOGIC_VECTOR := "0000000";

BEGIN

	
		H0 <= zero when X0 = "00" else
				one when X0 = "01" else
				two when X0 = "10" else
				three when X0 = "11" else
				none;
		

END Behavioral;