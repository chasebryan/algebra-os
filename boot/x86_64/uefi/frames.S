/* Bounded physical-frame catalog, constructed from a validated firmware map.
 * RDI=output, RSI=config(map pointer/bytes/stride/version/image base/bytes),
 * RDX=output capacity (at least 81920). Returns EAX=0/1 success/failure.
 * Preserves callee-saved registers. Caller-owned pointers must be valid.
 * Header (64 bytes): magic, version/size, descriptors, free extents,
 * free frames, described frames, reserved image first/end PFNs.
 * Sorted work records at 64: PFN/pages/type/attributes (32 bytes each).
 * Free extents at 52480: first PFN/page count (16 bytes each).
 */
.section .text, "ax", @progbits
.code64
.global build_frame_catalog
.type build_frame_catalog, @function
build_frame_catalog:
	pushq %rbx
	pushq %rbp
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	subq $8, %rsp
	testq %rdi, %rdi
	jz .Lbad
	testq %rsi, %rsi
	jz .Lbad
	cmpq $81920, %rdx
	jb .Lbad
	movq %rdi, %r12
	movq %rsi, %r13
	movq %rdi, %r8
	addq $81920, %r8
	jc .Lbad
	movq %rsi, %r9
	addq $48, %r9
	jc .Lbad
	cmpq %r9, %rdi
	jae .Lconfig_clear
	cmpq %r8, %rsi
	jb .Lbad
.Lconfig_clear:
	movq (%r13), %rax
	movq %rax, %r9
	addq 8(%r13), %r9
	jc .Lbad
	cmpq %r9, %r12
	jae .Lmap_clear
	cmpq %r8, %rax
	jb .Lbad
.Lmap_clear:
	cld
	xorl %eax, %eax
	movl $10240, %ecx
	rep stosq
	movq 32(%r13), %rbx
	movq 40(%r13), %rbp
	movq %rbx, %rax
	orq %rbp, %rax
	testq $4095, %rax
	jnz .Lbad
	testq %rbp, %rbp
	jz .Lbad
	shrq $12, %rbx
	shrq $12, %rbp
	addq %rbx, %rbp
	movabsq $0x10000000000000, %rax
	cmpq %rax, %rbp
	ja .Lbad
	movq %rbx, 48(%r12)
	movq %rbp, 56(%r12)
	movq (%r13), %rdi
	movq 8(%r13), %rsi
	movq 16(%r13), %rdx
	movq 24(%r13), %rcx
	cmpq $1, %rcx
	jne .Lbad
	call validate_memory_map
	testl %eax, %eax
	jnz .Lbad
	movq 16(%r13), %r15
	movq 8(%r13), %rax
	xorl %edx, %edx
	divq %r15
	movq %rax, %r14
	cmpq $1638, %r14
	ja .Lbad
	movq %r14, 16(%r12)
	movq (%r13), %rsi
	leaq 64(%r12), %rdi
	xorl %ecx, %ecx
.Lnormalize:
	movq 8(%rsi), %rax
	shrq $12, %rax
	movq %rax, (%rdi)
	movq 24(%rsi), %rax
	movq %rax, 8(%rdi)
	movl (%rsi), %eax
	movq %rax, 16(%rdi)
	movq 32(%rsi), %rax
	movq %rax, 24(%rdi)
	addq %r15, %rsi
	addq $32, %rdi
	incq %rcx
	cmpq %r14, %rcx
	jb .Lnormalize

	/* Insertion sort: at most 1638 records, no dynamic allocation. */
	movl $1, %ecx
	leaq 64(%r12), %rdi
.Lsort:
	cmpq %r14, %rcx
	jae .Lsorted
	movq %rcx, %rax
	shlq $5, %rax
	leaq (%rdi,%rax), %rsi
	movq (%rsi), %r8
	movq 8(%rsi), %r9
	movq 16(%rsi), %r10
	movq 24(%rsi), %r11
.Lsearch:
	cmpq %rdi, %rsi
	je .Lplace
	leaq -32(%rsi), %rdx
	cmpq %r8, (%rdx)
	jbe .Lplace
	movq (%rdx), %rax
	movq %rax, (%rsi)
	movq 8(%rdx), %rax
	movq %rax, 8(%rsi)
	movq 16(%rdx), %rax
	movq %rax, 16(%rsi)
	movq 24(%rdx), %rax
	movq %rax, 24(%rsi)
	movq %rdx, %rsi
	jmp .Lsearch
.Lplace:
	movq %r8, (%rsi)
	movq %r9, 8(%rsi)
	movq %r10, 16(%rsi)
	movq %r11, 24(%rsi)
	incq %rcx
	jmp .Lsort
.Lsorted:
	xorl %ecx, %ecx
	xorl %edx, %edx
	leaq 64(%r12), %r15
.Loverlap:
	movq (%r15), %rax
	cmpq %rdx, %rax
	jb .Lbad
	movq 8(%r15), %r9
	addq %r9, %rax
	movq %rax, %rdx
	addq %r9, 40(%r12)
	addq $32, %r15
	incq %rcx
	cmpq %r14, %rcx
	jb .Loverlap
	xorl %ecx, %ecx
	leaq 64(%r12), %r15
.Lfree_range:
	movq 24(%r15), %rax
	testq %rax, %rax
	js .Lnext                    /* Runtime-owned memory remains reserved. */
	movq 16(%r15), %rax
	cmpq $3, %rax
	je .Leligible
	cmpq $4, %rax
	je .Leligible
	cmpq $7, %rax
	jne .Lnext
.Leligible:
	movq (%r15), %r8
	movq 8(%r15), %r9
	leaq (%r8,%r9), %r10
	cmpq %rbx, %r10
	jbe .Lwhole
	cmpq %rbp, %r8
	jae .Lwhole
	cmpq %rbx, %r8
	jae .Lright
	movq %rbx, %r9
	subq %r8, %r9
	call .Lappend
.Lright:
	cmpq %rbp, %r10
	jbe .Lnext
	movq %rbp, %r8
	movq %r10, %r9
	subq %r8, %r9
	call .Lappend
	jmp .Lnext
.Lwhole:
	call .Lappend
.Lnext:
	addq $32, %r15
	incq %rcx
	cmpq %r14, %rcx
	jb .Lfree_range
	movl $1, 8(%r12)
	movl $81920, 12(%r12)
	movabsq $0x00314d5246474c41, %rax /* "ALGFRM1\0": publish only on success. */
	movq %rax, (%r12)
	xorl %eax, %eax
	jmp .Ldone
.Lbad:
	movl $1, %eax
.Ldone:
	addq $8, %rsp
	popq %r15
	popq %r14
	popq %r13
	popq %r12
	popq %rbp
	popq %rbx
	ret

/* At most one extra extent can arise from cutting the reserved image.
 * Input R8=first PFN, R9=pages; clobbers RAX,RDX only.
 */
.Lappend:
	movq 24(%r12), %rax
	movq %rax, %rdx
	shlq $4, %rdx
	leaq 52480(%r12,%rdx), %rdx
	movq %r8, (%rdx)
	movq %r9, 8(%rdx)
	incq %rax
	movq %rax, 24(%r12)
	addq %r9, 32(%r12)
	ret
.size build_frame_catalog, . - build_frame_catalog
.section .note.GNU-stack, "", @progbits
