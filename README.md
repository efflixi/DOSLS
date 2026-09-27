# LS for DOS 6.22

This is a 16-bit DOS directory lister written in NASM assembly. The flat
8086-mode load module is wrapped in a real MZ executable header to produce
`LS.EXE`; it is not a `.COM` program renamed to `.EXE`.

## Build

Requires NASM and Python 3:

```sh
make
```

The result is `LS.EXE`. The assembly uses `bits 16` and only 8086-compatible
instructions. It does not use an FPU or DOS services newer than DOS 3.

## Usage

```text
LS [options] [directory|pattern|file]
  -a           include hidden/system entries and . / .. when returned
  -A           include hidden/system entries but omit . / .. entries
  -l           show directory marker and 32-bit file size
  -h           show sizes in rounded K/M/G units (implies -l)
  -1           force one entry per line
  -F           append / to directories and * to EXE/COM/BAT
  -p           append / to directories
  -r           reverse the selected sort order
  -t           sort newest first
  -S           sort largest files first
  -U           preserve DOS search order (do not sort)
  -f           include hidden/system files, do not sort, disable color
  --color      always enable ANSI colors (default)
  --color=auto enable colors only when standard output is a console
  --color=never disable colors
  -C           force 80-column multi-column output
```

Short options may be combined or supplied separately. For example, `LS -alh`
and `LS -a -l -h` both include hidden entries and show human-readable file
sizes.

Color sequences require `ANSI.SYS` (or a compatible ANSI driver) to be loaded
in `CONFIG.SYS`; because color is enabled by default, use `--color=never` if
the console has no ANSI driver. `--color=auto` disables ANSI sequences when
standard output is redirected. Directory operands are listed by contents;
wildcard patterns and file operands are passed to DOS FindFirst.

On a console, short-format listings use a fixed 80-column multi-column layout,
filled top-to-bottom in alphabetical order like Linux `ls`. Redirected output
uses one entry per line by default. `-C` forces the 80-column layout even when
output is redirected, and `-1` forces one-per-line output; `-l` and `-h`
always use one-per-line output because the long size format needs more room. The width is
intentionally fixed at 80 columns for the DOS 6.22 console rather than
attempting unreliable terminal-size detection.

For console output, LS automatically pauses after every 24 output lines and
waits for a key before continuing. This applies to both listings and help
text; redirected output never pauses.

Matching entries are collected and alphabetically sorted, case-insensitively
for ASCII characters, before display. The sort buffer is limited to 512
matches; larger results produce an explicit error and should be narrowed with
a path or wildcard. `-t` uses DOS modification date/time fields and `-S` uses
the DOS 32-bit file size; these sorts are descending by default and can be
reversed with `-r`. `-f` is the fast unsorted mode and, like GNU `ls -f`,
includes hidden/system entries. `-h` enables the size listing by itself and
displays whole K/M/G units rounded to nearest, not fractional units.

## Differences from Linux `ls`

This is a DOS-oriented subset, not a drop-in GNU `ls`. DOS uses 8.3 filenames,
DOS file attributes, and a 32-bit file size; it has no Unix inode numbers,
ownership, group, permission bits, symbolic links, or access/change times.
Consequently options that display or sort by those properties (`-i`, `-g`,
`-G`, `-o`, `-n`, `-u`, and `-c`) cannot be implemented faithfully.
Recursive traversal (`-R`) is possible in principle, but is omitted to keep
path handling within DOS limits and avoid an unreliable traversal when
directories change during enumeration. Allocated-block reporting (`-s`) has
no equivalent in the DOS FindFirst data. Alternative row-first and
comma-separated layouts (`-x`, `-m`) are not implemented; only the
column-major `-C` layout is provided, using the standard 80-column DOS console
width. Unix quoting/escaping, locale collation, and color-by-file-type
rules also have no direct DOS equivalent; sorting uses ASCII case-folding and
color classifications use DOS directory/hidden attributes and common 8.3
extensions. Results beyond the 512-entry buffer are reported as an error.

## Validation

`make` assembles the source with NASM's 8086 CPU restriction and packages a
real MZ executable. The MZ structure can be checked on a non-DOS host, but
actual file enumeration, ANSI behavior, and DOS 6.22 execution still require
a DOS machine or emulator.
