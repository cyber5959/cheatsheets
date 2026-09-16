# sed — Editing Text, Logs & Configuration Files

[Repository index](README.md) · [Regex syntax](regex.md)

## Contents

- [Example cookbook: 30 problems and commands](#example-cookbook)
- [Execution model](#execution-model)
- [Options and addresses](#options-and-addresses)
- [Substitutions](#substitutions)
- [Selecting and deleting](#selecting-and-deleting)
- [Configuration editing](#configuration-editing)
- [Logs and redaction](#logs-and-redaction)
- [Multiline and hold-space recipes](#multiline-and-hold-space-recipes)
- [Branching and script files](#branching-and-script-files)
- [Safer file changes](#safer-file-changes)
- [Portability and troubleshooting](#portability-and-troubleshooting)
- [Practice fixture](#practice-fixture)
- [Official references](#official-references)

## Example cookbook

Recipes print a preview to stdout unless explicitly labeled otherwise. Use a separate output file when saving changes; never redirect output back onto the input path. GNU-only examples are marked. Change the indicated filename, pattern, or replacement for your task.

### Find an example

- [S01: Replace a literal hostname everywhere](#s01-replace-a-literal-hostname-everywhere)
- [S02: Replace only the first occurrence on each line](#s02-replace-only-the-first-occurrence-on-each-line)
- [S03: Replace only the first occurrence in the whole file](#s03-replace-only-the-first-occurrence-in-the-whole-file)
- [S04: Replace a path without escaping every slash](#s04-replace-a-path-without-escaping-every-slash)
- [S05: Change an exact key=value setting](#s05-change-an-exact-keyvalue-setting)
- [S06: Change a directive with optional indentation](#s06-change-a-directive-with-optional-indentation)
- [S07: Uncomment one specific setting](#s07-uncomment-one-specific-setting)
- [S08: Comment out an active directive](#s08-comment-out-an-active-directive)
- [S09: Remove blank lines](#s09-remove-blank-lines)
- [S10: Remove full-line comments while preserving inline values](#s10-remove-full-line-comments-while-preserving-inline-values)
- [S11: Trim trailing spaces and tabs](#s11-trim-trailing-spaces-and-tabs)
- [S12: Remove CR characters from CRLF line endings](#s12-remove-cr-characters-from-crlf-line-endings)
- [S13: Collapse repeated spaces or tabs](#s13-collapse-repeated-spaces-or-tabs)
- [S14: Show just lines 200 through 240](#s14-show-just-lines-200-through-240)
- [S15: Remove a header row](#s15-remove-a-header-row)
- [S16: Remove a footer row](#s16-remove-a-footer-row)
- [S17: Keep a marker-delimited block](#s17-keep-a-marker-delimited-block)
- [S18: Delete a marker-delimited block](#s18-delete-a-marker-delimited-block)
- [S19: Print only text inside a marker block](#s19-print-only-text-inside-a-marker-block)
- [S20: Add a line after a matching setting](#s20-add-a-line-after-a-matching-setting)
- [S21: Add a line before a matching setting](#s21-add-a-line-before-a-matching-setting)
- [S22: Replace an entire matching line](#s22-replace-an-entire-matching-line)
- [S23: Swap two colon-separated fields](#s23-swap-two-colon-separated-fields)
- [S24: Redact a whitespace-delimited token](#s24-redact-a-whitespace-delimited-token)
- [S25: Wrap every decimal number for visual inspection](#s25-wrap-every-decimal-number-for-visual-inspection)
- [S26: Replace a literal ampersand correctly](#s26-replace-a-literal-ampersand-correctly)
- [S27: Edit only lines containing a second condition](#s27-edit-only-lines-containing-a-second-condition)
- [S28: Join each pair of lines with a space](#s28-join-each-pair-of-lines-with-a-space)
- [S29: Show hidden whitespace and line endings](#s29-show-hidden-whitespace-and-line-endings)
- [S30: Save a preview, inspect a diff, then choose whether to edit](#s30-save-a-preview-inspect-a-diff-then-choose-whether-to-edit)

### S01: Replace a literal hostname everywhere

```sh
sed 's/old[.]example[.]com/new.example.com/g' app.conf
```

Literal dots are escaped in the matching pattern; replacement dots are ordinary characters. Change both hostnames. This matches substrings, so use configuration-specific boundaries if longer names must remain untouched.

### S02: Replace only the first occurrence on each line

```sh
sed 's/ERROR/ALERT/' app.log
```

Omitting `g` changes only the first match per record. Change the two strings. This is not the same as replacing once in the entire file; use S03 for that.

### S03: Replace only the first occurrence in the whole file

```sh
sed '0,/old-host/s/old-host/new-host/' hosts.txt
```

GNU sed. The `0,/.../` range stops at the first matching line, including line 1. Change both strings. Any later occurrences on that same line remain unchanged because the substitution lacks `g`.

### S04: Replace a path without escaping every slash

```sh
sed 's|/srv/old-app|/srv/new-app|g' paths.conf
```

Uses `|` as the substitution delimiter. Change both paths; any `|`, backslash, or ampersand in dynamic values needs appropriate escaping.

### S05: Change an exact key=value setting

```sh
sed -E 's/^(timeout[[:blank:]]*=[[:blank:]]*).*/\130/' app.conf
```

Keeps the key and spacing, then sets the value to 30. Change `timeout` and `30`. `\1` is one capture reference followed by literal `30`; this replaces active lines starting exactly with the key.

### S06: Change a directive with optional indentation

```sh
sed -E 's/^[[:blank:]]*port[[:blank:]]+[0-9]+[[:blank:]]*$/port 1194/' server.conf
```

Matches an active numeric `port` directive and replaces the whole line. Change the directive and value. Inline comments are deliberately not matched by this version.

### S07: Uncomment one specific setting

```sh
sed -E 's/^[[:blank:]]*#[[:blank:]]*(enabled=true)[[:blank:]]*$/\1/' app.conf
```

Uncomments only a line whose content is exactly `enabled=true`. Change the literal setting. It does not uncomment every line containing the word enabled.

### S08: Comment out an active directive

```sh
sed -E 's/^([[:blank:]]*debug[[:blank:]]*=.*)$/# \1/' app.conf
```

Adds a comment marker before active `debug=` lines. Change the key/comment syntax. Already-commented lines do not match this pattern, avoiding repeated comment prefixes.

### S09: Remove blank lines

```sh
sed '/^[[:space:]]*$/d' input.txt
```

Deletes empty or whitespace-only records. Change filename. Preserve blank lines if they separate paragraphs or carry meaning in the format.

### S10: Remove full-line comments while preserving inline values

```sh
sed '/^[[:blank:]]*#/d' settings.conf
```

Deletes lines whose first nonblank character is `#`. Change the comment marker for your format. A value containing a literal hash later in the line is preserved.

### S11: Trim trailing spaces and tabs

```sh
sed 's/[[:blank:]]*$//' input.txt
```

Removes only horizontal trailing whitespace. Change filename. `[[:blank:]]` intentionally differs from all whitespace; a CR at line end needs separate handling.

### S12: Remove CR characters from CRLF line endings

```sh
sed 's/\r$//' windows.txt > unix.txt
```

GNU sed escape. Change input/output filenames, keeping them distinct. Removes a carriage return only at record end, not every CR in the file.

### S13: Collapse repeated spaces or tabs

```sh
sed -E 's/[[:blank:]]+/ /g' table.txt
```

Normalizes horizontal whitespace to one space. Change filename. This also changes spacing inside quotes and indentation, so use it for display-oriented text rather than arbitrary configs.

### S14: Show just lines 200 through 240

```sh
sed -n '200,240p' app.log
```

`-n` suppresses automatic output, then the address range prints selected rows. Change both numbers. For very large files, use `sed -n '200,240p;240q'` to stop after the range.

### S15: Remove a header row

```sh
sed '1d' table.tsv
```

Drops only the first line. Change `1` or use `1,3d` for a three-line header. This does not understand CSV records containing embedded newlines.

### S16: Remove a footer row

```sh
sed '$d' report.txt
```

Drops the final line. Change filename. Use only when the last line is reliably metadata; a missing footer would cause deletion of real data.

### S17: Keep a marker-delimited block

```sh
sed -n '/^BEGIN CERTIFICATE DATA$/,/^END CERTIFICATE DATA$/p' report.txt
```

Prints both marker lines and everything between them. Change the literal markers. This is a line-range operation, not a nested-block parser.

### S18: Delete a marker-delimited block

```sh
sed '/^BEGIN DEBUG$/,/^END DEBUG$/d' report.txt
```

Deletes both markers and their contents from the preview. Change the markers. If no ending marker occurs after a start, deletion continues to end-of-file.

### S19: Print only text inside a marker block

```sh
sed -n '/^BEGIN$/,/^END$/ { /^BEGIN$/d; /^END$/d; p; }' report.txt
```

Includes contents but excludes marker lines. Change all corresponding marker occurrences consistently. Multiple nonnested blocks can be emitted.

### S20: Add a line after a matching setting

```sh
sed '/^port 1194$/a\
# UDP listener for VPN clients
' server.conf
```

Uses portable newline syntax for append. Change the match and inserted line. It appends after every match and will add duplicates if you repeatedly apply the result to itself.

### S21: Add a line before a matching setting

```sh
sed '/^port 1194$/i\
# Listener configuration
' server.conf
```

Inserts before each exact match. Change pattern and text. This preview does not create a backup or edit the original file.

### S22: Replace an entire matching line

```sh
sed '/^log_level=/c\
log_level=warning
' app.conf
```

Changes whole lines starting with `log_level=`. Change the directive and replacement line. It does not create a missing key.

### S23: Swap two colon-separated fields

```sh
sed -E 's/^([^:]+):([^:]+)$/\2:\1/' pairs.txt
```

Turns `host:owner` into `owner:host` only for two nonempty fields. Change delimiter and captures as needed. IPv6 or values containing colons do not fit this schema.

### S24: Redact a whitespace-delimited token

```sh
sed -E 's/(api_key=)[^[:space:]]+/\1[REDACTED]/g' app.log
```

Preserves the field name while replacing its value. Change the key. Quoted multiline secrets and alternate spellings require additional handling and review before publishing.

### S25: Wrap every decimal number for visual inspection

```sh
sed -E 's/[0-9]+/[&]/g' report.txt
```

`&` inserts the matched text, producing values such as `[443]`. Change the regex or wrapper. It will also wrap digit runs inside IP addresses and identifiers.

### S26: Replace a literal ampersand correctly

```sh
sed 's/&/\&amp;/g' text.txt
```

The escaped replacement ampersand is literal; an unescaped one would expand to the match. This only handles ampersands, not complete HTML escaping, and can double-escape existing entities.

### S27: Edit only lines containing a second condition

```sh
sed '/environment=staging/s/enabled=false/enabled=true/g' settings.txt
```

Applies substitution only on lines containing the environment marker. Change condition and values. This is substring matching; tighten the patterns for exact fields.

### S28: Join each pair of lines with a space

```sh
sed 'N;s/\n/ /' pairs.txt
```

Combines lines 1–2, 3–4, and so on. For the normal GNU sed behavior, an odd final line is output unchanged. Change the replacement separator if needed; test implementation differences at EOF.

### S29: Show hidden whitespace and line endings

```sh
sed -n '1,20l' imported.txt
```

The lowercase `l` command renders records with escapes and end markers. Change the range. Useful when tabs, CR characters, or long wrapped display lines explain a failed pattern.

### S30: Save a preview, inspect a diff, then choose whether to edit

```sh
sed -E 's/^enabled=false$/enabled=true/' app.conf > app.conf.preview
diff -u app.conf app.conf.preview
```

Change the expression and filenames. These commands do not replace the original. After reviewing and validating the service configuration, use your normal deployment method; sed success alone does not prove any matching line changed.

## Execution model

Sed reads a line into **pattern space**, runs the script in order, and normally prints the result. It then repeats. **Hold space** is a second buffer for storing text between cycles.

```sh
sed 's/old/new/' input.txt             # first match per line
sed 's/old/new/g' input.txt            # every nonoverlapping match per line
sed -n '/ERROR/p' app.log              # only explicit prints
sed -E 's/[[:space:]]+/ /g' input.txt  # ERE patterns
sed -f cleanup.sed input.txt
sed -e 's/foo/bar/g' -e '/DEBUG/d' input.txt
```

Default output goes to stdout. Input files stay unchanged unless you use in-place editing or overwrite them separately. Sed is best for line-oriented transformations; awk is often clearer for arithmetic and fields.

## Options and addresses

| Option | Purpose | Portability |
|---|---|---|
| `-n` | Suppress automatic output | Portable |
| `-e SCRIPT` | Add script | Portable |
| `-f FILE` | Read script file | Portable |
| `-E` | Extended regular expressions | Modern implementations; check old systems |
| `-i.bak` | In-place editing with backup | Common GNU/BSD form, semantics differ |
| `-s` | Treat files as separate streams | GNU |
| `-z` | NUL-delimited records | GNU |
| `-u` | Less buffering | GNU |
| `--sandbox` | Disable execution and file I/O commands | GNU |
| `--debug` | Annotated execution trace | GNU |

| Address | Selects |
|---|---|
| `5` | Line 5 |
| `$` | Last line |
| `5,10` | Inclusive line range |
| `/ERROR/` | Matching lines |
| `/BEGIN/,/END/` | Inclusive pattern range |
| `5,$` | Line 5 through end |
| `0,/PATTERN/` | GNU range that can end on first line |
| `1~2` | GNU odd-numbered lines |
| `/pattern/!` | Lines not matching |

```sh
sed -n '10,20p' file
sed -n '$p' file
sed -n '/BEGIN/,/END/p' file
sed '/DEBUG/!s/ERROR/ALERT/g' file
sed -n '1~2p' file                    # GNU
```

With multiple files, sed normally treats them as one stream. GNU `-s` resets file-oriented addressing. A two-regex range is not a nesting-aware block parser, and its end matching rules can surprise you when start and end occur on the same line.

## Substitutions

General form: `[address]s<delimiter>pattern<delimiter>replacement<delimiter>flags`.

```sh
sed 's/error/ERROR/g' app.log
sed 's/error/ERROR/2' app.log          # second occurrence per line
sed -n 's/error/ERROR/p' app.log       # print only changed lines
sed 's|/var/old|/srv/new|g' paths.txt
sed -E 's/^([[:alnum:]_-]+)=([^=]*)$/\2 <- \1/' settings.txt
sed 's/[0-9][0-9]*/[&]/g' file
sed 's/&/\&amp;/g' text.txt
```

`&` in a replacement expands to the complete matched text. Escape it as `\&` for a literal ampersand. `\1` through `\9` reference captured groups. A replacement backslash and the chosen delimiter also need careful handling.

### Match only where intended

```sh
sed -E 's/^([[:space:]]*port[[:space:]]*=[[:space:]]*)[0-9]+/\18443/' app.conf
sed '/^#/!s/old-host/new-host/g' app.conf
sed '/^BEGIN/,/^END/s/disabled/enabled/g' report.txt
```

Sed numbered references are one digit, so `\18443` means capture 1 followed by `8443`. For readability in complex replacements, consider a script with an explicit replacement prefix instead.

### GNU-only substitution flags and escapes

```sh
sed 's/error/ERROR/gI' app.log          # case-insensitive regex
sed -E 's/([a-z]+)/\U\1/g' file        # uppercase replacement
sed -E 's/([A-Z]+)/\L\1/g' file        # lowercase replacement
```

Avoid `s///e` on untrusted data: it executes a shell command. `w filename` writes output and is a side effect. Prefer ordinary transformations for log processing.

## Selecting and deleting

```sh
sed -n '/ERROR/p' app.log
sed '/DEBUG/d' app.log
sed '/^[[:space:]]*$/d' file
sed '/^[[:space:]]*#/d' app.conf
sed -E '/^[[:space:]]*([#;]|$)/d' app.conf
sed '1d' table.tsv
sed '$d' file
sed '1,5d' file
sed -n '1,100p' file
sed '100q' file                       # first 100 lines, then stop
sed -n '/ERROR/=' app.log             # line numbers only
```

Deleting comment-looking lines is appropriate only when the format defines those markers as comments. Removing inline `#...` indiscriminately can corrupt URLs, passwords, quoted strings, and other values.

### Insert, append, and replace lines

Portable multiline script notation:

```sh
sed '/^listen /i\
# Listener configuration
' app.conf

sed '/^listen /a\
# Verify the matching firewall rule.
' app.conf

sed '/^enabled=/c\
enabled=true
' app.conf
```

GNU sed accepts shorter forms such as `sed '1i# Header' file`, but newline script syntax travels better between implementations.

## Configuration editing

### Anchored directive replacement

```sh
# OpenVPN: change an existing active port directive in a copy
sed -E 's/^[[:space:]]*port[[:space:]]+[0-9]+([[:space:]]*[#;].*)?$/port 1194/' server.conf > server.preview.conf

# SSH: replace existing active PermitRootLogin directives
sed -E 's/^[[:space:]]*PermitRootLogin[[:space:]]+.*/PermitRootLogin no/' sshd_config > sshd_config.preview

# Simple key=value file, whitespace allowed around =
sed -E 's/^[[:space:]]*log_level[[:space:]]*=.*/log_level=info/' app.conf > app.preview.conf
```

These do not add missing directives. Included files, repeated directives, and conditional blocks affect effective configuration. An SSH `Match` block has different scope from the global section; a broad replacement is not a complete SSH-hardening workflow. Validate the effective configuration with the service's own tools.

### Limit an INI-style edit to a section

```sh
# Assumes flat [section] headers and a timeout key within [network].
sed -E '/^\[network\]$/,/^\[/ {
  s/^(timeout[[:space:]]*=[[:space:]]*).*/\130/
}' settings.ini
```

The range includes the next section header, but the anchored key substitution does not match that header. Duplicate sections, comments, and whitespace around headers may require a real INI parser.

### Normalize text

```sh
sed 's/[[:blank:]]*$//' file          # remove trailing spaces/tabs
sed -E 's/^[[:blank:]]+//' file       # remove indentation
sed -E 's/[[:blank:]]+/ /g' file      # collapse horizontal whitespace
sed 's/\r$//' windows.txt             # GNU escape: CRLF to LF
sed 'y/ABCDEF/abcdef/' hex.txt        # character transliteration
```

Whitespace changes are not safe for every file type: indentation can be meaningful, and spaces inside quoted strings may be data.

## Logs and redaction

```sh
# Whitespace-delimited key=value records
sed -E 's/(password|token|api_key)=[^[:space:]]+/\1=[REDACTED]/g' events.log

# HTTP Authorization line in a text header dump
sed -E 's/^([Aa]uthorization:[[:space:]]*).*/\1[REDACTED]/' headers.txt

# Replace a literal documentation address
sed 's/192\.0\.2\.10/[HOST-A]/g' events.log

# Keep only a selected time interval by ordered line markers
sed -n '/2026-09-15T12:00:/,/2026-09-15T12:05:/p' app.log
```

These are format-specific examples, not comprehensive anonymization. They can miss case variants, quoted values with spaces, multiline secrets, URL-encoded content, and duplicated secret locations. Review sanitized output before publishing it. A marker range stops at the first matching end line; it does not include every event in the entire ending minute.

### Extract a field

```sh
sed -nE 's/.*(^|[[:space:]])src=([^[:space:]]+).*/\2/p' events.log
```

Because the prefix is greedy, multiple `src=` fields can produce the last eligible occurrence. Use awk with an explicit first/last-key policy when that distinction matters.

## Multiline and hold-space recipes

| Command | Effect |
|---|---|
| `N` | Append next input line to pattern space with newline |
| `D` | Remove through first embedded newline, restart script on remainder |
| `P` | Print only through first embedded newline |
| `h` / `H` | Replace / append to hold space |
| `g` / `G` | Replace / append from hold space |
| `x` | Exchange pattern and hold spaces |
| `d` | Delete pattern space and begin next cycle |

```sh
# Join pairs of lines; an unpaired final line is printed unchanged
sed 'N;s/\n/ /' file

# Double-space output by appending the initially empty hold space
sed 'G' file

# Collapse consecutive blank lines using a sliding window
sed '/^$/N;/^\n$/D' file

# Reverse line order with hold space; memory grows with file size
sed '1!G;h;$!d' file

# Join a small entire file with commas (GNU-style compact script)
sed ':a;N;$!ba;s/\n/,/g' file
```

Joining an entire file keeps it in memory and is unsuitable for huge logs. `N` at end-of-input has implementation/mode subtleties; test empty and single-line files. For general line joining, `paste -sd ',' file` is often simpler.

### NUL-delimited filenames: GNU sed

```sh
find . -type f -print0 | sed -z 's|^\./||'
```

Output remains NUL-delimited. Do not convert it to newline-separated filenames if downstream code must safely support newline characters in names.

## Branching and script files

| Command | Purpose |
|---|---|
| `:label` | Define label |
| `b label` | Unconditional branch |
| `t label` | Branch if a substitution succeeded since last input/conditional branch |
| `T label` | GNU branch if no substitution succeeded |
| `{ ... }` | Group commands under an address |
| `q` | Quit, with ordinary auto-print behavior |
| `Q` | GNU quit without auto-print |

Save as `normalize.sed`:

```sed
# Remove a CR at end of record (GNU sed escape).
s/\r$//
# Strip trailing horizontal whitespace.
s/[[:blank:]]*$//
# Remove empty and full-line comment records.
/^[[:blank:]]*$/d
/^[[:blank:]]*#/d
# Convert an explicitly known label.
s/^WARNING:/WARN:/
```

Run `sed -f normalize.sed input.txt > normalized.txt`. A script file reduces quoting complexity and is easier to review than a long shell one-liner.

## Safer file changes

```sh
# Preview and inspect a diff before replacing a file
sed -E 's/^enabled=false$/enabled=true/' app.conf > app.conf.preview
diff -u app.conf app.conf.preview

# GNU/BSD common backup-suffix form; review implementation semantics
sed -i.bak -E 's/^enabled=false$/enabled=true/' app.conf

# Inspect before restoring a backup
diff -u app.conf.bak app.conf
```

Never run `sed '...' file > file`: the shell truncates the input before sed reads it. Backups can contain credentials and should not be committed to a public repository.

In-place editing may replace the underlying file and affect symlinks, hard links, metadata, and ACLs. For privileged configuration, use a controlled deployment method that preserves intended owner/mode, validates syntax, and has rollback. Do not automatically restart a service just because sed returned success; matching zero lines can still be a successful sed execution.

## Portability and troubleshooting

| Symptom | Explanation or fix |
|---|---|
| Every matching line appears twice | Used `p` without `-n` |
| `+` treated literally | BRE mode; use `-E` or portable BRE repetition |
| Replacement includes matched text unexpectedly | Unescaped `&` |
| “Unknown option to s” | Unescaped delimiter in pattern/replacement |
| In-place command works only on Linux | GNU/BSD `-i` differences |
| Only first match changes | Missing `g` flag |
| No line changes but exit status is 0 | Successful execution does not imply a match |
| Output line endings differ | CRLF, binary input, or implementation behavior |
| Script hangs or consumes excessive memory | Branch loop or whole-file accumulation |
| Regex needs lookbehind | sed uses BRE/ERE, not PCRE |

For dynamic replacements, escape replacement backslashes, ampersands, and your delimiter. For arbitrary user-supplied text, use a language API with literal replacement semantics rather than assembling a sed program. GNU `--sandbox` limits sed execution/file commands, but is not an operating-system sandbox for arbitrary workloads.

## Practice fixture

Input:

```text
# test configuration
enabled=false
port 443
WARNING: src=192.0.2.10 token=example-placeholder
```

Try:

```sh
sed -E -e '/^#/d' -e 's/^enabled=false$/enabled=true/' \
  -e 's/token=[^[:space:]]+/token=[REDACTED]/g' fixture.txt
```

Expected:

```text
enabled=true
port 443
WARNING: src=192.0.2.10 token=[REDACTED]
```

## Official references

- [GNU sed manual](https://www.gnu.org/software/sed/manual/sed.html).
- [POSIX sed specification](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/sed.html).
- [GNU sed command summary](https://www.gnu.org/software/sed/manual/html_node/sed-commands-list.html).
- [GNU sed multiline techniques](https://www.gnu.org/software/sed/manual/html_node/Multiline-techniques.html).
