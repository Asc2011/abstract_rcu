
Figure-2 from page 7
---------------------

![Figure 2, page 7!](../assets/abstract_rcu_figure_2.png)


Changes and limitations to the Pseudo-/C-code
----------------------------------------------

- all RCU-related procedures are prefixed `rcu_`
- renamed:
  - procedure `sync` to `rcu_synchronize`.
  - the `r`-array-of-bool to `registered` from procedure-`sync` resp. `rcu_synchronize`.
- added `rcu_register`/`rcu_unregister`-procedures to register threads wanting to participate in RCU.
- will break with runtime-error, in case :
  - more than four threads attempts to register.
  - a not formerly registered thread tries to participate.
- added procedures for logging purposes:
  - `rcu_info(): string` returns array-slot-number and OS-thread-id.
  - `rcu_init( ch: ptr Channel[ Rec ], start: int64 )` passes a log-channel and starttime in ticks.
  - `rcu_id(): int` returns the threads array-slot-number.
- added a Thread-Array `TArray`-struct :
  - it is fixed-sized `N=4`. So at most four threads can participate.
  - keeps the thread's id from the operating-system in member `TArray.os_id`.
  - keeps the registered threads from `rcu[N]`-array-of-bool in member `TArray.slots`.