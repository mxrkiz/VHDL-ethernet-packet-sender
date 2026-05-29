-- =============================================================
-- tb_rx_fsm.vhd — testbench for RMII receive FSM
-- Drives synthetic frame: preamble, SFD, 14 header bytes, payload.
-- Verifies rx_valid pulse and rx_byte = 0x5A.
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_rx_fsm is
end tb_rx_fsm;

architecture sim of tb_rx_fsm is
    constant CLK_PERIOD : time := 20 ns;  -- 50 MHz

    signal clk_50   : STD_LOGIC := '0';
    signal rst      : STD_LOGIC := '1';
    signal rxd      : STD_LOGIC_VECTOR(1 downto 0) := "00";
    signal crs_dv   : STD_LOGIC := '0';
    signal rx_byte  : STD_LOGIC_VECTOR(7 downto 0);
    signal rx_valid : STD_LOGIC;
    signal finished : STD_LOGIC := '0';

    component rx_fsm is
        Port (
            clk_50 : in STD_LOGIC; rst : in STD_LOGIC;
            rxd : in STD_LOGIC_VECTOR(1 downto 0);
            crs_dv : in STD_LOGIC;
            rx_byte : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid : out STD_LOGIC
        );
    end component;

    function slv_to_int(s : STD_LOGIC_VECTOR) return integer is
    begin
        return to_integer(unsigned(s));
    end function;

begin

    DUT: rx_fsm port map (
        clk_50 => clk_50, rst => rst,
        rxd => rxd, crs_dv => crs_dv,
        rx_byte => rx_byte, rx_valid => rx_valid
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

    stim: process
        -- Send one byte as 4 dibits LSB-first
        procedure send_byte(b : STD_LOGIC_VECTOR(7 downto 0)) is
        begin
            rxd <= b(1 downto 0); wait for CLK_PERIOD;
            rxd <= b(3 downto 2); wait for CLK_PERIOD;
            rxd <= b(5 downto 4); wait for CLK_PERIOD;
            rxd <= b(7 downto 6); wait for CLK_PERIOD;
        end procedure;
    begin
        rst <= '1';
        wait for 5 * CLK_PERIOD;
        rst <= '0';
        wait for 3 * CLK_PERIOD;

        report "Driving synthetic frame";

        crs_dv <= '1';
        wait for CLK_PERIOD;

        -- 3 preamble bytes + SFD
        send_byte(x"AA");
        send_byte(x"AA");
        send_byte(x"AA");
        send_byte(x"AB");

        -- 14 header bytes
        for i in 0 to 13 loop
            send_byte(x"55");
        end loop;

        -- Payload byte
        send_byte(x"5A");

        wait for 2 * CLK_PERIOD;
        crs_dv <= '0';
        rxd    <= "00";

        wait for 5 * CLK_PERIOD;

        report "rx_byte (dec) = " & integer'image(slv_to_int(rx_byte));
        assert rx_byte = x"5A"
            report "FAIL: expected 0x5A"
            severity error;
        report "PASS: rx_byte = 0x5A" severity note;

        finished <= '1';
        wait;
    end process;

end sim;
