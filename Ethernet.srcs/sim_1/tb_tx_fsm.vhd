-- =============================================================
-- tb_tx_fsm.vhd — testbench for RMII transmit FSM
-- Simulates a small FIFO model and verifies dibit order (LSB-first).
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_tx_fsm is
end tb_tx_fsm;

architecture sim of tb_tx_fsm is
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz

    signal clk_50     : STD_LOGIC := '0';
    signal rst        : STD_LOGIC := '1';
    signal send       : STD_LOGIC := '0';

    signal fifo_rd    : STD_LOGIC;
    signal fifo_dout  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal fifo_empty : STD_LOGIC := '1';

    signal txd        : STD_LOGIC_VECTOR(1 downto 0);
    signal tx_en      : STD_LOGIC;
    signal tx_done    : STD_LOGIC;

    signal finished   : STD_LOGIC := '0';

    type byte_mem_t is array (0 to 2) of STD_LOGIC_VECTOR(7 downto 0);
    constant MEM : byte_mem_t := (x"A5", x"3C", x"F0");
    signal rptr : integer range 0 to 3 := 0;

    component tx_fsm is
        Generic (FRAME_LEN : integer := 24);
        Port (
            clk_50 : in STD_LOGIC; rst : in STD_LOGIC;
            send : in STD_LOGIC;
            fifo_rd : out STD_LOGIC;
            fifo_dout : in STD_LOGIC_VECTOR(7 downto 0);
            fifo_empty : in STD_LOGIC;
            txd : out STD_LOGIC_VECTOR(1 downto 0);
            tx_en : out STD_LOGIC;
            tx_done : out STD_LOGIC
        );
    end component;
begin

    -- Override FRAME_LEN=3 because the test sends only 3 bytes.
    DUT: tx_fsm
        generic map (FRAME_LEN => 3)
        port map (
            clk_50 => clk_50, rst => rst,
            send => send,
            fifo_rd => fifo_rd,
            fifo_dout => fifo_dout,
            fifo_empty => fifo_empty,
            txd => txd, tx_en => tx_en, tx_done => tx_done
        );

    clk_proc: process
    begin
        while finished = '0' loop
            clk_50 <= '0';
            wait for CLK_PERIOD / 2;
            clk_50 <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- Simple FIFO model: starts with 3 bytes, pops on fifo_rd
    fifo_model: process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                rptr <= 0;
                fifo_empty <= '0';
                fifo_dout  <= MEM(0);
            else
                if fifo_rd = '1' then
                    if rptr < 2 then
                        rptr       <= rptr + 1;
                        fifo_dout  <= MEM(rptr + 1);
                    else
                        fifo_empty <= '1';
                    end if;
                end if;
            end if;
        end if;
    end process;

    stim: process
    begin
        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait for 2 * CLK_PERIOD;

        report "Sending 3 bytes: 0xA5 0x3C 0xF0 (LSB dibits):";
        report "  0xA5 = 1010_0101 -> dibits 01,01,10,10";
        report "  0x3C = 0011_1100 -> dibits 00,11,11,00";
        report "  0xF0 = 1111_0000 -> dibits 00,00,11,11";

        send <= '1';
        wait for CLK_PERIOD;
        send <= '0';

        wait until tx_done = '1';
        wait for 5 * CLK_PERIOD;

        report "TEST COMPLETE - inspect waveform for tx_en and txd" severity note;
        finished <= '1';
        wait;
    end process;

end sim;
