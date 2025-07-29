ORG 0000H
	SJMP 0030H            ;lEAVING SPACE FOR VECTORED INTERRUPTS
ORG 0030H
	MOV P0, #00H          ;Port 0.7, 0.6, 0.5 sends control signal output to LCD RS, R/W and E respectively
	MOV P2, #00H          ;Port 2 is Data line output
	MOV TMOD,#21H         ;Timer1=Mode2<For serial comms> and Timer0=Mode1<For delay>
	MOV TH1,#-3D          ;loads TH1 with 253D(9600 baud)
	MOV SCON,#50H         ;sets serial port to Mode1 <8 bit UART> and receiver enabled
	MOV IE, #90H          ;Interrupt enabled but only serial communication interrupt enabled
	SETB TR1              ;Timer set to start serial communication
	CLR PSW.3             ;Register bank 00 is used
	CLR PSW.4
;command for lcd initialization
	MOV A, #38H ; 8 bit mode
	ACALL CMD
	ACALL DLAY
;	MOV A, #0EH ; display on curson on
;	MOV A, #0FH ; Blinking block cursor
	MOV A, #0CH ; display on cursor off
	ACALL CMD
	ACALL DLAY
	MOV A, #01H ; clear LCD
	ACALL CMD
	ACALL DLAY
;Initial commands over, starting to move data to LCD
	MOV A, #080H ;1st line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESS01
	ACALL RTLCD
	MOV A, #0C0H ;2nd line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESS02
	ACALL RTLCD
	MOV A, #090H ;3nd line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESS03
	ACALL RTLCD
	MOV A, #0D0H ;4nd line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESS04
	ACALL RTLCD
; 20 to 2F Area Initialization <Bit addressable range cleared to 0, where each bit works like a single button ON/OFF switch>
	MOV R2,#00H
	MOV R1,#20H
A0:	MOV @R1,#00
	INC R1
	INC R2
	CJNE R2,#010H,A0 ;<16 bits cleared to 0>
	  
	MOV R3, #00H  ;Initializing registers to avoid data corruption
	MOV R4, #00H
	MOV R5, #00H
	MOV 7DH, #00H ;INITIALIZE LSB OF COST
	MOV 7EH, #00H ;INITIALIZE MSB OF COST
	MOV 7FH, #00H ;INITIALIZE TOTAL NO OF PRODUCTS

DETECTION:
;TIMER DELAY TO PREVENT REPEATED SCANS OF THE SAME CARD
	MOV R0, #2D
LL:	MOV TH0,#00H
	MOV TL0,#00H
	SETB TR0
HH: JNB TF0, HH
	CLR TF0
	CLR TR0
	DJNZ R0, LL
; 70 to 7B Area Initialization <12 Hexadecimal Digit RFID code is stored here>
	MOV R2,#00H
	MOV R1,#70H
A1:	MOV @R1,#00H
	INC R1
	INC R2
	CJNE R2,#0CH,A1 ;<12 bits cleared to 0 Leaving 7D, 7E and 7F untouched>

	MOV R1, #70H
	MOV R2, #12D
WAIT:   CJNE R2,#00H, WAIT 	;Wait for R2==0 <Waiting indefinitely for an RFID card to get scanned>
;RFID card detected
;Now display the RFID of the corresponding card on the LCD
	MOV A, #0C4H          ;2nd line 4th pos
	ACALL CMD
	ACALL DLAY
	MOV R1,#70H           ;R1 used as pointer to 70H 
        MOV R2,#12D           ;loads R1 with 12D
BACK1:  MOV A,@R1             ;loads A with data pointed by R1
	ACALL DAT             ;calls DAT <data display> subroutine
        ACALL DLAY
	INC R1                ;incremets R1
        DJNZ R2,BACK1 


;RFID Comparison begins here. Compare Subroutine is used for this purpose
;If card numbers match, product is added, if the same card is scanned twice, product is removed and total cost and count are updated and displayed
;If card numbers don't match, UNRECOGNIZED is displayed on the screen
;If Master card is scanned, shopping stops and final cost and count are displayed. After this, no card can be further scanned
;User can update the cost of a product by storing LSB and MSB or cost in Hexidecimal in registers R3 and R4 respectively
	;egg
        MOV DPTR,#RF0        ;load the address of the first character of the stored rfid into the dptr for the compare subroutine to compare 2 rfids
	ACALL Compare        ;Compare subroutine which used cjne to compare the immediately scanned rfid with an rfid stored in the database
	JB PSW.7, n0         ;The compare subroutine sets the carry bit if the rfids don't match, hence prompting the program to compare 
						 ;the immediately scanned rfid with the next rfid in the database and hence check for the next product. 
						 ;If the cards match, the next line is executed.
	CPL 00H              ;Complementing the bit corresponding to the product in the bit addressable range
	JNB 00H, eggrem      ;jump to product removal subroutine if the bit corresponding to the product is cleared
	ACALL eggadd         ;go to product adding subroutine if the bit corresponding to the product is set
        JMP DETECTION            ;after the product is added or removed, the space where the scanned rfid is stored needs to be initialized again
eggadd:                  ; product adding subroutine
	MOV DPTR,#MESS06 
	ACALL recdisp        ;display product added message
	ACALL PRODADD        ;increment product count
	ACALL no_disp        ;display the updated product count
	MOV R4, #00H         ;MSBytes of the cost of the product in hexadecimal
	MOV R3, #46H         ;LSBytes of the cost of the product in hexadecimal <70 rupees>
	ACALL COSTADD        ;Add the cost of this product to the total cost
	ACALL cost_disp      ;display the updated total cost
	RET                  ;return from this subroutine
eggrem:                  ;product removing subroutine
	MOV DPTR,#MESS07     ;display product added message
	ACALL recdisp        ;display product added message
	ACALL PRODSUBB       ;decrement product count
	ACALL no_disp        ;display the updated product count
	MOV R4, #00H         ;MSBytes of the cost of the product in hexadecimal
	MOV R3, #46H         ;LSBytes of the cost of the product in hexadecimal <70 rupees>
	ACALL COSTSUBB       ;Subtract the cost of this product to the total cost
	ACALL cost_disp      ;display the updated total cost
        JMP DETECTION            ;jump for detecting the next scanned card

n0:	              ;milk	 ;identification of the next product happens if the rfid scanned erlier didn't match earlier
	MOV DPTR,#RF1
	ACALL Compare
	JB PSW.7, n1
	CPL 01H
	JNB 01H, milkrem 
	ACALL milkadd 
	JMP DETECTION
milkadd:
	MOV DPTR,#MESS08
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #46H ;<70 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
milkrem:
	MOV DPTR,#MESS09
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #46H ;<70 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n1:					;butter
	MOV DPTR,#RF2
	ACALL Compare
	JB PSW.7, n2
	CPL 02H
	JNB 02H, butterrem 
	ACALL butteradd 
	JMP DETECTION
butteradd:
	MOV DPTR,#MESS0A
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
butterrem:
	MOV DPTR,#MESS0B
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n2:					;cereal
	MOV DPTR,#RF3
	ACALL Compare
	JB PSW.7, n3
	CPL 03H
	JNB 03H, p4rem 
	ACALL p4add 
        JMP DETECTION
p4add:
	MOV DPTR,#MESS0C
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #0AAH ;<170 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p4rem:
	MOV DPTR,#MESS0D
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #0AAH ;<170 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n3:					;salt
	MOV DPTR,#RF4
	ACALL Compare
	JB PSW.7, n4
	CPL 04H
	JNB 04H, p5rem 
	ACALL p5add 
	JMP DETECTION
p5add:
	MOV DPTR,#MESS0E
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #32H ;<50 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p5rem:
	MOV DPTR,#MESS0F
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #32H ;<50 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n4:					;cheese
	MOV DPTR,#RF5
	ACALL Compare
	JB PSW.7, n5
	CPL 05H
	JNB 05H, p6rem 
	ACALL p6add 
	JMP DETECTION
p6add:
	MOV DPTR,#MESS10
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p6rem:
	MOV DPTR,#MESS11
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n5:					;bread
	MOV DPTR,#RF6
	ACALL Compare
	JB PSW.7, n6
	CPL 06H
	JNB 06H, p7rem 
	ACALL p7add 
        JMP DETECTION
p7add:
	MOV DPTR,#MESS12
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #28H ;<40 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p7rem:
	MOV DPTR,#MESS13
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #28H ;<40 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n6:					;sugar
	MOV DPTR,#RF7
	ACALL Compare
	JB PSW.7, n7
	CPL 07H
	JNB 07H, p8rem 
	ACALL p8add 
	JMP DETECTION
p8add:
	MOV DPTR,#MESS14
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #28H ;<40 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p8rem:
	MOV DPTR,#MESS15
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #28H ;<40 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

n7:					;apples
	MOV DPTR,#RF8
	ACALL Compare
	JB PSW.7, M
	CPL 08H
	JNB 08H, p9rem 
	ACALL p9add 
	JMP DETECTION
p9add:
	MOV DPTR,#MESS16
	ACALL recdisp
	ACALL PRODADD
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTADD 
	ACALL cost_disp
	RET
p9rem:
	MOV DPTR,#MESS17
	ACALL recdisp
	ACALL PRODSUBB
	ACALL no_disp
	MOV R4, #00H
	MOV R3, #64H ;<100 rupees>
	ACALL COSTSUBB
	ACALL cost_disp
        JMP DETECTION

M:	MOV DPTR,#RF9      ;RFID of the master card is loaded
	ACALL Compare      ;checking whethe the scanned card is the master card
	JB PSW.7, unrec    ;if it is  neither any card stored in the database nor a master card, display "UNRECOGNIZED"
	ACALL MASTER       ;If it is the master card, go to its subroutine
MASTER:                ;The master card subroutine begins
	MOV DPTR,#MESSMm   ;Move the address of the final messages to the dptr 
	ACALL recdisp      ;display the messages indicating that shopping has ended on the 1st line of the LCD
	MOV A, #0C0H       ;2nd line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESSNn
	ACALL RTLCD        ;display the messages indicating that shopping has ended on the 2nd line of the LCD
	
EXITT:  SJMP EXITT       ;program gets stuck in this loop indefinitely until the reset button is pressed


;IMPORTANT SUBROUTINES:
;CJNE used 12 times for RFID digit comparizon and recognization
Compare:
	CLR PSW.7
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,70H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,71H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,72H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,73H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,74H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,75H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,76H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,77H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,78H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,79H,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,7AH,Fail
	INC DPTR
	CLR A
	MOVC A, @A+DPTR	
	CJNE A,7BH,Fail
	SJMP Success
Fail:
	SETB PSW.7
	SJMP Fin
Success:
	CLR PSW.7
	SJMP Fin
Fin:    RET

;Display for Unrecognized Card
unrec:  NOP
	MOV A, #080H ;1st line
	ACALL CMD
	ACALL DLAY
	MOV DPTR,#MESS05
	ACALL RTLCD
	JMP DETECTION
;Display Recognized Product
recdisp:MOV A, #080H ;1st line
	ACALL CMD
	ACALL DLAY
	ACALL RTLCD
	RET
;ADD A PRODUCT
PRODADD:
	MOV A, 7FH
	CLR C
	ADD A, #01H
	MOV 7FH, A
	RET
;REMOVE A PRODUCT
PRODSUBB: 
	MOV A, 7FH
	CLR C
	SUBB A, #01H
	MOV 7FH, A
	RET
;Display total number of Products
no_disp:
	MOV A, #097H ;3rd line 7th position
	ACALL CMD
	ACALL DLAY
;HEX TO DECIMAL CONVERSION OF TOTAL NUMBER OF PRODUCTS
HTD:
	MOV A, 7FH
	MOV B, #100D
	DIV AB
	MOV R1, A
	MOV A, B
	MOV B, #10D
	DIV AB
	MOV R2, A
	MOV R3, B
	MOV A, R1
	ADD A, #30H
	ACALL DAT
	ACALL DLAY
	MOV A, R2
	ADD A, #30H
	ACALL DAT
	ACALL DLAY
	MOV A, R3
	ADD A, #30H
	ACALL DAT
	ACALL DLAY
	RET

;COST AFTER ADDING A PRODUCT
 COSTADD:
  ;Step 1 of the process
        MOV A,7DH     ;Move the low-byte into the accumulator
        ADD A,R3      ;Add the second low-byte to the accumulator
        MOV R3,A      ;Move the answer to the low-byte of the result
        MOV 7DH,A
        ;Step 2 of the process
        MOV A,7EH     ;Move the high-byte into the accumulator
        ADDC A,R4     ;Add the second high-byte to the accumulator, plus carry.
        MOV R4,A      ;Move the answer to the high-byte of the result
        MOV 7EH,A
        RET           ;Return 
;COST AFTER REMOVING A PRODUCT
COSTSUBB:
  ;Step 1 of the process
        MOV A,7DH     ;Move the low-byte into the accumulator
        CLR C         ;Always clear carry before first subtraction
        SUBB A,R3     ;Subtract the second low-byte from the accumulator
        MOV R3,A      ;Move the answer to the low-byte of the result
        MOV 7DH,A
        ;Step 2 of the process
        MOV A,7EH     ;Move the high-byte into the accumulator
        SUBB A,R4     ;Subtract the second high-byte from the accumulator
        MOV R4,A      ;Move the answer to the high-byte of the result
        MOV 7EH,A
        RET           ;Return 

;Display total cost of Products
cost_disp:
	MOV A, #0DBH ;1st line
	ACALL CMD
	ACALL DLAY
	MOV A, R4 
	MOV R1, A ;R1 HAS MSByte
	MOV A, R3 
	MOV R2, A ;R2 HAS LSByte
;HEX TO DECIMAL CONVERSION OF TOTAL COST OF PRODUCTS
Hex2BCD:
        MOV R3,#00D
        MOV R4,#00D
        MOV R5,#00D
        MOV R6,#00D
        MOV R7,#00D
           
        MOV B,#10D
        MOV A,R2
        DIV AB
        MOV R3,B ; 
        MOV B,#10 ; R7,R6,R5,R4,R3
        DIV AB
        MOV R4,B
        MOV R5,A
        CJNE R1,#0H,HIGH_BYTE ; CHECK FOR HIGH BYTE
        SJMP ENDD
HIGH_BYTE:
        MOV A,#6
        ADD A,R3
        MOV B,#10
        DIV AB
        MOV R3,B
        ADD A,#5
        ADD A,R4
        MOV B,#10
        DIV AB
        MOV R4,B
        ADD A,#2
        ADD A,R5
        MOV B,#10
        DIV AB
        MOV R5,B
        CJNE R6,#00D, ADD_IT
        SJMP CONTINUE
ADD_IT:
        ADD A,R6
CONTINUE:
        MOV R6,A
        DJNZ R1, HIGH_BYTE
        MOV B, #10D
        MOV A,R6
        DIV AB
        MOV R6,B
        MOV R7,A
ENDD:   NOP		
	MOV A, R7
	ADD A, #30H  ;Adding 30H to each decimal digit converts it to the corresponding ascii value of the same digit so that it can be displayed on the LCD
	ACALL DATSP
	ACALL DLAYSP
	MOV A, R6
	ADD A, #30H
	ACALL DATSP
	ACALL DLAYSP
	MOV A, R5
	ADD A, #30H
	ACALL DATSP
	ACALL DLAYSP
	MOV A, R4
	ADD A, #30H
	ACALL DATSP
	ACALL DLAYSP
	MOV A, R3
	ADD A, #30H
	ACALL DATSP
	ACALL DLAYSP
        RET
	
;Command Subroutine
CMD: CLR P0.7
	CLR P0.6
	SETB P0.5
	MOV P2, A
	ACALL DLAY
	CLR P0.5
	RET
;Data Subroutine
DAT: SETB P0.7
	CLR P0.6
	SETB P0.5
	MOV P2, A
	ACALL DLAY
	CLR P0.5
	RET
;Delay Subroutine
DLAY:   MOV R7, #0FFH
Back:   MOV R6, #0AH
Here:   DJNZ R6, Here
	DJNZ R7, Back
	RET
;Return to LCD Subroutine
RTLCD:  NOP
L1:     CLR A
	MOVC A,@A+DPTR
	JZ OVER
	ACALL DAT
	ACALL DLAY
	INC DPTR
	SJMP L1
OVER:RET
;SPECIAL DELAY RESERVED IF R7 AND R6 ARE UNDER USE
DLAYSP: MOV R1, #0FFH
Back2:  MOV R2, #0AH
Here1:  DJNZ R2, Here1
	DJNZ R1, Back2
	RET
;SPECIAL Data Subroutine WHICH USES SPECIAL DELAY
DATSP:  SETB P0.7
	CLR P0.6
	SETB P0.5
	MOV P2, A
	ACALL DLAYSP
	CLR P0.5
	RET


;DATABASE
;Initial Display Messages
MESS01:DB '  AUTO BILLING  ',0
MESS02:DB 'ID: ############',0
MESS03:DB 'ITEMS: 000      ',0
MESS04:DB 'TOTAL AMT: 00000',0
MESS05:DB '  UNRECOGNIZED  ',0
MESS06:DB '   EGGS ADDED   ',0
MESS07:DB '  EGGS REMOVED  ',0	
MESS08:DB '   MILK ADDED   ',0
MESS09:DB '  MILK REMOVED  ',0
MESS0A:DB '  BUTTER ADDED  ',0
MESS0B:DB ' BUTTER REMOVED ',0
MESS0C:DB '  CEREAL ADDED  ',0
MESS0D:DB ' CEREAL REMOVED ',0
MESS0E:DB '   SALT ADDED   ',0
MESS0F:DB '  SALT REMOVED  ',0
MESS10:DB '  CHEESE ADDED  ',0
MESS11:DB ' CHEESE REMOVED ',0
MESS12:DB '   BREAD ADDED  ',0
MESS13:DB '  BREAD REMOVED ',0
MESS14:DB '   SUGAR ADDED  ',0
MESS15:DB '  SUGAR REMOVED ',0
MESS16:DB '  APPLES ADDED  ',0
MESS17:DB ' APPLES REMOVED ',0	
MESSMm:DB '   THANK YOU!   ',0
MESSNn:DB ' DO VISIT AGAIN ',0
	
;RFIDs Stored as strings corresponding to the product
RF0:DB '4300435A2D77',0
RF1:DB '43004357E2B5',0
RF2:DB '4300433493A7',0
RF3:DB '4300432E9FB1',0
RF4:DB '4300430AD6DC',0
RF5:DB '43004305FAFF',0
RF6:DB '430042F75BAD',0
RF7:DB '430042F58470',0
RF8:DB '430042DC04D9',0
RF9:DB '430042CD7AB6',0

;Serial Communication Interrupt
ORG 0023H
        JMP 0A00H
ORG 0A00H
	CLR RI
	MOV A, SBUF
	MOV @R1,A
	INC R1
	DEC R2
	RETI  	
END
