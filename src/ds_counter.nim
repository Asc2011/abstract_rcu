type
  Counter* = ref object
    value: Atomic[ ptr int ]

proc CAS(
    location: var Atomic[ptr int],
    expected: var ptr int,
    desired:  var ptr int
): bool =
  location.compareExchange( expected, desired, moAcquire, moRelease )

proc read*( counter: var Counter ): int =
  counter.value.load( moRelaxed )[]

#[ Figure.3, page-7, right, Counter

  int inc() {
    int v, *n, *s;
    n = new int; rcu_enter();
    do {
      rcu_exit();
      rcu_enter();
      s = C;
      v = *s;
      *n = v+1;
    } while ( !CAS(&C,s,n) );

    rcu_exit();
    reclaim(s);
    return v;
  }
]#
proc inc*( counter: var Counter ): int =

  var new_int_ptr = createShared( int, sizeof( int ) )

  dbg &"new_int_ptr : { new_int_ptr.repr } | value = { new_int_ptr[] }"

  rcu_enter()

  var old_int_ptr = counter.value.load moAcquire
  #dbg "old_int_ptr : { old_int_ptr.repr }"
  new_int_ptr[] = old_int_ptr[] + 1
  #dbg &"new_int_ptr : { new_int_ptr.repr } | value = { new_int_ptr[] }"

  repeat_until CAS( counter.value, old_int_ptr, new_int_ptr ):
    rcu_exit()
    rcu_enter()
    # TODO: CAS should update the location. on failure - maybe not needed ?
    old_int_ptr = counter.value.load moAcquire
    new_int_ptr[] = old_int_ptr[] + 1

  rcu_exit()
  rcu_reclaim old_int_ptr

  return counter.read()
