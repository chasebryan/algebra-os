/* Internal ABI: RDI=map, RSI=bytes, RDX=stride, ECX=version.
 * Returns EAX=0 for valid shape/ranges, EAX=1 otherwise.
 * Clobbers only RAX, RCX, RDX, R8-R11. Uses no firmware services.
 */
.section .text, "ax", @progbits
.code64
.global validate_memory_map
.type validate_memory_map, @function
validate_memory_map:
	cmpl $1, %ecx
	jne .Linvalid
	testq %rdi, %rdi
	jz .Linvalid
	testq %rsi, %rsi
	jz .Linvalid
	cmpq $65536, %rsi
	ja .Linvalid
	cmpq $40, %rdx
	jb .Linvalid
	testq $7, %rdx
	jnz .Linvalid
	movq %rdi, %r8
	addq %rsi, %r8
	jc .Linvalid
	movq %rdx, %r9
	movq %rsi, %rax
	xorl %edx, %edx
	divq %r9
	testq %rdx, %rdx
	jnz .Linvalid
	movq %rdi, %r10
.Ldescriptor:
	movq 24(%r10), %rax          /* NumberOfPages must be nonzero. */
	testq %rax, %rax
	jz .Linvalid
	decq %rax                    /* Validate the last page's start address. */
	movq %rax, %r11
	shrq $52, %r11
	jnz .Linvalid
	shlq $12, %rax
	movq 8(%r10), %rcx          /* PhysicalStart. */
	testq $4095, %rcx
	jnz .Linvalid
	addq %rax, %rcx
	jc .Linvalid
	movq 16(%r10), %rcx         /* VirtualStart. */
	testq $4095, %rcx
	jnz .Linvalid
	addq %rax, %rcx
	jc .Linvalid
	addq %r9, %r10
	cmpq %r8, %r10
	jb .Ldescriptor
	xorl %eax, %eax
	ret
.Linvalid:
	movl $1, %eax
	ret
.size validate_memory_map, . - validate_memory_map
.section .note.GNU-stack, "", @progbits
