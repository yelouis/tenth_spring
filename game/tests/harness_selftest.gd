extends Node

# Harness self-test (Item 0 / F25)
# Explicitly returns false to verify that test harness catches test failures.
func run_test() -> bool:
	return false
