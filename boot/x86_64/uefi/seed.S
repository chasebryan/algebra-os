/*
 * Algebra x86_64 UEFI seed.
 *
 * This is target code: it deliberately includes no firmware headers, host
 * runtime, or borrowed startup objects. Offsets below come from the public
 * UEFI table layouts recorded in docs/BOOTSTRAP.md.
 */

.equ EFI_SYSTEM_TABLE_CON_OUT, 64
.equ EFI_SIMPLE_TEXT_OUTPUT_STRING, 8
.equ EFI_SYSTEM_TABLE_BOOT_SERVICES, 96
.equ EFI_BOOT_SERVICES_GET_MEMORY_MAP, 56
.equ EFI_BOOT_SERVICES_EXIT_BOOT_SERVICES, 232
.equ IMAGE_REL_BASED_DIR64, 10

.section .text.entry, "ax", @progbits
.code64
.global efi_main
.type efi_main, @function
efi_main:
	/* UEFI x64 entry: RCX = image handle, RDX = system table. */
	pushq %rbp
	movq %rsp, %rbp
	pushq %r12
	pushq %r13
	pushq %rdi
	pushq %rsi
	subq $48, %rsp               /* Shadow space plus fifth argument. */
	movq %rcx, 40(%rsp)          /* Image handle survives firmware calls. */
	movl $0, exit_attempts(%rip)
	movq EFI_SYSTEM_TABLE_BOOT_SERVICES(%rdx), %r12

	/* ConOut->OutputString(ConOut, seed_message). */
	movq EFI_SYSTEM_TABLE_CON_OUT(%rdx), %rcx
	movq seed_message_pointer(%rip), %rdx
	movq EFI_SIMPLE_TEXT_OUTPUT_STRING(%rcx), %rax
	call *%rax
	call serial_init

	/* One fixed buffer bounds early firmware-map handling. */
.Lget_map:
	movq $65536, map_size(%rip)
	leaq map_size(%rip), %rcx
	leaq memory_map(%rip), %rdx
	leaq map_key(%rip), %r8
	leaq descriptor_size(%rip), %r9
	leaq descriptor_version(%rip), %rax
	movq %rax, 32(%rsp)
	call *EFI_BOOT_SERVICES_GET_MEMORY_MAP(%r12)
	testq %rax, %rax
	jnz .Lmap_failed

	leaq memory_map(%rip), %rdi
	movq map_size(%rip), %rsi
	movq descriptor_size(%rip), %rdx
	movl descriptor_version(%rip), %ecx
	call validate_memory_map
	testl %eax, %eax
	jnz .Lmap_invalid
	cmpl $0, exit_attempts(%rip)
	jne .Lexit_services
	leaq serial_message(%rip), %r8
	call serial_write
.Lexit_services:
	incl exit_attempts(%rip)
	movq 40(%rsp), %rcx
	movq map_key(%rip), %rdx
.ifdef TEST_STALE_MAP_KEY
	cmpl $1, exit_attempts(%rip)
	jne .Ltest_key_ready
	xorq $1, %rdx                /* Test build: invalidate exactly the first key. */
.Ltest_key_ready:
.endif
	call *EFI_BOOT_SERVICES_EXIT_BOOT_SERVICES(%r12)
	testq %rax, %rax
	jz .Lhandoff
	movabsq $0x8000000000000002, %rdx
	cmpq %rdx, %rax
	jne .Lexit_failed
	cmpl $3, exit_attempts(%rip)
	jb .Lget_map                 /* Only GetMemoryMap and ExitBootServices retry. */
.Lexit_failed:
	leaq handoff_failure(%rip), %r8
	jmp .Lreport_failure
.Lhandoff:
	/* No firmware call is permitted beyond this point. */
	cli
	cld
	leaq memory_map(%rip), %rax
	movq %rax, boot_info+24(%rip)
	movq map_size(%rip), %rax
	movq %rax, boot_info+32(%rip)
	movq descriptor_size(%rip), %rax
	movq %rax, boot_info+40(%rip)
	movl descriptor_version(%rip), %eax
	movl %eax, boot_info+48(%rip)
	movq $1, boot_info+16(%rip)
	leaq __image_base(%rip), %rax
	movq %rax, boot_info+64(%rip)
	movq $__image_end, boot_info+72(%rip)
	leaq boot_info(%rip), %rdi
	leaq kernel_stack_top(%rip), %rsp
	xorl %ebp, %ebp
	jmp kernel_entry
.Lmap_invalid:
	movabsq $0x8000000000000002, %rax  /* EFI_INVALID_PARAMETER. */
.Lmap_failed:
	leaq serial_failure(%rip), %r8
.Lreport_failure:
	movq %rax, %r13
	call serial_write
	cmpl $0, exit_attempts(%rip)
	jne .Lfatal_halt             /* Firmware may be partially shut down. */
	movq %r13, %rax
	addq $48, %rsp
	popq %rsi
	popq %rdi
	popq %r13
	popq %r12
	leave
	ret
.Lfatal_halt:
	cli
	hlt
	jmp .Lfatal_halt
.size efi_main, . - efi_main

.section .rdata, "a", @progbits
.p2align 1
seed_message:
	.short 'A', 'l', 'g', 'e', 'b', 'r', 'a', ' '
	.short 's', 'e', 'e', 'd', ' ', '0', '0', '0', '1'
	.short ':', ' ', 'x', '8', '6', '_', '6', '4', ' ', 'u', 'e', 'f', 'i'
	.short 13, 10, 0

serial_message:
	.ascii "Algebra serial 0001: uefi entry\r\n"
	.asciz "Algebra memory map 0001: validated\r\n"
serial_failure:
	.asciz "Algebra memory map 0001: failed\r\n"
handoff_failure:
	.asciz "Algebra handoff 0001: failed\r\n"

/*
 * Keeping the message address as data gives the seed one real DIR64 base
 * relocation. Firmware can therefore place the image away from ImageBase 0.
 */
.section .data, "aw", @progbits
.p2align 3
.Ldata_page:
seed_message_pointer:
	.quad seed_message
.p2align 3
map_size:
	.quad 0
map_key:
	.quad 0
descriptor_size:
	.quad 0
descriptor_version:
	.long 0
exit_attempts:
	.long 0
.p2align 3
boot_info:
	.ascii "ALGBOOT\0"
	.long 1, 80
	.quad 0, 0, 0, 0
	.long 0, 0
	.quad 0x3f8, 0, 0
.p2align 3
memory_map:
	.fill 65536, 1, 0
.p2align 12
.global kernel_stack_guard
kernel_stack_guard:
	.fill 4096, 1, 0
kernel_stack:
	.fill 16384, 1, 0
.global kernel_stack_top
kernel_stack_top:

.section .reloc, "a", @progbits
.p2align 2
.Lreloc_block:
	.long .Ldata_page
	.long .Lreloc_end - .Lreloc_block
	.short (IMAGE_REL_BASED_DIR64 << 12) + (seed_message_pointer - .Ldata_page)
	.short 0
.Lreloc_end:

.section .note.GNU-stack, "", @progbits
