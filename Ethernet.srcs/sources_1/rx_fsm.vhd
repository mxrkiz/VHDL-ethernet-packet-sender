-- =============================================================
-- rx_fsm.vhd
-- RMII Receiver — captures Ethernet frame and extracts payload.
--
-- Flow:
--   IDLE     : wait for crs_dv='1'
--   PREAMBLE : accumulate dibits LSB-first, look for SFD=0xAB
--   SKIP     : ignore 14 bytes (6 DST + 6 SRC + 2 EtherType)
--   PAYLOAD  : capture 1 byte, assert rx_valid
--   DONE_ST  : wait for carrier to drop
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity rx_fsm is
    Port (
        clk_50    : in  STD_LOGIC;
        rst       : in  STD_LOGIC;
        rxd       : in  STD_LOGIC_VECTOR(1 downto 0);
        crs_dv    : in  STD_LOGIC;
        rx_byte   : out STD_LOGIC_VECTOR(7 downto 0);
        rx_valid  : out STD_LOGIC
    );
end rx_fsm;

architecture Behavioral of rx_fsm is

    type state_t is (IDLE, PREAMBLE, SKIP, PAYLOAD, DONE_ST);
    signal state : state_t := IDLE;

    signal byte_buf  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal next_buf  : STD_LOGIC_VECTOR(7 downto 0);
    signal dibit_cnt : integer range 0 to 3 := 0;
    signal skip_cnt  : integer range 0 to 20 := 0;

    -- After SFD: 6 DST + 6 SRC + 2 EtherType = 14 bytes
    constant SKIP_BYTES : integer := 14;

begin

    -- Shift right: new dibit lands in the top 2 bits (MSB end),
    -- giving LSB-first byte assembly as per RMII spec.
    next_buf <= rxd & byte_buf(7 downto 2);

    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                state     <= IDLE;
                rx_valid  <= '0';
                rx_byte   <= (others => '0');
                dibit_cnt <= 0;
                skip_cnt  <= 0;
                byte_buf  <= (others => '0');
            else
                rx_valid <= '0';

                case state is

                    when IDLE =>
                        dibit_cnt <= 0;
                        byte_buf  <= (others => '0');
                        if crs_dv = '1' then
                            state <= PREAMBLE;
                        end if;

                    when PREAMBLE =>
                        if crs_dv = '0' then
                            state <= IDLE;
                        else
                            byte_buf <= next_buf;
                            -- Compare against next_buf (the value that will
                            -- be stored next cycle) to avoid off-by-one.
                            if next_buf = x"AB" then
                                skip_cnt  <= 0;
                                dibit_cnt <= 0;
                                byte_buf  <= (others => '0');
                                state     <= SKIP;
                            end if;
                        end if;

                    when SKIP =>
                        if crs_dv = '0' then
                            state <= IDLE;
                        else
                            byte_buf <= next_buf;
                            if dibit_cnt = 3 then
                                dibit_cnt <= 0;
                                byte_buf  <= (others => '0');
                                if skip_cnt = SKIP_BYTES - 1 then
                                    skip_cnt <= 0;
                                    state    <= PAYLOAD;
                                else
                                    skip_cnt <= skip_cnt + 1;
                                end if;
                            else
                                dibit_cnt <= dibit_cnt + 1;
                            end if;
                        end if;

                    when PAYLOAD =>
                        if crs_dv = '0' then
                            state <= IDLE;
                        else
                            byte_buf <= next_buf;
                            if dibit_cnt = 3 then
                                rx_byte  <= next_buf;
                                rx_valid <= '1';
                                state    <= DONE_ST;
                            else
                                dibit_cnt <= dibit_cnt + 1;
                            end if;
                        end if;

                    when DONE_ST =>
                        if crs_dv = '0' then
                            state <= IDLE;
                        end if;

                end case;
            end if;
        end if;
    end process;

end Behavioral;