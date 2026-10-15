# Bounded, memory-only browser network state. Domain attributes are accepted
# only for the exact response host: no public-suffix list is bundled yet.
# Expires-only cookies are rejected; Max-Age and session cookies are supported.
import libs.standard.web.http_client
import lib.time

const int WIN_COOKIE_COUNT = 32
const int WIN_COOKIE_LIMIT = 2048
struct win_cookie:
	char* host
	char* path
	char* pair
	int secure
	int expires

win_cookie*[32] win_cookies
int win_cookie_next

int win_net_decimal(char* value, int limit):
	if (value == 0 || value[0] == 0): return -1
	int n = 0
	int i = 0
	while (value[i] != 0):
		if (value[i] < '0' || value[i] > '9'): return -1
		if (n > (limit - (value[i] - '0')) / 10): return -1
		n = n * 10 + value[i] - '0'
		i = i + 1
	return n

int win_net_equal(char* a, char* b):
	if (a == 0 || b == 0): return 0
	int i = 0
	while (a[i] != 0 && b[i] != 0):
		if (http_lower_char(a[i]) != http_lower_char(b[i])): return 0
		i = i + 1
	return a[i] == b[i]

void win_cookie_drop(int i):
	win_cookie* c = win_cookies[i]
	if (c == 0): return
	free(c.host)
	free(c.path)
	free(c.pair)
	free(c)
	win_cookies[i] = 0

int win_cookie_name_equal(char* a, char* b):
	int i = 0
	while (a[i] != 0 && a[i] != '=' && a[i] == b[i]): i = i + 1
	return a[i] == '=' && b[i] == '='

void win_cookie_set(char* address, char* header):
	if (header == 0 || strlen(header) > WIN_COOKIE_LIMIT): return
	int length = strlen(header)
	# Comma-folded Set-Cookie is ambiguous (notably Expires); fail closed.
	for i in range(length):
		if (header[i] < 32 || header[i] >= 127 || header[i] == ','): return
	URL* u = url_parse(address)
	if (u == 0): return
	int end = 0
	while (header[end] != 0 && header[end] != ';'): end = end + 1
	char* pair = http_trimmed_value(header, 0, end)
	int eq = 0
	while (pair[eq] != 0 && pair[eq] != '='): eq = eq + 1
	int valid = eq > 0 && pair[eq] == '='
	for i in range(eq):
		if (http_is_token_char(pair[i]) == 0): valid = 0
	int plen = strlen(u.path)
	int slash = 0
	for i in range(plen):
		if (u.path[i] == '/'): slash = i
	char* path = strclone(c"/")
	if (slash > 0):
		free(path)
		path = substring(u.path, 0, slash)
	int secure = 0
	int age = -1
	int has_age = 0
	int expires_attr = 0
	while (header[end] != 0):
		int start = end + 1
		end = start
		while (header[end] != 0 && header[end] != ';'): end = end + 1
		char* attr = http_trimmed_value(header, start, end)
		int split = 0
		while (attr[split] != 0 && attr[split] != '='): split = split + 1
		char* value = c""
		if (attr[split] == '='):
			attr[split] = 0
			value = attr + split + 1
		if (win_net_equal(attr, c"secure")): secure = 1
		else if (win_net_equal(attr, c"domain")):
			if (value[0] == '.'): value = value + 1
			if (win_net_equal(value, u.host) == 0): valid = 0
		else if (win_net_equal(attr, c"path") && value[0] == '/'):
			free(path)
			path = strclone(value)
		else if (win_net_equal(attr, c"max-age")):
			has_age = 1
			age = win_net_decimal(value, 31536000)
			if (value[0] == '-'): age = 0
			if (age < 0): valid = 0
		else if (win_net_equal(attr, c"expires")): expires_attr = 1
		free(attr)
	if (expires_attr && has_age == 0): valid = 0
	if (secure && strcmp(u.scheme, c"https") != 0): valid = 0
	if (starts_with(pair, c"__Secure-") && secure == 0): valid = 0
	# __Host- additionally forbids Domain, conservatively reject this prefix.
	if (starts_with(pair, c"__Host-")): valid = 0
	int slot = -1
	for i in range(WIN_COOKIE_COUNT):
		win_cookie* c = win_cookies[i]
		if (c != 0 && strcmp(c.host, u.host) == 0 && strcmp(c.path, path) == 0 && win_cookie_name_equal(c.pair, pair)):
			# HTTP cannot overwrite a Secure cookie.
			if (c.secure && strcmp(u.scheme, c"https") != 0): valid = 0
			slot = i
	if (valid):
		if (slot < 0):
			for i in range(WIN_COOKIE_COUNT):
				if (slot < 0 && win_cookies[i] == 0): slot = i
		if (slot < 0):
			slot = win_cookie_next
			win_cookie_next = (win_cookie_next + 1) % WIN_COOKIE_COUNT
		win_cookie_drop(slot)
		if (has_age == 0 || age > 0):
			win_cookie* c = new win_cookie()
			c.host = strclone(u.host)
			c.path = strclone(path)
			c.pair = strclone(pair)
			c.secure = secure
			c.expires = 0
			if (has_age): c.expires = time_now() + age
			win_cookies[slot] = c
	free(path)
	free(pair)
	url_free(u)

char* win_cookie_header(char* address):
	URL* u = url_parse(address)
	string_builder* out = string_new()
	if (u != 0):
		for i in range(WIN_COOKIE_COUNT):
			win_cookie* c = win_cookies[i]
			if (c == 0): continue
			if (c.expires != 0 && c.expires <= time_now()):
				win_cookie_drop(i)
				continue
			if (strcmp(c.host, u.host) != 0 || (c.secure && strcmp(u.scheme, c"https") != 0)): continue
			int size = strlen(c.path)
			if (starts_with(u.path, c.path) == 0): continue
			if (c.path[size - 1] != '/' && u.path[size] != 0 && u.path[size] != '/'): continue
			if (out.length != 0): string_append(out, c"; ")
			string_append(out, c.pair)
		url_free(u)
	char* result = strclone(out.data)
	string_free(out)
	return result

# Snapshot uses synthetic Set-Cookie records. Only sanitized stored strings
# enter the environment; credentials never appear in argv or on disk.
char* win_cookie_snapshot():
	string_builder* out = string_new()
	for i in range(WIN_COOKIE_COUNT):
		win_cookie* c = win_cookies[i]
		if (c == 0): continue
		if (c.expires != 0 && c.expires <= time_now()): continue
		if (c.secure): string_append(out, c"https://")
		else: string_append(out, c"http://")
		string_append(out, c.host)
		string_append(out, c"/\n")
		string_append(out, c.pair)
		string_append(out, c"; Path=")
		string_append(out, c.path)
		if (c.secure): string_append(out, c"; Secure")
		if (c.expires != 0):
			string_append(out, c"; Max-Age=")
			string_append_int(out, c.expires - time_now())
		string_append(out, c"\n")
	char* result = strclone(out.data)
	string_free(out)
	return result

void win_cookie_restore(char* snapshot):
	if (snapshot == 0 || strlen(snapshot) > 131072): return
	int pos = 0
	for i in range(WIN_COOKIE_COUNT):
		int start = pos
		while (snapshot[pos] != 0 && snapshot[pos] != 10): pos = pos + 1
		if (snapshot[pos] == 0): return
		char* address = substring(snapshot, start, pos)
		pos = pos + 1
		start = pos
		while (snapshot[pos] != 0 && snapshot[pos] != 10): pos = pos + 1
		char* value = substring(snapshot, start, pos)
		win_cookie_set(address, value)
		free(address)
		free(value)
		if (snapshot[pos] == 0): return
		pos = pos + 1

# Cache only explicitly fresh, unvarying, credential-free 200 GET responses.
# The parent stores already decoded/validated worker payloads, at most 8 MiB.
struct win_cache_entry:
	char* address
	char* kind
	char* source
	int length
	int expires

win_cache_entry*[16] win_cache
int win_cache_next
int win_cache_bytes

void win_cache_clear():
	for i in range(16):
		win_cache_entry* e = win_cache[i]
		if (e == 0): continue
		free(e.address)
		free(e.kind)
		free(e.source)
		free(e)
		win_cache[i] = 0
	win_cache_bytes = 0

# Parse the preferred HTTP-date form. Obsolete/invalid dates disable caching.
int win_net_http_date(char* value):
	if (strlen(value) != 29): return -1
	if (value[3] != ',' || value[4] != 32 || value[7] != 32 || value[11] != 32 || value[16] != 32 || value[19] != ':' || value[22] != ':' || strcmp(value + 25, c" GMT") != 0): return -1
	date_time dt
	char* part = substring(value, 5, 7)
	dt.day = win_net_decimal(part, 31)
	free(part)
	part = substring(value, 8, 11)
	dt.month = time_month_from_abbrev(part)
	free(part)
	part = substring(value, 12, 16)
	dt.year = win_net_decimal(part, 9999)
	free(part)
	part = substring(value, 17, 19)
	dt.hour = win_net_decimal(part, 23)
	free(part)
	part = substring(value, 20, 22)
	dt.minute = win_net_decimal(part, 59)
	free(part)
	part = substring(value, 23, 25)
	dt.second = win_net_decimal(part, 59)
	free(part)
	if (dt.year < 1970 || dt.month < 1 || dt.day < 1 || dt.hour < 0 || dt.minute < 0 || dt.second < 0): return -1
	if (dt.day > time_days_in_month(dt.year, dt.month)): return -1
	return time_unix_from_utc(&dt)

int win_cache_lifetime(http_response* response, int credentialed):
	if (credentialed || response.status != 200 || response.redirect_count != 0): return 0
	if (http_response_header(response, c"set-cookie") != 0 || http_response_header(response, c"vary") != 0): return 0
	char* control = http_response_header(response, c"cache-control")
	if (control == 0): return 0
	int pos = 0
	int age = 0
	while (control[pos] != 0):
		int start = pos
		while (control[pos] != 0 && control[pos] != ','): pos = pos + 1
		char* directive = http_trimmed_value(control, start, pos)
		int eq = 0
		while (directive[eq] != 0 && directive[eq] != '='): eq = eq + 1
		char* value = c""
		if (directive[eq] == '='):
			directive[eq] = 0
			value = directive + eq + 1
		char* name = http_trimmed_value(directive, 0, strlen(directive))
		int forbidden = win_net_equal(name, c"no-store") || win_net_equal(name, c"no-cache") || win_net_equal(name, c"private")
		if (win_net_equal(name, c"max-age")): age = win_net_decimal(value, 86400)
		free(name)
		free(directive)
		if (forbidden): return 0
		if (control[pos] == ','): pos = pos + 1
	int apparent_age = 0
	char* date_header = http_response_header(response, c"date")
	if (date_header != 0):
		int dated = win_net_http_date(date_header)
		if (dated < 0): return 0
		if (dated < time_now()): apparent_age = time_now() - dated
	char* age_header = http_response_header(response, c"age")
	if (age_header != 0):
		int elapsed = win_net_decimal(age_header, 2147483647)
		if (elapsed < 0): return 0
		if (elapsed > apparent_age): apparent_age = elapsed
	age = age - apparent_age
	if (age < 0): return 0
	return age

win_cache_entry* win_cache_find(char* address, char* kind):
	char* cookie = win_cookie_header(address)
	int credentialed = cookie[0] != 0
	free(cookie)
	if (credentialed): return 0
	for i in range(16):
		win_cache_entry* e = win_cache[i]
		if (e != 0 && e.expires > time_now() && strcmp(e.address, address) == 0 && strcmp(e.kind, kind) == 0): return e
	return 0

void win_cache_store(char* address, char* kind, char* source, int length, int expires):
	if (expires <= time_now() || length > 1048576): return
	if (win_cache_bytes + length > 8388608): win_cache_clear()
	int slot = win_cache_next
	for i in range(16):
		win_cache_entry* existing = win_cache[i]
		if (existing != 0 && strcmp(existing.address, address) == 0 && strcmp(existing.kind, kind) == 0): slot = i
	win_cache_next = (win_cache_next + 1) % 16
	win_cache_entry* old = win_cache[slot]
	if (old != 0):
		win_cache_bytes = win_cache_bytes - old.length
		free(old.address)
		free(old.kind)
		free(old.source)
		free(old)
	win_cache_entry* e = new win_cache_entry()
	e.address = strclone(address)
	e.kind = strclone(kind)
	e.source = substring(source, 0, length)
	e.length = length
	e.expires = expires
	win_cache[slot] = e
	win_cache_bytes = win_cache_bytes + length

# W's transport comma-folds repeated Set-Cookie headers. Split only at a
# comma followed by a cookie token and '=' (never at an HTTP-date comma).
void win_cookie_set_many(char* address, char* header):
	int start = 0
	int pos = 0
	while (1):
		int split = header[pos] == 0
		if (header[pos] == ','):
			int next = pos + 1
			while (header[next] == 32): next = next + 1
			int token = next
			while (http_is_token_char(header[next])): next = next + 1
			if (next > token && header[next] == '='): split = 1
		if (split):
			char* part = http_trimmed_value(header, start, pos)
			win_cookie_set(address, part)
			free(part)
			start = pos + 1
		if (header[pos] == 0): break
		pos = pos + 1

# Optional application shutdown/test hook. No initialization is required.
void win_network_state_clear():
	for i in range(WIN_COOKIE_COUNT): win_cookie_drop(i)
	win_cache_clear()
	win_cookie_next = 0
	win_cache_next = 0
