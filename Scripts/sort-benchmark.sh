#!/bin/zsh
# Builds the sortlist benchmark in release and runs it, with any arguments given:
#
#   Scripts/sort-benchmark.sh
#   Scripts/sort-benchmark.sh --sizes 1000,100000 --only text
#
# It sorts in process (no Apple events are sent), so it runs from any terminal.

package="${0:A:h:h}/Packages/MTCOSAXKit"
swift build --package-path "$package" -c release --product sort-benchmark || exit
exec "$(swift build --package-path "$package" -c release --show-bin-path)/sort-benchmark" "$@"
