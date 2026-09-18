5 ( D1 SCL ) constant: SCL
4 ( D2 SDA ) constant: SDA
0 ( D3 RST ) constant: RST 
16r36        constant: SLAVE
0            constant: BUS
2 ( 400K )   constant: FREQ

exception: EI2C
2 buffer:  buf
1 buffer:  reg-angle
1 buffer:  reg-status

16r0E reg-angle  c!
16r0B reg-status c!

: check ( code -- | throws:EI2C ) 0<> if EI2C throw then ;
: bus-init ( -- ) FREQ SDA SCL BUS i2c-init check ;

: read-register ( len buf reg-addr -- ) SLAVE BUS i2c-read-slave check ;

: status ( -- n )
  1 buf reg-status read-register
  buf c@ ;

: read-raw-angle ( -- ) 2 buf reg-angle read-register ;

: convert ( -- n )
  buf    c@ 8 lshift
  buf 1+ c@   or
  16rFFF      and
  360 *  12   rshift ;

: angle ( -- ) read-raw-angle convert ;

: main ( -- )
  bus-init
  print: "Status: "
  status . cr
  begin
    angle . cr
    500 ms
  again ;

main
