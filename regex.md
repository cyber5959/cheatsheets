# Regular Expressions — General, Networking & Security

[Repository index](README.md)

## Contents

- [Example cookbook: 30 problems and commands](#example-cookbook)
- [Choose an engine](#choose-an-engine)
- [Core syntax](#core-syntax)
- [Quoting and escaping](#quoting-and-escaping)
- [Matching and extraction](#matching-and-extraction)
- [Network identifiers](#network-identifiers)
- [Log and security recipes](#log-and-security-recipes)
- [Advanced PCRE patterns](#advanced-pcre-patterns)
- [Replacement syntax](#replacement-syntax)
- [Validation and performance](#validation-and-performance)
- [Practice data](#practice-data)
- [Official references](#official-references)

## Example cookbook

Commands below use a Linux shell with GNU grep unless stated otherwise. Each recipe is independent. Change filenames and the literal values named in the explanation. Matching a string in a log is a triage step, not a verdict about what happened.

### Find an example

- [R01: Find a literal IP without matching wildcard dots](#r01-find-a-literal-ip-without-matching-wildcard-dots)
- [R02: Find an exact source-IP field](#r02-find-an-exact-source-ip-field)
- [R03: Search for any of several error words](#r03-search-for-any-of-several-error-words)
- [R04: Require two terms on the same line](#r04-require-two-terms-on-the-same-line)
- [R05: Exclude noise from an error search](#r05-exclude-noise-from-an-error-search)
- [R06: Display context around a failure](#r06-display-context-around-a-failure)
- [R07: Search configuration files recursively](#r07-search-configuration-files-recursively)
- [R08: List matching filenames without printing contents](#r08-list-matching-filenames-without-printing-contents)
- [R09: Search a list of literal indicators](#r09-search-a-list-of-literal-indicators)
- [R10: Find a whole username token](#r10-find-a-whole-username-token)
- [R11: Extract IPv4-looking strings and count them](#r11-extract-ipv4-looking-strings-and-count-them)
- [R12: Validate an entire IPv4 value](#r12-validate-an-entire-ipv4-value)
- [R13: Extract a colon-separated MAC address](#r13-extract-a-colon-separated-mac-address)
- [R14: Find requests returning an HTTP 5xx status](#r14-find-requests-returning-an-http-5xx-status)
- [R15: Extract the path from a conventional HTTP request line](#r15-extract-the-path-from-a-conventional-http-request-line)
- [R16: Find plain or encoded traversal-looking paths](#r16-find-plain-or-encoded-traversal-looking-paths)
- [R17: Extract simple domain values from a DNS log](#r17-extract-simple-domain-values-from-a-dns-log)
- [R18: Match a domain and its subdomains, but not a suffix lookalike](#r18-match-a-domain-and-its-subdomains-but-not-a-suffix-lookalike)
- [R19: Find SHA-256-shaped values](#r19-find-sha-256-shaped-values)
- [R20: Find timestamps in one hour](#r20-find-timestamps-in-one-hour)
- [R21: Allow optional fractional seconds in UTC timestamps](#r21-allow-optional-fractional-seconds-in-utc-timestamps)
- [R22: Extract an unquoted key=value token](#r22-extract-an-unquoted-keyvalue-token)
- [R23: Extract a simple quoted value containing spaces](#r23-extract-a-simple-quoted-value-containing-spaces)
- [R24: Find two identical adjacent words](#r24-find-two-identical-adjacent-words)
- [R25: Count matching records versus matching occurrences](#r25-count-matching-records-versus-matching-occurrences)
- [R26: Match only lines without a comment or blank line](#r26-match-only-lines-without-a-comment-or-blank-line)
- [R27: Find lines containing a literal backslash or dollar sign](#r27-find-lines-containing-a-literal-backslash-or-dollar-sign)
- [R28: Detect carriage returns at line ends](#r28-detect-carriage-returns-at-line-ends)
- [R29: Search a compressed rotated log](#r29-search-a-compressed-rotated-log)
- [R30: Test a pattern against positive and negative cases](#r30-test-a-pattern-against-positive-and-negative-cases)

### R01: Find a literal IP without matching wildcard dots

```sh
grep -Fn -- '192.0.2.10' events.log
```

`-F` treats the address literally and `-n` prints line numbers. Change the address and filename. This is substring matching: it can also find `192.0.2.100`. Use R02 when boundaries matter.

### R02: Find an exact source-IP field

```sh
grep -En '(^|[[:space:]])src=192[.]0[.]2[.]10([[:space:]]|$)' events.log
```

Matches a whitespace-delimited `src=` value exactly. Change the address and field name; `[.]` means a literal dot. It will not match `src=192.0.2.100`.

### R03: Search for any of several error words

```sh
grep -Ein 'timeout|refused|unreachable|denied' app.log
```

Alternation matches any listed term; `-i` ignores case. Replace the words between `|`. This returns matching lines, not a separate row for every matching word.

### R04: Require two terms on the same line

```sh
grep -F 'user=alice' auth.log | grep -F 'result=failed'
```

Each filter adds a condition, regardless of term order. Replace both literal strings. For exact fields, add boundaries with `grep -E` instead of using substring matching.

### R05: Exclude noise from an error search

```sh
grep -Ei 'error|failed' app.log | grep -Eiv 'healthcheck|expected failure'
```

Finds candidate failures, then removes known noisy lines. Change inclusion/exclusion terms. Broad exclusions can hide useful events, so keep them specific.

### R06: Display context around a failure

```sh
grep -n -B 3 -A 8 -F 'TLS handshake failed' vpn.log
```

Shows three preceding and eight following lines. Change the message and context sizes. GNU grep adds separators between separated groups.

### R07: Search configuration files recursively

```sh
grep -rEn --include='*.conf' -- '^[[:space:]]*listen[[:space:]]' ./configs
```

Searches `.conf` files below a directory for active `listen` lines. Change the extension, directive, and directory. `-r` behavior differs from `-R` around symlinks; use deliberate traversal.

### R08: List matching filenames without printing contents

```sh
grep -rlF --include='*.conf' -- 'vpn.example.com' ./configs
```

Useful for locating files to review without dumping their contents. Change the host and path. Review filenames privately if the directory contains sensitive operational material.

### R09: Search a list of literal indicators

```sh
grep -Fn -f indicators.txt events.log
```

Put one literal substring per line in `indicators.txt`. Remove empty lines first: an empty pattern matches every line. This is substring matching, not automatic domain/IP boundary validation.

### R10: Find a whole username token

```sh
grep -En '(^|[^[:alnum:]_])alice([^[:alnum:]_]|$)' auth.log
```

Avoids matching `malice` or `alice2`. Change `alice`; punctuation such as a hyphen is treated as a boundary here. For a specific log schema, match its `user=` field instead.

### R11: Extract IPv4-looking strings and count them

```sh
grep -Eo '([0-9]{1,3}[.]){3}[0-9]{1,3}' events.log | sort | uniq -c | sort -nr
```

Produces a frequency ranking of candidate addresses. Change the input file. This accepts impossible octets such as 999 and can extract substrings from longer tokens; validate candidates before using them as addresses.

### R12: Validate an entire IPv4 value

```sh
oct='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
grep -Ex "($oct[.]){3}$oct" addresses.txt
```

Prints one-address-per-line records with four octets in 0..255. Leading-zero octets are intentionally excluded. Change only the filename unless you want different acceptance rules.

### R13: Extract a colon-separated MAC address

```sh
grep -Eio '([0-9a-f]{2}:){5}[0-9a-f]{2}' neighbor.log
```

Extracts six hexadecimal byte pairs. Change `:` to `-` for a hyphen-only format. For full-line validation, add anchors or use `-x` instead of `-o`.

### R14: Find requests returning an HTTP 5xx status

```sh
grep -En '(^|[[:space:]])status=5[0-9]{2}([[:space:]]|$)' requests.log
```

Assumes whitespace-separated `status=503` fields. Change `5` to `4` for client-error statuses. This does not assume the format of an Apache combined log.

### R15: Extract the path from a conventional HTTP request line

```sh
grep -Po '"(?:GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS) \K[^ ]+(?= HTTP/[0-9.]+")' access.log
```

PCRE required. Extracts a space-free request target from a quoted request such as `"GET /health HTTP/1.1"`. Change the method list if necessary. Custom formats and malformed requests require a format-aware parser.

### R16: Find plain or encoded traversal-looking paths

```sh
grep -Ein '([.][.]|%2e%2e)(/|%2f|%5c)' requests.log
```

Flags a narrow family of candidate traversal strings. Change the input, not the escaping. It does not cover every mixed/double encoding or normalization rule and can match benign strings.

### R17: Extract simple domain values from a DNS log

```sh
grep -Po '\bqname=\K[A-Za-z0-9_.-]+' dns.log | sort -u
```

PCRE required; assumes a `qname=` field without quoted spaces. Change the key name. This extracts common presentation-format names, not every legal DNS label encoding.

### R18: Match a domain and its subdomains, but not a suffix lookalike

```sh
grep -Ei '(^|[[:space:]])host=([a-z0-9-]+[.])*example[.]com[.]?([[:space:]]|$)' proxy.log
```

Matches `host=example.com` and `host=api.example.com`, not `host=example.com.evil.test`. Change the domain and keep its dots literal. Assumes ASCII hostnames without ports.

### R19: Find SHA-256-shaped values

```sh
grep -Ei '^[0-9a-f]{64}$' hashes.txt
```

Whole-line shape check for 64 hex characters. Change `{64}` to `{40}` for a SHA-1-shaped value or `{32}` for an MD5-shaped value. Shape alone neither identifies the algorithm nor verifies a file.

### R20: Find timestamps in one hour

```sh
grep -E '^2026-09-15T14:[0-5][0-9]:[0-5][0-9]Z([[:space:]]|$)' events.log
```

Assumes timestamps at line start, UTC, and no fractional seconds. Change date/hour. This is string filtering; it does not convert timezones or compare epochs.

### R21: Allow optional fractional seconds in UTC timestamps

```sh
grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z([[:space:]]|$)' events.log
```

Matches timestamp shapes with or without fractions. Change the delimiter boundary if your format differs. This does not reject impossible calendar dates such as February 31.

### R22: Extract an unquoted key=value token

```sh
grep -Po '(^|[[:space:]])session_id=\K[^[:space:]]+' app.log
```

PCRE required. Returns only the value after `session_id=`. Change the field name. Quoted values containing spaces need a different pattern or parser.

### R23: Extract a simple quoted value containing spaces

```sh
grep -Po 'message="\K[^"\r\n]*(?=")' app.log
```

PCRE required. Handles `message="login failed"`; it does not decode escaped quotes or backslashes. Change `message` to the field you need.

### R24: Find two identical adjacent words

```sh
grep -Pin '\b([A-Za-z]+)[[:blank:]]+\1\b' notes.txt
```

PCRE backreference detects `the the`, ignoring case. Useful for cleaning notes and reports. Change `[A-Za-z]+` if your definition of a word includes other characters.

### R25: Count matching records versus matching occurrences

```sh
grep -c 'ERROR' app.log
grep -o 'ERROR' app.log | wc -l
```

First command counts lines containing ERROR; second counts each nonoverlapping occurrence. A line containing ERROR twice contributes 1 versus 2. Change the literal/pattern and filename.

### R26: Match only lines without a comment or blank line

```sh
grep -Ev '^[[:space:]]*([#;]|$)' settings.conf
```

Removes full-line comments and whitespace-only records from the displayed output. Change accepted comment markers for your format. Inline comments and quoted values remain intact.

### R27: Find lines containing a literal backslash or dollar sign

```sh
grep -Fn -- '\' paths.txt
grep -Fn -- '$HOME' script.sh
```

Single quotes preserve shell metacharacters, and `-F` avoids regex escaping. Replace the literal content inside the quotes. These are separate searches.

### R28: Detect carriage returns at line ends

```sh
grep -nP '\r$' imported.txt
```

PCRE required. Finds lines carrying the CR part of CRLF endings. Change the filename. If an anchored pattern mysteriously fails on imported text, line endings are worth checking.

### R29: Search a compressed rotated log

```sh
gzip -cd -- access.log.1.gz | grep -En '(^|[[:space:]])status=403([[:space:]]|$)'
```

Decompresses to stdout and filters without modifying the archive. Change the archive and status. `-n` reports line numbers in the decompressed stream.

### R30: Test a pattern against positive and negative cases

```sh
printf '%s\n' 'status=403' 'status=4030' 'xstatus=403' 'status=200' |
  grep -En '(^|[[:space:]])status=403([[:space:]]|$)'
```

Expected result: only `1:status=403`. Replace the sample strings with valid, invalid, boundary, and almost-matching examples from your actual problem before scanning a large file.

## Choose an engine

A regex is interpreted by a particular program. A working Python expression may fail in awk or sed.

| Tool/mode | Family | Practical rule |
|---|---|---|
| `grep 'pattern'` | BRE | Grouping and repetition differ from ERE |
| `grep -E 'pattern'` | ERE | Good default for shell matching |
| `grep -F 'text'` | Literal | No regex interpretation; ideal for fixed strings |
| `grep -P 'pattern'` | PCRE, where supported | Lookarounds and PCRE syntax; not portable |
| `sed 'script'` | BRE | Default sed matching mode |
| `sed -E 'script'` | ERE | Widely available modern sed; check older systems |
| `awk '/pattern/'` | ERE | No PCRE lookarounds or regex backreferences |
| Python `re` | Python regex | Similar to PCRE, with important differences |
| JavaScript | ECMAScript regex | Separate flags and Unicode behavior |

```sh
grep -F '192.0.2.10' events.log       # literal dots
grep -E '192\.0\.2\.10' events.log    # escaped regex dots
grep -En 'error|warning' events.log  # include line numbers
grep -Ei 'error|warning' events.log  # ignore case
grep -Ev '^[[:space:]]*(#|$)' app.conf
```

`grep` usually returns 0 for a match, 1 for no match, and a larger status for errors. A no-match result is not the same as a failed command.

## Core syntax

| Pattern | Meaning | Example |
|---|---|---|
| `.` | One character, with newline behavior depending on engine/mode | `h.t` |
| `^` | Start of line/string depending on mode | `^ERROR` |
| `$` | End of line/string depending on mode | `denied$` |
| `[abc]` | One listed character | `[Tt]imeout` |
| `[^abc]` | One character not listed | `[^,]+` |
| `[0-9]` | Digit range | `[0-9]{4}` |
| `*` | Zero or more | `[[:space:]]*` |
| `+` | One or more in ERE/PCRE | `[0-9]+` |
| `?` | Optional in ERE/PCRE | `https?` |
| `{n}` | Exactly n | `[0-9]{2}` |
| `{n,}` | At least n | `[A-Fa-f0-9]{8,}` |
| `{n,m}` | Between n and m | `[0-9]{1,5}` |
| `(ab)` | Group in ERE/PCRE | `(GET\|POST)` |
| `a\|b` | Alternation in ERE/PCRE | `allow\|deny` |

Order of operations: repetition binds tightly, then concatenation, then alternation. `^GET|POST$` means “starts with GET OR ends with POST.” Use `^(GET|POST)$` for a whole-value choice.

### POSIX character classes

| Class | Use |
|---|---|
| `[[:digit:]]` | Digits |
| `[[:xdigit:]]` | Hexadecimal digits |
| `[[:alpha:]]` | Letters according to locale |
| `[[:alnum:]]` | Letters and digits |
| `[[:space:]]` | Whitespace |
| `[[:blank:]]` | Space and tab |
| `[[:lower:]]`, `[[:upper:]]` | Letter case |
| `[[:punct:]]` | Punctuation |
| `[[:cntrl:]]` | Control characters |

Use both bracket pairs: `[[:digit:]]`, not `[:digit:]`. For predictable ASCII-oriented parsing, prefix a command with `LC_ALL=C`.

### BRE versus ERE

```sh
# Capturing groups: BRE versus ERE
sed 's/\([0-9][0-9]*\)-\([0-9][0-9]*\)/\2:\1/' file
sed -E 's/([0-9]+)-([0-9]+)/\2:\1/' file

# ERE alternation: portable to awk and grep -E
grep -E '^(WARN|ERROR):' file
awk '/^(WARN|ERROR):/' file
```

GNU BRE supports extensions such as `\+` and `\|`; avoid assuming another BRE implementation does. ERE matching backreferences are also not a portable awk feature.

## Quoting and escaping

There can be several interpreters: shell → tool → regex → replacement. Escape for each layer, not by guesswork.

```sh
grep -E '\.conf$' paths.txt       # shell single quotes preserve backslash
grep -F '$HOME' script.sh         # literal dollar sign
grep -F -- '-danger' notes.txt    # -- ends option parsing
awk '$0 ~ /\.conf$/' paths.txt    # regex literal
awk -v re='[.]conf$' '$0 ~ re' paths.txt
```

In an awk string, a regex backslash may need doubling: `"\\."`. `[.]` often avoids that extra escaping. Inside a character class, place `-` first/last or escape it appropriately, and treat `]` and `^` carefully.

Do not interpolate untrusted strings into executable shell/awk/sed code. Use literal matching or pass data separately. Passing data via `awk -v` avoids code injection, but it still gives regex semantics when used with `~`.

## Matching and extraction

```sh
grep -E 'timeout|refused|unreachable' app.log
grep -Eiv 'debug|trace' app.log
grep -Ec '^ERROR' app.log                 # matching lines, not occurrences
grep -Eo '[[:xdigit:]]{64}' hashes.txt     # -o widely supported, not POSIX
grep -E -A 3 -B 2 'authentication failed' app.log
grep -El 'PermitRootLogin' ./*.conf       # matching filenames
```

`grep -o` extracts matched substrings. It does not validate boundaries automatically. A 64-character hexadecimal substring inside a longer token is still a match unless boundaries are specified.

### Whole-token matching without lookarounds

```sh
grep -E '(^|[^[:alnum:]_])admin([^[:alnum:]_]|$)' events.log
grep -E '(^|[[:space:]])status=403([[:space:]]|$)' events.log
```

The boundary characters belong to the match. This matters with `-o`, repeated extraction, and replacements. For structured data, field comparison is often clearer than a boundary regex.

## Network identifiers

### IPv4: extraction versus validation

```sh
# Candidate extraction only: accepts out-of-range octets
grep -Eo '([0-9]{1,3}[.]){3}[0-9]{1,3}' events.log

# Whole-value range validation: accepts 0..255, no leading-zero octets
oct='(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
grep -E "^($oct[.]){3}$oct$" addresses.txt

# IPv4 CIDR prefix range 0..32; octet restrictions as above
grep -E "^($oct[.]){3}$oct/(3[0-2]|[12]?[0-9])$" networks.txt
```

The CIDR expression checks notation, not whether host bits are zero. `192.0.2.7/24` matches; a network-address validator may reject or normalize it.

### IPv6

Use a parser for IPv6. Compression (`::`), embedded IPv4, zone identifiers, and bracketed URL literals make a short universal expression misleading.

```sh
python3 - <<'PY'
import ipaddress
for candidate in ['2001:db8::10', '192.0.2.9', '999.1.2.3']:
    try:
        address = ipaddress.ip_address(candidate)
        print(candidate, 'valid', 'IPv' + str(address.version))
    except ValueError:
        print(candidate, 'invalid')
PY
```

### MAC addresses

```regex
^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$
^([0-9A-Fa-f]{2}-){5}[0-9A-Fa-f]{2}$
^[0-9A-Fa-f]{4}[.][0-9A-Fa-f]{4}[.][0-9A-Fa-f]{4}$
```

These are separate formats. An expression using `[:-]` at every separator would allow mixed separators unless additional constraints were added.

### Ports, hostnames, URLs, and email

| Goal | Candidate expression | Limit |
|---|---|---|
| Decimal port token | `^[0-9]{1,5}$` | Compare numerically with 1..65535; port 0 is context-specific |
| Typical hostname label | `^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$` | One ASCII label, not full DNS validation |
| HTTP URL candidate | `https?://[^[:space:]<>"']+` | Can include sentence punctuation; use URL parser |
| Simple email candidate | `[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+` | Not full mailbox validation |
| SHA-256-looking value | `^[A-Fa-f0-9]{64}$` | Shape does not prove hash algorithm or integrity |
| UUID-shaped value | `^[A-Fa-f0-9]{8}(-[A-Fa-f0-9]{4}){3}-[A-Fa-f0-9]{12}$` | Does not enforce version/variant |

The URL row is regex notation, not a ready-to-paste single-quoted shell argument, because the expression itself contains a single quote.

## Log and security recipes

```sh
# SSH-related events; exact wording varies with daemon/version
grep -Ei 'Failed password|Invalid user|authentication failure' auth.log

# HTTP status in the declared key=value format
grep -E '(^|[[:space:]])status=(401|403|429)([[:space:]]|$)' events.log

# Suspicious path strings for triage, not a detection guarantee
grep -Ei '(%2e%2e|\.\.)[/\\]|/\.git/|/\.env([?[:space:]]|$)' requests.log

# PEM private-key headers: use filename output to limit exposure
grep -El -- '-----BEGIN ([A-Z0-9]+ )*PRIVATE KEY-----' ./*.txt

# Comment-only or empty config lines
grep -Ev '^[[:space:]]*([#;]|$)' app.conf

# Basic ISO-style timestamp shape; does not validate calendar dates
grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' events.log
```

Encoded, double-encoded, normalized, or split inputs can evade a string search. Correlate with application context. Secret-shaped matches can be false positives; do not paste matching secrets into tickets or public commits.

## Advanced PCRE patterns

These examples require an appropriate PCRE-capable tool, such as a compatible `grep -P` build. They do not work in ordinary awk or ERE sed.

| Feature | Pattern | Purpose |
|---|---|---|
| Noncapturing group | `(?:GET\|POST)` | Group without capture slot |
| Positive lookahead | `user=(\w+)(?=\s)` | Require following text without consuming it |
| Negative lookahead | `^(?!DEBUG\b).+` | Exclude prefix |
| Fixed-width lookbehind | `(?<=src=)[0-9.]+` | Extract after literal marker |
| Named capture | `(?<user>[A-Za-z0-9_-]+)` | Name a captured value |
| Lazy repetition | `".*?"` | Stop at the first usable closing quote |
| Negated delimiter | `"[^"\r\n]*"` | Usually clearer for simple quoted fields |
| Possessive repetition | `[0-9]++` | Do not give characters back |
| Atomic group | `(?>pattern)` | Restrict backtracking |
| Absolute anchors | `\A...\z` | Entire subject in PCRE |

```sh
grep -Po '(?<=src=)(?:[0-9]{1,3}\.){3}[0-9]{1,3}' events.log
grep -Po '\buser=\K[A-Za-z0-9_.-]+' events.log
```

`\K` resets the reported match start in PCRE. `\b`, `\w`, and `\d` depend on engine and Unicode options; they are not portable POSIX ERE. Python uses `(?P<name>...)` for named groups and has its own anchoring/version details.

## Replacement syntax

| Tool | Whole match | Captured group |
|---|---|---|
| sed replacement | `&` | `\1`, `\2`, ... |
| awk `sub` / `gsub` replacement | `&` | No portable numbered capture expansion |
| GNU awk `gensub` | `&` or escaped `\0` | Escaped `\1`, etc. in replacement string |
| Python `re.sub` | `\g<0>` | `\g<1>` / `\g<name>` |
| JavaScript replacement | `$&` | `$1`, `$2`, ... |

```sh
printf '%s\n' 'src=192.0.2.10 user=alice' |
  sed -E 's/(user=)[^[:space:]]+/\1[REDACTED]/g'
```

Matching syntax and replacement syntax are different languages. A dollar sign that is meaningful in one tool may be literal in another.

## Validation and performance

1. Decide whether you need a substring, token, complete line, or parsed value.
2. Fix the engine and flags before designing the expression.
3. Test normal, malformed, empty, boundary, and very long inputs.
4. Include nonmatches that are almost valid, such as an extra trailing character.
5. Use numeric comparisons and parsers for IP addresses, dates, URLs, and nested structures.
6. Prefer `grep -F` for literal indicators; it avoids escaping errors.
7. Avoid nested ambiguous repetitions such as `^(a+)+$` on untrusted long input in backtracking engines.
8. Bound input length and use engine timeouts where supported. Greedy-to-lazy changes alone do not prevent expensive backtracking.

| Symptom | Likely cause |
|---|---|
| `\d` matches the letter d or fails | Wrong engine; use `[0-9]` |
| Pattern matches part of a bad address | Missing boundaries or full-value validation |
| Works interactively but not in script | Shell quoting or different implementation |
| `$` fails on a Windows text file | CRLF leaves a carriage return in the record |
| Case behavior changes by machine | Locale or Unicode settings |
| Pattern misses multiline event | Tool processes one line at a time |
| Awk backreference does not work | ERE regex matching does not provide it |

## Practice data

```text
2026-09-15T12:00:00Z src=192.0.2.10 user=alice status=200
2026-09-15T12:00:01Z src=198.51.100.8 user=bob status=403
2026-09-15T12:00:02Z src=999.0.0.1 user=admin status=429
```

Try extracting `src`, selecting status 403 or 429, and redacting usernames. Candidate IPv4 extraction returns all three strings; strict validation should reject `999.0.0.1`.

## Official references

- [GNU grep manual](https://www.gnu.org/software/grep/manual/grep.html) — command modes and matching behavior.
- [PCRE2 pattern reference](https://www.pcre.org/current/doc/html/pcre2pattern.html) — PCRE-specific constructs.
- [GNU awk regular expressions](https://www.gnu.org/software/gawk/manual/html_node/Regexp.html) — awk expression syntax.
- [Python re documentation](https://docs.python.org/3/library/re.html) — Python-specific matching and replacement.
- [Python ipaddress documentation](https://docs.python.org/3/library/ipaddress.html) — semantic IP validation.
