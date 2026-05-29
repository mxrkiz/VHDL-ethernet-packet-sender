-- =============================================================
-- tb_fifo.vhd — testbench for synchronous FIFO 16x8
-- Tests: reset, fill, empty/full flags, drain, simultaneous r+w.
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_fifo is
end tb_fifo;

architecture sim of tb_fifo is
    constant CLK_PERIOD : time := 10 ns;

    signal clk    : STD_LOGIC := '0';
    signal rst    : STD_LOGIC := '1';
    signal wr_en  : STD_LOGIC := '0';
    signal rd_en  : STD_LOGIC := '0';
    signal din    : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal dout   : STD_LOGIC_VECTOR(7 downto 0);
    signal empty  : STD_LOGIC;
    signal full   : STD_LOGIC;
    signal finished : STD_LOGIC := '0';

    component fifo is
        Generic (DEPTH : integer := 16; WIDTH : integer := 8);
        Port (
            clk : in STD_LOGIC; rst : in STD_LOGIC;
            wr_en : in STD_LOGIC; rd_en : in STD_LOGIC;
            din : in STD_LOGIC_VECTOR(7 downto 0);
            dout : out STD_LOGIC_VECTOR(7 downto 0);
            empty : out STD_LOGIC; full : out STD_LOGIC
        );
    end component;
begin

    DUT: fifo generic map (DEPTH => 16, WIDTH => 8)
        port map (clk => clk, rst => rst,
                  wr_en => wr_en, rd_en => rd_en,
                  din => din, dout => dout,
                  empty => empty, full => full);

    -- Clock generator stops when finished='1' to avoid infinite sim
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

    stim: process
    begin
        -- Reset
        rst <= '1';
        wait for 3 * CLK_PERIOD;
        rst <= '0';
        wait for CLK_PERIOD;

        assert empty = '1' report "ERR: should be empty after reset" severity error;
        assert full  = '0' report "ERR: should not be full after reset" severity error;

        ----------------------------------------------------------
        -- TEST 1: write 5 bytes
        ----------------------------------------------------------
        report "TEST 1: write 5 bytes";
        for i in 1 to 5 loop
            din   <= std_logic_vector(to_unsigned(i * 16, 8));
            wr_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en <= '0';
        wait for CLK_PERIOD;

        assert empty = '0' report "ERR: should not be empty" severity error;
        assert full  = '0' report "ERR: should not be full"  severity error;

        ----------------------------------------------------------
        -- TEST 2: fill to full (11 more writes)
        ----------------------------------------------------------
        report "TEST 2: fill to full";
        for i in 6 to 16 loop
            din   <= std_logic_vector(to_unsigned(i * 16, 8));
            wr_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en <= '0';
        wait for CLK_PERIOD;

        assert full = '1' report "ERR: should be full at 16" severity error;

        ----------------------------------------------------------
        -- TEST 3: drain everything
        ----------------------------------------------------------
        report "TEST 3: drain all 16 bytes";
        for i in 1 to 16 loop
            rd_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        rd_en <= '0';
        wait for CLK_PERIOD;

        assert empty = '1' report "ERR: should be empty after drain" severity error;

        ----------------------------------------------------------
        -- TEST 4: simultaneous write+read
        ----------------------------------------------------------
        report "TEST 4: simultaneous r+w";
        -- Pre-fill with 4 bytes
        for i in 1 to 4 loop
            din   <= std_logic_vector(to_unsigned(i, 8));
            wr_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en <= '0';
        wait for CLK_PERIOD;

        -- Write+read simultaneously for 3 cycles
        for i in 5 to 7 loop
            din   <= std_logic_vector(to_unsigned(i, 8));
            wr_en <= '1';
            rd_en <= '1';
            wait for CLK_PERIOD;
        end loop;
        wr_en <= '0';
        rd_en <= '0';
        wait for CLK_PERIOD;

        assert empty = '0' report "ERR: should still hold bytes" severity error;
        assert full  = '0' report "ERR: should not be full"      severity error;

        report "All tests finished" severity note;
        finished <= '1';
        wait;
    end process;

end sim;
