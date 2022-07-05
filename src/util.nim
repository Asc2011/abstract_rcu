from std/macros import unpackVarargs
from std/bitops import bitsliced, testBit
import std/hashes
#[
template loop[T]*( i: iterator(): T, code: untyped ) =
  let iter = i
  var
    steps = -1
    former = iter()
    done = iter.finished

  proc next(): ( bool, T ) =
    let current = former
    former = iter()
    steps.inc
    done = iter.finished
    return if done: (true, current )
      else: (false, current )

  proc next( withSteps: bool ): ( bool, T, int ) =
    let current = former
    former = iter()
    steps.inc
    done = iter.finished
    return if done: (true, current, steps)
      else: (false, current, steps)

  while true:
    code
 ]#

template repeat_until*( cond: bool, code: untyped ) =
  while not cond:
    code

template unless*( cond: bool ) =
  if cond: break

template dbg*( s: varargs[ string, `$` ] ) =
  when not defined( release ):
    unpackVarargs echo, s
