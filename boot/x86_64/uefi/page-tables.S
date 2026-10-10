/* Pure bootstrap page-table construction.
 * RDI=32768-byte output; RSI=88-byte configuration:
 * table physical base, image base/bytes, text start/end, data start/end,
 * four guard-page addresses (all fields UINT64).
 * Returns EAX=0 on success or 1 before writing on invalid configuration.
 * Callee-saved registers are preserved. Output must not alias configuration.
 */
.section .text, "ax", @progbits
.code64
.global build_kernel_page_tables
.type build_kernel_page_tables, @function
build_kernel_page_tables:
	pushq %rbx
	pushq %rbp
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	testq %rdi, %rdi
	jz .Lbad
	testq %rsi, %rsi
	jz .Lbad
	movq %rdi, %r12
	movq %rsi, %rbx
	movq %rdi, %rax
	addq $32768, %rax
	jc .Lbad
	movq %rsi, %rdx
	addq $88, %rdx
	jc .Lbad
	cmpq %rdx, %rdi
	jae .Lno_alias
	cmpq %rax, %rsi
	jb .Lbad
.Lno_alias:
	movq 0(%rbx), %r13
	movq 8(%rbx), %r14
	movq 16(%rbx), %r15
	testq %r15, %r15
	jz .Lbad
	cmpq $1048576, %r15
	ja .Lbad
	cmpq $4096, %r14
	jb .Lbad
	movq %r13, %rax
	orq %r14, %rax
	orq %r15, %rax
	testq $4095, %rax
	jnz .Lbad
	addq %r14, %r15
	jc .Lbad
	movabsq $0x100000000, %rax
	cmpq %rax, %r15
	ja .Lbad
	movq 24(%rbx), %rax
	movq 32(%rbx), %rdx
	movq 40(%rbx), %r8
	movq 48(%rbx), %r9
	cmpq %r14, %rax
	jb .Lbad
	cmpq %rax, %rdx
	jbe .Lbad
	cmpq %rdx, %r8
	jb .Lbad
	cmpq %r8, %r9
	jbe .Lbad
	cmpq %r15, %r9
	ja .Lbad
	orq %rdx, %rax
	orq %r8, %rax
	orq %r9, %rax
	testq $4095, %rax
	jnz .Lbad
	cmpq %r8, %r13
	jb .Lbad
	movq %r13, %r10
	addq $32768, %r10
	jc .Lbad
	cmpq %r9, %r10
	ja .Lbad
	xorl %ecx, %ecx
.Lcheck_guard:
	movq 56(%rbx,%rcx,8), %rax
	testq $4095, %rax
	jnz .Lbad
	cmpq %r8, %rax
	jb .Lbad
	cmpq %r9, %rax
	jae .Lbad
	cmpq %r13, %rax
	jb .Lguard_not_table
	cmpq %r10, %rax
	jb .Lbad
.Lguard_not_table:
	xorl %edx, %edx
.Lunique_guard:
	cmpl %ecx, %edx
	jae .Lguard_next
	cmpq 56(%rbx,%rdx,8), %rax
	je .Lbad
	incl %edx
	jmp .Lunique_guard
.Lguard_next:
	incl %ecx
	cmpl $4, %ecx
	jb .Lcheck_guard

	cld
	movq %r12, %rdi
	xorl %eax, %eax
	movl $4096, %ecx
	rep stosq
	leaq 4096(%r13), %rax
	orq $3, %rax
	movq %rax, (%r12)
	xorl %ecx, %ecx
.Lpdpt:
	movq %rcx, %rax
	shlq $12, %rax
	leaq 8192(%r13,%rax), %rax
	orq $3, %rax
	movq %rax, 4096(%r12,%rcx,8)
	incl %ecx
	cmpl $4, %ecx
	jb .Lpdpt
	movq %r14, %rbp
.Lpage:
	movq %rbp, %r11
	shrq $21, %r11
	movq %r14, %rdx
	shrq $21, %rdx
	subq %rdx, %r11
	shlq $12, %r11              /* PT index: at most two 2 MiB regions. */
	leaq 24576(%r13,%r11), %rcx
	orq $3, %rcx
	movq %rbp, %rax
	shrq $30, %rax
	shlq $12, %rax
	leaq 8192(%r12,%rax), %rdx
	movq %rbp, %rax
	shrq $21, %rax
	andl $511, %eax
	movq %rcx, (%rdx,%rax,8)
	leaq 24576(%r12,%r11), %r11
	movabsq $0x8000000000000001, %rdx
	cmpq 24(%rbx), %rbp
	jb .Lnot_code
	cmpq 32(%rbx), %rbp
	jae .Lnot_code
	movl $1, %edx               /* Executable, read-only, supervisor. */
.Lnot_code:
	cmpq %r8, %rbp
	jb .Lnot_data
	cmpq %r9, %rbp
	jae .Lnot_data
	movabsq $0x8000000000000003, %rdx
.Lnot_data:
	xorl %ecx, %ecx
.Lguard:
	cmpq 56(%rbx,%rcx,8), %rbp
	je .Lunmapped
	incl %ecx
	cmpl $4, %ecx
	jb .Lguard
	orq %rbp, %rdx
	jmp .Lpte
.Lunmapped:
	xorl %edx, %edx
.Lpte:
	movq %rbp, %rax
	shrq $12, %rax
	andl $511, %eax
	movq %rdx, (%r11,%rax,8)
	addq $4096, %rbp
	cmpq %r15, %rbp
	jb .Lpage
	xorl %eax, %eax
	jmp .Ldone
.Lbad:
	movl $1, %eax
.Ldone:
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbp
	popq %rbx
	ret
.size build_kernel_page_tables, . - build_kernel_page_tables
.section .note.GNU-stack, "", @progbits
