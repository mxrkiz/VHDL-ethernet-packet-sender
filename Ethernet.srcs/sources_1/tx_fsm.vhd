-- =============================================================
-- tx_fsm.vhd
-- Transmit FSM: reads bytes from FIFO and sends via RMII
-- 2-bit dibits at 50 MHz (100 Mbps). LSB first.
--
-- Flow: IDLE -> FETCH -> LATCH_ST -> TRANSMIT (4 dibits) ->
--        (byte_cnt < FRAME_LEN ? FETCH : DONE_ST)
--
-- FETCH stalls on fifo_empty='1' instead of aborting, so the
-- frame is not torn apart when packet_builder briefly stops
-- writing (e.g. fifo_full backpressure).
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity tx_fsm is
    Generic (
        FRAME_LEN : integer := 24
    );
    Port (
        clk_50    : in  STD_LOGIC;
        rst       : in  STD_LOGIC;
        send      : in  STD_LOGIC;
        fifo_rd   : out STD_LOGIC;
        fifo_dout : in  STD_LOGIC_VECTOR(7 downto 0);
        fifo_empty: in  STD_LOGIC;
        txd       : out STD_LOGIC_VECTOR(1 downto 0);
        tx_en     : out STD_LOGIC;
        tx_done   : out STD_LOGIC
    );
end tx_fsm;

architecture Behavioral of tx_fsm is

    type state_t is (IDLE, FETCH, LATCH_ST, TRANSMIT, DONE_ST);
    signal state : state_t := IDLE;

    signal byte_buf  : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal dibit_cnt : integer range 0 to 3 := 0;
    signal byte_cnt  : integer range 0 to FRAME_LEN := 0;

begin

    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                state     <= IDLE;
                txd       <= "00";
                tx_en     <= '0';
                tx_done   <= '0';
                fifo_rd   <= '0';
                dibit_cnt <= 0;
                byte_cnt  <= 0;
                byte_buf  <= (others => '0');
            else
                fifo_rd <= '0';
                tx_done <= '0';

                case state is

                    when IDLE =>
                        tx_en    <= '0';
                        txd      <= "00";
                        byte_cnt <= 0;
                        if send = '1' and fifo_empty = '0' then
                            state <= FETCH;
                        end if;

                    when FETCH =>
                        -- Wait for next byte; do NOT abort frame on transient
                        -- empty (FIFO may briefly drain between bytes).
                        if fifo_empty = '0' then
                            fifo_rd <= '1';
                            state   <= LATCH_ST;
                        end if;

                    when LATCH_ST =>
                        byte_buf  <= fifo_dout;
                        dibit_cnt <= 0;
                        tx_en     <= '1';
                        byte_cnt  <= byte_cnt + 1;
                        state     <= TRANSMIT;

                    when TRANSMIT =>
                        tx_en <= '1';
                        -- All dibits come from byte_buf (stable after LATCH_ST)
                        case dibit_cnt is
                            when 0 => txd <= byte_buf(1 downto 0);
                            when 1 => txd <= byte_buf(3 downto 2);
                            when 2 => txd <= byte_buf(5 downto 4);
                            when 3 => txd <= byte_buf(7 downto 6);
                            when others => null;
                        end case;

                        if dibit_cnt = 3 then
                            dibit_cnt <= 0;
                            if byte_cnt = FRAME_LEN then
                                state <= DONE_ST;
                            else
                                state <= FETCH;
                            end if;
                        else
                            dibit_cnt <= dibit_cnt + 1;
                        end if;

                    when DONE_ST =>
                        tx_en    <= '0';
                        txd      <= "00";
                        tx_done  <= '1';
                        byte_cnt <= 0;
                        state    <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;