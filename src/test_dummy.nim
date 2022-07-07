static:
  echo """
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    +                                                          +
    + This code is will frequently crash and sometimes finish. +
    +                                                          +
    + Retry often until it does.                               +
    +                                                          +
    + i used :                                                 +
    +                                                          +
    + nim r -d:size --threads:on --gc:ORC test_dummy.nim       +
    + nim r -d:size --threads:on --gc:boehm test_dummy.nim     +
    +                                                          +
    + runtime is ~650ms on my Intel-i5 from 2014.              +
    + prints 50-60 entries in the output-table.                +
    +                                                          +
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    """

import std / [ algorithm, #[ os, ]# random, sets, strformat #[, threadpool ]# ]
randomize()
import terminaltables

import abstract_rcu
from util import dbg, Rec, now

var threads_work: bool = on

# sends a pointer to every worker-thread
var thr_chan: Channel[ ptr seq[int] ]
thr_chan.open()

# log-channel
var log_chan: Channel[ Rec ]
log_chan.open()

var global_list = @[1,2,3,4,5]
var appstart = now()
#
# The test_dummy rocks over a not-threadsafe seq[int] and breaks
# the data-structure quite often.
# To get some results it only .adds to the sequence, no pop- or
# clear-operations.
#
proc thr_worker() {.gcsafe.}  =

  randomize()

  # thread-local Set[ptr int] for detached pointers
  #
  detached_ptrs = initHashSet[ptr int]()
  var detached_ptr: ptr int

  rcu_register()          # register thread with RCU
  let rcu_slot = rcu_id() # this threads array-index 0..3
  var list_ptr = thr_chan.recv() # waiting for ptr to seq[int]

  proc log( what: string, detail: string = "" ) =
    log_chan.send Rec(
      tics:   now() - appstart,
      who:    rcu_slot,
      where:  "thread-fn",
      what:   what,
      detail: detail
    )

  while threads_work:

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
      of "delay": # slow down, should defer other threads
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
    log( "error", &"! not-freed : {garbage} !" )

  log( "exit", &"{list_ptr[]} not freed: {detached_ptrs.len}" )
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
    what:    "init",
    detail:  &"initial seq[int] : { global_list }"
  )
  #
  # only to the pass log-channel.
  # no more to init in abstract_rcu.
  #
  rcu_init log_chan.addr, appstart
  rcu_register() # register main-thread

  var ths: array[ 3, Thread[void] ]

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    thr_chan.send global_list.addr
    #spawn thr_worker

  # app should stop after ~500-millies
  #
  let ts = 500_000'i64 + now()

  while ts > now():
    let pkt = log_chan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg

  thr_chan.close()

  threads_work = off

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

  # terminaltables-API
  # https://xmonader.github.io/nim-terminaltables/api/terminaltables.html
  #
  let table = newUnicodeTable()
  table.separateRows = true
  table.setHeaders @[
    newCell "#" ,           # step-counter
    newCell "app/ns" ,      # nanos / appstart_t = 0
    newCell "delta/ns" ,    # delta_t = ( step-4_t - step-3_t )
    newCell "who" ,         # thread_id [0..3], main is always '0'
    newCell "where" ,       # code-location
    newCell "what" ,
    newCell "detail"
  ]

  var pred: int64 = msgs[0].tics
  for i, m in msgs:

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

  echo "The contents of the table are not 'correct'. \nThe timings don't reflect the precise ordering of events. \nTheres no memory-region 'freed', since no .pop-/.clear-operations are performed on the seq.\nThis makes this code currently rather a simulation.. "

when isMainModule:
  main()
