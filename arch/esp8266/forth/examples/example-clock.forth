NTP load
SSD1306I2C load
FONT57 load

variable: clock
variable: tick
variable: timezone
0 init-variable: offset
0 init-variable: last-sync
3 byte-array: ]mm   0 2 ]mm c!  : mm 0 ]mm ;
3 byte-array: ]hh   0 2 ]hh c!  : hh 0 ]hh ;

: age ( -- ms ) ms@ last-sync @ - ;
: expired? ( -- bool ) age 60000 15 * > ;
: stale? ( -- bool ) age 60000 60 * > ;
: fetch ( -- ts ) 123 "time.google.com" network-time ;
: sync ( -- ) { fetch clock ! ms@ last-sync ! } catch ?dup if print: 'sync error:' ex-type cr then ;
: time  ( -- ts )  clock @ offset @ 60 * + age 1000 / + ;
: mins ( ts -- n ) 60 / 60 % ;
: hour ( ts -- n ) 3600 / 24 % ;
: secs ( ts ---n ) 60 % ;

\ based on: http://howardhinnant.github.io/date_algorithms.html#civil_from_days
: era   ( ts -- n ) 86400 / 719468 + dup 0< if 146096 - then 146097 / ;
: doe   ( ts -- n ) dup 86400 / 719468 + swap era 146097 * - ;
: yoe   ( ts -- n ) doe dup 1460 / over 36524 / + over 146096 / - - 365 / ;
: doy   ( ts -- n ) dup doe swap yoe dup 365 * over 4 / + swap 100 / - - ;
: mp    ( ts -- n ) doy 5 * 2 + 153 / ;
: epoch-days ( ts -- n ) dup era 146097 * swap doe + 719468 - ;
: weekday ( ts -- 1..7=mon..sun ) epoch-days dup -4 >= if 4 + 7 % else 5 + 7 % 6 + then ?dup 0= if 7 then ;
: day   ( ts -- 1..31 ) dup doy swap mp 153 * 2 + 5 / - 1+ ;
: month ( ts -- 1..12 ) mp dup 10 < if 3 else -9 then + ;
: year  ( ts -- n ) dup yoe over era 400 * + swap month 2 < if 1 else 0 then + ;

: era ( year -- n ) dup 0< if 399 - then 400 / ;
: yoe ( year --n ) dup era 400 * - ;
: doy ( d m -- n ) dup 2 > if -3 else 9 then + 153 * 2 + 5 / swap + 1- ;
: doe ( d m y -- n ) yoe dup 365 * over 4 / + swap 100 / - -rot doy + ;
: days ( d m y -- days-since-epoch ) over 2 <= if 1- then dup era 146097 * >r doe r> + 719468 - ;
: >ts ( d m y -- ts ) days 86400 * ;

struct
    cell field: .week    \ last = 0 first second third fourth
    cell field: .dow     \ 1..7 = mon..sun
    cell field: .month   \ Jan = 1 .. Dec
    cell field: .hour    \ 0 .. 23
    cell field: .offset  \ Offset from UTC in minutes
    cell field: .name
constant: RULE
: rule: RULE create: allot ;

struct
    cell field: .standard
    cell field: .summer
constant: TZ
: tz: TZ create: allot ;

rule:  PST
 1     PST .week    !
 7     PST .dow     !
11     PST .month   !
 2     PST .hour    !
-480   PST .offset  !
"PST"  PST .name    !

rule:  PDT
 2     PDT .week    !
 7     PDT .dow     !
 3     PDT .month   !
 2     PDT .hour    !
-420   PDT .offset  !
"PDT"  PDT .name    !

rule:  CET
 0     CET .week    ! \ Last week
 7     CET .dow     !
10     CET .month   !
 3     CET .hour    !
60     CET .offset  !
"CET"  CET .name    !

rule:  CEST
 0     CEST .week   ! \ Last week
 7     CEST .dow    !
 3     CEST .month  !
 2     CEST .hour   !
120    CEST .offset !
"CEST" CEST .name   !

tz:  US
PST  US .standard !
PDT  US .summer   !

tz:  HU
CET  HU .standard !
CEST HU .summer   !

: 1stday ( month -- 1..7 ) 1 swap time year >ts weekday ;
: dday ( rule -- day )
    dup  .dow @ 
    over .month @ 1stday 2dup >= if - else 7 swap - + then 1+ 
    swap .week @ 1- 7 * + ;

: shifting-time ( rule -- utc ) \ TODO LAST WEEK handling
    dup  dday
    over .month @ time year >ts 
    over .offset @ -60 * +
    swap .hour   @ 3600 * + ;

: summer-change   ( -- utc ) timezone @ .summer   @ shifting-time ;
: standard-change ( -- utc ) timezone @ .standard @ shifting-time ;
: current-zone ( -- rule ) \ TODO south hemisphere
    time summer-change   < if timezone @ .standard @ exit then
    time standard-change < if timezone @ .summer   @ exit then
    timezone @ .standard @ ;

: apply-zone ( -- ) current-zone .offset @ offset ! ;

: format
    time hour 10 < if $0 hh c! 1 else 0 then ]hh time hour >str
    time mins 10 < if $0 mm c! 1 else 0 then ]mm time mins >str ;

: centery HEIGHT 2 / 4 - text-top ! ;
: colon tick @ if ":" else " " then draw-str tick @ invert tick ! ;
: draw-time
    0 fill-buffer
    0 text-left ! centery
    hh draw-str colon mm draw-str " " draw-str
    current-zone .name @ draw-str ;

: draw format draw-time display ;
: start ( task -- ) activate begin expired? if sync then apply-zone draw 1000 ms pause again ;

0 task: time-task
: main
    HU timezone !
    display-init font5x7 font !  
    sync multi time-task start ;

main
