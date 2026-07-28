OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(efi_main)

SECTIONS
{
	. = 0x1000;
	.text : ALIGN(0x1000)
	{
		KEEP(*(.text.entry))
		*(.text .text.*)
	}

	. = ALIGN(0x1000);
	.rdata :
	{
		*(.rdata .rdata.*)
	}

	. = ALIGN(0x1000);
	__data_page = .;
	.data :
	{
		*(.data .data.*)
	}

	. = ALIGN(0x1000);
	.reloc :
	{
		KEEP(*(.reloc))
	}

	/DISCARD/ :
	{
		*(.comment)
		*(.note .note.*)
		*(.eh_frame .eh_frame.*)
	}
}

ASSERT((efi_main >= ADDR(.text)) && (efi_main < ADDR(.text) + SIZEOF(.text)),
	"UEFI entry point must be in .text")
ASSERT((__data_page & 0xfff) == 0,
	"base-relocation page must be 4 KiB aligned")
ASSERT(SIZEOF(.reloc) == 12,
	"seed must contain exactly one padded base-relocation block")
