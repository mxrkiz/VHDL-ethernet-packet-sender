-- =============================================================
-- tb_packet_builder.vhd — testbench for Ethernet frame builder
-- Pulses build, captures 24 bytes written to FIFO, verifies
-- preamble, SFD, DST MAC, SRC MAC, EtherType, payload.
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_packet_builder is
end tb_packet_builder;

architecture sim of tb_packet_builder is
    constant CLK_PERIOD : time := 10 ns;

    signal clk       : STD_LOGIC := '0';
    signal rst       : STD_LOGIC := '1';
    signal build     : STD_LOGIC := '0';
    signal sw_data   : STD_LOGIC_VECTOR(7 downto 0) := x"42";
    signal fifo_wr   : STD_LOGIC;
    signal fifo_din  : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_full : STD_LOGIC := '0';
    signal done      : STD_LOGIC;
    signal finished  : STD_LOGIC := '0';

    type byte_array_t is array (0 to 31) of STD_LOGIC_VECTOR(7 downto 0);
    signal captured : byte_array_t := (others => (others => '0'));
    signal cap_idx  : integer := 0;

    component packet_builder is
        Generic (SRC_MAC : STD_LOGIC_VECTOR(47 downto 0) := x"AABBCCDDEEFF");
        Port (
            clk : in STD_LOGIC; rst : in STD_LOGIC;
            build : in STD_LOGIC;
            sw_data : in STD_LOGIC_VECTOR(7 downto 0);
            fifo_wr : out STD_LOGIC;
            fifo_din : out STD_LOGIC_VECTOR(7 downto 0);
            fifo_full : in STD_LOGIC;
            done : out STD_LOGIC
        );
    end component;

    function slv_to_int(s : STD_LOGIC_VECTOR) return integer is
    begin
        return to_integer(unsigned(s));
    end function;

begin

    DUT: packet_builder
        generic map (SRC_MAC => x"123456789ABC")
        port map (
            clk => clk, rst => rst,
            build => build,
            sw_data => sw_data,
            fifo_wr => fifo_wr,
            fifo_din => fifo_din,
            fifo_full => fifo_full,
            done => done
        );

    clk_proc: process
    begin
        while finished = '0' loop
            clk <= '0';
            wait for CLK_PERIOD / 2;
            clk <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Capture bytes as they are written
    capture: process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                cap_idx <= 0;
            elsif fifo_wr = '1' and cap_idx < 32 then
                captured(cap_idx) <= fifo_din;
                cap_idx <= cap_idx + 1;
            end if;
        end if;
    end process;

    stim: process
    begin
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        sw_data <= x"42";

        build <= '1';
        wait for CLK_PERIOD;
        build <= '0';

        wait until done = '1';
        wait for 2 * CLK_PERIOD;

        report "Captured " & integer'image(cap_idx) & " bytes";
        for i in 0 to 23 loop
            report "  byte[" & integer'image(i) & "] = " &
                   integer'image(slv_to_int(captured(i)));
        end loop;

        -- Assertions
        report "Checking preamble (bytes 0..6 = 0xAA)";
        for i in 0 to 6 loop
            assert captured(i) = x"AA"
                report "Byte " & integer'image(i) & " should be 0xAA"
                severity error;
        end loop;

        assert captured(7) = x"AB" report "SFD wrong"   severity error;

        for i in 8 to 13 loop
            assert captured(i) = x"FF"
                report "DST byte " & integer'image(i) & " wrong"
                severity error;
        end loop;

        assert captured(14) = x"12" report "SRC[0] wrong" severity error;
        assert captured(15) = x"34" report "SRC[1] wrong" severity error;
        assert captured(16) = x"56" report "SRC[2] wrong" severity error;
        assert captured(17) = x"78" report "SRC[3] wrong" severity error;
        assert captured(18) = x"9A" report "SRC[4] wrong" severity error;
        assert captured(19) = x"BC" report "SRC[5] wrong" severity error;

        assert captured(20) = x"08" report "EtherType[0] wrong" severity error;
        assert captured(21) = x"00" report "EtherType[1] wrong" severity error;

        assert captured(22) = x"42" report "Payload wrong" severity error;

        report "CRC byte 23 (dec) = " & integer'image(slv_to_int(captured(23)));

        report "TEST COMPLETE" severity note;
        finished <= '1';
        wait;
    end process;

end sim;
