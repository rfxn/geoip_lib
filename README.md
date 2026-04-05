# geoip_lib

<p align="center">
  <a href="https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml"><img src="https://github.com/rfxn/geoip_lib/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="CHANGELOG"><img src="https://img.shields.io/badge/version-1.0.4-blue.svg?style=flat-square" alt="Version"></a>
  <a href="https://www.gnu.org/licenses/old-licenses/gpl-2.0.html"><img src="https://img.shields.io/badge/license-GPL_v2-green.svg?style=flat-square" alt="License: GPL v2"></a>
  <a href="https://www.gnu.org/software/bash/"><img src="https://img.shields.io/badge/bash-4.1%2B-green.svg?style=flat-square" alt="Bash 4.1+"></a>
</p>

**GeoIP lookup library for Bash** -- IP-to-country resolution with binary
search, IPv4/IPv6, auto-updating databases, and multi-vendor CIDR downloads.

> (C) 2002-2026, R-fx Networks <proj@rfxn.com>
> Licensed under GNU GPL v2

---

## Quick Start

```bash
# Source the library
source /path/to/geoip_lib.sh

# Look up a country name
name=$(geoip_cc_name "US")
echo "$name"                   # "United States"

# Get continent for a country
cont=$(geoip_cc_continent "BR")
echo "$cont"                   # "@SA"

# Look up an IPv4 address
geoip_ip_lookup "8.8.8.8" /var/lib/geoip/ipcountry.dat
# prints: US

# Validate a country or continent code
if geoip_validate_cc "@EU"; then
    echo "$_GEOIP_VCC_TYPE"   # "continent"
    echo "$_GEOIP_VCC_CODES"  # "AD,AL,AT,AX,BA,BE,..."
fi
```

---

## 1. Introduction

geoip_lib is a shared Bash library for GeoIP operations. It provides
country name resolution, continent mapping, code validation, multi-vendor
CIDR zone downloads with staleness tracking, and IPv4/IPv6 address-to-country
lookups via consolidated databases.

Consumed by [BFD](https://github.com/rfxn/linux-brute-force-detection) and
[APF](https://github.com/rfxn/linux-firewall) via source inclusion.

- **Country name lookup** -- ISO 3166-1 alpha-2 to country name (~180 countries)
- **Continent mapping** -- country code to continent shorthand (@AF/@AS/@EU/@NA/@SA/@OC)
- **Continent expansion** -- shorthand to full comma-separated country code list
- **Code validation** -- country or continent format validation with typed output
- **Multi-vendor CIDR download** -- ipverse.net with ipdeny.com fallback, TLS retry for CentOS 6
- **Bulk tarball download** -- ipdeny.com all-zones.tar.gz for batch country acquisition
- **Staleness tracking** -- age-based freshness checks via `.last_update` timestamp
- **IPv4 database builder** -- consolidated integer-range database from all country CIDRs
- **IPv4-to-country lookup** -- fast integer-range search in consolidated database
- **IPv6 database builder** -- consolidated hex-range database from per-country CIDR downloads
- **IPv6-to-country lookup** -- 32-char hex string comparison (no 128-bit arithmetic)
- **CIDR search** -- portable AWK IPv4 containment check (mawk-safe)
- **Eval-free** -- case-based comma search replaces eval-based variable lookup
- **Bash 4.1+ compatible** -- no associative arrays, no bash 4.2+ features
- **Source guard** -- safe for repeated sourcing

### 1.1 Supported Systems

- Bash 4.1+ (CentOS 6 compatible)
- No external dependencies for metadata functions
- curl or wget required for download functions (auto-detected at source time)
- AWK required for CIDR search (mawk-safe, gawk not required)

### 1.2 Key Files

| File | Purpose |
|------|---------|
| `files/geoip_lib.sh` | Library source file |
| `tests/` | BATS test suite (230 tests) |
| `CHANGELOG` | Full version history |

---

## 2. Installation

Copy `files/geoip_lib.sh` to your project's internals directory and source
it early in your startup sequence.

### 2.1 Source Integration

```bash
# Copy the library into your project
cp geoip_lib/files/geoip_lib.sh /opt/myapp/lib/

# Source in your script
if [ -f "$_internals_dir/geoip_lib.sh" ]; then
    # shellcheck disable=SC1091
    . "$_internals_dir/geoip_lib.sh"
fi
```

All output is via stdout or named shell variables -- no project-specific
code, all behavior controlled via environment variables.

### 2.2 Upgrading

Replace `geoip_lib.sh` with the new version. The source guard ensures safe
repeated sourcing. Check CHANGELOG for API changes between versions.

---

## 3. Configuration

Configure geoip_lib by setting environment variables before sourcing.

### 3.1 Environment Overrides

| Variable | Default | Purpose |
|----------|---------|---------|
| `GEOIP_CURL_BIN` | `command -v curl` | Path to curl binary |
| `GEOIP_WGET_BIN` | `command -v wget` | Path to wget binary |
| `GEOIP_AWK_BIN` | `command -v awk` | Path to awk binary |
| `GEOIP_DL_TIMEOUT` | `120` | Download timeout in seconds |
| `GEOIP_TLS_INSECURE` | `0` | Set to `"1"` to allow insecure TLS fallback when strict TLS fails (for legacy systems with untrusted CA bundles). Without this, all TLS errors are fatal. |

### 3.2 Module Variables

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

---

## 4. Usage

Source the library and call functions directly. Metadata functions
(name lookup, continent mapping, validation) require no setup. Download
and database functions require curl or wget and a writable output path.

```bash
source /path/to/geoip_lib.sh

# Metadata operations (no network, no dependencies)
geoip_cc_name "CN"             # "China"
geoip_cc_continent "US"        # "@NA"
geoip_validate_cc "@EU"        # sets _GEOIP_VCC_TYPE, _GEOIP_VCC_CODES

# Download operations (require curl/wget)
geoip_download "US" "4" "/tmp/us.zone"

# Database build + lookup (require curl/wget + writable path)
geoip_build_ipdb "/var/lib/geoip/ipcountry.dat"
geoip_ip_lookup "8.8.8.8" /var/lib/geoip/ipcountry.dat
```

### 4.1 Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success -- operation completed, match found, or input valid |
| 1 | Failure -- invalid input, no match, download error, or build failure |

All public functions return 0 on success and 1 on failure. Metadata
functions (`geoip_cc_name`, `geoip_cc_continent`, `geoip_continent_name`)
always return 0, printing a passthrough value for unrecognized input.

---

## 5. API Reference

This section documents all public functions. Internal functions (prefixed
with `_geoip_`) are not part of the stable API.

### 5.1 geoip_cc_name(CC)

Map a 2-letter ISO 3166-1 alpha-2 country code to its common name.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints country name to stdout; returns bare code for unrecognized input
- **Returns:** Always 0

```bash
geoip_cc_name "CN"   # "China"
geoip_cc_name "AE"   # "UAE"
geoip_cc_name "ZZ"   # "ZZ" (passthrough)
```

### 5.2 geoip_cc_continent(CC)

Map a country code to its continent shorthand.

- **Args:** `CC` -- uppercase 2-letter country code
- **Output:** Prints continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC) or "unknown"
- **Returns:** Always 0

```bash
geoip_cc_continent "US"   # "@NA"
geoip_cc_continent "ZA"   # "@AF"
geoip_cc_continent "ZZ"   # "unknown"
```

### 5.3 geoip_continent_name(CONT)

Map a continent shorthand to its full name.

- **Args:** `CONT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Output:** Prints full name or passthrough for unrecognized input
- **Returns:** Always 0

```bash
geoip_continent_name "@EU"   # "Europe"
geoip_continent_name "@XX"   # "@XX" (passthrough)
```

### 5.4 geoip_expand_codes(INPUT)

Expand a continent shorthand to a comma-separated list of country codes.

- **Args:** `INPUT` -- continent shorthand (@AF, @AS, @EU, @NA, @SA, @OC)
- **Sets:** `_GEOIP_VCC_CODES` -- comma-separated CC list
- **Returns:** 0 on success, 1 on unknown continent

```bash
geoip_expand_codes "@AF"
echo "$_GEOIP_VCC_CODES"  # "AO,BF,BI,BJ,..."
```

### 5.5 geoip_validate_cc(INPUT)

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

### 5.6 geoip_all_cc()

Emit all known ISO 3166-1 country codes, one per line.

- **Output:** Prints uppercase 2-letter CCs to stdout (190-240 codes)
- **Returns:** Always 0

```bash
geoip_all_cc | head -3
# AO
# BF
# BI
```

### 5.7 geoip_download(CC, FAMILY, OUTPUT, [SOURCE])

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

### 5.8 geoip_is_stale(DATA_DIR, [MAX_AGE_DAYS])

Check whether CIDR data in a directory needs refreshing.

- **Args:** `DATA_DIR` -- directory containing `.last_update` file; `MAX_AGE_DAYS` -- threshold (default: 30)
- **Returns:** 0 if stale or `.last_update` missing, 1 if fresh

```bash
if geoip_is_stale "/var/lib/geoip" 30; then
    echo "Data is stale, refreshing..."
fi
```

### 5.9 geoip_mark_updated(DATA_DIR)

Write current epoch timestamp to `.last_update` in the given directory.

- **Args:** `DATA_DIR` -- directory to write `.last_update` into (must exist)
- **Returns:** 0 on success, 1 on failure

```bash
geoip_mark_updated "/var/lib/geoip"
```

### 5.10 geoip_cidr_search(IP, FILE [FILE ...])

Search for an IPv4 address across one or more CIDR zone files using portable AWK.

- **Args:** `IP` -- IPv4 address to look up; `FILE` -- one or more CIDR zone files
- **Output:** Prints the matching file path to stdout
- **Returns:** 0 on match, 1 on no match

```bash
geoip_cidr_search "8.8.8.8" /var/lib/geoip/us.zone /var/lib/geoip/cn.zone
# prints: /var/lib/geoip/us.zone
```

### 5.11 geoip_ip_lookup(IP, DB_FILE)

Look up an IPv4 address in a consolidated integer-range database.

- **Args:** `IP` -- IPv4 dotted-quad address; `DB_FILE` -- integer-range database file
- **Output:** Prints 2-letter country code on match
- **Returns:** 0 on match, 1 on no match or invalid input
- **Complexity:** O(N) linear scan; high-frequency callers should cache results

```bash
geoip_ip_lookup "8.8.8.8" /var/lib/geoip/ipcountry.dat
# prints: US
```

### 5.12 geoip_ip6_lookup(IP, DB6_FILE)

Look up an IPv6 address in a consolidated hex-range database.

Normalizes the input IPv6 address to a 32-char lowercase hex string, then
performs lexicographic comparison against the database ranges (equivalent to
128-bit numeric comparison without integer overflow).

- **Args:** `IP` -- IPv6 address (any valid abbreviation); `DB6_FILE` -- hex-range database file
- **Output:** Prints 2-letter country code on match
- **Returns:** 0 on match, 1 on no match or invalid input
- **Rejects:** IPv4 addresses and dotted-quad mapped addresses (`::ffff:a.b.c.d`)
- **Complexity:** O(N) linear scan; high-frequency callers should cache results

```bash
geoip_ip6_lookup "2001:db8::1" /var/lib/geoip/ipcountry6.dat
# prints: JP
```

### 5.13 geoip_build_ipdb(OUTPUT, [MIN_RANGES])

Build a consolidated IPv4 integer-range database from all country CIDRs.
Uses ipdeny.com bulk tarball when available, falls back to per-country cascade.

- **Args:** `OUTPUT` -- destination file path; `MIN_RANGES` -- minimum range count (default: 1000)
- **Sets:** `_GEOIP_BUILD_COUNT`, `_GEOIP_BUILD_FAIL`, `_GEOIP_BUILD_RANGES`
- **Returns:** 0 on success, 1 on failure

```bash
geoip_build_ipdb "/var/lib/geoip/ipcountry.dat"
echo "$_GEOIP_BUILD_COUNT countries, $_GEOIP_BUILD_RANGES ranges"
```

### 5.14 geoip_build_ip6db(OUTPUT, [MIN_RANGES])

Build a consolidated IPv6 hex-range database from all country CIDRs.
Downloads IPv6 CIDR data per-country (~240 serial HTTP requests; no bulk
IPv6 tarball available). Typical build time: 2-5 minutes.

- **Args:** `OUTPUT` -- destination file path; `MIN_RANGES` -- minimum range count (default: 500)
- **Sets:** `_GEOIP_BUILD6_COUNT`, `_GEOIP_BUILD6_FAIL`, `_GEOIP_BUILD6_RANGES`
- **Returns:** 0 on success, 1 on failure

**IPv6 database format:**
```
START_HEX END_HEX CC
20010200000000000000000000000000 200102000007ffffffffffffffffffff JP
20010db8000000000000000000000000 20010db80000ffffffffffffffffffff US
```

Three columns: 32-char lowercase hex start, 32-char lowercase hex end, 2-letter CC.
Sorted lexicographically by START_HEX (`LC_ALL=C`).

```bash
geoip_build_ip6db "/var/lib/geoip/ipcountry6.dat"
echo "$_GEOIP_BUILD6_COUNT countries, $_GEOIP_BUILD6_RANGES ranges"
```

---

## 6. Testing

```bash
# Run tests on Debian 12 (default)
make -C tests test

# Run on a specific OS
make -C tests test-rocky9

# Run on all supported OS targets
make -C tests test-all
```

---

## License

GNU General Public License v2 -- see source file headers for details.

## Support

- **Issues:** [github.com/rfxn/geoip_lib/issues](https://github.com/rfxn/geoip_lib/issues)
- **Email:** proj@rfxn.com
