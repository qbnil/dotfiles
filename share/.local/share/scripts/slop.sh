#!/bin/sh
read -r X Y W H < <(slop -f "%x %y %w %h")
st -g "${W}x${H}+${X}+${Y}"
