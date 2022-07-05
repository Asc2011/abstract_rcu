import std / [ atomics, strformat ]

from util import dbg
#[
  This is strictly a proof-of-concept and not intended for other purposes than
  exploring and understanding the concept behind Read-Copy-Update (RCU).
  And understanding of Nim's memory semantics.
  Consider the code-examples as experimental prototypes. Maybe over time it
  grows into a workbench for concurrent data-structures.
  Try this [Userspace-RCU]( http://liburcu.org ) library for real purposes.
]#
proc rcu_register*()    # every threads must register with RCU on thread-creation.
proc rcu_unregister*()  # every thread should deregister before thread destruction.
proc rcu_enter*()       # signal the begin of a critical-section.
proc rcu_exit*()        # signal the end of a critical-section.
proc rcu_synchronize*() # synchronize with other threads. Starts of 'grace-period'.

proc rcu_reclaim*( old_int_ptr: ptr int ) # takes a detached pointer for later disposal.
proc rcu_info(): string # returns the threads-id and index in the thread-array.


proc os_thread_id(): int = getThreadId()

# Set for detached-pointers for deferred/later reclamation.
# Needs initialization at the start of any worker-thread-function.
#
var detached* {.threadvar.}: seq[ptr int]

type TArray = object
  #
  # Maps the os_thread_id to a array-slot-idx 0..3
  # slots[0..3] expresses the fact, that a thread is in a critical-section.
  # Allows for four threads 0..3 at most.
  #
  pos: Atomic[ int ]
  slots: array[ 4, bool ]
  os_id: array[ 4,  int ]

proc slot( ta: TArray ): int =
  #
  # returns the slot-position of the current thread.
  #
  let thread_id:int = os_thread_id()
  for idx in 0 .. 3:
    if ta.os_id[ idx ] == thread_id: return idx

  doAssert( false, &"slot:: unknown thread-{ os_thread_id() } ! Maybe thread has not registered ?" )

proc add( ta: var TArray ) =
  #
  # registers the calling thread into a empty array-slot.
  #
  var slot = ta.pos.load
  ta.pos.atomicInc

  doAssert( slot < 4, &"All four slots in use. Cannot register more threads. was: { os_thread_id() }")

  ta.slots[ slot ] = off
  ta.os_id[ slot ] = os_thread_id()

proc rem( ta: var TArray ) =
  let slot = ta.slot()
  ta.slots[ slot ] = off
  ta.os_id[ slot ] = -1

proc unset( ta: var TArray ) =
  #
  # sets the calling threads-slot to FALSE.
  # Marks the end of a critical-section.
  #
  let thread_id = os_thread_id()
  for idx in 0 .. 3:
    if ta.os_id[ idx ] == thread_id:
      ta.slots[ idx ] = false
      return

  doAssert( false, &"unset:: Unknown thread-{thread_id}." )

proc set( ta: var TArray ) =
  #
  # sets the calling threads-slot to TRUE.
  # Marks the begin of a critical-section.
  #
  let idx = ta.slot()
  doAssert( ( idx in  0..3  ) , &"set:: thread-{ os_thread_id() } not found. Maybe not registered ?" )
  ta.slots[ idx ] = true


# the global thread-array
#
var thread_arr = TArray()

proc rcu_register()    = thread_arr.add()
proc rcu_enter()       = thread_arr.set()
proc rcu_exit()        = thread_arr.unset()
proc rcu_unregister()  =
  # TODO: test if clean-up/flush of detached-pointers
  # has to be done.
  thread_arr.rem()

proc rcu_info(): string =
  let slot = thread_arr.slot()
  result = &"os-id: { thread_arr.os_id[ slot ] }, slot: {slot}"

proc rcu_synchronize() =
  #
  # lockfree synchronization
  #
  dbg "synchronize -> ", thread_arr.slots

  var registered: array[ 4, bool ]
  for idx in 0 .. 3:
    registered[ idx ] = thread_arr.slots[ idx ]

  for idx in 0 .. 3:
    if registered[ idx ] == true:

      while thread_arr.slots[ idx ] == true:
        discard
      # dbg &"<- {idx}-thread leaves synchronize"

#[ Figure.2, left-side
  int *C = new int(0);
  bool rcu[N] = {0};
  Set detached[N] = {∅};

  void reclaim(int* s) {
    insert(detached[tid-1], s);
    if (nondet()) return;
    sync();
    while ( !isEmpty(detached[tid]) )
      free( pop(detached[tid]));
  }
]#
proc rcu_reclaim( old_int_ptr: ptr int) =

  # stores a detached-pointer in the thread-local Set 'detached' for later reclamation.
  #
  detached.add( old_int_ptr )

  dbg &"thread-{rcu_info()} detached pointer: { old_int_ptr.repr }"
  #
  # ?? if nondet(): return ?? unclear..
  # TODO: some random condition
  #
  rcu_synchronize()
  while detached.len > 0:
    freeShared[int]( detached.pop )


#[

template critical_section*( code: untyped ) =

  rcu_enter()
  try:
    proc rcu_synchronize() {.error: "rcu_synchronize() is forbidden inside a critical-section".} = echo "call rcu_synchronize() AFTER a critical-section, but NOT from inside."
    #proc defer_rcu( cb: rcu_cb, p: pointer ) {.error: "defer_rcu() is forbidden inside a critical-section".} = echo "call defer_rcu() AFTER a critical-section, but NOT from inside."
    #proc dereference( p: pointer ):pointer = rcu_dereference_sym p

    code

  finally:
    rcu_exit()

 ]#



