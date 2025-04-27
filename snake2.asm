; Program snake.asm
; Pętla gry w takt przerwań zegarowych
; Uruchomienie w trybie rzeczywistym procesora x86
; lub na maszynie wirtualnej
; zakończenie programu po naciśnięciu klawisza 'X'
; asemblacja (MASM 4.0): masm snake.asm,,,;
; konsolidacja (LINK 3.60): link snake.obj;

; rozdzielczość 320x200
; rozmiar planszy gry 40x25 - 1 komórka = 8x8 pikseli

.386
ASSUME CS:code, DS:data, SS:stack

stack segment STACK
  db 256 dup (0)
stack ends

data SEGMENT para PUBLIC
	pixel_color db 0Fh ; numer koloru obiektow
	background_color db 0 ; numer koloru tla
	
	pixel_size dw 8 ; rozmiar piksela 8x8
	x_max db 40 ; rozmiar planszy - x
	y_max db 25 ; rozmiar planszy - y
	
	snake_start_pos dw 0505h ; pozycja startowa weza
	
	direction db 00000000b ; kierunek w formacie 0,0,0,0,X+,X-,Y+,Y-
	snake_len dw 1 ; dlugosc weza
	snake_seg_pos dw 1000 dup (0) ; pozycje w formacie XXh YYh
	
	bonus_set db 0
	bonus_pos dw 0
	
	points_num db 0
	points_len db 0
	points db 3 dup (?)
	
	skip dw 0
	skip_num dw 1
	
	rand_seed dw ?
	wektor8 dd ?
data ENDS

code SEGMENT USE16 PARA PUBLIC 'CODE'

; ========================
;   Rysowanie na ekranie
; ========================
;wspolrzedne jako word XXYYh przakzaywane przez stos
;wartosc adresu zwracana w rejestrze bx
display_points PROC
	push ax
	push bx
	push cx
	push dx
	push di
	push es
	push bp
	
	mov ax, data
	mov es, ax
	
	mov ah, 13h
	mov al, 0
	
	mov bh, 0
	mov bl, 00001111b ; kolor pisanych znakow
	movzx cx, byte ptr points_len ; ilosc pisanych znakow
	
	mov dh, 1 ; y
	mov dl, 1 ; x
	
	mov bp, offset points
	
	int 10h
	
	pop bp
	pop es
	pop di
	pop dx
	pop cx
	pop bx
	pop ax
	ret
display_points ENDP

translate_xy PROC
	push bp
	mov bp, sp
	push ax
	push cx
	push dx
	push di
	
	; działania związane z zmienną rozmiaru piksela
	mov di, pixel_size ;di = rozmiar 1 piksela np. 2x2
	
	xor dx,dx
	mov ax, 320
	mul di ; pomnozenie szerokosci rozdzielczosci przez rozmiar 1 piksela
	       ; - tyle trzeba dodać aby uzyskać adres kolejnego wiersza
	mov cx, ax ;przeniesienie wyniku do cx, pozniej uzyty przy wspolrzednej y
	
	; działania związane z obliczanie adresu wspolrzednej x
	xor dx,dx
	mov ax, [bp+4]
	movzx ax, ah ; wspolrzedna x
	mul di ; pomnozenie wspolrzednej x przez rozmiar pixela
	mov bx, ax
	
	;działania związane z obliczanie adresu wspolrzednej y
	xor dx,dx
	mov ax, [bp+4]
	movzx ax, al ; wspolrzedna y
	mul cx  ;mnożenie wspolrzednej y przez 320 (lub więcej), aby uzyskac miejsce w pamieci danego wiersza
	
	add bx, ax ;dodanie adresu dla (0,y) do adresu (x,0) uzyskując adres dla (x,y)
	
	pop di
	pop dx
	pop cx
	pop ax
	pop bp
	ret
translate_xy ENDP

; adres piksela podany przez bx (wykonywana po funkcji translate_xy)
; rozmiar piksela pobierany ze zmiennej pixel_size
; kolor pobierany ze zmiennej pixel_color
draw PROC
	push bp
	mov bp, sp
	push di
	push dx
	push cx
	push bx
	push ax
	
	mov cx, 0A000H ; adres pamięci ekranu dla trybu 13H
	mov es, cx
	
	mov dx, pixel_size
	mov al, pixel_color
	
	;petla rysujaca pixel o rozmiarze (rozmiar_piksela x rozmiar_piksela)
	mov di, dx
	et_y:
		mov cx, dx
		et_x:
			mov es:[bx], al ; wpisanie kodu koloru do pamięci ekranu
			inc bx
		loop et_x
		sub bx, dx
		add bx, 320
		
		dec di
		test di,di
	jnz et_y
	
	pop ax
	pop bx
	pop cx
	pop dx
	pop di
	pop bp
	ret
draw ENDP

; funkcja do wyczyszczenia zawartosci planszy
; wpisuje na calym obszarze ekranu kolor tla ze zmiennej background_color
draw_background PROC
	push ax
	push bx
	push cx
	
	mov ax, 0A000H ; adres pamięci ekranu dla trybu 13H
	mov es, ax
	
	mov cx, 320*200
	mov bx, 0
	mov al, background_color
	
	;petla wpisujaca w pamiec ekranu kolor background_color
	blanking:
		mov es:[bx], al
		inc bx
	loop blanking
	
	pop cx
	pop bx
	pop ax
	ret
draw_background ENDP

draw_segments PROC
	push bx
	push cx
	push si
	
	mov cx, snake_len ;petla odczytuje snake_len segmentow
	xor si,si ; si = 0
	seg_draw_loop:
		push word ptr snake_seg_pos[si]
		call translate_xy ; uzyskanie adresu pamieci dla wspolrzednych x,y !MODYFIKUJE REJESTR bx!
		add sp, 2
		call draw ; rysowanie na danej pozycji
		
		add si, 2 ; przesuniecie o 2 bajty (= word) wskaznika na segment 
	loop seg_draw_loop
	
	pop si
	pop cx
	pop bx
	ret
draw_segments ENDP

; ===============
;   Sterowanie
; ===============
; scancode klawisza przekazywany w rejestrze ah
get_input PROC
	push ax
	push bx
	push es
	
	xor bx, bx
	; prawo
		cmp ah, 32 ; d
		jne left
		bt word ptr direction, 2 ; sprawdzenie czy waz nie porusza sie w przeciwnym kierunku
		jc end_input
		bts bx, 3 ; ustawienie bitu X+ na 1
		jmp save_direction
	
	; lewo 
	left:
		cmp ah, 30 ; a
		jne up
		bt word ptr direction, 3 ; sprawdzenie czy waz nie porusza sie w przeciwnym kierunku
		jc end_input
		bts bx, 2 ; ustawienie bitu X- na 1
		jmp save_direction
		
	; gora
	up:
		cmp ah, 17 ; w
		jne down
		bt word ptr direction, 1 ; sprawdzenie czy waz nie porusza sie w przeciwnym kierunku
		jc end_input
		bts bx, 0 ; ustawienie bitu Y- na 1
		jmp save_direction
		
	; dol
	down:
		cmp ah, 31 ; s
		jne add_seg
		bt word ptr direction, 0 ; sprawdzenie czy waz nie porusza sie w przeciwnym kierunku
		jc end_input
		bts bx, 1 ; ustawienie bitu Y+ na 1
		jmp save_direction
		
	add_seg: ; debug
		cmp ah, 16 ; q
		jne end_input
		mov bx, word ptr snake_len
		inc bx
		mov snake_len, bx
		inc byte ptr points_num
		jmp end_input
	
	save_direction:
		mov direction, bl
	end_input:
	pop es
	pop bx
	pop ax
	ret
get_input ENDP

; ===============
;   Logika gry
; ===============
; funkcja sprawdzajacy czy waz wyszedl poza obszar ekranu i korygujaca jego pozycje
; koordynaty przekazywane przez bx
; skorygowane wspolrzedne zapisywane w bx
check_border PROC
	; test czy y < 0
		cmp bl, 0FFh
		jne test_y_h
			mov bl, y_max
			dec bl
			jmp test_x_0
	; test czy y > wysokosci ekranu
	test_y_h:
		cmp bl, y_max
		jb test_x_0
			mov bl, 0
	; test czy x < 0
	test_x_0:
		cmp bh, 0FFh
		jne test_x_w
			mov bh, x_max
			dec bh
			jmp zapis_pozycji
	; test czy x > szerokosci ekranu
	test_x_w:
		cmp bh, x_max
		jb zapis_pozycji
			mov bh, 0
	
	zapis_pozycji:
		ret
check_border ENDP

; sprawdzanie kolizji weza z samym soba (= koniec gry) oraz
; kolizcji weza z bonusem (= zwiekszenie dlugosci weza)
check_collision PROC
	push ax
	push cx
	push si
	
	; sprawdzenie czy waz zebral bonus
	mov ax, snake_seg_pos ;pozycja 1 segmentu
	cmp ax, bonus_pos ;pozycja bonusu
	jne seg_collision
		mov bonus_set, byte ptr 0
		inc byte ptr points_num
		inc word ptr snake_len
	
	seg_collision:
	mov cx, snake_len
	dec cx
	jcxz end_of_check ;skok na koniec jesli snake_len = 1
	mov si, 2 ; wpisanie do si indeksu 2 segmentu
	
	seg_collision_loop:
		mov ax, snake_seg_pos[si]
		cmp ax, word ptr snake_seg_pos ;sprawdzenie czy doszlo do kolizji weza z soba
		je collision_reset
		add si, 2
	loop seg_collision_loop
	jmp end_of_check
	
	;reset gry po kolizji weza z soba
	collision_reset:
		mov snake_len, 1
		mov ax, snake_start_pos
		mov snake_seg_pos, ax
		mov bx, ax
		mov direction, byte ptr 0
		mov bonus_set, byte ptr 0
		mov points_num, byte ptr 0
	
	end_of_check:
	pop si
	pop cx
	pop ax
	ret
check_collision ENDP

;aktualizowanie pozycji segmentow (od konca do drugiego segementu - kazdy segment otrzymuje pozycje następnego)
update_segments_pos PROC
	push ax
	push cx
	push si
	push di
	
	mov cx, snake_len
	dec cx ; wpisanie do cx dlugosci-1 poniewaz przenosimy pozycje z segmentu i-1 do i
	jcxz seg_loop_end ;dla snake_len = 1 nie wykonuje sie petla
	
	mov si, cx
	add si, si ; wpisanie do si indeksu ostatniego segmentu (adres = (snake_len-1)*2)
	
	mov di, si
	sub di, 2 ; wpisanie do di indeksu przedostatniego segmentu
	seg_update_loop:
		mov ax, snake_seg_pos[di]
		mov snake_seg_pos[si], ax
		sub di, 2
		sub si, 2
	loop seg_update_loop
	seg_loop_end:
	
	pop di
	pop si
	pop cx
	pop ax
	ret
update_segments_pos ENDP

;funkcja umieszczajaca bonus na planszy
;jesli jest ustawiony to odpowiada za jego narysowanie
;jesli nie jest ustawiony to wyznacza nowa losowa pozycje
put_bonus PROC
	push ax
	push bx
	push cx
	push dx
	push di
	
	mov bx, bonus_pos
	mov al, bonus_set
	cmp al, 0
	jne draw_bonus ;skok do rysowania bonusu jesli bonus jest ustawiony
	
	gen_coord:
		call rand ; umieszcza w ax losowa liczbe
		mov di, ax ; przechowanie losowej liczby w di
		
		xor dx,dx
		movzx cx, byte ptr x_max
		div cx
		mov bh, dl ; przepisanie rand%x_max do bh
		
		xor dx,dx
		mov ax, di ; wpisanie zapamietanej losowej liczby do ax
		movzx cx, byte ptr y_max
		div cx
		mov bl, dl ; przepisanie rand%y_max do bl
		
		mov cx, snake_len
		xor di, di
		check_for_col:
			cmp bx, snake_seg_pos[di]
			je gen_coord ; ponowne wygenerowanie pozycji, jesli kolizja z wezem
			add di, 2
		loop check_for_col
	
	;zapisanie pozycji bonusu do zmiennej bonus_pos i ustawienie bonus_set na 1
		mov bonus_pos, bx
		mov bonus_set, byte ptr 1
	
	; narysowanie bonusu na danej pozycji
	draw_bonus:
		push bx
		call translate_xy
		add sp, 2
		call draw
	
	pop di
	pop dx
	pop cx
	pop bx
	pop ax
	ret
put_bonus ENDP

; ======================
;   Funkcje pomocnicze
; ======================
;generuje losową liczbę i zwraca ją w rejestrze AX
rand PROC
	push dx
	
	mov ax, 25173 ; mnoznik LCG
	mul word ptr rand_seed
	add ax, 13849 ; wartosc inkrementacji LCG
	mov rand_seed, ax
	
	pop dx
	ret
rand ENDP

points_to_string PROC
	push ax
	push dx
	push cx
	push si
	
	xor si,si
	
	
	movzx ax, byte ptr points_num
	mov cx, 10
	divide:
		xor dx,dx
		div cx
		inc si
		push dx
		test ax,ax
	jnz divide
	
	mov cx, si
	mov points_len, cl
	xor si,si
	write_chars:
		pop ax
		add ax, '0'
		mov points[si], al
		inc si
	loop write_chars
	
	
	pop si
	pop cx
	pop dx
	pop ax
	ret
points_to_string ENDP

; ====================
;   Glowna petla gry
; ====================
snake_update PROC
	; przechowanie rejestrów
	push ax
	push bx
	push dx
	push es
	
	mov ax, skip
	cmp ax, skip_num ; porownanie czy pominieto wymagana ilosc klatek
	jne inc_skip
	xor ax,ax  ;       wyzerowanie licznika
	mov skip, ax ;     pominietych klatek
	
	; ruch wedlug kierunku w zmiennej direction
	mov bx, snake_seg_pos
	ruch:
		movzx dx, byte ptr direction
		
		bt dx, 3 ; kierunek X+
		adc bh, 0
		
		bt dx, 2 ; kierunek X-
		sbb bh, 0
		
		bt dx, 1 ; kierunek Y+
		adc bl, 0
		
		bt dx, 0 ; kierunek Y-
		sbb bl, 0
		
		jmp check
		
	check: ;problem z MASM 5.0 który robi tylko 2 przejscia??
		
		; sprawdzenie czy waz nie wyszedl poza obszar planszy
		; jesli tak, to stosowne poprawienie wspolrzednych
		call check_border ; nadpisuje pozycje w bx
		
		call check_collision ; sprawdzenie kolizji weza z soba, oraz kolizji z bonusem
		
		call update_segments_pos ; aktualizowanie pozycji segmentow
		
		mov snake_seg_pos, bx ; wpisanie do 1 segmentu (wiodącego) jego nowej pozycji
		
		; rysowanie
		call draw_background ; wyczyszczenie ekranu - wypelnienie kolorem tla
		call draw_segments ; narysowanie wszystkich segmentow weza
		call put_bonus ; narysowanie bonusa
		call points_to_string
		call display_points
		
		jmp koniec
		
	inc_skip:
		inc ax
		mov skip, ax
		
	koniec:
		pop es
		pop dx
		pop bx
		pop ax
		; skok do oryginalnego podprogramu obsługi przerwania zegarowego
		jmp dword PTR wektor8
snake_update ENDP

;main
start:
	;inicjalizacja ds
	mov ax, data
	mov ds, ax
	
	; wpisanie pozycji poczatkowej
	mov ax, snake_start_pos
	mov snake_seg_pos, ax ; ustawienie pozycji startowej na (5,5)
	
	; wpisanie czasu systemowego do zmiennej seed
	xor ah, ah ; ah = 00h
	int 1ah
	mov rand_seed, dx

	; ustawienie trybu graficznego
	mov ah, 0
	mov al, 13H
	int 10H
	
	; nadpisanie wektora przerwan dla odswiezania obrazu
	xor bx, bx ; bx = 0
	mov es, bx ; zerowanie rejestru ES
	mov eax, es:[32] ; odczytanie wektora nr 8
	mov wektor8, eax; zapamiętanie wektora nr 8
	; adres petli gry 'snake_update' w postaci segment:offset
	mov ax, SEG snake_update
	mov bx, OFFSET snake_update
	cli ; zablokowanie przerwań
	; zapisanie adresu petli gry 'snake_update' do wektora nr 8
	mov es:[32], bx
	mov es:[32+2], ax
	sti ; odblokowanie przerwań
	
	; pobieranie wcisnietego klawisza
	; wywolanie funkcji get_input
	; jesli =x to koniec programu
	czekaj:
		xor ah, ah ; ah = 00h
		int 16h
		call get_input
		cmp ah, 45 ; scancode 45 = x
		jne czekaj
		
	;ustawienie trybu tekstowego
	mov ah, 0
	mov al, 3H
	int 10H
	
	; odtworzenie oryginalnej zawartości wektora nr 8
	mov eax, wektor8
	mov es:[32], eax
	
	; zakończenie wykonywania programu
	mov ax, 4C00H
	int 21H
code ENDS
end start