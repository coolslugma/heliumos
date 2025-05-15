	BITS 16

protected_prep:
	jmp nmi_enable
	jmp get_a20_state
	jmp enable_a20
	jmp setGdt

[BITS 32]
protected_init:
	jmp protected_prep
	cli
	lgdt [gdtr]
	mov eax, cr0
	or al, 1
	mov cr0, eax
	call 08h:os_main.setup_stack

[BITS 16]
nmi_enable:
	mov dx, 0x70
	in al, dx
	and al, 0x7F
	out dx, al
	mov dx, 0x71
	in al, dx
	ret

nmi_disable:
	mov dx, 0x70
	in al, dx
	or al, 0x80
	out dx, al
	mov dx, 0x71
	in al, dx
	ret

get_a20_state:
	pushf
	push si
	push di
	push ds
	push es
	cli

	mov ax, 0x0000					;	0x0000:0x0500(0x00000500) -> ds:si
	mov ds, ax
	mov si, 0x0500

	not ax							;	0xffff:0x0510(0x00100500) -> es:di
	mov es, ax
	mov di, 0x0510

	mov al, [ds:si]					;	save old values
	mov byte [.BufferBelowMB], al
	mov al, [es:di]
	mov byte [.BufferOverMB], al

	mov ah, 1						;	check byte [0x00100500] == byte [0x0500]
	mov byte [ds:si], 0
	mov byte [es:di], 1
	mov al, [ds:si]
	cmp al, [es:di]
	jne .exit
	dec ah
.exit:
	mov al, [.BufferBelowMB]
	mov [ds:si], al
	mov al, [.BufferOverMB]
	mov [es:di], al
	shr ax, 8
	sti
	pop es
	pop ds
	pop di
	pop si
	popf
	ret
	
	.BufferBelowMB:	db 0
	.BufferOverMB	db 0

;	out:
;		ax - a20 support bits (bit #0 - supported on keyboard controller; bit #1 - supported with bit #1 of port 0x92)
;		cf - set on error
query_a20_support:
	push bx
	clc

	mov ax, 0x2403
	int 0x15
	jc .error

	test ah, ah
	jnz .error

	mov ax, bx
	pop bx
	ret
.error:
	stc
	pop bx
	ret

[BITS 32]
enable_a20_keyboard_controller:
	cli

	call .wait_io1
	mov al, 0xad
	out 0x64, al
	
	call .wait_io1
	mov al, 0xd0
	out 0x64, al
	
	call .wait_io2
	in al, 0x60
	push eax
	
	call .wait_io1
	mov al, 0xd1
	out 0x64, al
	
	call .wait_io1
	pop eax
	or al, 2
	out 0x60, al
	
	call .wait_io1
	mov al, 0xae
	out 0x64, al
	
	call .wait_io1
	sti
	ret
.wait_io1:
	in al, 0x64
	test al, 2
	jnz .wait_io1
	ret
.wait_io2:
	in al, 0x64
	test al, 1
	jz .wait_io2
	ret

;	out:
;		cf - set on error
enable_a20:
	clc									;	clear cf
	pusha
	mov bh, 0							;	clear bh

	call get_a20_state
	jc .fast_gate

	test ax, ax
	jnz .done

	call query_a20_support
	mov bl, al
	test bl, 1							;	enable A20 using keyboard controller
	jnz .keybord_controller

	test bl, 2							;	enable A20 using fast A20 gate
	jnz .fast_gate
.bios_int:
	mov ax, 0x2401
	int 0x15
	jc .fast_gate
	test ah, ah
	jnz .failed
	call get_a20_state
	test ax, ax
	jnz .done
.fast_gate:
	in al, 0x92
	test al, 2
	jnz .done

	or al, 2
	and al, 0xfe
	out 0x92, al

	call get_a20_state
	test ax, ax
	jnz .done

	test bh, bh							;	test if there was an attempt using the keyboard controller
	jnz .failed
.keybord_controller:
	call enable_a20_keyboard_controller
	call get_a20_state
	test ax, ax
	jnz .done

	mov bh, 1							;	flag enable attempt with keyboard controller

	test bl, 2
	jnz .fast_gate
	jmp .failed
.failed:
	stc
.done:
	popa
	ret

gdtr DW 0 ; For limit storage
     DD 0 ; For base storage

setGdt:
   MOV   AX, [esp + 4]
   MOV   [gdtr], AX
   MOV   EAX, [ESP + 8]
   MOV   [gdtr + 2], EAX
   LGDT  [gdtr]
   RET