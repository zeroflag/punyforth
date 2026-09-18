WIFI load
NETCON load

6589            constant: SERVER_PORT
"192.168.0.151" constant: SERVER_IP
3               constant: MIN_CHANGE

variable: voltage
variable: server

: read-pot ( -- n )
  adc-read
  8 1 do adc-read + loop
  3 rshift ; \ div by 8

: changed? ( a b -- bool ) - abs MIN_CHANGE >= ;

: send-voltage ( -- )
  SERVER_PORT SERVER_IP UDP netcon-connect
  dup voltage 4 netcon-send-buf
  netcon-dispose ;

: main ( -- )
  begin
    read-pot
    dup voltage @ changed? if
      dup . cr
      voltage !
      send-voltage
    else
      drop
    then
    10 ms
  again ;

main

