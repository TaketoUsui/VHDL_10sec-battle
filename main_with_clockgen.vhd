library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity main_with_clockgen is
  generic(N: integer := 32;
          K: integer := 4;
          W: integer := 3);
  port(
    CLOCK_50, RESET_N: in std_logic;

    -- KEYはボタン。FPGAボードの4つのボタンを押すと、対応するビットが0になる。
    KEY: in std_logic_vector(3 downto 0);

    -- SWはスイッチ。FPGAボードでONとOFFを切り替えられるが、今回は使わない。
    SW: in std_logic_vector(9 downto 0);
    
    -- GPIOは相手回路とつなぐ導線の電気信号。
    GPIO_0: inout std_logic_vector (35 downto 0);
    GPIO_1: inout std_logic_vector (35 downto 0);
    
    -- LEDRはLEDランプだが、今回は使わない。
    LEDR: out std_logic_vector (9 downto 0);
    
    -- HEXは7セグメントディスプレイ
    HEX0, HEX1, HEX2, HEX3, HEX4, HEX5: out std_logic_vector(6 downto 0));
end main_with_clockgen;

architecture rtl of main_with_clockgen is

  -- 通信周期の5分の1の長さをクロック数で指定。回路が想定通り動作していることをすぐに確かめられるよう、目に見えるぐらいの遅さにしている。
  constant CNT_MAX: std_logic_vector(31 downto 0):= X"004AF080";

  -- 0.1ミリ秒のクロック数。FPGAボードは50MHzのクロックで作動。
  constant HUND_MICRO_SEC: std_logic_vector(31 downto 0):= X"00001388";

  -- ステートマシンを実装するための「ステート」の定義。
  type state_type is (s0, s1, s2, s3, s4, s5, s6);
  signal state: state_type;

  -- 「準備OK」と「アイドル」の2種類のモードを表現。
  signal mode: std_logic;

  -- クロックシグナルと、この回路全体のリセットシグナル
  signal clk, xrst: std_logic;

  -- enableが'1'である間、通信周期の生成を行う。
  signal enable: std_logic;

  -- 「通信周期の5分の1」を5回繰り返すために使用。
  signal clk_tx_state: state_type;

  -- 「通信周期の5分の1」ごとに1になるフラグ。
  signal clk_tx: std_logic;

  -- clk_on_cntが1の間、クロックの回数をカウントする。
  signal clk_cnt: std_logic_vector(31 downto 0);
  
  -- 相手回路から受け取ったレディー信号と、送るレディー信号。
  signal ready_received: std_logic;
  signal ready_send: std_logic;

  -- 相手回路から受け取ったデータ4bitと、送るデータ4bit。
  signal data_received: std_logic_vector (3 downto 0);
  signal data_send: std_logic_vector (3 downto 0);

  -- 送信中のステートを管理。
  signal send_state: state_type;

  -- 勝敗を記録。
  type win_or_lose_type is (win, lose, draw, nodata);
  signal win_or_lose: win_or_lose_type;

  -- ディスプレイに段階表示するためのステート。
  signal display_state: state_type;

  -- 0.1ミリ秒単位でカウントできるカウンター。
   -- 最上位ビットは符号（正：0000, 負：0001）
   -- 十の位：counter(23 downto 20), 一の位：counter(19 downto 16), 小数第一位：counter(15 downto 12)...
  signal counter: std_logic_vector(27 downto 0);

  -- 自分のゲーム記録と、相手の記録をそれぞれ保存。
  signal my_score: std_logic_vector(23 downto 0);
  signal en_score: std_logic_vector(23 downto 0);

  -- 7セグメントディスプレイで表示する値を管理するためのシグナル。
  signal led0, led1, led2, led3, led4, led5: std_logic_vector(6 downto 0); -- ディスプレイに表示する文字。
  signal led0_num, led1_num, led2_num, led3_num, led4_num, led5_num: std_logic_vector(3 downto 0):= "0000"; -- ディスプレイに表示する数字。
  signal led_num_digit: std_logic_vector(41 downto 0); -- ディスプレイに表示する数字をデコードしたもの。
  signal led_isnum: std_logic_vector(5 downto 0); -- ディスプレイに文字を表示するか、数字を表示するかを設定するためのシグナル。

  -- 非同期な入力を同期回路の中で処理するためのフラグ。
  signal key_flag: std_logic_vector (3 downto 0);
  signal clk_tx_flag, clk_tx_prev: std_logic;
  signal clk_on_cnt: std_logic;

  -- 送信用クロック（＝送信周期）生成回路
  component clock_gen
    generic(N: integer);
    port(clk, xrst: in std_logic;
         enable: in std_logic;
         cnt_max: in std_logic_vector (N-1 downto 0);
         clk_tx: out std_logic);
  end component;

  -- 7セグメントデコーダ
  component seven_seg_decoder is
    port(clk: in std_logic;
         xrst: in std_logic;
         din: in std_logic_vector(3 downto 0);
         dout: out std_logic_vector(6 downto 0));
  end component;

begin
  clk <= CLOCK_50;
  xrst <= RESET_N;
  data_received <= GPIO_0(4 downto 1);
  ready_received <= GPIO_0(0);

  -- 通信周期生成の回路をインスタンス化。
  cg1: clock_gen generic map(N => N) port map(clk => clk, xrst => xrst, enable => enable, cnt_max => CNT_MAX, clk_tx => clk_tx);
  -- 7セグディスプレイに表示するために、2進数をデコードする回路をインスタンス化。
  ssd0: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led0_num, dout => led_num_digit(6 downto 0));
  ssd1: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led1_num, dout => led_num_digit(13 downto 7));
  ssd2: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led2_num, dout => led_num_digit(20 downto 14));
  ssd3: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led3_num, dout => led_num_digit(27 downto 21));
  ssd4: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led4_num, dout => led_num_digit(34 downto 28));
  ssd5: seven_seg_decoder port map(clk => clk, xrst => xrst, din => led5_num, dout => led_num_digit(41 downto 35));

-- process記述開始

  -- 送信周期ごとに一瞬だけ「1」になるclk_txの立ち上がりをキャッチし、二つ目のプロセス「process(clk, xrst)」で処理できるようにするためのプロセス。
  process(clk_tx, clk) begin
    if(clk_tx'event and clk_tx = '1')then
      clk_tx_flag <= '1';
    end if;
    if(clk_tx_prev = '1')then
      clk_tx_flag <= '0';
    end if;
  end process;

  -- メインプロセス。
  process(clk, xrst) begin
  
    -- リセットボタンが押された場合、非同期で回路の状態をリセットする。
    if(xrst = '0') then
      state <= s0;
      
      enable <= '0';
      mode <= '0';
      ready_send <= '0';

      clk_on_cnt <= '0';
      send_state <= s0;
      win_or_lose <= nodata;
    
    -- clkによる同期処理の実装。
    elsif(clk'event and clk = '1') then

      -- ステート０での処理。「準備OK」と「アイドル」の状態を切り替えられる。
      -- 「準備OK」なら、相手方の回路へ「readyシグナル」を送る。
      if(state = s0) then
        if(KEY(0) = '0') then
          mode <= '1';
          ready_send <= '1';
        else
          mode <= '0';
          ready_send <= '0';
        end if;
        if(mode = '1' and ready_received = '1') then
          state <= s1;
          counter <= X"0110000";
        end if;

      -- ステート１での処理。ゲームスタート。
      -- カウントダウンが始まるが、実際にカウントダウンをする処理は、このコードの下の方で実装している。
      elsif(state = s1) then
        ready_send <= '0';
        clk_on_cnt <= '1';
        if(KEY(0) = '0' and (counter(27 downto 24) = X"1" or counter(23 downto 16) < X"10")) then
          state <= s2;
          clk_on_cnt <= '0';
        end if;

      -- ステート２での処理。ストップボタンが押下され、相手のストップボタン押下を待つフェーズ。
      -- 相手を待っている間に、10進数7桁の記録を、10進数6桁の記録に圧縮する。記録があまりにも悪い場合は、符号バイトを2として、オーバーフロー扱いにする。
      elsif(state = s2) then
        if(counter(23 downto 20) = X"0") then
          my_score(23 downto 20) <= counter(27 downto 24);
        else
          my_score(23 downto 20) <= X"2";
        end if;
        my_score(19 downto 0) <= counter(19 downto 0);

        if(ready_received = '1')then
          state <= s3;
          send_state <= s0;
          clk_tx_state <= s0;
          ready_send <= '0';
          enable <= '1';
        end if;

      -- ステート３での処理。双方向通信を行う。
      elsif(state = s3) then
        if(clk_tx_flag /= clk_tx_prev) then
          if(clk_tx_flag = '1') then
            if(clk_tx_state = s0) then
              if(send_state = s0 and ready_send = '0') then
                ready_send <= '1';
              elsif(send_state = s0 and ready_send = '1') then
                ready_send <= '0';
                send_state <= s6;
                data_send <= my_score(23 downto 20);
              elsif(send_state = s6) then
                send_state <= s5;
                data_send <= my_score(19 downto 16);
              elsif(send_state = s5) then
                send_state <= s4;
                data_send <= my_score(15 downto 12);
              elsif(send_state = s4) then
                send_state <= s3;
                data_send <= my_score(11 downto 8);
              elsif(send_state = s3) then
                send_state <= s2;
                data_send <= my_score(7 downto 4);
              elsif(send_state = s2) then
                send_state <= s1;
                data_send <= my_score(3 downto 0);
              elsif(send_state = s1) then
                send_state <= s0;
                state <= s4;
                display_state <= s0;
              end if;
              clk_tx_state <= s1;
              display_state <= s0;
            elsif(clk_tx_state = s1) then
              clk_tx_state <= s2;
            elsif(clk_tx_state = s2) then
              clk_tx_state <= s3;
              if(send_state = s6) then
                en_score(23 downto 20) <= data_received;
              elsif(send_state = s5) then
                en_score(19 downto 16) <= data_received;
              elsif(send_state = s4) then
                en_score(15 downto 12) <= data_received;
              elsif(send_state = s3) then
                en_score(11 downto 8) <= data_received;
              elsif(send_state = s2) then
                en_score(7 downto 4) <= data_received;
              elsif(send_state = s1) then
                en_score(3 downto 0) <= data_received;
              end if;
            elsif(clk_tx_state = s3) then
              clk_tx_state <= s4;
            else
              clk_tx_state <= s0;
            end if;
          end if;
          clk_tx_prev <= clk_tx_flag;
        end if;

      -- ステート４での処理。結果発表のフェーズ。
      -- 自分の記録を1秒ごとに1桁ずつ表示する。
      elsif(state = s4) then
        if(display_state = s0) then
          if(my_score(23 downto 20) = X"2" and en_score(23 downto 20) /= X"2") then
            win_or_lose <= lose;
          elsif(my_score(23 downto 20) /= X"2" and en_score(23 downto 20) = X"2") then
            win_or_lose <= win;
          elsif(my_score(23 downto 20) = X"2" and en_score(23 downto 20) = X"2") then
            win_or_lose <= draw;
          else
            if(my_score(19 downto 0) > en_score(19 downto 0)) then
              win_or_lose <= lose;
            elsif(my_score(19 downto 0) < en_score(19 downto 0)) then
              win_or_lose <= win;
            else
              win_or_lose <= draw;
            end if;
          end if;
          display_state <= s6;
          counter <= X"0010000";
          clk_on_cnt <= '1';
        elsif(display_state = s6) then
          if(counter >= X"1000000") then
            display_state <= s5;
            counter <= X"0010000";
          end if;
        elsif(display_state = s5) then
          if(counter >= X"1000000") then
            -- if(my_score(23 downto 16) = en_score(23 downto 16)) then
              display_state <= s4;
              counter <= X"0010000";
            -- else
              -- state <= s5;
              -- clk_on_cnt <= '0';
            -- end if;
          end if;
        elsif(display_state = s4) then
          if(counter >= X"1000000") then
            -- if(my_score(15 downto 12) = en_score(15 downto 12)) then
              display_state <= s3;
              counter <= X"0010000";
            -- else
              -- state <= s5;
              -- clk_on_cnt <= '0';
            -- end if;
          end if;
        elsif(display_state = s3) then
          if(counter >= X"1000000") then
            -- if(my_score(11 downto 8) = en_score(11 downto 8)) then
              display_state <= s2;
              counter <= X"0010000";
            -- else
              -- state <= s5;
              -- clk_on_cnt <= '0';
            -- end if;
          end if;
        elsif(display_state = s2) then
          if(counter >= X"1000000") then
            -- if(my_score(7 downto 4) = en_score(7 downto 4)) then
              display_state <= s1;
              counter <= X"0010000";
            -- else
              -- state <= s5;
              -- clk_on_cnt <= '0';
            -- end if;
          end if;
        elsif(display_state = s1) then
          if(counter >= X"1000000") then
            state <= s5;
            clk_on_cnt <= '0';
          end if;
        end if;

      -- ステート５での処理。
      -- ボタンが押されるとステートを６にする。
      -- 7セグメントディスプレイには勝敗が表示されるが、表示の処理は下に記述している。
      elsif(state = s5) then
        if(KEY(0) /= key_flag(0)) then
          if(KEY(0) = '0') then
            state <= s6;
          end if;
          key_flag(0) <= KEY(0);
        end if;
        
      -- ステート６での処理。
      -- ボタンが押されるとステートを５にする。
      -- 7セグメントディスプレイには自分の記録が表示されるが、表示の処理は下に記述している。
      elsif(state = s6) then
        if(KEY(0) /= key_flag(0)) then
          if(KEY(0) = '0') then
            state <= s5;
          end if;
          key_flag(0) <= KEY(0);
        end if;
      end if;


      -- ↓↓↓ 7セグメントディスプレイの表示処理 ここから ↓↓↓

      -- ステート０での表示。「準備OK」なら「rEAdy」、「アイドル」なら「SLEEP」と表示。
      -- 7セグメントディスプレイなので、全てのアルファベットを表現できるわけではない。大文字Rは大文字Aと見分けがつかないため、小文字で表現している。dやyも同様。
      if(state = s0)then
        case mode is
          when '0' =>
            led_isnum <= "000000";
            led5 <= "0010010"; -- S
            led4 <= "1000111"; -- L
            led3 <= "0000110"; -- E
            led2 <= "0000110"; -- E
            led1 <= "0001100"; -- P
            led0 <= "1111111"; -- 
          when '1' =>
            led_isnum <= "000000";
            led5 <= "0101111"; -- r
            led4 <= "0000110"; -- E
            led3 <= "0001000"; -- A
            led2 <= "0100001"; -- d
            led1 <= "0010001"; -- y
            led0 <= "1110111"; -- _
          when others => null;
        end case;

      -- ステート１での表示。
      -- ゲーム開始後一秒間は「GO」（レディーゴーのGO）
      -- その後、「残り4秒」になるまでカウントダウンを表示。
      -- それ以降は何も表示しない。
      elsif(state = s1)then
        if(counter(27 downto 24) = X"0") then
          if(counter(23 downto 16) >= X"10") then
            led_isnum <= "000000";
            led5 <= "1111111"; --
            led4 <= "1111111"; --
            led3 <= "1000010"; -- G
            led2 <= "1000000"; -- O
            led1 <= "1111111"; --
            led0 <= "1111111"; --
          elsif(counter(23 downto 16) >= X"04") then
            led_isnum <= "011111";
            led5 <= "1111111"; --
            led4_num <= counter(19 downto 16);
            led3_num <= counter(15 downto 12);
            led2_num <= counter(11 downto 8);
            led1_num <= counter(7 downto 4);
            led0_num <= counter(3 downto 0);
          else
            led_isnum <= "000000";
            led5 <= "1111111"; --
            led4 <= "1111111"; --
            led3 <= "1111111"; --
            led2 <= "1111111"; --
            led1 <= "1111111"; --
            led0 <= "1111111"; --
          end if;
        elsif(counter(27 downto 24) = X"1") then
          led_isnum <= "000000";
          led5 <= "1111111"; --
          led4 <= "1111111"; --
          led3 <= "1111111"; --
          led2 <= "1111111"; --
          led1 <= "1111111"; --
          led0 <= "1111111"; --
        end if;

      -- ステート２での表示。「HOLd」。
      elsif(state = s2)then
        led_isnum <= "000000";
        led5 <= "1111111"; --
        led4 <= "0001001"; -- H
        led3 <= "1000000"; -- O
        led2 <= "1000111"; -- L
        led1 <= "0100001"; -- d
        led0 <= "1111111"; --
      
      -- ステート３のうち、通信周期を指定している時間の表示。「clock」。
      elsif(state = s3 and send_state = s0)then
        led_isnum <= "000000";
        led5 <= "0100111"; -- c
        led4 <= "1111001"; -- l
        led3 <= "0100011"; -- o
        led2 <= "0100111"; -- c
        led1 <= "0000111"; -- k
        led0 <= "1110111"; -- _
      
      -- ステート３のうち、実際にデータを送受信している時間の表示。「SEnd」。
      elsif(state = s3)then
        led_isnum <= "000000";
        led5 <= "1111111"; --
        led4 <= "0010010"; -- S
        led3 <= "0000110"; -- E
        led2 <= "0101011"; -- n
        led1 <= "0100001"; -- d
        led0 <= "1111111"; --

      -- ステート４の表示。最下位から1秒ごとに1桁ずつ表示。
      elsif(state = s4)then
        case display_state is
          when s0 =>
            led_isnum <= "000000";
          when s6 =>
            led_isnum <= "000001";
          when s5 =>
            led_isnum <= "000011";
          when s4 =>
            led_isnum <= "000111";
          when s3 =>
            led_isnum <= "001111";
          when s2 =>
            led_isnum <= "011111";
          when s1 =>
            led_isnum <= "011111";
          when others => null;
        end case;

        if(display_state = s1 and my_score(23 downto 20) = X"1") then
          led5 <= "0111111"; -- -
        else
          led5 <= "1111111"; -- 
        end if;
        led4 <= "1111111"; --
        led3 <= "1111111"; --
        led2 <= "1111111"; --
        led1 <= "1111111"; --
        led0 <= "1111111"; --
        led4_num <= my_score(19 downto 16); --
        led3_num <= my_score(15 downto 12); --
        led2_num <= my_score(11 downto 8); --
        led1_num <= my_score(7 downto 4); --
        led0_num <= my_score(3 downto 0); --
      
      -- ステート５の表示。勝ちなら「uin」（wが表現できないため）、負けなら「loSE」、引き分けなら「drAu」（wが表現できないため）、勝敗が不明なら「Error」。
      elsif(state = s5) then
        case win_or_lose is
          when win =>
            led_isnum <= "000000";
            led5 <= "1111111"; --
            led4 <= "1100011"; -- u
            led3 <= "1111011"; -- i
            led2 <= "0101011"; -- n
            led1 <= "1111111"; --
            led0 <= "1111111"; --
          when lose =>
            led_isnum <= "000000";
            led5 <= "1111111"; --
            led4 <= "1111001"; -- l
            led3 <= "0100011"; -- o
            led2 <= "0010010"; -- S
            led1 <= "0000110"; -- E
            led0 <= "1111111"; --
          when draw =>
            led_isnum <= "000000";
            led5 <= "1111111"; --
            led4 <= "0100001"; -- d
            led3 <= "0101111"; -- r
            led2 <= "0001000"; -- A
            led1 <= "1100011"; -- u
            led0 <= "1111111"; --
          when nodata =>
            led_isnum <= "000000";
            led5 <= "0000110"; -- E
            led4 <= "0101111"; -- r
            led3 <= "0101111"; -- r
            led2 <= "0100011"; -- o
            led1 <= "0101111"; -- r
            led0 <= "1111111"; --
        end case;
      
      -- ステート６での表示。記録を全て表示。
      elsif(state = s6) then
        led_isnum <= "011111";
        if(my_score(23 downto 20) = X"1") then
          led5 <= "0111111"; -- -
        else
          led5 <= "1111111"; -- 
        end if;
        led4_num <= my_score(19 downto 16); --
        led3_num <= my_score(15 downto 12); --
        led2_num <= my_score(11 downto 8); --
        led1_num <= my_score(7 downto 4); --
        led0_num <= my_score(3 downto 0); --
      end if;


      -- ↓↓↓ カウントダウン・カウントアップの処理 ここから ↓↓↓ ---

      if(clk_on_cnt = '0') then
        clk_cnt <= X"00000000";
      else
        if(clk_cnt /= X"FFFFFFFF")then
          clk_cnt <= clk_cnt + 1;
        end if;
        if(clk_cnt >= HUND_MICRO_SEC) then
          clk_cnt <= clk_cnt - HUND_MICRO_SEC;
          if(counter(27 downto 24) = X"0" and counter /= X"0000000") then
            if(counter(3 downto 0) /= X"0") then
              counter(3 downto 0) <= counter(3 downto 0) - 1;
            else
              if(counter(7 downto 4) /= X"0") then
                counter(7 downto 4) <= counter(7 downto 4) - 1;
                counter(3 downto 0) <= X"9";
              else
                if(counter(11 downto 8) /= X"0") then
                  counter(11 downto 8) <= counter(11 downto 8) - 1;
                  counter(7 downto 0) <= X"99";
                else
                  if(counter(15 downto 12) /= X"0") then
                    counter(15 downto 12) <= counter(15 downto 12) - 1;
                    counter(11 downto 0) <= X"999";
                  else
                    if(counter(19 downto 16) /= X"0") then
                      counter(19 downto 16) <= counter(19 downto 16) - 1;
                      counter(15 downto 0) <= X"9999";
                    else
                      if(counter(23 downto 20) /= X"0") then
                        counter(23 downto 20) <= counter(23 downto 20) - 1;
                        counter(19 downto 0) <= X"99999";
                      else
                        counter(27 downto 24) <= X"1";
                        counter(3 downto 0) <= X"1";
                      end if;
                    end if;
                  end if;
                end if;
              end if;
            end if;
          elsif(counter = X"0000000") then
            counter <= X"1000000";
          else
            if(counter(3 downto 0) /= X"9") then
              counter(3 downto 0) <= counter(3 downto 0) + 1;
            else
              if(counter(7 downto 4) /= X"9") then
                counter(7 downto 4) <= counter(7 downto 4) + 1;
                counter(3 downto 0) <= X"0";
              else
                if(counter(11 downto 8) /= X"9") then
                  counter(11 downto 8) <= counter(11 downto 8) + 1;
                  counter(7 downto 0) <= X"00";
                else
                  if(counter(15 downto 12) /= X"9") then
                    counter(15 downto 12) <= counter(15 downto 12) + 1;
                    counter(11 downto 0) <= X"000";
                  else
                    if(counter(19 downto 16) /= X"9") then
                      counter(19 downto 16) <= counter(19 downto 16) + 1;
                      counter(15 downto 0) <= X"0000";
                    else
                      if(counter(23 downto 20) /= X"9") then
                        counter(23 downto 20) <= counter(23 downto 20) + 1;
                        counter(19 downto 0) <= X"00000";
                      end if;
                    end if;
                  end if;
                end if;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;


    -- ↓↓↓ 出力を行う処理 ここから ↓↓↓
    
    -- led_isnumが1なら数字（7セグデコーダを通した値）を採用。0なら文字を採用。
    -- 採用した値を7セグディスプレイに送る。
    if(led_isnum(0) = '1') then
      HEX0 <= led_num_digit(6 downto 0);
    else
      HEX0 <= led0;
    end if;
    if(led_isnum(1) = '1') then
      HEX1 <= led_num_digit(13 downto 7);
    else
      HEX1 <= led1;
    end if;
    if(led_isnum(2) = '1') then
      HEX2 <= led_num_digit(20 downto 14);
    else
      HEX2 <= led2;
    end if;
    if(led_isnum(3) = '1') then
      HEX3 <= led_num_digit(27 downto 21);
    else
      HEX3 <= led3;
    end if;
    if(led_isnum(4) = '1') then
      HEX4 <= led_num_digit(34 downto 28);
    else
      HEX4 <= led4;
    end if;
    if(led_isnum(5) = '1') then
      HEX5 <= led_num_digit(41 downto 35);
    else
      HEX5 <= led5;
    end if;
  end process;

  -- レディー信号を相手回路に送る。
  GPIO_1(0) <= ready_send;

  -- データを相手回路に送る。
  GPIO_1(4 downto 1) <= data_send;

-- 記述終了
end rtl;