## Abstract RCU

  1. [ ] find and use a memory-region where threads can concurrently operate on a data-structure.

  2. [ ] test if the simplest possible Nim-code actually works.


### Planned lockfree data-Structures

  - [x] A Dummy to test the setup in [`./test_dummy.nim`](test_dummy.nim)

#### Counter

  - [ ] as described in [Figure.3](./ds_rcu/counter.md). WIP needs a working abstract RCU. see above 1,2

#### List-type ( Linked-List )

#### Set-type ( Ordered-Set )

#### Mapping-type ( Table/Dictionary )

#### Tree-type ( HAMT or smth. from gh/fusion )