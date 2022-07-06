
Figure-2 from page 7
---------------------

![Figure 2, page 7!](../assets/abstract_rcu_figure_2.png)


Changes and limitations to the Pseudo-/C-code
----------------------------------------------

- all RCU-related procedures are prefixed `rcu_`
- renamed:
  - procedure Pseudo-`sync` to `rcu_synchronize()`.
  - the `r`-array-of-bool to `registered: array[4, bool]` from Pseudo-`sync` resp. nim-`rcu_synchronize()`.
  - the Set-of-detached-pointers from Pseudo-`detached` to `detached_ptrs: HashSet[ptr int]`
- added `rcu_register()`/`rcu_unregister()`-procedures to register threads wanting to participate in RCU.
- will break at runtime, in case :
  - more than four threads attempts to register with RCU.
  - a not formerly registered thread tries to participate.
- added informal procedures for logging purposes:
  - `rcu_info(): string` returns array-slot-number and OS-thread-id.
  - `rcu_init( ch: ptr Channel[ Rec ], start: int64 )` passes a log-channel and starttime in ticks.
  - `rcu_id(): int` returns the threads array-slot-index.
- added a Thread-Array `TArray`-struct :
  - it is fixed-sized `N=4`. So at most four threads can participate.
  - keeps the thread's id from the operating-system in member `TArray.os_id`.
  - keeps the registered threads from Pseudo-`rcu[N]`-array-of-bool in member `TArray.slots`.