
import std / [ atomics, monotimes, os, random, sets, strformat, threadpool ]

import abstract_rcu
from util import dbg, repeat_until

type
  Counter = ref object
    value: Atomic[ ptr int ]

proc CAS(
    location: var Atomic[ptr int],
    expected: var ptr int,
    desired:  var ptr int
): bool =
  location.compareExchange( expected, desired, moAcquire, moRelease )

proc read( counter: var Counter ): int =
  counter.value.load( moRelaxed )[]

#[ Figure.3, page-7, right, Counter

  int inc() {
    int v, *n, *s;
    n = new int; rcu_enter();
    do {
      rcu_exit();
      rcu_enter();
      s = C;
      v = *s;
      *n = v+1;
    } while ( !CAS(&C,s,n) );

    rcu_exit();
    reclaim(s);
    return v;
  }
]#
proc inc( counter: var Counter ): int =

  var new_int_ptr = createShared( int, sizeof( int ) )

  dbg &"new_int_ptr : { new_int_ptr.repr } | value = { new_int_ptr[] }"

  rcu_enter()

  var old_int_ptr = counter.value.load moAcquire
  #dbg "old_int_ptr : { old_int_ptr.repr }"
  new_int_ptr[] = old_int_ptr[] + 1
  #dbg &"new_int_ptr : { new_int_ptr.repr } | value = { new_int_ptr[] }"

  repeat_until CAS( counter.value, old_int_ptr, new_int_ptr ):
    rcu_exit()
    rcu_enter()
    old_int_ptr = counter.value.load moAcquire
    new_int_ptr[] = old_int_ptr[] + 1

  rcu_exit()
  rcu_reclaim old_int_ptr

  return counter.read()




#var counter = createShared( Counter, sizeof( Counter ) )[]
#var counter = cast[Counter]( allocShared0( sizeof Counter ) )
#var counter = Counter()

let c_ptr = alloc0( sizeof Counter )
dbg repr c_ptr
var counter = cast[Counter]( c_ptr )
dbg counter.repr

var thrs_work: Atomic[ bool ]
thrs_work.store on


#
# Any worker might perform reads or writes.
#
proc thr_worker() {.gcsafe.}  =

  # thread-local set for detached int-pointers
  #
  detached = newSeq[ptr int]()

  rcu_register()  # register thread with RCU

  while thrs_work.load:

    rcu_enter() # announce start of the 'critical-section'

    dbg "thread sees counter ? ", counter.repr

    let OP = random.sample @[ "inc", "dec", "read", "reset", "noop" ]
    case OP:
      of "inc":
        discard counter.inc()
      of "read":
        discard counter.read()
      else: discard

    rcu_exit() # announce end of 'critical-section'

    #dbg &"{rcu_info() }-worker '{OP}' counter =  {counter.read()}"

    if OP in [ "inc", "dec", "reset" ]:
      #
      # Have we mutated the counter ?
      # then we need to synchronize.
      #
      rcu_synchronize()
    else:
      continue


  #dbg &"{ rcu_info() }-worker-thread exits.."

  # flush anything leftover in the detached-Set
  # could be done in rcu_unregister ?
  #rcu_unregister() # unregister thread


proc now(): int64 = getMonoTime().ticks()

proc main =

  rcu_register()

  var ths: array[ 3, Thread[ void ] ]

  dbg "main-thread id is ", getThreadId()

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    #spawn thr_worker

  let ts = 200_000'i64 + getMonoTime().ticks()
  #dbg "will end ", ts
  while ts > getMonoTime().ticks(): discard

  thrs_work.store off
  dbg &"{rcu_info()}-main::stopping threads now +{now() - ts}"

  # rcu_reclaim()   # free detached-pointers, if any ?
  rcu_unregister()
  sleep 1000

  for i in 0 .. 2:
    dbg &"thread-{i} running ? { ths[i].running }"

when isMainModule:
  main()