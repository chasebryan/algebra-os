/*
 * Algebra x86_64 UEFI seed.
 *
 * This is target code: it deliberately includes no firmware headers, host
 * runtime, or borrowed startup objects. Offsets below come from the public
 * UEFI table layouts recorded in docs/BOOTSTRAP.md.
 */

.equ EFI_SYSTEM_TABLE_CON_OUT, 64
.equ EFI_SIMPLE_TEXT_OUTPUT_STRING, 8
.equ IMAGE_REL_BASED_DIR64, 10

.section .text.entry, "ax", @progbits
.code64
.global efi_main
.type efi_main, @function
efi_main:
	/* UEFI x64 entry: RCX = image handle, RDX = system table. */
	pushq %rbp
	movq %rsp, %rbp
	subq $32, %rsp

	/* ConOut->OutputString(ConOut, seed_message). */
	movq EFI_SYSTEM_TABLE_CON_OUT(%rdx), %rcx
	movq seed_message_pointer(%rip), %rdx
	movq EFI_SIMPLE_TEXT_OUTPUT_STRING(%rcx), %rax
	call *%rax

	leave
	ret
.size efi_main, . - efi_main

.section .rdata, "a", @progbits
.p2align 1
seed_message:
	.short 'A', 'l', 'g', 'e', 'b', 'r', 'a', ' '
	.short 's', 'e', 'e', 'd', ' ', '0', '0', '0', '1'
	.short ':', ' ', 'x', '8', '6', '_', '6', '4', ' ', 'u', 'e', 'f', 'i'
	.short 13, 10, 0

/*
 * Keeping the message address as data gives the seed one real DIR64 base
 * relocation. Firmware can therefore place the image away from ImageBase 0.
 */
.section .data, "aw", @progbits
.p2align 3
.Ldata_page:
seed_message_pointer:
	.quad seed_message

.section .reloc, "a", @progbits
.p2align 2
.Lreloc_block:
	.long .Ldata_page
	.long .Lreloc_end - .Lreloc_block
	.short (IMAGE_REL_BASED_DIR64 << 12) + (seed_message_pointer - .Ldata_page)
	.short 0
.Lreloc_end:

.section .note.GNU-stack, "", @progbits
