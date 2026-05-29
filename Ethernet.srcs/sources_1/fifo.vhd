-- =============================================================
-- fifo.vhd
-- Synchronous FIFO, depth=16, width=8
-- Used between Packet Builder and PHY TX
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity fifo is
    Generic (
        DEPTH : integer := 16;
        WIDTH : integer := 8
    );
    Port (
        clk      : in  STD_LOGIC;
        rst      : in  STD_LOGIC;
        wr_en    : in  STD_LOGIC;
        rd_en    : in  STD_LOGIC;
        din      : in  STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        dout     : out STD_LOGIC_VECTOR(WIDTH-1 downto 0);
        empty    : out STD_LOGIC;
        full     : out STD_LOGIC
    );
end fifo;

architecture Behavioral of fifo is
    type mem_t is array(0 to DEPTH-1) of STD_LOGIC_VECTOR(WIDTH-1 downto 0);
    signal mem    : mem_t := (others => (others => '0'));
    signal wr_ptr : unsigned(3 downto 0) := (others => '0');
    signal rd_ptr : unsigned(3 downto 0) := (others => '0');
    signal count  : integer range 0 to DEPTH := 0;

    signal can_write : STD_LOGIC;
    signal can_read  : STD_LOGIC;

begin

    empty <= '1' when count = 0     else '0';
    full  <= '1' when count = DEPTH else '0';

    can_write <= wr_en when count < DEPTH else '0';
    can_read  <= rd_en when count > 0     else '0';

    -- First-word-fall-through (FWFT): dout always shows the byte that
    -- WOULD be popped on the next rd_en pulse, so a consumer FSM that
    -- samples dout one cycle after asserting rd_en (e.g. tx_fsm's
    -- FETCH → LATCH_ST sequence) receives the correct byte. The
    -- previous "show-after-read" version delayed dout by one cycle,
    -- which made the first byte arrive as junk and silently dropped
    -- the last (CRC) byte from every transmitted frame.
    dout <= mem(to_integer(rd_ptr)) when count > 0 else (others => '0');

    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                wr_ptr <= (others => '0');
                rd_ptr <= (others => '0');
                count  <= 0;
            else
                -- Write
                if can_write = '1' then
                    mem(to_integer(wr_ptr)) <= din;
                    if wr_ptr = DEPTH-1 then
                        wr_ptr <= (others => '0');
                    else
                        wr_ptr <= wr_ptr + 1;
                    end if;
                end if;

                -- Read: only advance the pointer; dout is combinational
                if can_read = '1' then
                    if rd_ptr = DEPTH-1 then
                        rd_ptr <= (others => '0');
                    else
                        rd_ptr <= rd_ptr + 1;
                    end if;
                end if;

                -- Count: handle all four combinations
                if can_write = '1' and can_read = '0' then
                    count <= count + 1;
                elsif can_write = '0' and can_read = '1' then
                    count <= count - 1;
                -- else: idle OR simultaneous r+w -> unchanged
                end if;
            end if;
        end if;
    end process;

end Behavioral;