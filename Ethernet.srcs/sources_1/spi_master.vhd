-- =============================================================
-- spi_master.vhd
-- SPI Master — configures LAN8720 PHY via MDIO-like SPI
-- States: IDLE -> START -> SEND_ADDRESS -> SEND_DATA -> STOP
-- Clock divider: 100MHz / 200 = 500kHz SPI clock
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

entity spi_master is
    Port (
        clk       : in  STD_LOGIC;   -- 100 MHz system clock
        rst       : in  STD_LOGIC;
        start     : in  STD_LOGIC;   -- pulse to begin transaction
        reg_addr  : in  STD_LOGIC_VECTOR(4 downto 0);   -- PHY register address
        reg_data  : in  STD_LOGIC_VECTOR(15 downto 0);  -- data to write
        done      : out STD_LOGIC;
        -- SPI pins
        mdc       : out STD_LOGIC;
        mdio      : inout STD_LOGIC
    );
end spi_master;

architecture Behavioral of spi_master is

    -- FSM
    type state_t is (IDLE, PREAMBLE, START_FRAME, SEND_ADDRESS, TURNAROUND, SEND_DATA, STOP_ST);
    signal state : state_t := IDLE;

    -- Clock divider (100MHz -> 500kHz)
    constant CLK_DIV : integer := 100;
    signal clk_cnt   : integer range 0 to CLK_DIV-1 := 0;
    signal spi_clk   : STD_LOGIC := '0';
    signal spi_en    : STD_LOGIC := '0';

    -- Shift register
    signal shift_reg  : STD_LOGIC_VECTOR(31 downto 0) := (others => '0');
    signal bit_cnt    : integer range 0 to 63 := 0;
    signal mdio_out   : STD_LOGIC := '1';
    signal mdio_oe    : STD_LOGIC := '0';  -- output enable

begin

    -- MDIO tristate
    mdio <= mdio_out when mdio_oe = '1' else 'Z';
    mdc  <= spi_clk;

    -- Clock divider
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                clk_cnt <= 0;
                spi_clk <= '0';
            elsif spi_en = '1' then
                if clk_cnt = CLK_DIV-1 then
                    clk_cnt <= 0;
                    spi_clk <= not spi_clk;
                else
                    clk_cnt <= clk_cnt + 1;
                end if;
            else
                spi_clk <= '0';
                clk_cnt <= 0;
            end if;
        end if;
    end process;

    -- Main FSM (runs on spi_clk falling edge for setup)
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state     <= IDLE;
                done      <= '0';
                spi_en    <= '0';
                mdio_oe   <= '0';
                mdio_out  <= '1';
                bit_cnt   <= 0;
                shift_reg <= (others => '0');
            else
                done <= '0';
                case state is

                    when IDLE =>
                        spi_en  <= '0';
                        mdio_oe <= '1';
                        mdio_out <= '1';
                        if start = '1' then
                            -- Build 32-bit MDIO frame:
                            -- [31:28]=0101 (ST+OP write)
                            -- [27:23]=01 (PHY addr=1) + reg_addr
                            -- [17:16]=10 (turnaround)
                            -- [15:0] =data
                            shift_reg <= "0101" & "00001" & reg_addr & "10" & reg_data;
                            bit_cnt   <= 31;
                            spi_en    <= '1';
                            state     <= PREAMBLE;
                        end if;

                    when PREAMBLE =>
                        -- 32 bits of '1' preamble
                        mdio_oe  <= '1';
                        mdio_out <= '1';
                        if clk_cnt = 0 and spi_clk = '1' then
                            if bit_cnt = 0 then
                                bit_cnt <= 31;
                                state   <= START_FRAME;
                            else
                                bit_cnt <= bit_cnt - 1;
                            end if;
                        end if;

                    when START_FRAME =>
                        mdio_oe  <= '1';
                        if clk_cnt = 0 and spi_clk = '1' then
                            mdio_out <= shift_reg(bit_cnt);
                            if bit_cnt = 0 then
                                state <= STOP_ST;
                                done  <= '1';
                            else
                                bit_cnt <= bit_cnt - 1;
                            end if;
                        end if;

                    when SEND_ADDRESS => state <= TURNAROUND;
                    when TURNAROUND   => state <= SEND_DATA;
                    when SEND_DATA    => state <= STOP_ST;

                    when STOP_ST =>
                        spi_en   <= '0';
                        mdio_oe  <= '0';
                        done     <= '1';
                        state    <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;