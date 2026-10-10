/* Algebra's ring-0 GDT, TSS, IDT, and terminal exception diagnostics.
 * install_processor_tables clobbers volatile registers, including RDI/RSI.
 * Maskable interrupts must already be disabled; firmware paging persists.
 */
.section .text, "ax", @progbits
.code64
.global install_processor_tables
.type install_processor_tables, @function
install_processor_tables:
	subq $8, %rsp
	leaq kernel_stack_top(%rip), %rax
	movq %rax, tss+4(%rip)
	leaq df_stack_top(%rip), %rax
	movq %rax, tss+36(%rip)
	leaq nmi_stack_top(%rip), %rax
	movq %rax, tss+44(%rip)
	leaq mc_stack_top(%rip), %rax
	movq %rax, tss+52(%rip)
	movw $104, tss+102(%rip)
	leaq gdt+24(%rip), %rdi
	leaq tss(%rip), %rsi
	call build_tss_descriptor
	leaq idt(%rip), %rdi
	leaq exception_offsets(%rip), %rsi
	leaq exception_stubs(%rip), %rdx
	call build_idt
	leaq gdt(%rip), %rax
	movq %rax, gdtr+2(%rip)
	leaq idt(%rip), %rax
	movq %rax, idtr+2(%rip)
	lgdt gdtr(%rip)
	pushq $8
	leaq .Lnew_cs(%rip), %rax
	pushq %rax
	lretq
.Lnew_cs:
	movw $16, %ax
	movw %ax, %ds
	movw %ax, %es
	movw %ax, %ss
	xorw %ax, %ax
	movw %ax, %fs
	movw %ax, %gs
	movw $24, %ax
	ltr %ax
	lidt idtr(%rip)
	xorl %eax, %eax
	xorl %edx, %edx
	movl $0xc0000100, %ecx       /* Clear inherited FS/GS base state. */
	wrmsr
	incl %ecx
	wrmsr
	incl %ecx
	wrmsr
	addq $8, %rsp
	ret
.size install_processor_tables, . - install_processor_tables

/* Normalize CPU-pushed error codes before preserving all GPRs. */
.altmacro
.macro EXCEPTION number
.Lexception_\number:
.if (\number == 8) || (\number == 10) || (\number == 11) || (\number == 12) || (\number == 13) || (\number == 14) || (\number == 17) || (\number == 21) || (\number == 29) || (\number == 30)
.else
	pushq $0
.endif
	pushq $\number
	jmp exception_common
.endm
exception_stubs:
.set vector, 0
.rept 256
EXCEPTION %vector
.set vector, vector+1
.endr

exception_common:
	cld
	pushq %rax
	pushq %rcx
	pushq %rdx
	pushq %rbx
	pushq %rbp
	pushq %rsi
	pushq %rdi
	pushq %r8
	pushq %r9
	pushq %r10
	pushq %r11
	pushq %r12
	pushq %r13
	pushq %r14
	pushq %r15
	movq %rsp, %r12            /* Saved GPRs then vector/error/hardware frame. */
	andq $-16, %rsp
	leaq fault_vector(%rip), %rdi
	movq 120(%r12), %rsi
	call encode_hex64
	leaq fault_error(%rip), %rdi
	movq 128(%r12), %rsi
	call encode_hex64
	leaq fault_rip(%rip), %rdi
	movq 136(%r12), %rsi
	call encode_hex64
	leaq fault_cr2(%rip), %rdi
	movq %cr2, %rsi
	call encode_hex64
	leaq fault_line(%rip), %r8
	call serial_write
	xorl %r13d, %r13d
	leaq register_names(%rip), %r14
.Lregister:
	movw (%r14), %ax
	movw %ax, register_name(%rip)
	movb 2(%r14), %al
	movb %al, register_name+2(%rip)
	leaq register_value(%rip), %rdi
	movq (%r12,%r13,8), %rsi
	call encode_hex64
	leaq register_line(%rip), %r8
	call serial_write
	addq $3, %r14
	incl %r13d
	cmpl $15, %r13d
	jb .Lregister
	leaq fault_rsp(%rip), %rdi
	movq 160(%r12), %rsi
	call encode_hex64
	leaq fault_flags(%rip), %rdi
	movq 152(%r12), %rsi
	call encode_hex64
	leaq state_line(%rip), %r8
	call serial_write
	leaq fault_complete(%rip), %r8
	call serial_write
.Lfault_halt:
	cli
	hlt
	jmp .Lfault_halt

.section .rdata, "a", @progbits
.p2align 2
.macro OFFSET number
	.long .Lexception_\number - exception_stubs
.endm
exception_offsets:
.set vector, 0
.rept 256
OFFSET %vector
.set vector, vector+1
.endr
register_names:
	.ascii "r15", "r14", "r13", "r12", "r11", "r10", "r9 ", "r8 "
	.ascii "rdi", "rsi", "rbp", "rbx", "rdx", "rcx", "rax"
fault_complete:
	.asciz "Algebra fault 0001: diagnostics complete\r\n"

.section .data, "aw", @progbits
.p2align 4
gdt:
	.quad 0, 0x00af9b000000ffff, 0x00cf93000000ffff
	.fill 16, 1, 0
gdtr:
	.word 39
	.quad 0
idtr:
	.word 4095
	.quad 0
.p2align 4
tss:
	.fill 104, 1, 0
.p2align 4
idt:
	.fill 4096, 1, 0
fault_line:
	.ascii "Algebra fault 0001: vector="
fault_vector:
	.fill 16, 1, '0'
	.ascii " error="
fault_error:
	.fill 16, 1, '0'
	.ascii " rip="
fault_rip:
	.fill 16, 1, '0'
	.ascii " cr2="
fault_cr2:
	.fill 16, 1, '0'
	.asciz "\r\n"
register_line:
	.ascii "Algebra register 0001: "
register_name:
	.ascii "xxx="
register_value:
	.fill 16, 1, '0'
	.asciz "\r\n"
state_line:
	.ascii "Algebra state 0001: rsp="
fault_rsp:
	.fill 16, 1, '0'
	.ascii " rflags="
fault_flags:
	.fill 16, 1, '0'
	.asciz "\r\n"
.p2align 4
df_stack:
	.fill 16384, 1, 0
df_stack_top:
nmi_stack:
	.fill 16384, 1, 0
nmi_stack_top:
mc_stack:
	.fill 16384, 1, 0
mc_stack_top:
.section .note.GNU-stack, "", @progbits
