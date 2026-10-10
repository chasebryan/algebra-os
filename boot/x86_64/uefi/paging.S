/* RDI=validated boot information. Returns EAX=0 after CR3 replacement,
 * or EAX=1 while firmware translation remains active on unsupported input.
 */
.section .text, "ax", @progbits
.code64
.global install_kernel_paging
.type install_kernel_paging, @function
install_kernel_paging:
	pushq %rbx
	pushq %r12
	subq $8, %rsp
	movq %rdi, %r12
	movl $0x80000000, %eax
	cpuid
	cmpl $0x80000001, %eax
	jb .Lunsupported
	movl $0x80000001, %eax
	cpuid
	testl $0x100000, %edx        /* Execute-disable support is mandatory. */
	jz .Lunsupported
	movq %cr4, %rax
	testq $0x1000, %rax         /* This bootstrap uses four-level paging. */
	jnz .Lunsupported
	leaq kernel_page_tables(%rip), %rax
	movq %rax, paging_config(%rip)
	movq 64(%r12), %rax
	movq %rax, paging_config+8(%rip)
	movq 72(%r12), %rax
	movq %rax, paging_config+16(%rip)
	leaq __text_start(%rip), %rax
	movq %rax, paging_config+24(%rip)
	leaq __text_end(%rip), %rax
	movq %rax, paging_config+32(%rip)
	leaq __data_start(%rip), %rax
	movq %rax, paging_config+40(%rip)
	leaq __data_end(%rip), %rax
	movq %rax, paging_config+48(%rip)
	leaq kernel_stack_guard(%rip), %rax
	movq %rax, paging_config+56(%rip)
	leaq df_stack_guard(%rip), %rax
	movq %rax, paging_config+64(%rip)
	leaq nmi_stack_guard(%rip), %rax
	movq %rax, paging_config+72(%rip)
	leaq mc_stack_guard(%rip), %rax
	movq %rax, paging_config+80(%rip)
	leaq kernel_page_tables(%rip), %rdi
	leaq paging_config(%rip), %rsi
	call build_kernel_page_tables
	testl %eax, %eax
	jnz .Lunsupported
	movl $0xc0000080, %ecx
	rdmsr
	orl $0x800, %eax            /* IA32_EFER.NXE. */
	wrmsr
	movq %cr4, %rax
	andq $-131201, %rax         /* Clear PGE and PCIDE; flush firmware globals. */
	movq %rax, %cr4
	movq %cr0, %rax
	orq $0x10000, %rax          /* Supervisor writes obey read-only PTEs. */
	movq %rax, %cr0
	leaq kernel_page_tables(%rip), %rax
	movq %rax, %cr3
	xorl %eax, %eax
	jmp .Ldone
.Lunsupported:
	movl $1, %eax
.Ldone:
	addq $8, %rsp
	popq %r12
	popq %rbx
	ret
.size install_kernel_paging, . - install_kernel_paging
.section .data, "aw", @progbits
.p2align 3
paging_config:
	.fill 88, 1, 0
.p2align 12
kernel_page_tables:
	.fill 32768, 1, 0
.section .note.GNU-stack, "", @progbits
