#!/bin/sh
set -eu
LC_ALL=C
TZ=UTC0
export LC_ALL TZ

if [ "$#" -ne 2 ]; then
	printf 'usage: %s SEED_ELF SEED_EFI\n' "$0" >&2
	exit 2
fi

seed_elf=$1
seed_efi=$2
objdump=${OBJDUMP:-objdump}
readelf=${READELF:-readelf}
nm=${NM:-nm}

fail()
{
	printf 'seed audit: %s\n' "$1" >&2
	exit 1
}

[ -s "$seed_elf" ] || fail "missing ELF intermediate: $seed_elf"
[ -s "$seed_efi" ] || fail "missing EFI image: $seed_efi"

pe_headers=$("$objdump" -p "$seed_efi") || fail 'objdump could not inspect PE headers'
pe_sections=$("$objdump" -h "$seed_efi") || fail 'objdump could not inspect PE sections'

printf '%s\n' "$pe_headers" | grep -q 'file format pei-x86-64' || \
	fail 'image is not x86_64 PE/COFF'
printf '%s\n' "$pe_headers" | grep -Eq 'Magic[[:space:]]+020b' || \
	fail 'image is not PE32+'
printf '%s\n' "$pe_headers" | grep -Eq 'Subsystem[[:space:]]+0000000a' || \
	fail 'image is not an EFI application'
printf '%s\n' "$pe_headers" | grep -Eq 'AddressOfEntryPoint[[:space:]]+0000000000001000' || \
	fail 'image entry point is not the start of .text'
printf '%s\n' "$pe_headers" | grep -Eq 'Time/Date[[:space:]]+Thu Jan[[:space:]]+1 00:00:00 1970$' || \
	fail 'PE timestamp is not deterministic'
if printf '%s\n' "$pe_headers" | grep -q 'relocations stripped'; then
	fail 'image is marked as non-relocatable'
fi
printf '%s\n' "$pe_headers" | grep -Eq \
	'Entry 1 0000000000000000 00000000 Import Directory' || \
	fail 'image has an import directory'
printf '%s\n' "$pe_headers" | grep -Eq \
	'Entry 5 [[:xdigit:]]+ 0000000c Base Relocation Directory.*\.reloc' || \
	fail 'image lacks the expected base-relocation directory'

for section in .text .rdata .data .reloc; do
	printf '%s\n' "$pe_sections" | grep -Eq "[[:space:]]$section[[:space:]]" || \
		fail "image lacks $section"
done

section_count=$(printf '%s\n' "$pe_sections" | \
	awk '$1 ~ /^[0-9]+$/ && $2 ~ /^\./ { count++ } END { print count + 0 }')
[ "$section_count" -eq 4 ] || fail "image contains unexpected sections"

printf '%s\n' "$pe_sections" | awk '
	$2 == ".text" { getline; ok = /READONLY, CODE/ }
	END { exit ok ? 0 : 1 }
' || fail '.text is not read-only executable code'
printf '%s\n' "$pe_sections" | awk '
	$2 == ".rdata" { getline; ok = /READONLY, DATA/ }
	END { exit ok ? 0 : 1 }
' || fail '.rdata is not read-only data'
printf '%s\n' "$pe_sections" | awk '
	$2 == ".data" { getline; ok = /DATA/ && !/READONLY/ && !/CODE/ }
	END { exit ok ? 0 : 1 }
' || fail '.data is not writable, non-executable data'

elf_dynamic=$("$readelf" --dynamic "$seed_elf") || fail 'readelf could not inspect ELF dependencies'
if printf '%s\n' "$elf_dynamic" | grep -q '(NEEDED)'; then
	fail 'ELF intermediate has a runtime dependency'
fi

elf_undefined=$("$nm" --undefined-only "$seed_elf") || fail 'nm could not inspect ELF symbols'
if [ -n "$elf_undefined" ]; then
	fail 'ELF intermediate has undefined symbols'
fi

printf '%s\n' 'seed audit: PE32+ x86_64 EFI application'
printf '%s\n' 'seed audit: no imports or undefined symbols'
printf '%s\n' 'seed audit: deterministic timestamp and DIR64 relocation present'
