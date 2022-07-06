import std / [ algorithm, atomics, monotimes, os, random, sets, strformat, threadpool ]

import abstract_rcu
from util import dbg, Rec, now

var threads_work: Atomic[ bool ]
threads_work.store on

var chan: Channel[ ptr seq[int] ]
chan.open()
var lchan: Channel[ Rec ]
lchan.open()

var global_list = @[1,2,3,4,5]
var appstart = now()
#
# Any worker might perform reads or writes.
#
proc thr_worker() {.gcsafe.}  =

  proc log( who: int, what: string, detail: string = "" ) =
    lchan.send(
      Rec(
        tics:   now() - appstart,
        who:    who,
        where:  "worker",
        what:   what,
        detail: detail
    ))
  # thread-local seq[ptr int] for detached int-pointers
  #
  detached = newSeq[ptr int]()
  rcu_register()  # register thread with RCU

  var list_ptr = chan.recv()

  while threads_work.load == on:

    rcu_enter() # announce start of the 'critical-section'

    let OP = random.sample @[ "push", "wait", "pop", "store" ]
    case OP:
      of "pop":
        list_ptr[].add( random.rand 100..110 )
        log( rcu_id(), OP, &"{list_ptr[]}" )
        #if list_ptr[].len > 0: discard list_ptr[].pop()
      of "push":
        list_ptr[].add( random.rand 1..10 )
        log( rcu_id(), OP, &"{list_ptr[]}" )
      of "store": # slow down
        detached.add list_ptr[][0].addr
        log( rcu_id(), OP, &"{list_ptr[]}" )
      else: discard

    rcu_exit() # announce end of 'critical-section'

    if OP in @[ "pop", "push" ]:
      rcu_synchronize()

    #if rcu_id() == 3:
    #dbg &"{rcu_info() }-worker '{OP}' list = {list_ptr[]}"

  #dbg &"{ rcu_info() }-worker-thread exits.. detached {detached.len}"
  log( rcu_id(), "exit", &"{list_ptr[]} {detached.len}" )

  # TODO: flush anything leftover in the detached-Set
  # could be done in rcu_unregister ?
  rcu_unregister() # unregister thread


proc main =
  var msgs: seq[Rec]

  rcu_init( lchan.addr, appstart )
  rcu_register()

  var ths: array[ 3, Thread[void] ]

  #dbg "main-thread id : ", rcu_info()

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    chan.send global_list.addr
    #spawn thr_worker

  let ts = 500_000'i64 + now()
  while ts > now():
    let test = lchan.tryRecv()
    if test.dataAvailable:
      msgs.add test.msg

  threads_work.store off
  #dbg &"{rcu_info()}-main::stopping threads now +{now() - ts}"
  lchan.send(
    Rec(
      tics:     now() - appstart,
      who:      0,
      where:    "main",
      what:     "stopped worker"
  ))
  # TODO: take care of detached-set
  # rcu_reclaim()
  rcu_unregister()
  sleep 2000

  for i in 0 .. 2:
    dbg &"thread-{i} running ? { ths[i].running }"

  chan.close()

  while true:
    let test = lchan.tryRecv()
    if test.dataAvailable:
      msgs.add test.msg
    else:
      break
  lchan.close()

  dbg &"got {msgs.len} x msgs."
  sort(msgs) do (x, y: Rec) -> int:
    cmp(x.tics, y.tics)

  for msg in msgs: dbg msg

when isMainModule:
  main()
