#!/bin/zsh
# Runs every test in tests/, tests/maps/, tests/camp/, tests/inventory/ and tests/overworld/ headless and reports PASS or FAIL for each. Exit code is the number of failures.
# usage: tests/run_all.sh   (from anywhere; godot must be on the PATH)
cd "$(dirname "$0")/.." || exit 1
failures=0
# A fresh clone has no global class cache (.godot/ is ignored), and new class_name types need it: import first.
godot --headless --path . --import > /dev/null 2>&1
for t in tests/*.gd tests/maps/*.gd tests/camp/*.gd tests/inventory/*.gd tests/overworld/*.gd; do
	[[ "$t" == tests/fixture.gd || "$t" == tests/upgrade_index.gd || "$t" == tests/overworld/fake_nature_sprites.gd || "$t" == tests/overworld/horde_fixture.gd ]] && continue
	# A script error in a test leaves its SceneTree running forever, so give each test a time limit.
	# Each test gets its own save file path (it does not exist yet) so banking coins never touches the player's save.
	save=$(mktemp -u)
	out=$(HERO_HORDE_SAVE="$save" perl -e 'alarm 180; exec @ARGV' godot --headless --path . --script "$t" 2>&1)
	rm -f "$save" "$save.tmp" "$save.bad" "$save.inventory" "$save.inventory.tmp" "$save.inventory.bad" "$save.journey.knight" "$save.journey.knight.tmp" "$save.journey.knight.bad" "$save.journey.wizard" "$save.journey.wizard.tmp" "$save.journey.wizard.bad" "$save.journey.archer" "$save.journey.archer.tmp" "$save.journey.archer.bad"
	if echo "$out" | grep -q "^PASS$" && ! echo "$out" | grep -q "SCRIPT ERROR\|^FAIL"; then
		printf "PASS  %s\n" "$t"
	else
		printf "FAIL  %s\n" "$t"
		echo "$out" | grep "FAIL\|ERROR" | head -5 | sed 's/^/        /'
		failures=$((failures + 1))
	fi
done
exit $failures
