/* Embedded kernel entry stub: RDI=boot information, RSP aligned to 16 bytes,
 * interrupts disabled, direction flag clear, firmware page tables inherited.
 * This entry never returns and never calls firmware.
 */
.section .text, "ax", @progbits
.code64
.global kernel_entry
.type kernel_entry, @function
kernel_entry:
	movq %rdi, %r12
	movabsq $0x00544f4f42474c41, %rax /* "ALGBOOT\0". */
	cmpq %rax, (%r12)
	jne .Lbad_info
	cmpl $1, 8(%r12)
	jne .Lbad_info
	cmpl $80, 12(%r12)
	jne .Lbad_info
	cmpq $1, 16(%r12)
	jne .Lbad_info
	movq 24(%r12), %rdi
	movq 32(%r12), %rsi
	movq 40(%r12), %rdx
	movl 48(%r12), %ecx
	call validate_memory_map
	testl %eax, %eax
	jnz .Lbad_info
	leaq kernel_message(%rip), %r8
	call serial_write
	call install_processor_tables
	leaq processor_message(%rip), %r8
	call serial_write
	movq %r12, %rdi
	call install_kernel_paging
	testl %eax, %eax
	jnz .Lbad_paging
	leaq paging_message(%rip), %r8
	call serial_write
	movq 24(%r12), %rax
	movq %rax, frame_config(%rip)
	movq 32(%r12), %rax
	movq %rax, frame_config+8(%rip)
	movq 40(%r12), %rax
	movq %rax, frame_config+16(%rip)
	movl 48(%r12), %eax
	movq %rax, frame_config+24(%rip)
	movq 64(%r12), %rax
	movq %rax, frame_config+32(%rip)
	movq 72(%r12), %rax
	movq %rax, frame_config+40(%rip)
	leaq frame_catalog(%rip), %rdi
	leaq frame_config(%rip), %rsi
	movl $81920, %edx
	call build_frame_catalog
	testl %eax, %eax
	jnz .Lbad_frames
	cmpq $0, frame_catalog+32(%rip)
	je .Lbad_frames
	leaq frame_extents(%rip), %rdi
	movq frame_catalog+24(%rip), %rsi
	call encode_hex64
	leaq frame_count(%rip), %rdi
	movq frame_catalog+32(%rip), %rsi
	call encode_hex64
	leaq frame_summary(%rip), %r8
	call serial_write
	leaq frame_message(%rip), %r8
	call serial_write
.ifdef TEST_BREAKPOINT
	int3
.endif
.ifdef TEST_INVALID_OPCODE
	ud2
.endif
.ifdef TEST_DIVIDE_ERROR
	xorl %ecx, %ecx
	movl $1, %eax
	xorl %edx, %edx
	divq %rcx
.endif
.ifdef TEST_GENERAL_PROTECTION
	movw $0xfff8, %ax
	movw %ax, %ds
.endif
.ifdef TEST_PAGE_FAULT
	movabsq $0x0000400000000000, %rax
	movq (%rax), %rax
.endif
.ifdef TEST_DOUBLE_FAULT
	xorq %rsp, %rsp
	movw $0xfff8, %ax
	movw %ax, %ds
.endif
.ifdef TEST_WRITE_CODE
	leaq kernel_entry(%rip), %rax
	movb $0x90, (%rax)
.endif
.ifdef TEST_WRITE_RODATA
	leaq kernel_message(%rip), %rax
	movb $0, (%rax)
.endif
.ifdef TEST_EXECUTE_DATA
	leaq nx_probe(%rip), %rax
	call *%rax
.endif
.ifdef TEST_STACK_GUARD
	leaq kernel_stack_guard(%rip), %rax
	movq (%rax), %rcx
.endif
	jmp .Lhalt
.Lbad_paging:
	leaq paging_failure(%rip), %r8
	call serial_write
	jmp .Lhalt
.Lbad_frames:
	leaq frame_failure(%rip), %r8
	call serial_write
	jmp .Lhalt
.Lbad_info:
	leaq kernel_failure(%rip), %r8
	call serial_write
.Lhalt:
	cli
	hlt
	jmp .Lhalt
.size kernel_entry, . - kernel_entry
.section .rdata, "a", @progbits
kernel_message:
	.asciz "Algebra kernel 0001: boot services exited\r\n"
kernel_failure:
	.asciz "Algebra kernel 0001: invalid boot information\r\n"
processor_message:
	.asciz "Algebra machine 0001: descriptor tables installed\r\n"
paging_message:
	.asciz "Algebra memory 0001: own page tables active\r\n"
paging_failure:
	.asciz "Algebra memory 0001: paging configuration unsupported\r\n"
frame_message:
	.asciz "Algebra frames 0001: inventory ready\r\n"
frame_failure:
	.asciz "Algebra frames 0001: inventory invalid\r\n"
.section .data, "aw", @progbits
.ifdef TEST_EXECUTE_DATA
nx_probe:
	.byte 0xc3                  /* A return instruction on a non-executable page. */
.endif
.p2align 3
frame_config:
	.fill 48, 1, 0
frame_summary:
	.ascii "Algebra frames 0001: extents="
frame_extents:
	.fill 16, 1, '0'
	.ascii " free="
frame_count:
	.fill 16, 1, '0'
	.asciz "\r\n"
.p2align 12
frame_catalog:
	.fill 81920, 1, 0
.section .note.GNU-stack, "", @progbits
