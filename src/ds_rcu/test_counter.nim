import std / [ atomics, monotimes, os, random, sets, strformat, threadpool ]

import abstract_rcu
import ds_counter
from util import dbg


#var counter = createShared( Counter, sizeof( Counter ) )[]
#var counter = cast[Counter]( allocShared0( sizeof Counter ) )
#var counter = Counter()

let c_ptr = alloc0( sizeof Counter )
dbg repr c_ptr
var counter = cast[Counter]( c_ptr )
dbg counter.repr




var threads_work: Atomic[ bool ]
threads_work.store on
#
# Any worker might perform reads or writes.
#
proc thr_worker() {.gcsafe.}  =

  # thread-local seq[ptr int] for detached int-pointers
  #
  detached = newSeq[ptr int]()

  rcu_register()  # register thread with RCU

  while threads_work.load:

    rcu_enter() # announce start of the 'critical-section'

    dbg "thread sees counter ? ", counter.repr

    let OP = random.sample @[ "inc", "dec", "read", "reset", "" ]
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

  dbg &"{ rcu_info() }-worker-thread exits.."

  # TODO: flush anything leftover in the detached-Set
  # could be done in rcu_unregister ?
  rcu_unregister() # unregister thread


proc now(): int64 = getMonoTime().ticks()

proc main =

  rcu_register()

  var ths: array[ 3, Thread[ void ] ]

  dbg "main-thread id : ", getThreadId()

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    #spawn thr_worker

  let ts = 200_000'i64 + getMonoTime().ticks()
  #dbg "will end ", ts
  while ts > getMonoTime().ticks(): discard

  thrs_work.store off
  dbg &"{rcu_info()}-main::stopping threads now +{now() - ts}"

  # TODO: take care of detached-set
  # rcu_reclaim()   # free detached-pointers, if any ?
  rcu_unregister()
  sleep 1000

  for i in 0 .. 2:
    dbg &"thread-{i} running ? { ths[i].running }"

when isMainModule:
  main()