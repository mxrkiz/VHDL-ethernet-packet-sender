-- =============================================================
-- packet_builder.vhd
-- Constructs Ethernet frame and writes bytes into TX FIFO
--
-- Frame layout (24 bytes total):
--   [7 bytes] Preamble  = 0xAA
--   [1 byte]  SFD       = 0xAB
--   [6 bytes] DST MAC   = FF:FF:FF:FF:FF:FF (broadcast)
--   [6 bytes] SRC MAC   = configured via generic
--   [2 bytes] EtherType = 0x0800
--   [1 byte]  Payload   = sw_data
--   [1 byte]  CRC-8 over header+payload (bytes 8..22)
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

entity packet_builder is
    Generic (
        SRC_MAC : STD_LOGIC_VECTOR(47 downto 0) := x"AABBCCDDEEFF"
    );
    Port (
        clk       : in  STD_LOGIC;
        rst       : in  STD_LOGIC;
        build     : in  STD_LOGIC;
        sw_data   : in  STD_LOGIC_VECTOR(7 downto 0);
        fifo_wr   : out STD_LOGIC;
        fifo_din  : out STD_LOGIC_VECTOR(7 downto 0);
        fifo_full : in  STD_LOGIC;
        done      : out STD_LOGIC
    );
end packet_builder;

architecture Behavioral of packet_builder is

    constant FRAME_LEN : integer := 24;

    type frame_t is array(0 to FRAME_LEN-1) of STD_LOGIC_VECTOR(7 downto 0);
    signal frame : frame_t := (others => (others => '0'));

    signal idx : integer range 0 to FRAME_LEN := 0;

    type state_t is (IDLE, BUILD_ST, WAIT_ST, SEND, FINISH_ST);
    signal state : state_t := IDLE;

    component crc8 is
        Port (
            data_in  : in  STD_LOGIC_VECTOR(7 downto 0);
            crc_in   : in  STD_LOGIC_VECTOR(7 downto 0);
            crc_out  : out STD_LOGIC_VECTOR(7 downto 0)
        );
    end component;

    signal crc_data   : STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
    signal crc_acc    : STD_LOGIC_VECTOR(7 downto 0) := x"FF";
    signal crc_result : STD_LOGIC_VECTOR(7 downto 0);

    -- Range of frame bytes that participate in the CRC
    constant CRC_FIRST : integer := 8;   -- first DST MAC byte
    constant CRC_LAST  : integer := 22;  -- payload byte (frame(22))

begin

    CRC_INST: crc8
        port map (
            data_in => crc_data,
            crc_in  => crc_acc,
            crc_out => crc_result
        );

    -- Feed current frame byte into CRC combinationally
    crc_data <= frame(idx) when idx < FRAME_LEN else x"00";

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                state    <= IDLE;
                done     <= '0';
                fifo_wr  <= '0';
                fifo_din <= (others => '0');
                idx      <= 0;
                crc_acc  <= x"FF";
                frame    <= (others => (others => '0'));
            else
                fifo_wr <= '0';
                done    <= '0';

                case state is

                    when IDLE =>
                        if build = '1' then
                            state <= BUILD_ST;
                        end if;

                    when BUILD_ST =>
                        -- Preamble x7
                        frame(0)  <= x"AA"; frame(1)  <= x"AA"; frame(2)  <= x"AA";
                        frame(3)  <= x"AA"; frame(4)  <= x"AA"; frame(5)  <= x"AA";
                        frame(6)  <= x"AA";
                        -- SFD
                        frame(7)  <= x"AB";
                        -- DST MAC (broadcast)
                        frame(8)  <= x"FF"; frame(9)  <= x"FF"; frame(10) <= x"FF";
                        frame(11) <= x"FF"; frame(12) <= x"FF"; frame(13) <= x"FF";
                        -- SRC MAC
                        frame(14) <= SRC_MAC(47 downto 40);
                        frame(15) <= SRC_MAC(39 downto 32);
                        frame(16) <= SRC_MAC(31 downto 24);
                        frame(17) <= SRC_MAC(23 downto 16);
                        frame(18) <= SRC_MAC(15 downto 8);
                        frame(19) <= SRC_MAC(7  downto 0);
                        -- EtherType 0x0800
                        frame(20) <= x"08"; frame(21) <= x"00";
                        -- Payload
                        frame(22) <= sw_data;
                        -- CRC placeholder (overwritten in SEND with crc_acc)
                        frame(23) <= x"00";

                        crc_acc <= x"FF";
                        idx     <= 0;
                        state   <= WAIT_ST;

                    when WAIT_ST =>
                        -- One cycle for frame signals to settle
                        state <= SEND;

                    when SEND =>
                        if fifo_full = '0' then
                            if idx < FRAME_LEN - 1 then
                                fifo_din <= frame(idx);
                                fifo_wr  <= '1';
                                if idx >= CRC_FIRST and idx <= CRC_LAST then
                                    crc_acc <= crc_result;
                                end if;
                                idx <= idx + 1;
                            else
                                -- Last slot: write accumulated CRC
                                fifo_din <= crc_acc;
                                fifo_wr  <= '1';
                                state    <= FINISH_ST;
                            end if;
                        end if;

                    when FINISH_ST =>
                        done  <= '1';
                        idx   <= 0;
                        state <= IDLE;

                end case;
            end if;
        end if;
    end process;

end Behavioral;