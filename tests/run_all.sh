#!/bin/zsh
# Runs every test in tests/ headless and reports PASS or FAIL for each. Exit code is the number of failures.
# usage: tests/run_all.sh   (from anywhere; godot must be on the PATH)
cd "$(dirname "$0")/.." || exit 1
failures=0
for t in tests/*.gd; do
	[[ "$t" == tests/fixture.gd ]] && continue
	out=$(godot --headless --path . --script "$t" 2>&1)
	if echo "$out" | grep -q "^PASS$" && ! echo "$out" | grep -q "SCRIPT ERROR\|^FAIL"; then
		printf "PASS  %s\n" "$t"
	else
		printf "FAIL  %s\n" "$t"
		echo "$out" | grep "FAIL\|ERROR" | head -5 | sed 's/^/        /'
		failures=$((failures + 1))
	fi
done
exit $failures
