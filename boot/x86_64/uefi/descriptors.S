/* Pure descriptor construction, shared by the kernel and host tests.
 * build_idt: RDI=4096-byte table, RSI=256 signed handler offsets,
 * RDX=handler base. Clobbers RAX,RCX,R8-R11. All gates are ring-0 interrupts.
 */
.section .text, "ax", @progbits
.code64
.global build_idt
.type build_idt, @function
build_idt:
	xorl %ecx, %ecx
	movq %rdi, %r8
.Lgate:
	movslq (%rsi,%rcx,4), %rax
	addq %rdx, %rax
	movw %ax, (%r8)
	movw $8, 2(%r8)
	movw $0x8e00, 4(%r8)
	cmpl $8, %ecx
	jne .Lnot_df
	movb $1, 4(%r8)
.Lnot_df:
	cmpl $2, %ecx
	jne .Lnot_nmi
	movb $2, 4(%r8)
.Lnot_nmi:
	cmpl $18, %ecx
	jne .Lnot_mc
	movb $3, 4(%r8)
.Lnot_mc:
	shrq $16, %rax
	movw %ax, 6(%r8)
	shrq $16, %rax
	movl %eax, 8(%r8)
	movl $0, 12(%r8)
	addq $16, %r8
	incl %ecx
	cmpl $256, %ecx
	jb .Lgate
	ret
.size build_idt, . - build_idt

/* RDI=16-byte descriptor, RSI=104-byte TSS base. Clobbers RAX. */
.global build_tss_descriptor
.type build_tss_descriptor, @function
build_tss_descriptor:
	movw $103, (%rdi)
	movq %rsi, %rax
	movw %ax, 2(%rdi)
	shrq $16, %rax
	movb %al, 4(%rdi)
	movb $0x89, 5(%rdi)
	movb $0, 6(%rdi)
	shrq $8, %rax
	movb %al, 7(%rdi)
	shrq $8, %rax
	movl %eax, 8(%rdi)
	movl $0, 12(%rdi)
	ret
.size build_tss_descriptor, . - build_tss_descriptor

/* RDI=16-byte destination, RSI=value. Clobbers RAX,RCX,RDX,RSI.
 * Emits exactly 16 lowercase hexadecimal characters, without a terminator.
 */
.global encode_hex64
.type encode_hex64, @function
encode_hex64:
	xorl %ecx, %ecx
.Lhex:
	rolq $4, %rsi
	movq %rsi, %rax
	andl $15, %eax
	leal 48(%rax), %edx
	cmpl $9, %eax
	jbe .Ldigit
	addl $39, %edx
.Ldigit:
	movb %dl, (%rdi,%rcx)
	incl %ecx
	cmpl $16, %ecx
	jb .Lhex
	ret
.size encode_hex64, . - encode_hex64
.section .note.GNU-stack, "", @progbits
