static:
  echo """
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    +                                                          +
    + This code shall not crash and always finish.             +
    +                                                          +
    + i used :                                                 +
    +                                                          +
    + nim r -d:size --threads:on --gc:ORC test_counter_FAA.nim +
    + nim r -d:size --threads:on --gc:ARC test_counter_FAA.nim +
    +                                                          +
    + runtime is ~750ms on my Intel-i5 from 2014.              +
    + prints out 50-60 entries to the output-table.            +
    +                                                          +
    ++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++
    """

import std/[ algorithm, os, random, sets, strformat, strutils, #[, threadpool ]# ]
randomize()

import threading/channels
import threading/atomics

import terminaltables
import util # dbg, Rec, now

import ds_rcu/counter_FAA

var
  appstart: int64       = now()      ## measured in monotimes.ticks
  duration: int64       = 350 * 1000 ## 500ms = 500_000 nanos
  global_counter        = Counter()  ## data for worker-threads
  threads_work: bool    = on         ## thread-worker flag
  thr_chan: Channel[ ptr Counter ]   ## sends ptr of global_counter to worker-threads
  log_chan: Channel[ Rec ]           ## logging channel
  thread_nr: Atomic[int]

thr_chan.open()
log_chan.open()

#
#
# Thread-Code workers
#
#
proc thr_worker() {.thread.}  =

  # waiting for the ptr to Counter
  #
  var counter_ptr = thr_chan.recv()

  thread_nr.atomicInc()
  let slot = thread_nr.load

  proc log( what: string, detail: string = "" ) =
    log_chan.send Rec(
      tics:   now() - appstart,
      who:    slot,
      where:  "thread-fn",
      what:   what,
      detail: detail
    )

  while threads_work:

    let OP = random.sample @[ "inc", "dec", "inc 2", "dec 2", "read" ]
    case OP:
      of "inc":
        log OP, &"{ counter_ptr[].inc }"
      of "dec":
        log OP, &"{ counter_ptr[].dec }"
      of "inc 2":
        log OP, &"{ counter_ptr[].inc 2 }"
      of "dec 2":
        log OP, &"{ counter_ptr[].dec 2 }"
      of "read":
        log OP, &"{ counter_ptr[].value.load SeqCst }"
      # of "reset":
      #   counter_ptr[].reset()
      #   log "0=reset", &"{counter_ptr[].repr}"
      of "delay":
        cpuRelax()
        log OP, &"{counter_ptr[].value.load}"
      else:
        log "noop", &"{counter_ptr[].value.load}"

  # end-of while-loop
  #
  log "exit", &"{counter_ptr[].value.load}"
#
# end-of Thread-Code workers
#


#
#  Main-Thread
#
proc main =

  # the log-records of this session.
  #
  var msgs: seq[Rec]

  msgs.add Rec(
    tics:    now() - appstart,
    who:     0,
    where:   "test_counter_FAA.nim",
    what:    "init",
    detail:  &"initial Counter : { global_counter.value.load }"
  )

  var ths: array[ 3, Thread[void] ]

  for i in 0 .. 2:
    createThread ths[i], thr_worker
    thr_chan.send global_counter.addr

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
    detail:  &"{global_counter[].repr}"
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
      "The timings don't reflect the precise ordering of events.",
      "There is no real memory-region 'freed', since no ",
      "destructive-operations performed on the global singleton Counter.",
      "This code uses atomic FetchAndAdd-/FetchAndSub-calls."
  ].join "\n"


when isMainModule:
  main()