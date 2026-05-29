-- =============================================================
-- crc8.vhd
-- CRC-8 (polynomial x^8 + x^2 + x + 1 = 0x07)
-- Combinational: takes 8-bit data, outputs 8-bit CRC
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity crc8 is
    Port (
        data_in  : in  STD_LOGIC_VECTOR(7 downto 0);
        crc_in   : in  STD_LOGIC_VECTOR(7 downto 0);  -- previous CRC (init = 0xFF)
        crc_out  : out STD_LOGIC_VECTOR(7 downto 0)
    );
end crc8;

architecture Behavioral of crc8 is
    signal d : STD_LOGIC_VECTOR(7 downto 0);
begin
    d <= data_in xor crc_in;

    crc_out(0) <= d(6) xor d(7);
    crc_out(1) <= d(5) xor d(6) xor d(7);
    crc_out(2) <= d(4) xor d(5) xor d(6) xor d(7);
    crc_out(3) <= d(3) xor d(4) xor d(5) xor d(6);
    crc_out(4) <= d(2) xor d(3) xor d(4) xor d(5);
    crc_out(5) <= d(1) xor d(2) xor d(3) xor d(4);
    crc_out(6) <= d(0) xor d(1) xor d(2) xor d(3);
    crc_out(7) <= d(0) xor d(1) xor d(2);
end Behavioral;
