# geoip_lib -- GeoIP Metadata Library for Bash

[![CI](https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml/badge.svg)](https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml)
[![Version](https://img.shields.io/badge/version-1.0.1-blue.svg)](https://github.com/rfxn/geoip_lib)
[![Bash](https://img.shields.io/badge/bash-4.1%2B-green.svg)](https://www.gnu.org/software/bash/)
[![License](https://img.shields.io/badge/license-GPL%20v2-orange.svg)](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)

A shared Bash library for GeoIP operations: country name resolution, continent
mapping, continent-to-country expansion, country code validation, and multi-vendor
CIDR zone downloads with staleness tracking. Source it into your script and call
the functions -- no external dependencies beyond curl or wget for downloads.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection) and
[APF](https://github.com/rfxn/linux-firewall) via source inclusion.

```bash
source /opt/myapp/lib/geoip_lib.sh
geoip_cc_name "CN"        # => "China"
geoip_cc_continent "CN"   # => "@AS"
geoip_continent_name "@AS" # => "Asia"
```

## Features

- **Country name lookup** -- ISO 3166-1 alpha-2 to country name (~180 countries)
- **Continent mapping** -- country code to continent shorthand (@AF/@AS/@EU/@NA/@SA/@OC)
- **Continent expansion** -- shorthand to full comma-separated country code list
- **Code validation** -- country or continent format validation with typed output
- **Module-level data** -- continent lists defined once, no duplication across functions
- **Eval-free** -- case-based comma search replaces eval-based variable lookup
- **Bash 4.1+ compatible** -- no associative arrays, no bash 4.2+ features
- **Source guard** -- safe for repeated sourcing
- **Multi-vendor CIDR download** -- ipverse.net with ipdeny.com fallback, TLS retry for CentOS 6
- **Bulk tarball download** -- ipdeny.com all-zones.tar.gz for batch country acquisition
- **Staleness tracking** -- age-based freshness checks via `.last_update` timestamp
- **CIDR search** -- portable AWK IPv4 containment check (mawk-safe)
- **IP database builder** -- consolidated integer-range database from all country CIDRs
- **IP-to-country lookup** -- fast integer-range search in consolidated database
- **Country code enumeration** -- iterate all known CCs from continent variables

## Quick Start

```bash
# Source the library
source /path/to/geoip_lib.sh

# Look up a country name
name=$(geoip_cc_name "US")
echo "$name"  # "United States"

# Get continent for a country
cont=$(geoip_cc_continent "BR")
echo "$cont"  # "@SA"

# Expand continent to country list
geoip_expand_codes "@EU"
echo "$_GEOIP_VCC_CODES"  # "AD,AL,AT,AX,BA,BE,..."

# Validate input (country or continent)
if geoip_validate_cc "@AF"; then
    echo "Type: $_GEOIP_VCC_TYPE"    # "continent"
    echo "Codes: $_GEOIP_VCC_CODES"  # "AO,BF,BI,..."
fi
```

## API Reference

### geoip_cc_name(CC)

Map a 2-letter ISO 3166-1 alpha-2 country code to its common name.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints country name to stdout; returns bare code for unrecognized input
- **Returns:** Always 0

```bash
geoip_cc_name "CN"   # "China"
geoip_cc_name "AE"   # "UAE"
geoip_cc_name "ZZ"   # "ZZ" (passthrough)
```

### geoip_cc_continent(CC)

Map a country code to its continent shorthand.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC) or "unknown"
- **Returns:** Always 0

```bash
geoip_cc_continent "US"   # "@NA"
geoip_cc_continent "ZA"   # "@AF"
geoip_cc_continent "ZZ"   # "unknown"
```

### geoip_continent_name(CONT)

Map a continent shorthand to its full name.

- **Args:** `CONT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Output:** Prints full name or passthrough for unrecognized input
- **Returns:** Always 0

```bash
geoip_continent_name "@EU"   # "Europe"
geoip_continent_name "@XX"   # "@XX" (passthrough)
```

### geoip_expand_codes(INPUT)

Expand a continent shorthand to a comma-separated list of country codes.

- **Args:** `INPUT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Sets:** `_GEOIP_VCC_CODES` -- comma-separated CC list
- **Returns:** 0 on success, 1 on unknown continent

```bash
geoip_expand_codes "@AF"
echo "$_GEOIP_VCC_CODES"  # "AO,BF,BI,BJ,..."
```

### geoip_validate_cc(INPUT)

Validate a country code or continent shorthand.

- **Args:** `INPUT` -- 2-letter country code (XX) or continent shorthand (@XX)
- **Sets:** `_GEOIP_VCC_TYPE` ("country" or "continent"), `_GEOIP_VCC_CODES` (CC list)
- **Returns:** 0 on valid input, 1 on invalid

For country codes, `_GEOIP_VCC_CODES` is set to the input code directly.
For continent shorthands, `_GEOIP_VCC_CODES` is set to the expanded CC list.

```bash
geoip_validate_cc "CN"
# _GEOIP_VCC_TYPE="country", _GEOIP_VCC_CODES="CN"

geoip_validate_cc "@EU"
# _GEOIP_VCC_TYPE="continent", _GEOIP_VCC_CODES="AD,AL,AT,..."
```

### geoip_download(CC, FAMILY, OUTPUT, [SOURCE])

Download CIDR zone data for a country code from public sources.

- **Args:**
  - `CC` -- 2-letter country code
  - `FAMILY` -- address family: `4` (IPv4) or `6` (IPv6)
  - `OUTPUT` -- output file path for CIDR data
  - `SOURCE` -- (optional) `"auto"` (default), `"ipverse"`, or `"ipdeny"`
- **Returns:** 0 on success, 1 on failure (invalid args, download error, corrupt data)

Auto mode cascades ipverse.net first, falls back to ipdeny.com. Downloaded data
is validated against CIDR format before writing.

```bash
geoip_download "CN" "4" "/tmp/cn.zone"            # auto cascade
geoip_download "US" "6" "/tmp/us6.zone" "ipverse"  # specific source
```

### geoip_is_stale(DATA_DIR, [MAX_AGE_DAYS])

Check whether CIDR data in a directory needs refreshing.

- **Args:** `DATA_DIR` -- directory containing `.last_update` file; `MAX_AGE_DAYS` -- threshold (default: 30)
- **Returns:** 0 if stale or `.last_update` missing, 1 if fresh

```bash
if geoip_is_stale "/var/lib/geoip" 30; then
    echo "Data is stale, refreshing..."
fi
```

### geoip_mark_updated(DATA_DIR)

Write current epoch timestamp to `.last_update` in the given directory.

- **Args:** `DATA_DIR` -- directory to write `.last_update` into (must exist)
- **Returns:** 0 on success, 1 on failure

```bash
geoip_mark_updated "/var/lib/geoip"
```

### geoip_cidr_search(IP, FILE [FILE ...])

Search for an IPv4 address across one or more CIDR zone files using portable AWK.

- **Args:** `IP` -- IPv4 address to look up; `FILE` -- one or more CIDR zone files
- **Output:** Prints the matching file path to stdout
- **Returns:** 0 on match, 1 on no match

```bash
geoip_cidr_search "8.8.8.8" /var/lib/geoip/us.zone /var/lib/geoip/cn.zone
# prints: /var/lib/geoip/us.zone
```

### geoip_all_cc()

Emit all known ISO 3166-1 country codes, one per line.

- **Output:** Prints uppercase 2-letter CCs to stdout (190-240 codes)
- **Returns:** Always 0

```bash
geoip_all_cc | head -3
# AO
# BF
# BI
```

### geoip_ip_lookup(IP, DB_FILE)

Look up an IPv4 address in a consolidated integer-range database.

- **Args:** `IP` -- IPv4 dotted-quad address; `DB_FILE` -- integer-range database file
- **Output:** Prints 2-letter country code on match
- **Returns:** 0 on match, 1 on no match or invalid input
- **Complexity:** O(N) linear scan; high-frequency callers should cache results

```bash
geoip_ip_lookup "8.8.8.8" /var/lib/geoip/ipcountry.dat
# prints: US
```

### geoip_build_ipdb(OUTPUT, [MIN_RANGES])

Build a consolidated IPv4 integer-range database from all country CIDRs.
Uses ipdeny.com bulk tarball when available, falls back to per-country cascade.

- **Args:** `OUTPUT` -- destination file path; `MIN_RANGES` -- minimum range count (default: 1000)
- **Sets:** `_GEOIP_BUILD_COUNT`, `_GEOIP_BUILD_FAIL`, `_GEOIP_BUILD_RANGES`
- **Returns:** 0 on success, 1 on failure

```bash
geoip_build_ipdb "/var/lib/geoip/ipcountry.dat"
echo "$_GEOIP_BUILD_COUNT countries, $_GEOIP_BUILD_RANGES ranges"
```

## Module Variables

After sourcing, these read-only variables are available:

| Variable | Description |
|----------|-------------|
| `GEOIP_LIB_VERSION` | Library version (semver) |
| `_GEOIP_CC_AF` | Africa country codes (comma-separated) |
| `_GEOIP_CC_AS` | Asia country codes (comma-separated) |
| `_GEOIP_CC_EU` | Europe country codes (comma-separated) |
| `_GEOIP_CC_NA` | North America country codes (comma-separated) |
| `_GEOIP_CC_SA` | South America country codes (comma-separated) |
| `_GEOIP_CC_OC` | Oceania country codes (comma-separated) |

## Consumer Integration

To use geoip_lib in your project:

1. Copy `files/geoip_lib.sh` to your project's internals directory
2. Source it early in your startup sequence:
   ```bash
   if [ -f "$_internals_dir/geoip_lib.sh" ]; then
       # shellcheck disable=SC1091
       . "$_internals_dir/geoip_lib.sh"
   fi
   ```
3. Call functions directly -- all output is via stdout or named variables

## Testing

```bash
# Run tests on Debian 12 (default)
make -C tests test

# Run on a specific OS
make -C tests test-rocky9

# Run on all supported OS targets
make -C tests test-all
```

## Requirements

- Bash 4.1+ (CentOS 6 compatible)
- No external dependencies for metadata functions
- curl or wget required for download functions (auto-detected at source time)

## License

GNU General Public License v2 -- see source file headers for details.
