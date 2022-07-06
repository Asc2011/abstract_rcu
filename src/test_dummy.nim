import std / [ algorithm, atomics, monotimes, os, random, sets, strformat, threadpool ]
randomize()
import terminaltables

import abstract_rcu
from util import dbg, Rec, now

var threads_work: Atomic[ bool ]
threads_work.store on

# sends a pointer to every worker-thread
var thr_chan: Channel[ ptr seq[int] ]
thr_chan.open()

# log-channel
var log_chan: Channel[ Rec ]
log_chan.open()

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
  var list_ptr = thr_chan.recv()

  proc log( what: string, detail: string = "" ) =
    log_chan.send Rec(
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
      rcu_reclaim detached_ptr  # recycle/free pointer

  # end-of while-loop
  #
  if detached_ptrs.len > 0:
    var garbage = newSeq[uint64]()
    for p in detached_ptrs:
      garbage.add cast[uint64]( p )
    log( "error", &"{garbage}" )

  log( "exit", &"{list_ptr[]} {detached_ptrs.len}" )
  rcu_unregister() # unregister thread


proc main =
  #
  # keeps the log-records of the session.
  var msgs: seq[Rec]
  #
  msgs.add Rec(
    tics:    now() - appstart,
    who:     0,
    where:   "test_dummy.nim",
    what:    "init"
  )
  rcu_init log_chan.addr, appstart

  rcu_register()

  var ths: array[ 3, Thread[void] ]

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    thr_chan.send global_list.addr
    #spawn thr_worker

  let ts = 1_000_000'i64 + now()
  while ts > now():
    let pkt = log_chan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg

  thr_chan.close()

  threads_work.store off

  msgs.add Rec(
    tics:     now() - appstart,
    who:      0,
    where:    "main-fn",
    what:     "prepare join",
    detail:   "cleared 'threads_work'-condition."
  )
  #
  joinThreads ths
  #
  msgs.add Rec(
    tics:     now() - appstart,
    who:      0,
    where:    "main-fn",
    what:     "joined",
    detail:   "all 'thr_worker' have stopped."
  )
  # TODO: take care of Set-detached_ptrs ?
  rcu_unregister()

  for i in 0..2: doAssert( not ths[i].running )

  while true:
    let pkt = log_chan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg
    else:
      log_chan.close()
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
  #
  let table = newUnicodeTable()
  table.separateRows = true
  table.setHeaders @[
    newCell "#" ,
    newCell "app/ns" ,
    newCell "delta/ns" ,
    newCell "who" ,
    newCell "where" ,
    newCell "what" ,
    newCell "detail"
  ]

  var pred: int64 = msgs[0].tics
  for i,m in msgs:

    let who = if m.who == 0: "main" else: &"worker-{m.who}"

    let delta_t = m.tics - pred
    pred = m.tics

    let app_t = m.tics

    table.addRow @[
      &"{  i }",
      &"{  app_t }",
      &"+{ delta_t }",
      who,
      m.where,
      m.what,
      m.detail
    ]

  table.printTable
  #for m in msgs: dbg m

when isMainModule:
  main()
