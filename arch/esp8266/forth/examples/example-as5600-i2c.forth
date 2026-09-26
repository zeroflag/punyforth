5 ( D1 SCL ) constant: SCL
4 ( D2 SDA ) constant: SDA
16r36        constant: SLAVE
0            constant: BUS
2 ( 400K )   constant: FREQ
3            constant: MIN_CHANGE

exception: EI2C
2 buffer:  buf
1 buffer:  reg-angle
1 buffer:  reg-status

16r0E reg-angle  c!
16r0B reg-status c!

variable: angle

: check ( code -- | throws:EI2C ) 0<> if EI2C throw then ;
: bus-init ( -- ) FREQ SDA SCL BUS i2c-init check ;

: read-register ( len buf reg-addr -- ) SLAVE BUS i2c-read-slave check ;

: status ( -- n )
  1 buf reg-status read-register
  buf c@ ;

\ bit:   7 6  5   4   3  2 1 0
\        - -  MD  ML MH  - - -
: magnet-detected?   status 32 and 0<> ;
: magnet-too-weak?   status 16 and 0<> ;
: magnet-too-strong? status 8  and 0<> ;

: convert ( -- n )
  buf    c@ 8 lshift
  buf 1+ c@   or
  16rFFF      and
  360 *  12   rshift ;

: read-raw-angle ( -- n )
  2 buf reg-angle read-register
  convert ;

: read-angle ( -- n ) 
  read-raw-angle
  ;
  \ 8 1 do read-raw-angle + loop
  \ 3 rshift ;

: changed? ( a b -- bool ) - abs MIN_CHANGE >= ;

: main ( -- )
  bus-init
  begin
    magnet-detected? if
      read-angle
      dup angle @ changed? if
        dup . cr
      then
      angle !
      10 ms
    else
      print: "Status:" status . cr
      magnet-too-weak? if
        println: "Magnet too weak."
      then
      magnet-too-strong? if
        println: "Magnet too strong."
      then
      500 ms
    then
  again ;

main
