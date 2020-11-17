
stack-clear 
\ common words for communication with mqtt broker
NETCON load 
DECOMP load 

\ configuration for communicating with your broker
"192.168.1.172" constant: broker_addr 
1883 constant: broker_port 
"YourMQTT-ClientId" constant: mqtt-clientid 

\ mqtt message types
\ 10 = CONNECT message type 
16r10 constant: msgtype_connect 
16r20 constant: msgtype_conact 
16rE0 constant: msgtype_disconnect 
16r30 constant: msgtype_publish 
16r82 constant: msgtype_subscribe 
16r90 constant: msgtype_subresp 

\ socket reference to broker 
variable: broker 

\ communication packet buffer. expect small packets  
255 constant: packet_size 
packet_size byte-array: packet 
\ paki is an index into packet byte array when building the packet 
\ note that the packet size to send is 1+ the paki value 
variable: paki 

\ store two byte number into an address 
: !pack-num ( num addr -- ) 
    2dup 
    \ store high order byte to address 
    swap 8 rshift swap c! 
    \ store low order byte to address+1 
    1+ c! ; 

\ store string at an address 
: !str ( s addr -- ) 
    swap dup strlen ( addr s len ) 
    rot swap ( s addr len ) 
    cmove ; 

\ store string into len+string struct that mqtt likes (packed string) 
: !pack-str ( s addr -- len) 
    2dup ( s addr s addr) 
    swap strlen dup >r swap ( s addr len addr) 
    !pack-num ( s addr) 
    \ fill rest of buffer with the string 
    2 + ( s addr ) 
    r> dup >r ( s addr len ) 
    cmove ( ) 
    \ return length of string we just stored plus the length of num 
    r> 2 + 
    ; 

\ establish tcp socket connection to broker 
: mqtt-con broker_port broker_addr TCP netcon-connect broker ! ; 
: mqtt-close broker @ netcon-dispose ; 
\ send packet to broker 
: send-pak broker @ rot rot netcon-write-buf ; 
: send-packet 0 packet paki @ send-pak ; 
\ store single byte character in packet 
: !c-packet ( c -- ) paki @ packet c! 1 paki +! ; 
\ store packed string in packet 
: !str-packet ( s -- ) paki @ packet !pack-str paki +! ; 
\ store message length in the packet header ie. packet size - 2 
: !packet-len paki @ 2 - 1 packet c! ; 

\ stores mqtt CONNECT command into packet 
: make-packet-connect 
    \ initialize the index into the byte-array 
    0 paki ! 
    msgtype_connect !c-packet 
    1 paki +! 
    \ msg len, must be calculated at the end 
    \ protocol name 
    "MQTT" !str-packet 
    \ protocol version 
    16r04 !c-packet 
    \ flags 
    16r02 !c-packet 
    \ keep-alive 
    60 paki @ packet !pack-num 
    2 paki +! 
    \ clientid 
    mqtt-clientid !str-packet 
    !packet-len 
    ; 

: make-packet-disconnect ( -- ) 
    0 paki ! 
    msgtype_disconnect !c-packet 
    1 paki +! 
    \ 2 - 2 = 0, will store 0 
    !packet-len ; 

: make-packet-publish ( topic msg -- ) 
    0 paki ! 
    msgtype_publish !c-packet 
    1 paki +! 
    \ store topic with length 
    swap !str-packet 
    dup strlen swap paki @ packet !str paki +!
    !packet-len ; 

\ compare buffer contents 
: =buf ( b1 b2 n -- T|F) 
   0 do
       2dup
       i + c@ swap i + c@ <> if 
         2drop unloop FALSE exit then 
   loop 
   2drop TRUE ;

\ read message from broker into packet and store length
: read-broker broker @ packet_size 0 packet netcon-read
    paki ! ; 

\ compare broker response to expected response
: expect ( buf n -- TRUE | FALSE) 
    paki @
    dup -1 = if \ no bytes read from broker
        2drop FALSE exit 
    then 
    dup rot <> if \ did not read the expected number of bytes 
      2drop FALSE exit 
    then 
      0 packet swap =buf ;

create: pak-conack 16r20 c, 16r02 c, 16r00 c, 16r00 c,
create: pak-disconnect 16re0 c, 16r00 c,

: expect-conack pak-conack 4 expect ; 

: print-results 
    if 
      println: "Success" else println: "Failed" 
      print: "got " paki @ . print: " bytes" cr 
    then 
    0 packet 10 dump ; 

: mqtt-pub 
    make-packet-connect mqtt-con send-packet
    read-broker expect-conack if
      make-packet-publish send-packet
      pak-disconnect 2 send-pak
    then mqtt-close ;
 
\ example usage 
\ "house/t1" "testmessage" mqtt-pub
\ print-results 
/end 

