#!/bin/zsh
# Runs every test in tests/, tests/maps/ and tests/camp/ headless and reports PASS or FAIL for each. Exit code is the number of failures.
# usage: tests/run_all.sh   (from anywhere; godot must be on the PATH)
cd "$(dirname "$0")/.." || exit 1
failures=0
# A fresh clone has no global class cache (.godot/ is ignored), and new class_name types need it: import first.
godot --headless --path . --import > /dev/null 2>&1
for t in tests/*.gd tests/maps/*.gd tests/camp/*.gd; do
	[[ "$t" == tests/fixture.gd || "$t" == tests/upgrade_index.gd ]] && continue
	# A script error in a test leaves its SceneTree running forever, so give each test a time limit.
	# Each test gets its own save file path (it does not exist yet) so banking coins never touches the player's save.
	save=$(mktemp -u)
	out=$(HERO_HORDE_SAVE="$save" perl -e 'alarm 180; exec @ARGV' godot --headless --path . --script "$t" 2>&1)
	rm -f "$save" "$save.tmp" "$save.bad"
	if echo "$out" | grep -q "^PASS$" && ! echo "$out" | grep -q "SCRIPT ERROR\|^FAIL"; then
		printf "PASS  %s\n" "$t"
	else
		printf "FAIL  %s\n" "$t"
		echo "$out" | grep "FAIL\|ERROR" | head -5 | sed 's/^/        /'
		failures=$((failures + 1))
	fi
done
exit $failures
