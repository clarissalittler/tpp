--title Inline Formatting
--author Example
--date today
--newpage
--heading Inline formatting tokens

You can mix --b bold --/b and --u underline --/u in a line.
This also does --rev reverse --/rev and --c red color --/c.

Escaping: use \\--b to show a literal token like \\--b.

--beginoutput
Tokens inside output blocks are verbatim:
--b not bold --/b, --c green not colored --/c
--endoutput

--newpage
--heading Combined styles

Normal --b bold --/b then --b --u both --/u --/b back to normal.
