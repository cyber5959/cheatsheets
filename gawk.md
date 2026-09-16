# GNU awk (gawk) — Advanced Processing & Network Analysis

[Repository index](README.md) · [Portable awk foundation](awk.md)

## Contents

- [Example cookbook: 30 problems and commands](#example-cookbook)
- [Version and execution modes](#version-and-execution-modes)
- [GNU feature map](#gnu-feature-map)
- [Capture groups and replacements](#capture-groups-and-replacements)
- [Field and record parsing](#field-and-record-parsing)
- [Sorting and arrays](#sorting-and-arrays)
- [Multiple files and errors](#multiple-files-and-errors)
- [Time and network calculations](#time-and-network-calculations)
- [Security-analysis recipes](#security-analysis-recipes)
- [Reusable report](#reusable-report)
- [Debugging and performance](#debugging-and-performance)
- [Interoperability and limitations](#interoperability-and-limitations)
- [Official references](#official-references)

## Example cookbook

These recipes deliberately invoke `gawk`, because they use GNU features or benefit from GNU behavior. Each is independent; change fields, filenames, and example values as described. See [awk](awk.md#example-cookbook) for basic portable recipes.

### Find an example

- [G01: Extract several named-looking fields with capture groups](#g01-extract-several-named-looking-fields-with-capture-groups)
- [G02: Extract source address and port from a socket value](#g02-extract-source-address-and-port-from-a-socket-value)
- [G03: Extract a bracketed IPv6 endpoint](#g03-extract-a-bracketed-ipv6-endpoint)
- [G04: Redact a value while retaining the original record in memory](#g04-redact-a-value-while-retaining-the-original-record-in-memory)
- [G05: Change only the second occurrence of a pattern](#g05-change-only-the-second-occurrence-of-a-pattern)
- [G06: Extract every address-shaped occurrence on each line](#g06-extract-every-address-shaped-occurrence-on-each-line)
- [G07: Parse unordered key=value tokens](#g07-parse-unordered-keyvalue-tokens)
- [G08: Keep simple quoted words together](#g08-keep-simple-quoted-words-together)
- [G09: Read real CSV with quoted commas](#g09-read-real-csv-with-quoted-commas)
- [G10: Emit properly quoted simple CSV fields](#g10-emit-properly-quoted-simple-csv-fields)
- [G11: Rank counts without an external sort command](#g11-rank-counts-without-an-external-sort-command)
- [G12: Print exactly the first ten ranked entries](#g12-print-exactly-the-first-ten-ranked-entries)
- [G13: Sort numeric samples instead of lexical strings](#g13-sort-numeric-samples-instead-of-lexical-strings)
- [G14: Calculate a median](#g14-calculate-a-median)
- [G15: Calculate an adjustable nearest-rank percentile](#g15-calculate-an-adjustable-nearest-rank-percentile)
- [G16: Count unique destination ports per source](#g16-count-unique-destination-ports-per-source)
- [G17: Count source-to-destination pairs with nested maps](#g17-count-source-to-destination-pairs-with-nested-maps)
- [G18: Join files without the empty-first-file trap](#g18-join-files-without-the-empty-first-file-trap)
- [G19: Report row counts for every input file](#g19-report-row-counts-for-every-input-file)
- [G20: Stop scanning a file after its first match](#g20-stop-scanning-a-file-after-its-first-match)
- [G21: Convert epoch seconds to UTC timestamps](#g21-convert-epoch-seconds-to-utc-timestamps)
- [G22: Group epoch-based records into five-minute buckets](#g22-group-epoch-based-records-into-five-minute-buckets)
- [G23: Select recent epoch-based events](#g23-select-recent-epoch-based-events)
- [G24: Convert prefixed hex values to decimal](#g24-convert-prefixed-hex-values-to-decimal)
- [G25: Decode SYN, ACK, and RST flag bits](#g25-decode-syn-ack-and-rst-flag-bits)
- [G26: Process a whole file as one record](#g26-process-a-whole-file-as-one-record)
- [G27: Handle Unix and Windows line endings in one input](#g27-handle-unix-and-windows-line-endings-in-one-input)
- [G28: Compare the first data rows of two files](#g28-compare-the-first-data-rows-of-two-files)
- [G29: Normalize case before grouping usernames](#g29-normalize-case-before-grouping-usernames)
- [G30: Measure where a reusable awk program spends work](#g30-measure-where-a-reusable-awk-program-spends-work)

### G01: Extract several named-looking fields with capture groups

```sh
gawk 'match($0,/user=([^ ]+) src=([^ ]+) result=([^ ]+)/,m) {
 print m[1],m[2],m[3]
}' auth.log
```

Assumes those fields are adjacent and in that order, separated by single spaces. Change the regex and numbered captures together. For unordered fields, use G07.

### G02: Extract source address and port from a socket value

```sh
gawk 'match($1,/^([0-9.]+):([0-9]+)$/,m) { print m[1],m[2] }' endpoints.txt
```

Splits an IPv4-looking first-field value such as `192.0.2.10:443`. Change `$1` if needed. It checks shape only; validate address and port ranges separately.

### G03: Extract a bracketed IPv6 endpoint

```sh
gawk 'match($1,/^\[([^]]+)\]:([0-9]+)$/,m) { print m[1],m[2] }' endpoints.txt
```

Handles `[2001:db8::10]:443` without splitting IPv6's internal colons. Change the input field. This extracts text; it does not validate IPv6 syntax or zone identifiers.

### G04: Redact a value while retaining the original record in memory

```sh
gawk '{ safe=gensub(/(token=)[^[:space:]]+/,"\\1[REDACTED]","g",$0); print safe }' events.log
```

Changes the output copy, not `$0`. Replace `token` with the intended key. Assumes whitespace-delimited values and does not catch every secret representation.

### G05: Change only the second occurrence of a pattern

```sh
gawk '{ print gensub(/[0-9]+/,"[NUMBER]",2,$0) }' records.txt
```

Replaces the second run of digits per line. Change `2`, the pattern, or replacement. Lines with fewer than two matches stay unchanged.

### G06: Extract every address-shaped occurrence on each line

```sh
gawk '{ n=patsplit($0,a,/([0-9]{1,3}[.]){3}[0-9]{1,3}/)
 for(i=1;i<=n;i++) print FNR,a[i]
}' events.log
```

Produces line number plus every candidate, including repeated occurrences. Change the pattern for another token shape. Address octet ranges and boundaries remain unvalidated.

### G07: Parse unordered key=value tokens

```sh
gawk '{ delete kv
 for(i=1;i<=NF;i++) if((p=index($i,"="))>1)
   kv[substr($i,1,p-1)]=substr($i,p+1)
 if(kv["action"]=="DENY") print kv["src"],kv["dst"],kv["dport"]
}' firewall.log
```

Change the keys and comparison. Values cannot contain whitespace; repeated keys use their last value. Splitting only at the first equals sign preserves additional equals signs inside values.

### G08: Keep simple quoted words together

```sh
gawk 'BEGIN { FPAT="([^[:space:]]+)|(\"[^\"]*\")" }
 { for(i=1;i<=NF;i++) print i,$i }' quoted.txt
```

Treats `"hello world"` as one field when the quote starts the token. Does not parse escaped quotes or arbitrary nested syntax. Change FPAT only after testing representative input.

### G09: Read real CSV with quoted commas

```sh
gawk --csv 'NR>1 { print $1,$3 }' assets.csv
```

Requires gawk 5.3+. Parses CSV input rather than merely splitting on commas. Change selected columns. Output is ordinary space-delimited text, not automatically escaped CSV.

### G10: Emit properly quoted simple CSV fields

```sh
gawk 'function csv(s) { gsub(/"/,"\"\"",s); return "\"" s "\"" }
 BEGIN { OFS="," }
 { print csv($1),csv($2) }' two-columns.txt
```

Quotes each output field and doubles internal quotes. Input here is whitespace-delimited, so use an appropriate input parser if original fields contain spaces. Change `$1,$2` to your selected values.

### G11: Rank counts without an external sort command

```sh
gawk 'NF { n[$1]++ }
 END { PROCINFO["sorted_in"]="@val_num_desc"; for(k in n) print n[k],k }' sources.txt
```

Sorts map entries by numeric count descending. Change the key. For an explicit alphabetical tie-breaker, use a custom comparator or external sort with multiple keys.

### G12: Print exactly the first ten ranked entries

```sh
gawk 'NF { n[$1]++ }
 END { PROCINFO["sorted_in"]="@val_num_desc"
 for(k in n) { print n[k],k; if(++shown>=10) break }
}' sources.txt
```

Prints up to ten entries if fewer exist. Change 10 and the key column. It stores all distinct keys before printing, so limiting output does not limit aggregation memory.

### G13: Sort numeric samples instead of lexical strings

```sh
gawk '$1 ~ /^[0-9]+([.][0-9]+)?$/ { a[++n]=$1+0 }
 END { asort(a,s,"@val_num_asc"); for(i=1;i<=n;i++) print s[i] }' latency.txt
```

Orders 2 before 10. Change the validation pattern if negatives or scientific notation are allowed. Original values remain in `a`; sorted values are in `s`.

### G14: Calculate a median

```sh
gawk '$1 ~ /^[0-9]+([.][0-9]+)?$/ { a[++n]=$1+0 }
 END {
   if(!n) { print "no valid values"; exit 1 }
   asort(a,s,"@val_num_asc")
   if(n%2) print s[(n+1)/2]
   else print (s[n/2]+s[n/2+1])/2
 }' latency.txt
```

Uses the middle value for odd counts and the mean of two middle values for even counts. Change the input field as necessary. Holds all accepted samples in memory.

### G15: Calculate an adjustable nearest-rank percentile

```sh
gawk -v p=99 '$1 ~ /^[0-9]+([.][0-9]+)?$/ { a[++n]=$1+0 }
 END {
   if(!n || p<=0 || p>100) { print "need samples and 0<p<=100"; exit 1 }
   asort(a,s,"@val_num_asc")
   rank=int(p*n/100); if(rank<p*n/100) rank++
   print s[rank]
 }' latency.txt
```

Change `p=99` to 95 or another percentile. This uses nearest rank, not interpolation; other tools can legitimately give different values.

### G16: Count unique destination ports per source

```sh
gawk 'NF>=2 { ports[$1][$2]=1 }
 END { for(ip in ports) print ip,length(ports[ip]) }' source-port.txt
```

Input columns are source IP and destination port. Change the fields. Repeated source/port pairs count once; distinct-port counts alone do not prove scanning.

### G17: Count source-to-destination pairs with nested maps

```sh
gawk 'NF>=2 { n[$1][$2]++ }
 END { for(src in n) for(dst in n[src]) print src,dst,n[src][dst] }' pairs.txt
```

Avoids composite-string key collisions by using nested arrays. Change fields. Add deterministic traversal if output order matters.

### G18: Join files without the empty-first-file trap

```sh
gawk 'ARGIND==1 { owner[$1]=$2; next }
 ARGIND==2 { print $0,(($1 in owner)?owner[$1]:"UNKNOWN") }' owners.txt events.txt
```

Uses argument index rather than `NR==FNR`. Change lookup and event columns. Handles an empty owners file by reporting UNKNOWN for each event.

### G19: Report row counts for every input file

```sh
gawk 'BEGINFILE { count=0 } { count++ }
 ENDFILE { print FILENAME,count }' first.log second.log
```

Reports empty files as zero. Change the file list or replace `{ count++ }` with a condition such as `/ERROR/ { count++ }`.

### G20: Stop scanning a file after its first match

```sh
gawk '/TLS handshake failed/ { print FILENAME,FNR,$0; nextfile }' ./*.log
```

Prints one matching row per file, then skips the rest of that file. Change the search regex. Unlike `exit`, `nextfile` continues to the following input file.

### G21: Convert epoch seconds to UTC timestamps

```sh
gawk '$1 ~ /^[0-9]+$/ { print strftime("%Y-%m-%dT%H:%M:%SZ",$1,1) }' epoch.txt
```

The third argument requests UTC. Change the output format or field. If input is epoch milliseconds, use `$1/1000`; subsecond precision is not shown here.

### G22: Group epoch-based records into five-minute buckets

```sh
gawk '$1 ~ /^[0-9]+$/ { n[int($1/300)*300]++ }
 END { PROCINFO["sorted_in"]="@ind_num_asc"
 for(t in n) print strftime("%Y-%m-%dT%H:%M:%SZ",t,1),n[t]
}' events-epoch.txt
```

Change 300 consistently for another bucket length in seconds. Assumes nonnegative epoch seconds in field 1; all buckets align to the epoch.

### G23: Select recent epoch-based events

```sh
gawk -v seconds=3600 'BEGIN { now=systime(); start=now-seconds }
 $1 ~ /^[0-9]+$/ && $1+0>=start && $1+0<=now' events-epoch.txt
```

Keeps the preceding hour relative to execution time, excluding future timestamps. Change seconds and field. Requires a correct local clock and epoch-seconds input.

### G24: Convert prefixed hex values to decimal

```sh
gawk '$1 ~ /^0[xX][0-9A-Fa-f]+$/ { print $1,strtonum($1) }' hex.txt
```

Handles values such as `0x1f`. Change the field. Large integers can exceed exact default numeric precision; do not use this blindly for 128-bit identifiers.

### G25: Decode SYN, ACK, and RST flag bits

```sh
gawk '$1 ~ /^0[xX][0-9A-Fa-f]+$/ {
 f=strtonum($1)
 print $1,"SYN=" (and(f,2)!=0),"ACK=" (and(f,16)!=0),"RST=" (and(f,4)!=0)
}' tcp-flags.txt
```

Expects numeric TCP flag bitmasks, not the textual flag output of every packet tool. Change masks only for documented bits in your input format.

### G26: Process a whole file as one record

```sh
gawk 'BEGIN { RS="\0" } { print FILENAME,length($0) }' report.txt
```

For a text file with no NUL bytes, reads the file into one record and reports its character length. Change filename. This consumes memory proportional to file size; add `-b` if you specifically need byte-oriented length.

### G27: Handle Unix and Windows line endings in one input

```sh
gawk 'BEGIN { RS="\r?\n" } { print $0 }' mixed-endings.txt
```

Consumes LF or CRLF separators and emits LF records through the default ORS. Change filename. A trailing lone CR is not matched as a separator by this recipe.

### G28: Compare the first data rows of two files

```sh
gawk 'FNR==1 { first[ARGIND]=$0; nextfile }
 END {
   if(!(1 in first) || !(2 in first)) { print "one file is empty"; exit 1 }
   print (first[1]==first[2] ? "same" : "different")
 }' before.txt after.txt
```

Reads only one row per file. Change `FNR==1` to another row number if you also adjust the empty/missing-row message. Useful for schema/header comparisons, not full file comparison.

### G29: Normalize case before grouping usernames

```sh
gawk 'NF { n[tolower($1)]++ }
 END { PROCINFO["sorted_in"]="@ind_str_asc"; for(user in n) print user,n[user] }' users.txt
```

Aggregates ALICE and alice into one key. Change the field. Only do this if your identity system treats case variants as equivalent.

### G30: Measure where a reusable awk program spends work

```sh
gawk --profile=report.profile -f report.awk sample.log
```

Runs the program and writes execution-count profiling output. Change script/input/profile paths. This really executes the program, including its file/command side effects; use a trusted script and representative sample.

## Version and execution modes

GNU awk implements awk plus additional features. `/usr/bin/awk` might point to mawk, BusyBox awk, or another implementation. Invoke `gawk` explicitly when using this sheet.

```sh
gawk --version
gawk --help
gawk --lint -f report.awk input.log
gawk --lint=fatal -f portable.awk input.log
gawk --posix -f portable.awk input.log
gawk --profile=profile.txt -f report.awk input.log
gawk --pretty-print=formatted.awk -f report.awk
gawk --debug -f report.awk input.log
gawk -b '{ print length($0) }' input.log   # byte-oriented mode
```

`--lint` can warn about deliberate GNU features; use it to understand dependencies. `--posix` changes behavior and disables extensions. Feature availability depends on the installed build. CSV mode requires gawk 5.3 or later; do not infer support merely because `gawk` exists.

## GNU feature map

| Feature | Why use it |
|---|---|
| `match(s,re,captures)` | Capture substrings into an array |
| `gensub()` | Return a replacement result with capture expansion |
| `patsplit()` / `FPAT` | Describe fields by what they contain |
| `FIELDWIDTHS` | Read fixed-width fields |
| Regex `RS`, `RT` | Match multi-character record separators |
| `asort()`, `asorti()` | Sort values or indices |
| `PROCINFO["sorted_in"]` | Control array traversal order |
| Arrays of arrays | Represent nested maps directly |
| `ARGIND` | Know which input argument is active |
| `BEGINFILE`, `ENDFILE` | Per-file setup and finalization |
| `strtonum()` | Explicit base-aware number conversion |
| `systime`, `mktime`, `strftime` | Timestamps and formatting |
| Bitwise functions | IPv4 masking and flag operations |
| `@include` | Share source files |
| `--csv` | Parse CSV using a dedicated mode, gawk 5.3+ |

## Capture groups and replacements

```sh
# Extract address and port; candidate address shape only
gawk 'match($0,/src=([0-9.]+):([0-9]+)/,m) { print m[1],m[2] }' events.log

# Capture ranges also expose start and length metadata
gawk 'match($0,/(user)=([^ ]+)/,m) {
  print m[2],m[2,"start"],m[2,"length"]
}' events.log

# Return a changed string; original $0 remains available
gawk '{ out=gensub(/(user=)[^[:space:]]+/,"\\1[REDACTED]","g"); print out }' events.log

# Swap two fields inside a string
gawk '{ print gensub(/^([^:]+):([^:]+)$/,"\\2:\\1",1,$0) }' pairs.txt
```

The replacement is an awk string, so `\\1` in source passes a capture reference to `gensub`. `gensub` returns a string; it does not mutate the target. `sub` and `gsub` mutate and return a replacement count.

### GNU word operators

GNU regex supports `\<`, `\>`, `\y`, and `\B` word-related operators in appropriate modes. A slash regex keeps escaping simpler than a string regex. Do not assume PCRE `\b` means a word boundary in awk: it commonly denotes backspace.

```sh
gawk '/\<root\>/' accounts.txt
gawk 'BEGIN { IGNORECASE=1 } /denied|failed/' app.log
```

`IGNORECASE` affects regex and relevant string operations; it does not make associative-array keys case-insensitive. Normalize keys explicitly with `tolower()` when aggregating case-insensitively.

## Field and record parsing

### Match fields instead of separators

```sh
# Simple tokens or simple double-quoted fields; not a full CSV parser
gawk 'BEGIN { FPAT="([^[:space:]]+)|(\"[^\"]*\")" }
 { for(i=1;i<=NF;i++) print i,$i }' quoted.log

# Simple key=value tokens, optionally double quoted; no escaped quotes
gawk '{
  n=patsplit($0,a,/[A-Za-z_][A-Za-z0-9_]*=("[^"]*"|[^[:space:]]+)/)
  for(i=1;i<=n;i++) print a[i]
}' events.log
```

`FPAT` and `patsplit` describe matching field content. Neither magically handles arbitrary escaped delimiters, embedded newlines, or malformed serialization.

### Actual CSV, gawk 5.3+

```sh
gawk --csv 'NR>1 { print $1,$3 }' inventory.csv
gawk --csv 'NR>1 { count[$2]++ }
 END { for(k in count) print k,count[k] }' inventory.csv
```

CSV mode owns CSV record/field parsing. Do not combine it with custom `RS`, `FS`, `FPAT`, or `FIELDWIDTHS` and expect ordinary separator behavior. `print` does not automatically serialize valid CSV. Quote output fields with a CSV writer when necessary.

### Fixed-width reports

```sh
gawk 'BEGIN { FIELDWIDTHS="15 8 12" }
 { print "host=" $1, "state=" $2, "bytes=" $3 }' fixed-width.txt
```

Widths apply to the input's defined layout. A copied terminal table with varying widths is not necessarily fixed-width data.

### Regex record separators and terminators

```sh
gawk 'BEGIN { RS="\r?\n" } { print NR,$0 }' mixed-endings.txt
gawk 'BEGIN { RS="--END--\n" }
 { print "record",NR,"length",length($0),"separator",RT }' records.txt
```

`RT` holds the text that matched the record separator. It can be empty for the final unterminated record. Regex separators can have surprising edge cases around empty matches; use a separator that consumes characters.

## Sorting and arrays

```sh
# Sort a frequency map by numeric values descending
gawk '{ count[$1]++ }
 END {
   PROCINFO["sorted_in"]="@val_num_desc"
   for(k in count) print count[k],k
 }' events.txt

# Sort keys into a separate array
gawk '{ count[$1]++ }
 END { n=asorti(count,keys); for(i=1;i<=n;i++) print keys[i],count[keys[i]] }' events.txt

# Sort numeric observations into a separate array
gawk '$1 ~ /^[0-9]+([.][0-9]+)?$/ { a[++n]=$1+0 }
 END { asort(a,s,"@val_num_asc"); for(i=1;i<=n;i++) print s[i] }' values.txt
```

| Traversal value | Behavior |
|---|---|
| `@ind_str_asc` | Indices as strings, ascending |
| `@ind_num_asc` | Indices numerically, ascending |
| `@val_str_asc` | Values as strings, ascending |
| `@val_num_desc` | Values numerically, descending |
| `@unsorted` | Default traversal |

Lexical IP sorting is not numerical IP sorting: `192.0.2.100` can sort before `192.0.2.20`. Convert IPv4 to an integer key if address order matters.

### Nested maps

```sh
gawk '{ count[$1][$2]++ }
 END {
   for(src in count)
     for(dst in count[src])
       print src,dst,count[src][dst]
 }' src-dst.txt
```

Do not mix scalar and array use for the same element. Use `isarray()` when traversing heterogeneous nested structures. GNU awk supports `delete array` to remove all elements.

## Multiple files and errors

```sh
# Empty lookup file handled correctly
gawk 'ARGIND==1 { allowed[$1]=1; next }
 ARGIND==2 && ($1 in allowed)' allow.txt events.txt

# Counts per file, including empty files
gawk 'BEGINFILE { n=0 }
 { n++ }
 ENDFILE { print FILENAME,n }' ./*.log

# Gracefully report inaccessible inputs, mark overall failure
gawk 'BEGINFILE {
  if(ERRNO!="") {
    print FILENAME ": " ERRNO > "/dev/stderr"
    failed=1; nextfile
  }
}
{ records++ }
END { print "records",records+0; if(failed) exit 1 }' ./*.log
```

`nextfile` skips the rest of a file; `next` skips only the current record. `/dev/stderr` is appropriate on Linux; output destinations may differ elsewhere. Handle failure intentionally instead of silently reporting partial results as complete.

## Time and network calculations

```sh
gawk 'BEGIN {
  now=systime()
  print now
  print strftime("%Y-%m-%dT%H:%M:%SZ",now,1)
  print mktime("2026 09 15 12 00 00",1)
}'
```

The extra UTC argument avoids depending on the workstation timezone. `mktime` is not a strict calendar validator; out-of-range fields can normalize. ISO timestamps with arbitrary offsets need additional parsing.

### Fixed UTC timestamp to per-minute bucket

```sh
gawk 'match($1,/^([0-9]{4})-([0-9]{2})-([0-9]{2})T([0-9]{2}):([0-9]{2}):([0-9]{2})Z$/,m) {
  t=mktime(m[1] " " m[2] " " m[3] " " m[4] " " m[5] " " m[6],1)
  if(t>=0) count[int(t/60)*60]++
}
END {
  PROCINFO["sorted_in"]="@ind_num_asc"
  for(t in count) print strftime("%Y-%m-%dT%H:%M:00Z",t,1),count[t]
}' events.log
```

This recipe assumes already-valid UTC timestamps. It ignores nonmatching records; add a rejected-record counter for an audit report.

### IPv4 parsing and subnet membership

Save these functions in a script with the action below:

```awk
function ipv4(s, a,n,i,v) {
    n=split(s,a,".")
    if(n!=4) return -1
    v=0
    for(i=1;i<=4;i++) {
        if(a[i] !~ /^(0|[1-9][0-9]{0,2})$/ || a[i]+0>255) return -1
        v=v*256+a[i]
    }
    return v
}
BEGIN { base=ipv4("192.0.2.0"); mask=strtonum("0xffffff00") }
{
    ip=ipv4($1)
    if(ip>=0 && and(ip,mask)==base) print $1
}
```

This is a fixed `/24` example. IPv4 values fit exactly in ordinary double-precision numbers. Do not reuse this representation for 128-bit IPv6 addresses. Use an IP library for arbitrary CIDRs, IPv6, and address classification.

### Hexadecimal flags

```sh
gawk '{ flags=strtonum($1); print $1, "SYN=" (and(flags,2)!=0), "ACK=" (and(flags,16)!=0) }' flags.txt
```

This assumes each input is a valid hexadecimal/decimal TCP flag bitmask. Validate upstream; conversion does not establish that data is trustworthy.

## Security-analysis recipes

### Top denied sources from key=value records

```sh
gawk '{
  delete kv
  for(i=1;i<=NF;i++) {
    pos=index($i,"=")
    if(pos>1) kv[substr($i,1,pos-1)]=substr($i,pos+1)
  }
  if(kv["action"]=="DENY" && kv["src"]!="") n[kv["src"]]++
}
END {
  PROCINFO["sorted_in"]="@val_num_desc"
  for(ip in n) { print n[ip],ip; if(++shown==20) break }
}' events.log
```

Schema: whitespace-separated key=value tokens without quoted spaces. Splitting at the first `=` preserves additional equals signs in a value. Repeated keys use the last occurrence.

### Nearest-rank p95 latency

```sh
gawk '$1 ~ /^[0-9]+([.][0-9]+)?$/ { a[++n]=$1+0 }
END {
  if(!n) { print "No valid observations"; exit 1 }
  asort(a,s,"@val_num_asc")
  rank=int(0.95*n); if(rank<0.95*n) rank++
  print "count",n,"p95",s[rank]
}' latency-ms.txt
```

This explicitly uses the nearest-rank percentile definition. Other tools may interpolate and give a different result. Memory grows with observation count.

### Bounded number of open output files

```sh
# Requires an existing reports/ directory; input action is allowlisted
gawk '$1=="ALLOW" || $1=="DENY" {
  path="reports/" tolower($1) ".log"
  print $0 >> path
  close(path)
}' action-first.log
```

Using `>>` avoids truncating earlier output when reopening. Do not substitute arbitrary input into filenames or command strings.

## Reusable report

Save as `denied-report.awk` and run `gawk -v limit=10 -f denied-report.awk flows.log`. Input is the six-column schema in [awk.md](awk.md#networking-and-security-cookbook).

```awk
BEGIN { if(limit=="") limit=10; OFS="\t" }
/^[[:space:]]*(#|$)/ { next }
NF!=6 { rejected++; next }
$4 !~ /^[0-9]+$/ || $4+0<1 || $4+0>65535 { rejected++; next }
$6 !~ /^[0-9]+$/ { rejected++; next }
$5!="ALLOW" && $5!="DENY" { rejected++; next }
{
    accepted++
    if($5=="DENY") {
        count[$2]++
        ports[$2][$4]=1
    }
}
END {
    print "source","denied_records","distinct_ports"
    PROCINFO["sorted_in"]="@val_num_desc"
    for(ip in count) {
        print ip,count[ip],length(ports[ip])
        if(++shown>=limit) break
    }
    printf "accepted=%d rejected=%d\n",accepted,rejected > "/dev/stderr"
}
```

The limit is a trusted operator parameter; add validation if it comes from an external interface. This report does not validate address or calendar semantics.

## Debugging and performance

1. Test a small representative fixture before processing large logs.
2. Print intermediate values to stderr so the data stream remains clean.
3. Use `--lint` to expose assumptions and `--profile` to find expensive paths.
4. Keep regex literals outside repeated dynamic construction when possible.
5. Use `index()` for literal searches and avoid shelling out per record.
6. Store aggregates rather than full records when possible.
7. For huge cardinality, partition inputs or use external `sort`/a database.
8. Use `LC_ALL=C` or `-b` only when byte-oriented processing is appropriate.
9. Close dynamically opened files and pipes.
10. GNU arbitrary-precision mode (`-M`) depends on build support; verify before relying on it for exact large integers.

## Interoperability and limitations

- `@include "helpers.awk"` and `AWKPATH` can organize reusable programs; keep include paths controlled.
- GNU awk can open pipes and coprocesses (`|&`). Closing/flushing correctly matters; never construct commands from untrusted fields.
- Do not use ad hoc awk extraction to parse arbitrary JSON, XML, or shell source. Use format-aware parsers.
- Case normalization, timezone normalization, and source identity normalization should be deliberate reporting choices.
- Native extensions can execute code. Load only trusted extensions; do not treat an awk script as a sandbox.

## Official references

- [GNU awk manual](https://www.gnu.org/software/gawk/manual/gawk.html).
- [String functions](https://www.gnu.org/software/gawk/manual/html_node/String-Functions.html).
- [Sorting arrays](https://www.gnu.org/software/gawk/manual/html_node/Array-Sorting.html).
- [Time functions](https://www.gnu.org/software/gawk/manual/html_node/Time-Functions.html).
- [CSV input](https://www.gnu.org/software/gawk/manual/html_node/Comma-Separated-Fields.html).
- [GNU awk debugger](https://www.gnu.org/software/gawk/manual/html_node/Debugger.html).
