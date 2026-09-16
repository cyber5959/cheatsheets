# awk — Portable Text Processing, Networking & Security

[Repository index](README.md) · [GNU extensions](gawk.md) · [Regex reference](regex.md)

## Contents

- [Example cookbook: 30 problems and commands](#example-cookbook)
- [Mental model and invocation](#mental-model-and-invocation)
- [Fields and built-in variables](#fields-and-built-in-variables)
- [Patterns and comparisons](#patterns-and-comparisons)
- [Output and formatting](#output-and-formatting)
- [Strings and numeric functions](#strings-and-numeric-functions)
- [Arrays and aggregation](#arrays-and-aggregation)
- [Multiple files and joins](#multiple-files-and-joins)
- [Networking and security cookbook](#networking-and-security-cookbook)
- [Reusable script](#reusable-script)
- [Control flow and input-output](#control-flow-and-input-output)
- [Troubleshooting and portability](#troubleshooting-and-portability)
- [Official references](#official-references)

## Example cookbook

These recipes use portable awk unless labeled otherwise. `$1` is the first field; default fields are separated by whitespace. Replace filenames, field numbers, separators, and example values for your data. Each block is independent.

### Find an example

- [A01: Print selected columns in a new order](#a01-print-selected-columns-in-a-new-order)
- [A02: Extract a column from a tab-separated export](#a02-extract-a-column-from-a-tab-separated-export)
- [A03: Keep a header while filtering data](#a03-keep-a-header-while-filtering-data)
- [A04: Print the final field only when a row is nonempty](#a04-print-the-final-field-only-when-a-row-is-nonempty)
- [A05: Print the last two fields](#a05-print-the-last-two-fields)
- [A06: Add row numbers without changing the original spacing](#a06-add-row-numbers-without-changing-the-original-spacing)
- [A07: Reject records with the wrong number of fields](#a07-reject-records-with-the-wrong-number-of-fields)
- [A08: Count valid and rejected rows](#a08-count-valid-and-rejected-rows)
- [A09: Select an exact source and destination](#a09-select-an-exact-source-and-destination)
- [A10: Keep only numeric ports in the usable range](#a10-keep-only-numeric-ports-in-the-usable-range)
- [A11: Filter using a shell variable safely](#a11-filter-using-a-shell-variable-safely)
- [A12: Sum bytes and display mebibytes](#a12-sum-bytes-and-display-mebibytes)
- [A13: Average numeric latency values](#a13-average-numeric-latency-values)
- [A14: Find the row with the highest byte count](#a14-find-the-row-with-the-highest-byte-count)
- [A15: Rank source addresses by frequency](#a15-rank-source-addresses-by-frequency)
- [A16: Deduplicate while preserving first appearance](#a16-deduplicate-while-preserving-first-appearance)
- [A17: Show only duplicated identifiers and their counts](#a17-show-only-duplicated-identifiers-and-their-counts)
- [A18: Keep event sources present in an allow list](#a18-keep-event-sources-present-in-an-allow-list)
- [A19: Find event sources absent from an inventory](#a19-find-event-sources-absent-from-an-inventory)
- [A20: Add an owner name to each address record](#a20-add-an-owner-name-to-each-address-record)
- [A21: Count a particular HTTP status in a conventional access log](#a21-count-a-particular-http-status-in-a-conventional-access-log)
- [A22: Sum response bytes by client in a conventional access log](#a22-sum-response-bytes-by-client-in-a-conventional-access-log)
- [A23: Count events by minute without timezone conversion](#a23-count-events-by-minute-without-timezone-conversion)
- [A24: Extract SRC and DPT from firewall key=value logs](#a24-extract-src-and-dpt-from-firewall-keyvalue-logs)
- [A25: Split a key=value line at only the first equals sign](#a25-split-a-keyvalue-line-at-only-the-first-equals-sign)
- [A26: List UID-zero accounts](#a26-list-uid-zero-accounts)
- [A27: Remove leading and trailing whitespace from each row](#a27-remove-leading-and-trailing-whitespace-from-each-row)
- [A28: Display a numbered line range](#a28-display-a-numbered-line-range)
- [A29: Pair consecutive records with the same key](#a29-pair-consecutive-records-with-the-same-key)
- [A30: Compute differences between cumulative counters](#a30-compute-differences-between-cumulative-counters)

### A01: Print selected columns in a new order

```sh
awk '{ print $3,$1,$5 }' inventory.txt
```

Prints fields 3, 1, and 5. Change the field numbers. Missing fields print empty strings; use `NF>=5` as a pattern if short rows should be rejected.

### A02: Extract a column from a tab-separated export

```sh
awk -F '\t' 'NR>1 { print $2 }' inventory.tsv
```

Skips one header line and prints the second tab-delimited field. Change `$2` or remove `NR>1` for headerless input. Tabs differ from arbitrary whitespace.

### A03: Keep a header while filtering data

```sh
awk 'NR==1 || $4=="DOWN"' interfaces.txt
```

Always prints the first record, then rows whose fourth field is DOWN. Change the field and comparison. Assumes a single header and single input file.

### A04: Print the final field only when a row is nonempty

```sh
awk 'NF { print $NF }' records.txt
```

Useful when preceding field counts vary. Change the file. `NF` skips empty/whitespace-only rows, avoiding `$0` behavior when NF is zero.

### A05: Print the last two fields

```sh
awk 'NF>=2 { print $(NF-1),$NF }' records.txt
```

Handles a variable-length prefix. Change `NF-1` for a different position counted from the right. Rows with fewer than two fields are skipped.

### A06: Add row numbers without changing the original spacing

```sh
awk '{ printf "%6d  %s\n",NR,$0 }' events.log
```

Formats a six-character line-number column followed by the unmodified record. Change the width in `%6d` if desired.

### A07: Reject records with the wrong number of fields

```sh
awk 'NF!=6 { print FNR,$0 }' flows.log
```

Prints malformed row candidates with input line numbers. Change 6 to the expected field count. A quoted string containing spaces may require a better parser rather than a larger expected count.

### A08: Count valid and rejected rows

```sh
awk 'NF==6 { good++; next } { bad++ }
 END { print "valid",good+0,"rejected",bad+0 }' flows.log
```

Reports both groups, including zero values. Change the validity condition to your actual schema. Headers/comments count as rejected unless you explicitly skip them first.

### A09: Select an exact source and destination

```sh
awk '$1=="192.0.2.10" && $2=="203.0.113.20"' pairs.txt
```

Exact string comparison avoids regex-dot mistakes. Change the two fields and addresses. This assumes source and destination occupy columns 1 and 2.

### A10: Keep only numeric ports in the usable range

```sh
awk '$1 ~ /^[0-9]+$/ && $1+0>=1 && $1+0<=65535' ports.txt
```

Validates decimal shape before numerical comparison. Change `$1` to your port field. Leading zeros are accepted; port zero is excluded intentionally.

### A11: Filter using a shell variable safely

```sh
min_bytes=1000000
awk -v minimum="$min_bytes" '$3 ~ /^[0-9]+$/ && $3+0>=minimum' flows.txt
```

Assumes bytes are in field 3. Change the threshold and field. Passing a value with `-v` avoids assembling executable awk source from shell data.

### A12: Sum bytes and display mebibytes

```sh
awk '$3 ~ /^[0-9]+$/ { sum+=$3 }
 END { printf "bytes=%.0f MiB=%.2f\n",sum,sum/1048576 }' flows.txt
```

Adds validated decimal values from column 3. Change the column. MiB is 1,048,576 bytes; use 1,000,000 for decimal MB.

### A13: Average numeric latency values

```sh
awk '$2 ~ /^[0-9]+([.][0-9]+)?$/ { total+=$2; n++ }
 END { if(n) printf "mean_ms=%.3f n=%d\n",total/n,n; else print "no valid values" }' latency.txt
```

Assumes nonnegative latency in milliseconds in field 2. Change field/unit. Invalid values are ignored; count them separately if completeness matters.

### A14: Find the row with the highest byte count

```sh
awk '$3 ~ /^[0-9]+$/ { if(!found || $3+0>max) { max=$3+0; row=$0; found=1 } }
 END { if(found) print row }' flows.txt
```

Returns the first row with the maximum field-3 value. Change the field; use `>=` instead of `>` if the last tied row should win.

### A15: Rank source addresses by frequency

```sh
awk '{ n[$1]++ } END { for(ip in n) print n[ip],ip }' sources.txt | sort -nr | head -20
```

Prints the top 20 first-field values. Change `$1` and 20. Empty lines would count an empty key; add `NF` before the action if needed.

### A16: Deduplicate while preserving first appearance

```sh
awk '!seen[$0]++' addresses.txt
```

Keeps the first copy of each complete line without sorting. Change `$0` to `$1` to deduplicate by the first field instead. Memory grows with unique keys.

### A17: Show only duplicated identifiers and their counts

```sh
awk 'NF { n[$1]++ } END { for(k in n) if(n[k]>1) print k,n[k] }' ids.txt
```

Reports each repeated field-1 identifier once. Change the key. Output order is unspecified; pipe to `sort` for consistent ordering.

### A18: Keep event sources present in an allow list

```sh
awk 'FILENAME==ARGV[1] { allow[$1]=1; next } $1 in allow' allow.txt events.txt
```

Loads field-1 keys from the first file, then selects matching rows from the second. Use distinct file paths. Unlike the common `NR==FNR` idiom, this handles an empty first file.

### A19: Find event sources absent from an inventory

```sh
awk 'FILENAME==ARGV[1] { known[$1]=1; next } !($1 in known)' inventory.txt events.txt
```

An anti-join for unknown identifiers. Change `$1` on either side if lookup and event columns differ. Header lines need explicit handling.

### A20: Add an owner name to each address record

```sh
awk 'FILENAME==ARGV[1] { owner[$1]=$2; next }
 { print $0,(($1 in owner)?owner[$1]:"UNKNOWN") }' owners.txt events.txt
```

Lookup format is `IP OWNER` with no spaces inside OWNER. Change lookup/value columns. Later duplicate lookup entries overwrite earlier ones.

### A21: Count a particular HTTP status in a conventional access log

```sh
awk '$9=="404" { n++ } END { print n+0 }' access.log
```

Uses status field 9 in a conventional common/combined log. Change the status or field after checking your configured log format. Do not assume custom JSON logs have these columns.

### A22: Sum response bytes by client in a conventional access log

```sh
awk '$10 ~ /^[0-9]+$/ { bytes[$1]+=$10 }
 END { for(ip in bytes) print bytes[ip],ip }' access.log | sort -nr
```

Assumes client address field 1 and response bytes field 10. Skips `-` and nonnumeric byte fields. Change fields to match your logging configuration.

### A23: Count events by minute without timezone conversion

```sh
awk '$1 ~ /^[0-9]{4}-/ { n[substr($1,1,16)]++ }
 END { for(t in n) print t,n[t] }' events.log | sort
```

Assumes fixed-width ISO timestamps in column 1 with a consistent timezone. Buckets strings by `YYYY-MM-DDTHH:MM`. Change the substring length for day/hour grouping.

### A24: Extract SRC and DPT from firewall key=value logs

```sh
awk '{ src=""; port=""
 for(i=1;i<=NF;i++) {
   if($i~/^SRC=/) src=substr($i,5)
   if($i~/^DPT=/) port=substr($i,5)
 }
 if(src!="" && port!="") print src,port
}' firewall.log
```

Works even when fields move, assuming whitespace-delimited unquoted tokens. Change the keys and substring offsets together. Variables reset for each record so missing values cannot leak from a previous row.

### A25: Split a key=value line at only the first equals sign

```sh
awk 'index($0,"=") { p=index($0,"="); print substr($0,1,p-1),substr($0,p+1) }' settings.txt
```

Preserves further `=` characters in the value. Change the delimiter string if necessary. This does not strip comments or interpret quoted values.

### A26: List UID-zero accounts

```sh
awk -F ':' '$3==0 { print $1,$3,$7 }' /etc/passwd
```

Prints username, numeric UID, and shell for UID 0. Change the UID comparison for another account range. This local file may not include directory-service accounts; use an appropriate account source for a full inventory.

### A27: Remove leading and trailing whitespace from each row

```sh
awk '{ sub(/^[[:space:]]+/,""); sub(/[[:space:]]+$/,""); print }' input.txt
```

Changes only the edges of each record, preserving internal spaces. Change the filename. This can intentionally remove a CR at the end, depending on locale/character classification.

### A28: Display a numbered line range

```sh
awk 'NR>=120 && NR<=150 { print NR,$0 } NR>150 { exit }' app.log
```

Shows lines 120–150 and stops reading soon afterward. Change both endpoints and the exit threshold consistently. Numbers count across multiple input files unless you use `FNR`.

### A29: Pair consecutive records with the same key

```sh
awk 'NR>1 && $1==previous { print saved; print $0 }
 { previous=$1; saved=$0 }' sorted-events.txt
```

Shows adjacent rows sharing field 1, useful for reviewing sorted duplicate IDs. In a run of three matches the middle row prints twice. For unique duplicate keys use A17 instead.

### A30: Compute differences between cumulative counters

```sh
awk '$2 ~ /^[0-9]+$/ {
 if(have) {
   if($2+0>=prev) print $1,$2-prev
   else print $1,"RESET_OR_WRAP"
 }
 prev=$2+0; have=1
}' counters.txt
```

Input is `timestamp cumulative_bytes` for one counter in chronological order. Change field 2 for another counter. This prints deltas, not bytes/second; divide by elapsed time to obtain a rate.

## Mental model and invocation

Awk reads records, splits them into fields, evaluates each rule in order, and runs actions for matching rules. Defaults: records are lines; fields are whitespace-separated.

```sh
awk 'pattern { action }' file
awk -F ':' '{ print $1 }' /etc/passwd
awk -v min=100 '$3 + 0 >= min' data.txt
awk -f report.awk data.txt
command_producing_text | awk '{ print $1 }'
```

```awk
BEGIN { FS = ":"; OFS = "\t" }  # before input
NF >= 3 { print $1, $3 }        # once per matching record
END { print "records", NR }     # after input
```

A pattern with no action prints matching records. An action with no pattern runs for every record. `BEGIN` and `END` do not themselves read input. Multiple matching rules all run unless control flow skips them.

## Fields and built-in variables

| Name | Meaning |
|---|---|
| `$0` | Complete current record |
| `$1`, `$2`, ... | Fields, starting at 1 |
| `$NF` | Last field |
| `NF` | Current field count |
| `NR` | Total records read |
| `FNR` | Records read in current file |
| `FILENAME` | Current input filename |
| `FS` | Input field separator |
| `OFS` | Output field separator |
| `RS` | Input record separator |
| `ORS` | Output record separator |
| `RSTART`, `RLENGTH` | Position and length from `match()` |
| `SUBSEP` | Separator used in multidimensional array keys |
| `ARGC`, `ARGV` | Command-line arguments |
| `ENVIRON` | Environment variables |

```sh
awk '{ print NR, NF, $1, $NF }' file
awk -F ':' 'BEGIN { OFS="\t" } { print $1,$3,$7 }' /etc/passwd
awk 'NF >= 2 { print $(NF-1) }' file
awk '{ $1=tolower($1); print }' file
awk 'BEGIN { FS=":"; OFS="," } { $1=$1; print }' file
```

Assigning a field rebuilds `$0` using `OFS`. Merely changing `OFS` does not change an unchanged `$0`. Rebuilding loses original spacing and can alter quoted or structured data.

### Delimiters

```sh
awk -F '\t' '{ print $1,$3 }' table.tsv
awk -F '[,:]' '{ print $1,$2 }' simple-data.txt
awk -F '=' 'NF==2 { print $1,$2 }' simple-settings.conf
awk 'BEGIN { RS=""; FS="\n" } { print "paragraph", NR, "lines", NF }' notes.txt
```

`FS=" "` has special whitespace-collapsing behavior. `FS=","` is suitable only for simple unquoted comma-separated data. Real CSV can contain delimiters, quotes, and newlines inside fields; use a CSV parser or supported GNU awk CSV mode.

## Patterns and comparisons

```sh
awk '/error/' app.log
awk '!/debug/' app.log
awk 'NR <= 10' file
awk 'NR >= 20 && NR <= 30' file
awk 'NF && $1 !~ /^#/' file
awk '$2 == "DENY" && $4 + 0 >= 1024' events.txt
awk '$1 ~ /^192[.]0[.]2[.]/' addresses.txt
awk 'tolower($0) ~ /failed|denied/' app.log
awk '/^BEGIN$/, /^END$/' report.txt
```

Range patterns include both endpoints and remain active until the end pattern matches. State can continue across files; they are not nested-block parsers.

### Numeric versus string comparison

```sh
awk '$3 + 0 > 500' metrics.txt            # numeric comparison
awk '$1 ~ /^[0-9]+$/ && $1+0 <= 65535 && $1+0 >= 1' ports.txt
awk '$1 == "00123"' ids.txt              # preserve identifiers as text
awk -v needle='admin' 'index($0,needle)' users.txt
```

`+0` forces numeric conversion but does not validate the original text: `abc` converts to zero and `12oops` can convert to 12. Validate first when malformed input matters. `index()` is a literal substring search; `~` interprets a regex.

## Output and formatting

```sh
awk 'BEGIN { OFS="\t" } { print $1,$3,$5 }' file
awk '{ printf "%6d  %-20s %10.2f\n", NR,$1,$2 }' costs.txt
awk '{ total += $2 } END { printf "total=%.2f\n",total }' costs.txt
awk 'BEGIN { ORS="," } { print $1 }' file
```

| Format | Use |
|---|---|
| `%s` | String |
| `%d` | Decimal integer formatting |
| `%f` | Fixed decimal |
| `%.2f` | Two digits after decimal point |
| `%g` | Compact numeric formatting |
| `%x` | Hexadecimal |
| `%10s` | Right-aligned width 10 |
| `%-10s` | Left-aligned width 10 |
| `%%` | Literal percent sign |

`printf` adds no newline automatically. Do not use an untrusted record as the format string: use `printf "%s\n", $0`, not `printf $0`.

## Strings and numeric functions

| Function | Result |
|---|---|
| `length(s)` | String length |
| `substr(s,p,n)` | Up to n characters from 1-based position p |
| `index(s,t)` | First literal occurrence, or 0 |
| `split(s,a,re)` | Split into array, return number of fields |
| `match(s,re)` | Match start, sets `RSTART` and `RLENGTH` |
| `sub(re,r,s)` | Replace first match; return count |
| `gsub(re,r,s)` | Replace all matches; return count |
| `tolower(s)`, `toupper(s)` | Case conversion |
| `sprintf(fmt,...)` | Format into a string |
| `int(x)` | Truncate toward zero |
| `sqrt`, `log`, `exp` | Mathematical functions |
| `rand`, `srand` | Pseudorandom numbers; not cryptographic |

```sh
awk '{ line=$0; sub(/^[[:space:]]+/,"",line); sub(/[[:space:]]+$/,"",line); print line }' file
awk '{ n=gsub(/ERROR/,"ERROR"); total+=n } END { print total+0 }' app.log
awk 'match($0,/src=[0-9.]+/) { print substr($0,RSTART+4,RLENGTH-4) }' events.log
awk '{ n=split($1,a,"."); if(n==4) print a[1] "." a[2] "." a[3] }' ipv4.txt
```

The `src` example extracts candidates, not validated addresses. `sub()` and `gsub()` mutate their target, defaulting to `$0` when omitted. In portable replacements, `&` means the whole match; numbered capture replacements are not available.

## Arrays and aggregation

Arrays are associative maps. Traversal order with `for (k in a)` is unspecified in portable awk.

```sh
# Count each first-field value
awk '{ count[$1]++ } END { for(k in count) print count[k],k }' file | sort -nr

# Preserve first occurrence of each complete line
awk '!seen[$0]++' file

# Preserve first occurrence by field
awk '!seen[$1]++' file

# Print only values occurring more than once
awk '{ n[$1]++ } END { for(k in n) if(n[k]>1) print k,n[k] }' file

# Sum bytes by source in a three-column src,dst,bytes whitespace table
awk '{ bytes[$1]+=$3 } END { for(ip in bytes) print bytes[ip],ip }' flows.txt | sort -nr

# Composite key: source and destination
awk '{ count[$1,$2]++ }
 END { for(k in count) { split(k,a,SUBSEP); print a[1],a[2],count[k] } }' flows.txt
```

Composite keys are concatenated using `SUBSEP`; arbitrary data containing that separator can collide. Arrays of arrays are a GNU extension, covered separately.

### Statistics

```sh
awk '$2 ~ /^[0-9]+([.][0-9]+)?$/ {
  x=$2+0; sum+=x
  if(n==0 || x<min) min=x
  if(n==0 || x>max) max=x
  n++
}
END {
  if(n) printf "n=%d min=%.2f max=%.2f mean=%.2f\n",n,min,max,sum/n
  else print "No valid observations"
}' latency.txt
```

For large integer counters, ordinary awk's floating-point arithmetic can lose precision. For stable variance, use an incremental algorithm rather than subtracting nearly equal large sums. Percentiles generally require storing/sorting values or a streaming approximation.

## Multiple files and joins

```sh
# Per-file record numbers
awk '{ print FILENAME,FNR,$0 }' first.txt second.txt

# Classic two-file membership filter; FIRST FILE MUST BE NONEMPTY
awk 'NR==FNR { allow[$1]=1; next } $1 in allow' allow.txt events.txt

# Empty-first-file-safe membership filter for two distinct paths
awk 'FILENAME==ARGV[1] { allow[$1]=1; next } $1 in allow' allow.txt events.txt

# Anti-join: event source not in allow list
awk 'FILENAME==ARGV[1] { allow[$1]=1; next } !($1 in allow)' allow.txt events.txt

# Enrich event rows from a two-column IP-to-owner table
awk 'FILENAME==ARGV[1] { owner[$1]=$2; next }
 { print $0, (($1 in owner) ? owner[$1] : "UNKNOWN") }' owners.txt events.txt
```

`NR==FNR` stays true when the first input is empty and the second file begins; this can silently treat event rows as lookup rows. The filename method assumes distinct input filenames and no unusual argument mutation. GNU `ARGIND` provides a cleaner extension.

Duplicate lookup keys overwrite earlier values. If owners contain spaces, define a proper delimiter and parse accordingly.

## Networking and security cookbook

### Declare the log schema first

The following sample is a whitespace-delimited table with exactly six fields:

```text
# time src dst port action bytes
2026-09-15T12:00:00Z 192.0.2.10 203.0.113.20 443 ALLOW 1200
2026-09-15T12:00:01Z 198.51.100.8 203.0.113.20 22 DENY 60
2026-09-15T12:00:02Z 198.51.100.8 203.0.113.20 22 DENY 60
2026-09-15T12:00:03Z 192.0.2.10 203.0.113.53 53 ALLOW 300
```

Save as `flows.log` for these recipes:

```sh
# Denied source counts; result: 2 198.51.100.8
awk '$1 !~ /^#/ && NF==6 && $5=="DENY" { n[$2]++ }
 END { for(ip in n) print n[ip],ip }' flows.log | sort -nr

# Allowed byte totals; result: 1500 192.0.2.10
awk '$1 !~ /^#/ && NF==6 && $5=="ALLOW" { b[$2]+=$6 }
 END { for(ip in b) print b[ip],ip }' flows.log | sort -nr

# Destination-port histogram
awk '$1 !~ /^#/ && NF==6 { n[$4]++ }
 END { for(p in n) print n[p],p }' flows.log | sort -nr

# Unique destination ports per source, useful for triage
awk '$1 !~ /^#/ && NF==6 && !seen[$2,$4]++ { n[$2]++ }
 END { for(ip in n) print n[ip],ip }' flows.log | sort -nr

# Per-minute counts, assuming identical timestamp format/timezone
awk '$1 !~ /^#/ && NF==6 { n[substr($1,1,16)]++ }
 END { for(t in n) print t,n[t] }' flows.log | sort
```

Port diversity can indicate scanning or normal service discovery. A count alone does not establish malicious intent. These examples process records, not packet captures; export packet metadata with a packet-analysis tool first.

### Key=value firewall logs

```sh
# Assumes whitespace-separated tokens; values contain no whitespace.
awk '{
  src=""; dst=""; dpt=""
  for(i=1;i<=NF;i++) {
    if($i ~ /^SRC=/) src=substr($i,5)
    else if($i ~ /^DST=/) dst=substr($i,5)
    else if($i ~ /^DPT=/) dpt=substr($i,5)
  }
  if(src!="" && dst!="") print src,dst,dpt
}' firewall.log
```

Reset variables for every row. Otherwise a missing field may accidentally reuse a previous record's value.

### Common/combined web access log

```sh
# Conventional combined format only: address field 1, status field 9
awk 'NF>=9 && $9 ~ /^5[0-9][0-9]$/ { n[$1]++ }
 END { for(ip in n) print n[ip],ip }' access.log | sort -nr
```

Custom proxy formats can shift the columns. Client-supplied forwarding headers are not trustworthy unless your proxy sanitizes them. JSON logs need a JSON parser.

### Account and inventory reports

```sh
awk -F ':' '$3==0 { print $1,$3,$7 }' /etc/passwd
awk -F ':' '$7 !~ /(nologin|false)$/ { print $1,$7 }' /etc/passwd
awk -F ':' '{ n[$7]++ } END { for(s in n) print n[s],s }' /etc/passwd
```

A login shell is only one part of account access policy; it does not prove an account is active or permitted to log in.

## Reusable script

Save as `flow-summary.awk`, run `awk -f flow-summary.awk flows.log`:

```awk
BEGIN { OFS="\t" }
/^[[:space:]]*(#|$)/ { next }
NF != 6 { malformed++; next }
$4 !~ /^[0-9]+$/ || $4+0 < 1 || $4+0 > 65535 { malformed++; next }
$6 !~ /^[0-9]+$/ { malformed++; next }
$5 != "ALLOW" && $5 != "DENY" { malformed++; next }
{
    records++
    bytes[$2]+=$6
    if($5=="DENY") denied[$2]++
}
END {
    print "source","bytes","denied"
    for(ip in bytes) print ip,bytes[ip],denied[ip]+0
    print "valid_records",records+0
    print "malformed_records",malformed+0
}
```

This checks field count, port range, byte shape, and action. It deliberately does not claim to validate IP addresses or timestamps. Output source order is unspecified.

## Control flow and input-output

```awk
if (condition) { ... } else { ... }
for (i=1; i<=NF; i++) { ... }
for (key in counts) { ... }
while (condition) { ... }
next                # next input record; END still runs
exit 2              # finish with status 2; END still runs
delete counts[key]  # delete one entry
```

```awk
function trim(s) {
    sub(/^[[:space:]]+/, "", s)
    sub(/[[:space:]]+$/, "", s)
    return s
}
```

Parameters are local. Extra unused formal parameters are a traditional way to declare function-local variables. Arrays are passed by reference; ordinary scalar arguments are passed by value.

```awk
print $0 > "selected.txt"      # first open truncates; later writes reuse stream
print $0 >> "append.txt"       # append mode
close("selected.txt")         # close a specific stream
while ((getline line < "lookup.txt") > 0) { ... }
close("lookup.txt")
```

`getline` returns 1 for a record, 0 at EOF, and -1 for an error. Bare `getline` also replaces `$0` and advances input counters; `getline line < file` behaves differently. Avoid mixing manual and automatic input unless necessary. Never derive shell commands or uncontrolled output paths directly from untrusted log fields.

## Troubleshooting and portability

| Problem | Check |
|---|---|
| Everything prints | Missing action, wrong pattern, or numeric/string coercion |
| Unexpected spacing | Assigning fields rebuilt `$0` with `OFS` |
| Join fails on empty lookup | `NR==FNR` idiom |
| Aggregates appear random | Associative arrays are unordered |
| Last field looks wrong | CRLF input or trailing delimiters |
| Regex works in PCRE but fails | awk uses ERE, not PCRE |
| `length(array)` fails | Not portable across older implementations |
| Entire-array deletion fails | Use `for(k in a) delete a[k]` for broad portability |
| Huge file exhausts memory | High-cardinality arrays; sort/stream or use a database |
| Data disappears during rewrite | Never redirect output to the input file |

Prefer `LC_ALL=C awk ...` for byte-oriented ASCII log processing. Use `awk -v value="$shell_value" '...'` to pass shell values; do not splice them into source code. Be aware that `-v` values can interpret backslash escapes.

## Official references

- [POSIX awk specification](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/awk.html) — portable language behavior.
- [GNU awk manual](https://www.gnu.org/software/gawk/manual/gawk.html) — additional explanation and implementation differences.
- [GNU awk input separators](https://www.gnu.org/software/gawk/manual/html_node/Field-Separators.html).
