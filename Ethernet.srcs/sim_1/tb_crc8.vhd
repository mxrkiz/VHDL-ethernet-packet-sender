-- =============================================================
-- tb_crc8.vhd — testbench for combinational CRC-8
-- Feeds a few known byte sequences and checks the accumulated CRC.
-- Observe crc_in and crc_out in the waveform viewer.
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_crc8 is
end tb_crc8;

architecture sim of tb_crc8 is
    signal data_in : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal crc_in  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal crc_out : STD_LOGIC_VECTOR(7 downto 0);

    component crc8 is
        Port (
            data_in  : in  STD_LOGIC_VECTOR(7 downto 0);
            crc_in   : in  STD_LOGIC_VECTOR(7 downto 0);
            crc_out  : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    function slv_to_int(s : STD_LOGIC_VECTOR) return integer is
    begin
        return to_integer(unsigned(s));
    end function;

begin

    DUT: crc8 port map (data_in => data_in, crc_in => crc_in, crc_out => crc_out);

    stim: process
        procedure step(b : STD_LOGIC_VECTOR(7 downto 0)) is
        begin
            data_in <= b;
            wait for 10 ns;
            crc_in  <= crc_out;
            wait for 10 ns;
        end procedure;
    begin
        crc_in <= x"FF";
        wait for 10 ns;

        report "Test 1: single byte 0x00";
        step(x"00");
        report "CRC after 0x00 (dec) = " & integer'image(slv_to_int(crc_in));

        crc_in <= x"FF";
        wait for 10 ns;

        report "Test 2: byte sequence 0xAA 0xBB";
        step(x"AA");
        step(x"BB");
        report "CRC after 0xAA,0xBB (dec) = " & integer'image(slv_to_int(crc_in));

        crc_in <= x"FF";
        wait for 10 ns;

        report "Test 3: broadcast MAC FF x6";
        step(x"FF"); step(x"FF"); step(x"FF");
        step(x"FF"); step(x"FF"); step(x"FF");
        report "CRC after 6x 0xFF (dec) = " & integer'image(slv_to_int(crc_in));

        report "Simulation complete" severity note;
        wait;
    end process;

end sim;
