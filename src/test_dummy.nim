import std / [ algorithm, atomics, monotimes, os, random, sets, strformat, threadpool ]
randomize()
import terminaltables

import abstract_rcu
from util import dbg, Rec, now

var threads_work: Atomic[ bool ]
threads_work.store on

# sends a pointer to every worker-thread
var chan: Channel[ ptr seq[int] ]
chan.open()

# log-channel
var lchan: Channel[ Rec ]
lchan.open()

var global_list = @[1,2,3,4,5]
var appstart = now()
#
# The dummy rocks over a not-threadsafe seq[int] and breaks the
# data-structure quite often.
# To get some results it only adds to the sequence, no pop- or
# clear-operations.
#
proc thr_worker() {.gcsafe.}  =

  randomize()

  # thread-local Set[ptr int] for detached pointers of int
  #
  detached_ptrs = initHashSet[ptr int]()
  var detached_ptr: ptr int

  rcu_register()  # register thread with RCU
  let rcu_slot = rcu_id()
  var list_ptr = chan.recv()

  proc log( what: string, detail: string = "" ) =
    lchan.send Rec(
      tics:   now() - appstart,
      who:    rcu_slot,
      where:  "thread-fn",
      what:   what,
      detail: detail
    )

  while threads_work.load == on:

    rcu_enter() # announce start of the 'critical-section'

    let OP = random.sample @[ "push", "delay", "pop", "store" ]
    case OP:
      of "pop":
        list_ptr[].add( random.rand 10..20 )
        log( OP, &"{list_ptr[]}" )
        detached_ptr = list_ptr[][ rand(0 .. list_ptr[].high) ].addr
      of "push":
        list_ptr[].add( random.rand 100..110 )
        log( OP, &"{list_ptr[]}" )
      of "store":
        log( OP, &"{list_ptr[]}" )
      of "delay": # slow down
        detached_ptr = list_ptr[][0].addr
        log( OP, &"{list_ptr[]}" )
        #sleep rand 0..4
      else: discard

    rcu_exit() # announce end of 'critical-section'

    if OP in @[ "pop", "delay" ]:
      rcu_reclaim detached_ptr  # recyle/free in rcu_reclaim

  # end-of while-loop
  #
  if detached_ptrs.len > 0:
    var garbage = newSeq[uint64]()
    for p in detached_ptrs:
      garbage.add cast[uint64]( p )
    log( "error", &"{garbage}" )

  log( "quit", &"{list_ptr[]} {detached_ptrs.len}" )

  rcu_unregister() # unregister thread


proc main =

  var msgs: seq[Rec]
  msgs.add Rec(
    tics:    now() - appstart,
    who:     0,
    where:   "test_dummy",
    what:    "init"
  )
  rcu_init lchan.addr, appstart
  rcu_register()

  var ths: array[ 3, Thread[void] ]

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    chan.send global_list.addr
    #spawn thr_worker

  let ts = 1_000_000'i64 + now()
  while ts > now():
    let pkt = lchan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg

  chan.close()

  msgs.add Rec(
    tics:     now() - appstart,
    who:      0,
    where:    "main-fn",
    what:     "prepare quit"
  )
  threads_work.store off
  joinThreads ths

  # TODO: take care of Set-detached_ptrs ?
  rcu_unregister()

  # for i in 0 .. 2:
  #   #dbg &"thread-{i} running ? { ths[i].running }"
  #   doAssert( not ths[i].running )

  while true:
    let pkt = lchan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg
    else:
      lchan.close()
      break

  msgs.add Rec(
    tics:    now() - appstart,
    who:     0,
    where:   "main-fn",
    what:    "shutdown",
    detail:  &"{global_list} {detached_ptrs.len}"
  )

  sort(msgs) do (x, y: Rec) -> int:
    cmp( x.tics, y.tics )

  # termintable-API
  # https://xmonader.github.io/nim-terminaltables/api/terminaltables.html
  
  let tt = newUnicodeTable()
  tt.separateRows = true
  tt.setHeaders @[
    newCell "#" ,
    newCell "tics" ,
    newCell "who" ,
    newCell "where" ,
    newCell "what" ,
    newCell "detail"
  ]

  let start_t = msgs[0].tics
  var diff_t = 0
  for i,m in msgs:
    let who = if m.who == 0: "main" else: &"worker-{m.who}"

    tt.addRow @[ &"{i}", &"+{m.tics-diff_t}", who, m.where, m.what, m.detail ]

  tt.printTable
  #for m in msgs: dbg m

when isMainModule:
  main()
