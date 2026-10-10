/* COM1 reference-profile diagnostics. No firmware calls or nonvolatile clobbers. */
.section .text, "ax", @progbits
.code64
.global serial_init
.type serial_init, @function
serial_init:
	movw $0x3f9, %dx
	xorb %al, %al
	outb %al, %dx
	movw $0x3fb, %dx
	movb $0x80, %al
	outb %al, %dx
	movw $0x3f8, %dx
	movb $1, %al
	outb %al, %dx
	movw $0x3f9, %dx
	xorb %al, %al
	outb %al, %dx
	movw $0x3fb, %dx
	movb $3, %al
	outb %al, %dx
	movw $0x3fa, %dx
	movb $7, %al
	outb %al, %dx
	movw $0x3fc, %dx
	movb $3, %al
	outb %al, %dx
	ret
.size serial_init, . - serial_init

/* R8=terminated ASCII message. Clobbers RAX,RDX,R8,R9,R10.
 * Every character has at most 65536 transmitter-ready polls.
 */
.global serial_write
.type serial_write, @function
serial_write:
.Lnext:
	movb (%r8), %r10b
	testb %r10b, %r10b
	jz .Ldone
	movl $65536, %r9d
	movw $0x3fd, %dx
.Lwait:
	inb %dx, %al
	testb $0x20, %al
	jnz .Lsend
	decl %r9d
	jnz .Lwait
	jmp .Ldone
.Lsend:
	movw $0x3f8, %dx
	movb %r10b, %al
	outb %al, %dx
	incq %r8
	jmp .Lnext
.Ldone:
	ret
.size serial_write, . - serial_write
.section .note.GNU-stack, "", @progbits
