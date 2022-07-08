Goals
=====

A. Understand the conceptual inner-workings of Read-Copy-Update and Hazard-Pointers. Idealy in 'slow-motion'-fashion, to be able to observe all events step-by-step.
B. Try to log and maybe visualize all events regarding alloccation, reclamation and freeing of (shared)-memory.
C. Figure out if and how concurrent data-structures, that need some technique of memory-reclamation, can be implemented while respecting and using Nim's memory-semantics including the facilities of ARC/ORC ?
D. Don't care for performance - if its correct in slo-mo, it ought to be ok at runtime.
E. If it enhances readabillity than {.magic.} is ok too
