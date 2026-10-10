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

	/* Preserve OutputString's status across bounded COM1 diagnostics.
	 * Only volatile x64 ABI registers are used below. See ADR 0002.
	 */
	movq %rax, %r11
	movw $0x3f9, %dx
	xorb %al, %al
	outb %al, %dx                 /* Disable UART interrupts. */
	movw $0x3fb, %dx
	movb $0x80, %al
	outb %al, %dx                 /* Divisor latch access. */
	movw $0x3f8, %dx
	movb $1, %al
	outb %al, %dx                 /* 115200 baud: divisor 1. */
	movw $0x3f9, %dx
	xorb %al, %al
	outb %al, %dx
	movw $0x3fb, %dx
	movb $3, %al
	outb %al, %dx                 /* Eight data bits, no parity, one stop. */
	movw $0x3fa, %dx
	movb $7, %al
	outb %al, %dx                 /* Enable and clear FIFOs. */
	movw $0x3fc, %dx
	movb $3, %al
	outb %al, %dx                 /* DTR and RTS. */
	leaq serial_message(%rip), %r8
.Lserial_next:
	movb (%r8), %r10b
	testb %r10b, %r10b
	jz .Lserial_done
	movl $65536, %r9d
	movw $0x3fd, %dx
.Lserial_wait:
	inb %dx, %al
	testb $0x20, %al
	jnz .Lserial_send
	decl %r9d
	jnz .Lserial_wait
	jmp .Lserial_done             /* A missing UART cannot hang the seed. */
.Lserial_send:
	movw $0x3f8, %dx
	movb %r10b, %al
	outb %al, %dx
	incq %r8
	jmp .Lserial_next
.Lserial_done:
	movq %r11, %rax
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

serial_message:
	.asciz "Algebra serial 0001: uefi entry\r\n"

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
