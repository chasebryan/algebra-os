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
.section .note.GNU-stack, "", @progbits
