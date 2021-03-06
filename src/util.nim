import std/monotimes
from std/macros import unpackVarargs

proc now*(): int64 = getMonoTime().ticks

type
  Rec* = object
    tics*:   int64
    who*:    int
    where*:  string
    what*:   string
    detail*: string

template repeat_until*( cond: bool, code: untyped ) =
  while not cond:
    code

template unless*( cond: bool ) =
  if cond: break

template dbg*( s: varargs[ string, `$` ] ) =
  when not defined( release ):
    unpackVarargs echo, s

template critical_section*( code: untyped ) =

  rcu_enter()
  try:
    proc rcu_synchronize() {.error: "rcu_synchronize() can lock the system and is thus disabled inside a critical-section".} = echo "call rcu_synchronize() AFTER a critical-section, but NOT from inside."
    #proc defer_rcu( cb: rcu_cb, p: pointer ) {.error: "defer_rcu() is disabled inside a critical-section".} = echo "call defer_rcu() AFTER a critical-section, but NOT from inside."

    code

  finally:
    rcu_exit()




