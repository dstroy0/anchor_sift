-- SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
--
-- The bench a record program's lane as VHDL runs under (record_vhdl_test.cpp). It holds no arithmetic: it reads the
-- memory image the test wrote (memory.txt: a line of the image's words, the lanes, the records' address and words and
-- the refusals' address, then each word in hex), runs every lane through the emitted cycle_lane with the launch at
-- address 0, as the device's resident kernel runs them, and writes the refusals and the records' words
-- (records.txt), each word in hex.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

use work.cycle_program.all;

entity record_vhdl_bench is
end entity record_vhdl_bench;

architecture run of record_vhdl_bench is
begin
    lanes_run : process
        file given : text open read_mode is "memory.txt";
        file written : text open write_mode is "records.txt";
        variable line_in : line;
        variable line_out : line;
        variable words : natural;
        variable lanes : natural;
        variable records_address : natural;
        variable record_words : natural;
        variable refused_address : natural;
        variable word : std_ulogic_vector(31 downto 0);
        type cycle_memory_access is access cycle_memory;
        variable memory : cycle_memory_access;
    begin
        readline(given, line_in);
        read(line_in, words);
        read(line_in, lanes);
        read(line_in, records_address);
        read(line_in, record_words);
        read(line_in, refused_address);
        memory := new cycle_memory(0 to words - 1);
        for at in 0 to words - 1 loop
            readline(given, line_in);
            hread(line_in, word);
            memory(at) := unsigned(word);
        end loop;
        for lane in 0 to lanes - 1 loop
            cycle_lane(memory.all, to_unsigned(0, 64), to_unsigned(lane, 64));
        end loop;
        write(line_out, to_integer(memory(refused_address / 4)));
        writeline(written, line_out);
        for at in 0 to record_words - 1 loop
            hwrite(line_out, std_ulogic_vector(memory((records_address / 4) + at)));
            writeline(written, line_out);
        end loop;
        wait;
    end process lanes_run;
end architecture run;
