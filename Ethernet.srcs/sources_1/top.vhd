-- =============================================================
-- top.vhd
-- Ethernet Packet Sender — Top-level
-- Board: Digilent Nexys A7-50T
-- PHY  : SMSC LAN8720A (RMII, address 0x01)
--
-- Clocking: single 50 MHz domain (clk_50). The 100 MHz onboard
-- oscillator (pin E3) drives only one toggle FF that produces
-- clk_50; that signal is forwarded to the PHY through an ODDR
-- primitive and clocks every other piece of fabric in this design
-- (debounce, FIFO, packet_builder, tx_fsm, rx_fsm, 7-seg scanner,
-- spi_master). Single-domain layout means no clock-domain crossing
-- between MAC building blocks.
--
-- I/O:
--   sw[7:0]  — payload byte
--   sw[8]    — show own MAC on RX display
--   btnC     — SEND pulse (debounced)
--   led[7:0] — mirror sw[7:0]
--   seg/an   — single shared 8-digit 7-seg (AN0/1 = TX byte, AN6/7 = RX)
--   eth_*    — RMII + MDIO to LAN8720A
-- =============================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.all;   -- ODDR primitive

entity top is
    Port (
        clk         : in    STD_LOGIC;   -- 100 MHz onboard (E3)
        rst         : in    STD_LOGIC;   -- btnR, active high (M17)
        sw          : in    STD_LOGIC_VECTOR(8 downto 0);
        btnC        : in    STD_LOGIC;   -- Send (N17)
        led         : out   STD_LOGIC_VECTOR(7 downto 0);
        -- 7-seg (shared bus, active LOW)
        seg         : out   STD_LOGIC_VECTOR(6 downto 0);
        dp          : out   STD_LOGIC;
        an          : out   STD_LOGIC_VECTOR(7 downto 0);
        -- RMII PHY
        eth_txd     : out   STD_LOGIC_VECTOR(1 downto 0);
        eth_tx_en   : out   STD_LOGIC;
        eth_rxd     : in    STD_LOGIC_VECTOR(1 downto 0);
        eth_crs_dv  : in    STD_LOGIC;
        eth_rxerr   : in    STD_LOGIC;
        eth_ref_clk : out   STD_LOGIC;
        eth_rst_n   : out   STD_LOGIC;
        -- MDIO
        eth_mdc     : out   STD_LOGIC;
        eth_mdio    : inout STD_LOGIC
    );
end top;

architecture Behavioral of top is

    -- ── Component declarations ────────────────────────────────
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

    component rx_fsm is
        Port (
            clk_50 : in STD_LOGIC; rst : in STD_LOGIC;
            rxd : in STD_LOGIC_VECTOR(1 downto 0);
            crs_dv : in STD_LOGIC;
            rx_byte : out STD_LOGIC_VECTOR(7 downto 0);
            rx_valid : out STD_LOGIC
        );
    end component;

    component spi_master is
        Port (
            clk : in STD_LOGIC; rst : in STD_LOGIC;
            start : in STD_LOGIC;
            reg_addr : in STD_LOGIC_VECTOR(4 downto 0);
            reg_data : in STD_LOGIC_VECTOR(15 downto 0);
            done : out STD_LOGIC;
            mdc : out STD_LOGIC;
            mdio : inout STD_LOGIC
        );
    end component;

    component debounce is
        Port (
            clk         : in  std_logic;
            rst         : in  std_logic;
            btn_in      : in  std_logic;
            btn_state   : out std_logic;
            btn_press   : out std_logic
        );
    end component;

    -- ── Clocks ───────────────────────────────────────────────
    -- clk_50_pre = toggle-FF output (logic net, in fabric)
    -- clk_50     = same signal AFTER BUFG, on a global clock network.
    -- Every sequential element AND the ODDR.C pin uses clk_50, so the
    -- BUFG promotion is mandatory: ODDR's clock input is hardwired to
    -- a global clock route, and a logic-driven net would not satisfy
    -- that — placement would either fail or yield a distorted REF_CLK.
    signal clk_50_pre : STD_LOGIC := '0';
    signal clk_50     : STD_LOGIC;

    -- ── Button debouncer output ──────────────────────────────
    signal send_pulse : STD_LOGIC;

    -- ── FIFO wires ───────────────────────────────────────────
    signal fifo_wr_en   : STD_LOGIC;
    signal fifo_rd_en   : STD_LOGIC;
    signal fifo_din_s   : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_dout_s  : STD_LOGIC_VECTOR(7 downto 0);
    signal fifo_empty_s : STD_LOGIC;
    signal fifo_full_s  : STD_LOGIC;

    -- ── Builder / TX ─────────────────────────────────────────
    signal build_done_s : STD_LOGIC;
    signal tx_start_s   : STD_LOGIC;  -- held high once build done, cleared when TX done
    signal tx_done_s    : STD_LOGIC;

    -- ── RX ───────────────────────────────────────────────────
    signal rx_byte_s  : STD_LOGIC_VECTOR(7 downto 0);
    signal rx_valid_s : STD_LOGIC;
    signal rx_display : STD_LOGIC_VECTOR(7 downto 0) := x"00";

    -- ── TX display latch ─────────────────────────────────────
    signal tx_display : STD_LOGIC_VECTOR(7 downto 0) := x"00";

    -- ── SPI / PHY init ───────────────────────────────────────
    signal spi_start      : STD_LOGIC := '0';
    signal phy_init_done  : STD_LOGIC := '0';
    -- 25 ms post-reset delay required by LAN8720A before first MDIO write.
    -- 25 ms * 50 MHz = 1_250_000 cycles.
    signal phy_rst_cnt    : integer range 0 to 1_250_000 := 0;
    signal phy_rst_done   : STD_LOGIC := '0';

    -- ── MAC constants ────────────────────────────────────────
    constant OWN_MAC : STD_LOGIC_VECTOR(47 downto 0) := x"AABBCCDDEEFF";
    signal mac_display : STD_LOGIC_VECTOR(7 downto 0);
    signal seg_data_rx : STD_LOGIC_VECTOR(7 downto 0);

    -- ── Diagnostic LED stretch (~0.5 s @ 50 MHz = 25_000_000) ──
    signal tx_led_stretch : integer range 0 to 25_000_000 := 0;
    signal tx_led         : STD_LOGIC := '0';

    -- ── 7-seg scanning (50 MHz domain: 49_999 cycles ≈ 1 ms / digit) ─
    signal seg_refresh : integer range 0 to 49999 := 0;
    signal seg_digit   : integer range 0 to 7 := 0;

begin

    ----------------------------------------------------------------
    -- 50 MHz reference clock generator (toggle divider on clk).
    -- This is the ONLY process clocked by the 100 MHz pin; it
    -- produces clk_50_pre that BUFG_50 promotes to a global clock
    -- (clk_50) used by the rest of the fabric and the ODDR primitive.
    ----------------------------------------------------------------
    process(clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                clk_50_pre <= '0';
            else
                clk_50_pre <= not clk_50_pre;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- BUFG: put the divided clock on a global clock network.
    -- Without this, Vivado may route clk_50 over generic fabric,
    -- giving large skew across loads and an unusable REF_CLK at
    -- the PHY (root cause of the missing TX activity LED).
    ----------------------------------------------------------------
    BUFG_50 : BUFG
        port map (
            I => clk_50_pre,
            O => clk_50
        );

    ----------------------------------------------------------------
    -- Forward clk_50 to PHY via ODDR primitive.
    -- OPPOSITE_EDGE mode: D1 is captured on rising edge of C, D2 on falling.
    -- D1='1', D2='0' → Q is HIGH on rising clk_50, LOW on falling clk_50
    -- → eth_ref_clk is in-phase with clk_50.
    -- TX_EN/TXD are registered in IOBs on rising clk_50, so they are
    -- stable well before the next rising edge of REF_CLK at the PHY
    -- (setup margin = one full 20 ns period minus IOB output delay ~2 ns).
    ----------------------------------------------------------------
    ODDR_REF_CLK : ODDR
        generic map (
            DDR_CLK_EDGE => "OPPOSITE_EDGE",
            INIT         => '0',
            SRTYPE       => "SYNC"
        )
        port map (
            Q  => eth_ref_clk,
            C  => clk_50,
            CE => '1',
            D1 => '1',
            D2 => '0',
            R  => '0',
            S  => '0'
        );

    -- PHY hardware reset: held low while rst=1
    eth_rst_n <= not rst;

    -- led(0): TX activity (stretched ~0.5s so a brief frame is visible)
    -- led(1): PHY init done (goes on 25ms after reset deasserts)
    -- led(7:2): mirror sw[5:0]
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                tx_led <= '0';
                tx_led_stretch <= 0;
            elsif tx_done_s = '1' then
                tx_led <= '1';
                tx_led_stretch <= 25_000_000;
            elsif tx_led_stretch > 0 then
                tx_led_stretch <= tx_led_stretch - 1;
            else
                tx_led <= '0';
            end if;
        end if;
    end process;
    led(0) <= tx_led;
    led(1) <= phy_init_done;
    led(7 downto 2) <= sw(5 downto 0);

    ----------------------------------------------------------------
    -- Debounced SEND button (lab_modules/debounce, runs on clk_50)
    ----------------------------------------------------------------
    DEB_SEND : debounce
        port map (
            clk       => clk_50,
            rst       => rst,
            btn_in    => btnC,
            btn_state => open,
            btn_press => send_pulse
        );

    -- Latch the TX byte on button press
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                tx_display <= (others => '0');
            elsif send_pulse = '1' then
                tx_display <= sw(7 downto 0);
            end if;
        end if;
    end process;

    -- Latch RX byte whenever a packet arrives.
    -- Drop the latch if the PHY signalled a receive error on this frame
    -- (eth_rxerr is the LAN8720A RXER pin; high = corrupt nibble).
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                rx_display <= (others => '0');
            elsif rx_valid_s = '1' and eth_rxerr = '0' then
                rx_display <= rx_byte_s;
            end if;
        end if;
    end process;

    mac_display <= OWN_MAC(47 downto 40);
    seg_data_rx <= mac_display when sw(8) = '1' else rx_display;

    ----------------------------------------------------------------
    -- Unified 8-digit 7-seg scanner
    --   AN0/AN1 = TX byte (low/high nibble)
    --   AN6/AN7 = RX byte (low/high nibble)
    --   others  = blank
    -- 49_999 cycles @ 50 MHz ≈ 1 ms / digit → 8 digits ≈ 8 ms full
    -- cycle ≈ 125 Hz refresh, well above flicker threshold.
    ----------------------------------------------------------------
    process(clk_50)
        variable nibble_v : STD_LOGIC_VECTOR(3 downto 0);
        variable seg_v    : STD_LOGIC_VECTOR(6 downto 0);
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                seg_refresh <= 0;
                seg_digit   <= 0;
                an          <= "11111111";
                seg         <= "1111111";
                dp          <= '1';
            else
                dp <= '1';

                if seg_refresh = 49999 then
                    seg_refresh <= 0;
                    if seg_digit = 7 then
                        seg_digit <= 0;
                    else
                        seg_digit <= seg_digit + 1;
                    end if;
                else
                    seg_refresh <= seg_refresh + 1;
                end if;

                an <= "11111111";
                nibble_v := "0000";
                case seg_digit is
                    when 0 => an(0) <= '0'; nibble_v := tx_display(3 downto 0);
                    when 1 => an(1) <= '0'; nibble_v := tx_display(7 downto 4);
                    when 6 => an(6) <= '0'; nibble_v := seg_data_rx(3 downto 0);
                    when 7 => an(7) <= '0'; nibble_v := seg_data_rx(7 downto 4);
                    when others => null;
                end case;

                case nibble_v is
                    when "0000" => seg_v := "1000000";
                    when "0001" => seg_v := "1111001";
                    when "0010" => seg_v := "0100100";
                    when "0011" => seg_v := "0110000";
                    when "0100" => seg_v := "0011001";
                    when "0101" => seg_v := "0010010";
                    when "0110" => seg_v := "0000010";
                    when "0111" => seg_v := "1111000";
                    when "1000" => seg_v := "0000000";
                    when "1001" => seg_v := "0010000";
                    when "1010" => seg_v := "0001000";
                    when "1011" => seg_v := "0000011";
                    when "1100" => seg_v := "1000110";
                    when "1101" => seg_v := "0100001";
                    when "1110" => seg_v := "0000110";
                    when "1111" => seg_v := "0001110";
                    when others => seg_v := "1111111";
                end case;
                seg <= seg_v;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- PHY post-reset delay + SPI init.
    -- LAN8720A requires RST# to be held low for ≥100 µs then a
    -- 25 ms quiet period before the first MDIO transaction.
    -- We wait 1_250_000 clk_50 cycles (= 25 ms) after rst deasserts,
    -- then fire a single MDIO write to register 0 (basic control).
    ----------------------------------------------------------------
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                phy_init_done <= '0';
                phy_rst_done  <= '0';
                phy_rst_cnt   <= 0;
                spi_start     <= '0';
            else
                spi_start <= '0';
                if phy_rst_done = '0' then
                    if phy_rst_cnt = 1_250_000 then
                        phy_rst_done <= '1';
                    else
                        phy_rst_cnt <= phy_rst_cnt + 1;
                    end if;
                elsif phy_init_done = '0' then
                    spi_start     <= '1';
                    phy_init_done <= '1';
                end if;
            end if;
        end if;
    end process;

    ----------------------------------------------------------------
    -- Module instantiations (everything on clk_50 — single domain)
    ----------------------------------------------------------------
    FIFO_INST : fifo
        generic map (DEPTH => 16, WIDTH => 8)
        port map (
            clk => clk_50, rst => rst,
            wr_en => fifo_wr_en, rd_en => fifo_rd_en,
            din => fifo_din_s, dout => fifo_dout_s,
            empty => fifo_empty_s, full => fifo_full_s
        );

    PKT_INST : packet_builder
        generic map (SRC_MAC => OWN_MAC)
        port map (
            clk => clk_50, rst => rst,
            build => send_pulse,
            sw_data => sw(7 downto 0),
            fifo_wr => fifo_wr_en,
            fifo_din => fifo_din_s,
            fifo_full => fifo_full_s,
            done => build_done_s
        );

    -- tx_start_s is set when packet_builder signals done (full frame in FIFO)
    -- and cleared when tx_fsm finishes sending. This prevents tx_fsm from
    -- seeing a non-empty FIFO mid-build and starting on a partial frame.
    process(clk_50)
    begin
        if rising_edge(clk_50) then
            if rst = '1' then
                tx_start_s <= '0';
            elsif build_done_s = '1' then
                tx_start_s <= '1';
            elsif tx_done_s = '1' then
                tx_start_s <= '0';
            end if;
        end if;
    end process;

    TX_INST : tx_fsm
        generic map (FRAME_LEN => 24)
        port map (
            clk_50 => clk_50, rst => rst,
            send => tx_start_s,
            fifo_rd => fifo_rd_en,
            fifo_dout => fifo_dout_s,
            fifo_empty => fifo_empty_s,
            txd => eth_txd,
            tx_en => eth_tx_en,
            tx_done => tx_done_s
        );

    RX_INST : rx_fsm
        port map (
            clk_50 => clk_50, rst => rst,
            rxd => eth_rxd,
            crs_dv => eth_crs_dv,
            rx_byte => rx_byte_s,
            rx_valid => rx_valid_s
        );

    SPI_INST : spi_master
        port map (
            clk => clk_50, rst => rst,
            start => spi_start,
            reg_addr => "00000",
            reg_data => x"2100",
            done => open,
            mdc => eth_mdc,
            mdio => eth_mdio
        );

end Behavioral;
