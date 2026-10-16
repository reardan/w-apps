# Explicit host policy, never writable by page code. Larger budgets permit
# heavier applications but also lengthen synchronous parent-UI stalls.
const int WIN_EXECUTION_DEFAULT = 1000000
const int WIN_EXECUTION_MAX = 200000000

int win_execution_budget_parse(char* text):
	if (text == 0): return WIN_EXECUTION_DEFAULT
	if (text[0] == 0): return 0
	int value = 0
	int at = 0
	while (text[at] != 0):
		int digit = text[at] - '0'
		if (digit < 0 || digit > 9): return 0
		if (value > (WIN_EXECUTION_MAX - digit) / 10): return 0
		value = value * 10 + digit
		at = at + 1
	return value
