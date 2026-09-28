-- SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
--
-- The bench a record program as VHDL runs under (record_vhdl_test.cpp). It holds no arithmetic and runs no lane: it
-- reads the memory image the test wrote (memory.txt: a line of the image's words, the lanes, the records' address and
-- words and the errors' address, then each word in hex), loads it into the emitted cycle_program_unit through its
-- ports a word a clock, runs the launch at address 0 by a clock of run, as the host launches the device's resident
-- kernel, waits for the unit's done, and reads back the errors and the records' words (records.txt), each word in
-- hex, then the clocks the launch ran, from its run to its done. The unit runs the lanes itself, as the kernel does.
-- The image's size is the generic words, which the test gives GHDL with -gwords.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.cycle_program.all;

entity record_vhdl_bench is
    generic (words : positive);
end entity record_vhdl_bench;

architecture run of record_vhdl_bench is
    signal clock : std_ulogic := '0';
    signal running : boolean := true;
    signal run : std_ulogic := '0';
    signal launch_given : cycle_wide := (others => '0');
    signal load : std_ulogic := '0';
    signal load_at : natural range 0 to words - 1 := 0;
    signal load_word : cycle_word := (others => '0');
    signal read_at : natural range 0 to words - 1 := 0;
    signal read_word : cycle_word;
    signal done : std_ulogic;
begin
    unit : entity work.cycle_program_unit
        generic map (words => words)
        port map (clock => clock, run => run, launch_given => launch_given, load => load, load_at => load_at,
                  load_word => load_word, read_at => read_at, read_word => read_word, done => done);

    ticking : process
    begin
        while running loop
            clock <= '0';
            wait for 5 ns;
            clock <= '1';
            wait for 5 ns;
        end loop;
        wait;
    end process ticking;

    launch_run : process
        file given : text open read_mode is "memory.txt";
        file written : text open write_mode is "records.txt";
        variable line_in : line;
        variable line_out : line;
        variable image_words : natural;
        variable lanes : natural;
        variable records_address : natural;
        variable record_words : natural;
        variable error_address : natural;
        variable word : std_ulogic_vector(31 downto 0);

        -- the word at `at` as the unit reads it back while done: read_at before a clock, which the unit asks for, and
        -- read_word after the next, which read it
        procedure read_back(constant at : in natural; variable value : out cycle_word) is
        begin
            read_at <= at;
            wait until rising_edge(clock);
            wait until rising_edge(clock);
            wait until falling_edge(clock);
            value := read_word;
        end procedure read_back;

        variable value : cycle_word;
        variable clocks : natural := 0;
    begin
        readline(given, line_in);
        read(line_in, image_words);
        read(line_in, lanes);
        read(line_in, records_address);
        read(line_in, record_words);
        read(line_in, error_address);
        assert image_words = words report "record vhdl bench: the image is not the size -gwords gives" severity failure;
        wait until falling_edge(clock);
        load <= '1';
        for at in 0 to words - 1 loop
            readline(given, line_in);
            hread(line_in, word);
            load_at <= at;
            load_word <= unsigned(word);
            wait until falling_edge(clock);
        end loop;
        load <= '0';
        wait until falling_edge(clock);
        run <= '1';
        wait until falling_edge(clock);
        run <= '0';
        clocks := clocks + 1;
        loop
            wait until falling_edge(clock);
            clocks := clocks + 1;
            exit when done = '1';
        end loop;
        read_back(error_address / 4, value);
        write(line_out, to_integer(value));
        writeline(written, line_out);
        for at in 0 to record_words - 1 loop
            read_back((records_address / 4) + at, value);
            hwrite(line_out, std_ulogic_vector(value));
            writeline(written, line_out);
        end loop;
        write(line_out, clocks);
        writeline(written, line_out);
        running <= false;
        wait;
    end process launch_run;
end architecture run;
