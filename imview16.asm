.386
ASSUME CS:code, DS:data, SS:stack

stack segment STACK
  db 256 dup (0)
stack ends

data SEGMENT para PUBLIC
	err_msg db "Blad otwierania pliku: ","$"
	prompt db "Podaj nazwe pliku: ", "$"
	filename_buf_size db 127
	filename_buf_read db 0
	filename db 128 dup (?)  ; 127 - maksymalna liczba znakow do bufora, 0 - minimalna liczba znakow do bufora
	filehandle dw ?
	colour_number dw 16
	rgb db 3 dup (0)
	pixels db 320*200 dup (?)
	frames dd ?
data ENDS

code SEGMENT USE16 PARA PUBLIC 'CODE'

load_palette PROC
	push ax
	push bx
	push cx
	push dx
	push si
	
	mov cx, word ptr colour_number
	xor si, si
	
	et:
	push cx ; zapisanie licznika petli
	
	;wczytanie wartosci rgb z pliku
	mov ah, 3fh
	mov bx, filehandle
	mov cx, 3
	mov dx, offset rgb
	int 21h	
	
	;nadpisanie wartosci w palecie barw
	mov ax, 1010h
	mov bx, si
	mov dh, rgb
	mov ch, rgb[1]
	mov cl, rgb[2]
	int 10h
	inc si
	
	
	pop cx ; przywrocenie licznika petli
	loop et
	
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret
load_palette ENDP

show_image PROC
	push ax
	push bx
	push cx
	push dx
	push si
	
	mov bx, 0A000H ; adres pamięci ekranu dla trybu 13H
	mov es, bx
	
	mov ah, 3fh
	mov bx, filehandle
	mov cx, 320*200
	mov dx, offset pixels
	int 21h
	
	xor si, si
	mov cx, 320*200
	et1:
		mov dl, pixels[si]
		mov es:[si], dl
		inc si
	loop et1
	
	
	pop si
	pop dx
	pop cx
	pop bx
	pop ax
	ret
show_image ENDP

input_filename PROC
push ax
push dx
push di
	;wypisanie "Podaj nazwe pliku: "
	mov dx, offset prompt
	mov ah, 09h
	int 21h

	;wczytanie nazwy pliku z inputu
	mov ah, 0ah
	mov dx, offset filename_buf_size
	int 21h
	
	;ustawienie znaku koncowego "$" na koncu sciezki do pliku
	movzx di, byte ptr filename_buf_read
	mov dl, "$"
	mov filename[di], dl
pop di
pop dx
pop ax
ret
input_filename ENDP

start:
	mov ax, data
	mov ds, ax
	
	call input_filename
	
	; wczytanie pliku
	mov dx, offset filename
	xor cx, cx
	mov ah, 3dh
	mov al, 00h
	int 21h
	jc blad ; skok na koniec jesli wystapil blad wczytywania pliku
	
	mov filehandle, ax
	
	mov ah, 3fh
	mov bx, filehandle
	mov cx, 4
	mov dx, offset frames
	int 21h	
	
	mov ah, 0
	mov al, 13H ; nr trybu
	int 10H
	mov cx, word ptr frames
	video:
		call load_palette
		call show_image
		;push cx
		; waiting for 1/12 of sec
		;mov CX, 01H
		;mov DX, 4585H
		;mov AH, 86H
		;int 15H
		;pop cx ; for some reason this doesn't work now :(
		mov ah, 1 ; sprawdzenie czy jest jakiś znak
		int 16h ; w buforze klawiatury
		jnz czekaj
	loop video
	czekaj:
		mov ah, 1 ; sprawdzenie czy jest jakiś znak
		int 16h ; w buforze klawiatury
		jz czekaj
	
	
	
	jmp koniec
	blad:
	;wypisanie tekstu "Blad otwierania pliku: "
	push ax
	mov dx, offset err_msg
	mov ah, 09h
	int 21h
	
	;wypisanie kodu bledu
	pop ax
	mov dx, ax
	add dx, '0'
	mov ah, 02h
	int 21h
	
	czekaj_blad:
		mov ah, 1 ; sprawdzenie czy jest jakiś znak
		int 16h ; w buforze klawiatury
		jz czekaj_blad
	
	koniec:
	mov ah, 0 ; funkcja nr 0 ustawia tryb sterownika
	mov al, 3H ; nr trybu
	int 10H
	
	;zakonczenie programu
	mov ah, 4ch
	int 21h
code ENDS
END start