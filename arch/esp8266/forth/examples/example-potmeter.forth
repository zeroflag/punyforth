variable: voltage
3 constant: MIN_CHANGE

: read-pot ( -- n )
  adc-read
  8 1 do adc-read + loop
  3 rshift ; \ div by 8

: changed? ( a b -- bool ) - abs MIN_CHANGE >= ;

: main ( -- )
  begin
    read-pot
    dup voltage @ changed? if
      dup . cr
    then
    voltage !
    10 ms
  again ;

main
