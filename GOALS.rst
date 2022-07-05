Goals
=====

A. Understand the conceptual inner-workings of Read-Copy-Update and Hazard-Pointers. Idealy in 'slow-motion'-fashion, to be able to observe all events step-by-step.
B. Try to log and maybe visualize all events regarding allocation, recycling and destruction of (shared)-memory -> memory-reclamation.
C. Figure out if and how concurrent data-structures, that need some technique of memory-reclamation, can be implemented while respecting and using Nim's memory-semantics ?
D. Don't care for performance - if its correct in slo-mo, it ought to be ok at runtime.
