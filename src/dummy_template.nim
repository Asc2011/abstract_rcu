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
    + runtime is ~750ms on my Intel-i5 from 2014.              +
    + prints out 50-60 entries to the output-table.            +
    +                                                          +
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    """

import std/[ algorithm, os, random, sets, strformat, strutils, #[, threadpool ]# ]
randomize()

import threading/channels
#import fusion/pools

import terminaltables

import abstract_rcu
import util # dbg, Rec, now

var
  appstart: int64       = now()      ## measured in monotimes.ticks
  duration: int64       = 500 * 1000 ## 500ms = 500_000 nanos
  global_list: seq[int] = @[1,2,3]   ## data for worker-threads
  threads_work: bool    = on         ## thread-worker flag
  thr_chan: Channel[ ptr seq[int] ]  ## sends ptr of global_list to worker-threads
  log_chan: Channel[ Rec ]           ## logging channel

thr_chan.open()
log_chan.open()

rcu_init log_chan.addr, appstart
#
#
# Thread-Code workers
#
#
proc thr_worker() {.gcsafe.}  =

  # waiting for the ptr to seq[int]
  #
  var list_ptr = thr_chan.recv()

  ## init thread-local Set[ptr int] for detached pointers
  #
  rcu_detached_ptrs = initHashSet[ ptr int ]()
  rcu_register()          ## register thread with RCU
  let rcu_slot = rcu_id() ## this threads rcu array-index 0..3


  proc log( what: string, detail: string = "" ) =
    log_chan.send Rec(
      tics:   now() - appstart,
      who:    rcu_slot,
      where:  "thread-fn",
      what:   what,
      detail: detail
    )

  proc random_pick: ptr int =
    random.sample( list_ptr[] ).unsafeAddr
  randomize()

  var a_pointer: ptr int

  while threads_work:

    a_pointer.reset
    rcu_enter() ## 'critical-section' begins

    let OP = random.sample @[ "push1", "push2", "push3", "noop", "delay" ]
    case OP:
      of "push1":
        list_ptr[].add( random.rand 0..9 )
        a_pointer = random_pick()
        log OP, &"{list_ptr[]} detached : {a_pointer.repr}"
      of "push2":
        list_ptr[].add( random.rand 10..20 )
        a_pointer = random_pick()
        log OP, &"{list_ptr[]} detached : {a_pointer.repr}"
      of "push3":
        list_ptr[].add( random.rand 100..110 )
        a_pointer = random_pick()
        log OP, &"{list_ptr[]} detached : {a_pointer.repr}"
      of "noop":
        cpuRelax()
        log OP, &"{list_ptr[]}"
      of "delay": # slow down, this should prolong 'grace-period'
        sleep rand 0..1
        log OP, &"{list_ptr[]}"
      # of "pop":
      # of "clear":
      else: discard

    rcu_exit() ## 'critical-section' ends

    if OP.startsWith "push":
      ## This disposes a pointer that points to e.g.
      ## a deleted member of a data-structure, but
      ## might be at-this-moment still
      ## referenced by other thr-readers.
      ## Passing it to rcu_reclaim( a_pointer )
      ## will trigger a call to rcu_synchronize()
      ## and thus guarantee, that all other thr-readers
      ## have finished.
      rcu_reclaim a_pointer

  # end-of while-loop
  #
  if rcu_detached_ptrs.len > 0:
    var garbage = newSeq[uint64]()
    for p in rcu_detached_ptrs:
      garbage.add cast[uint64]( p )
    log "error", &"! not-freed : {garbage} !"
  else:
    log( "exit", &"{list_ptr[]} not freed: {rcu_detached_ptrs.len}" )

  rcu_unregister() ## unregister thread
#
#
# end-of Thread-Code workers
#
#

#
#  Main-Thread
#
#
proc main =

  # the log-records of this session.
  #
  var msgs: seq[Rec]

  msgs.add Rec(
    tics:    now() - appstart,
    who:     0,
    where:   "test_dummy.nim",
    what:    "init",
    detail:  &"initial seq[int] : { global_list }"
  )

  rcu_register() # register main-thread

  var ths: array[ 3, Thread[void] ]

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    thr_chan.send global_list.addr
    #spawn thr_worker

  let end_t = now() + duration
  #
  while end_t > now():
    let pkt = log_chan.tryRecv()
    if pkt.dataAvailable:
      msgs.add pkt.msg

  threads_work = off
  thr_chan.close()

  msgs.add Rec(
    tics:     now() - appstart,
    who:      0,
    where:    "main-fn",
    what:     "prepare join",
    detail:   "cleared 'threads_work'-flag."
  )

  joinThreads ths
  rcu_unregister()
#
#
#  end-of Main-Thread
#
#

  msgs.add Rec(
    tics:     now() - appstart,
    who:      0,
    where:    "main-fn",
    what:     "joined",
    detail:   "all 'thr_worker' have stopped."
  )

  for i in 0..2: doAssert( not ths[i].running, &"thread-{i} still alive ?" )

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
    detail:  &"{global_list} {rcu_detached_ptrs.len}"
  )

  sort(msgs) do (x, y: Rec) -> int:
    cmp( x.tics, y.tics )

  # terminaltables-API
  # https://xmonader.github.io/nim-terminaltables/api/terminaltables.html
  #
  let table = newUnicodeTable()
  table.separateRows = true
  table.setHeaders @[
    newCell "#" ,           ## step-counter
    newCell "app/ns" ,      ## nanos / appstart_t = 0
    newCell "delta/ns" ,    ## e.g ( step-4_t - step-3_t )
    newCell "who" ,         ## thread_id [0..3], with main-thr always=0
    newCell "where" ,       ## code-location
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
      &"{  i        }",
      &"{  app_t    }",
      &"+{ delta_t  }",
      who,
      m.where,
      m.what,
      m.detail
    ]

  table.printTable

  echo @[
      "The contents of this table are strictly 'not correct'. ",
      "It must show garbled and distorted data to makes sense.",
      "The timings don't reflect the precise ordering of events.",
      "There is no real memory-region 'freed', since no destructive-operations .pop() are performed on the seq[int].",
      "This makes the code currently rather a showcase. "
  ].join "\n"


when isMainModule:
  main()