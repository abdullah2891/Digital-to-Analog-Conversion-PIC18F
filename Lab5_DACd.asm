;;;;;;; DAC for QwikFlash board ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Use 10 MHz crystal frequency.
; Use Timer0 for ten millisecond looptime.
; Blink "Alive" LED every two and a half seconds.
; Toggle C2 output every ten milliseconds for measuring looptime precisely.
;
;;;;;;; Program hierarchy ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; Mainline
;   Initial
;   BlinkAlive
;   LoopTime
;
;;;;;;; Assembler directives ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

       list  P=PIC18F4520, F=INHX32, C=160, N=0, ST=OFF, MM=OFF, R=DEC, X=ON
        #include <P18F4520.inc>
        __CONFIG  _CONFIG1H, _OSC_HS_1H  ;HS oscillator
        __CONFIG  _CONFIG2L, _PWRT_ON_2L & _BOREN_ON_2L & _BORV_2_2L  ;Reset
        __CONFIG  _CONFIG2H, _WDT_OFF_2H  ;Watchdog timer disabled
        __CONFIG  _CONFIG3H, _CCP2MX_PORTC_3H  ;CCP2 to RC1 (rather than to RB3)
        __CONFIG  _CONFIG4L, _LVP_OFF_4L & _XINST_OFF_4L  ;RB5 enabled for I/O
        errorlevel -314, -315          ;Ignore lfsr messages


;;;;;;; Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        cblock  0x000           ;Beginning of Access RAM
        TMR0LCOPY               ;Copy of sixteen-bit Timer0 used by LoopTime
        TMR0HCOPY
        INTCONCOPY              ;Copy of INTCON for LoopTime subroutine
        ALIVECNT                ;Counter for blinking "Alive" LED
		COUNT
        endc

;;;;;;; Macro definitions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

MOVLF   macro  literal,dest
        movlw  literal
        movwf  dest
        endm

ValAdc	macro literal
		bcf PORTC, RC5			        ;enable DAC Converter
		MOVLF   B'00100001', SSPBUF 	;send control byte
		LOOP1 	BTFSS SSPSTAT, BF    	; is the transmission complete? 
		bra LOOP1 	            ;No 
		MOVLF literal, SSPBUF	; send new data byte
		LOOP2 	BTFSS SSPSTAT, BF	    ;is the transmission complete? 
		bra LOOP2 	            ;No 
		rcall LoopTime			;hold digital output voltage for 20ms
		endm

;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

        org  0x0000             ;Reset vector
        nop
        goto  Mainline

        org  0x0008             ;High priority interrupt vector
        goto  $                 ;Trap

        org  0x0018             ;Low priority interrupt vector
        goto  $                 ;Trap

;;;;;;; Mainline program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

Mainline
        rcall  Initial          ;Initialize everything
Loop	
	ValAdc	D'128'		; 0 degrees, Vout= 5 V
	ValAdc	D'192'		; 0.5 degrees, Vout= 7.5 V
	ValAdc	D'238'		; 0.866 degrees, Vout= 9.33 V
	ValAdc	D'255'		; 1.0 degrees, Vout= 10 V
	ValAdc	D'238'		; 0.866 degrees, Vout= 9.33 V
	ValAdc	D'192'		; 0.5 degrees, Vout= 7.5 V
	ValAdc	D'128'		; 0 degrees, Vout= 5 V
	ValAdc	D'64'		; -0.5 degrees, Vout= 2.5 V
	ValAdc	D'17'		; -0.866 degrees, Vout= 0.669 V
	ValAdc	D'0'		; -1.0 degrees, Vout= 0 V
	ValAdc	D'17'		; -0.866 degrees, Vout= 0.669 V
	ValAdc	D'64'		; -0.5 degrees, Vout= 2.5 V
	ValAdc	D'128'		; 0 degrees, Vout= 5 V

		BRA Loop
		;rcall  BlinkAlive       ;Blink "Alive" LED

;;;;;;; Initial subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine performs all initializations of variables and registers.

Initial
		MOVLF  B'10001110',ADCON1  ;Enable PORTA & PORTE digital I/O pins
        MOVLF  B'11100001',TRISA  ;Set I/O for PORTA
        MOVLF  B'11000000',TRISB  ;Set I/O for PORTB
        MOVLF  B'00001111',TRISD  ;Set I/O for PORTD
        MOVLF  B'00000000',TRISE  ;Set I/O for PORTE
        MOVLF  B'10000110',T0CON  ;Set up Timer0 for a looptime of 10 ms
        MOVLF  B'00010000',PORTA  ;Turn off all four LEDs driven from PORTA

		MOVLF B'00100001', SSPCON1	; enable SPI master mode, select idle, Fosc/16
		MOVLF B'01000000', SSPSTAT	; select rising edge to shift out register 
									; and input data in middle of a bit time
		bcf	TRISC,SDO		; set RC5/SDO as output
		bcf TRISC,SCK		; set RC3/SCK as output
		bcf TRISC,RC0		; set RC0 as output
        return

;;;;;;; LoopTime subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine waits for Timer0 to complete its ten millisecond count
; sequence. It does so by waiting for sixteen-bit Timer0 to roll over. To obtain
; a period of precisely 20000/0.4 = 50000 clock periods, it needs to remove
; 65536-25000 or 40536 counts from the sixteen-bit count sequence.  The
; algorithm below first copies Timer0 to RAM, adds "Bignum" to the copy ,and
; then writes the result back to Timer0. It actually needs to add somewhat more
; counts to Timer0 than 40536.  The extra number of 12+2 counts added into
; "Bignum" makes the precise correction.

Bignum  equ     65536-50000+12+2

LoopTime
        btfss  INTCON,TMR0IF    ;Wait until ten milliseconds are up
        bra  LoopTime
        movff  INTCON,INTCONCOPY  ;Disable all interrupts to CPU
        bcf  INTCON,GIEH
        movff  TMR0L,TMR0LCOPY  ;Read 16-bit counter at this moment
        movff  TMR0H,TMR0HCOPY
        movlw  low  Bignum
        addwf  TMR0LCOPY,F
        movlw  high  Bignum
        addwfc  TMR0HCOPY,F
        movff  TMR0HCOPY,TMR0H
        movff  TMR0LCOPY,TMR0L  ;Write 16-bit counter at this moment
        movf  INTCONCOPY,W      ;Restore GIEH interrupt enable bitd
        andlw  B'10000000'
        iorwf  INTCON,F
        bcf  INTCON,TMR0IF      ;Clear Timer0 flag
        return

;;;;;;; BlinkAlive subroutine ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;
; This subroutine briefly blinks the LED next to the PIC every two-and-a-half
; seconds.

BlinkAlive
	MOVLF 100, COUNT		;COUNT2 multiplied by 20 ms is blink time of RA2 LED
Repeat2
	rcall  LoopTime         ;Make looptime be twenty milliseconds
	decfsz COUNT , f            
	bra Repeat2
	return
        end