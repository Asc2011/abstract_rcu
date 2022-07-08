import threading/atomics

from ../util import dbg

type
  Counter* = ref object
    value*: Atomic[ int ]

# proc `=destroy`( counter: var ref Counter ) =
#   dbg &"Counter destroyed : {counter.repr}"
#   #if counter.value

proc FetchAndAdd(
  location: var Atomic[int],
  value: int,
) :int =
  location.fetchAdd value

proc FetchAndSub(
  location: var Atomic[int],
  value: int,
) :int =
  location.fetchSub value

proc dec*( counter: Counter, toSub: int = 1 ): int =
  return FetchAndSub( counter.value, toSub )

proc inc*( counter: Counter, toAdd: int = 1 ): int =
  return FetchAndAdd( counter.value, toAdd )

# proc reset*( counter: Counter ) =
#   var loc = counter.value
#   loc.store 0, SeqCst
