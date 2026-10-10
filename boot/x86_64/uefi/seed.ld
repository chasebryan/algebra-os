OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(efi_main)

SECTIONS
{
	__image_base = 0;
	. = 0x1000;
	__text_start = .;
	.text : ALIGN(0x1000)
	{
		KEEP(*(.text.entry))
		*(.text .text.*)
	}

	. = ALIGN(0x1000);
	__text_end = .;
	.rdata :
	{
		*(.rdata .rdata.*)
	}

	. = ALIGN(0x1000);
	__data_page = .;
	__data_start = .;
	.data :
	{
		*(.data .data.*)
	}

	. = ALIGN(0x1000);
	__data_end = .;
	.reloc :
	{
		KEEP(*(.reloc))
	}
	__image_end = ALIGN(0x1000);

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
ASSERT((kernel_stack_top & 15) == 0, "kernel stack must be 16-byte aligned")
ASSERT(__image_end <= 1048576, "bootstrap image must fit the bounded paging layout")
