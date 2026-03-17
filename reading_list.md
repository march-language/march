# March Language — PLT Reading List

A map from March's major language features to foundational papers, books, and articles. Intended as a self-directed PLT curriculum organized around the language you're building.

Each section pairs the academic source with something more approachable — a blog post, a talk, or documentation.

---

## 1. Hindley-Milner Type Inference

**What March does:** Core type inference; type variables, let-polymorphism, unification.

| Resource | Kind | Notes |
|---|---|---|
| [Milner — *A Theory of Type Polymorphism in Programming* (1978)](https://homepages.inf.ed.ac.uk/wadler/papers/papers-we-love/milner-type-polymorphism.pdf) | Paper | The original HM paper. Dense but worth reading. |
| [Damas & Milner — *Principal Type-Schemes for Functional Programs* (POPL 1982)](https://people.eecs.berkeley.edu/~necula/Papers/DamasMilnerAlgoW.pdf) | Paper | The "Algorithm W" paper — the practical formulation most implementations follow. |
| [Cardelli — *Basic Polymorphic Typechecking* (1987)](http://lucacardelli.name/Papers/BasicTypechecking.pdf) | Paper | Gentler exposition of Algorithm W with worked examples. Best entry point to the literature. |
| Pierce, B. — *TAPL*, Ch. 22–23 | Book | The standard textbook treatment. |
| [Heeren et al. — *Generalizing Hindley-Milner Type Inference Algorithms* (2002)](https://www.cs.uu.nl/research/techreps/repo/CS-2002/2002-031.pdf) | Paper | Reformulates HM as constraint generation + solving; maps directly to modern compiler structure. |
| [Nystrom — *Crafting Interpreters*, Ch. 30 (Type Inference)](https://craftinginterpreters.com) | Book/Web | Free online. The most readable step-by-step walk through implementing HM inference. |
| Diehl — *Write You a Haskell* (type inference chapters) | Blog | A worked Haskell implementation of Algorithm W with clear prose. Search: "Write You A Haskell type inference" (Diehl). |

---

## 2. Bidirectional Type Checking

**What March does:** At annotated positions, the expected type flows inward ("checking mode") rather than being inferred bottom-up.

| Resource | Kind | Notes |
|---|---|---|
| [Pierce & Turner — *Local Type Inference* (TOPLAS 2000)](https://www.cis.upenn.edu/~bcpierce/papers/lti-toplas.pdf) | Paper | The foundational paper. Distinguishes "infer" from "check" modes. |
| [Dunfield & Krishnaswami — *Bidirectional Typing* (CSUR 2021)](https://arxiv.org/abs/1908.05839) | Paper | Comprehensive modern survey. Read after Pierce & Turner. |
| [Dunfield & Pfenning — *Tridirectional Typechecking* (POPL 2004)](https://research.cs.queensu.ca/home/jana/papers/tridirectional-typechecking/Dunfield04_tridirectional.pdf) | Paper | Extends to refinement types; shows where the technique goes. |
| Christiansen — *Bidirectional Type Checking* | Blog | Blog post with diagrams and worked examples. Very accessible. Search: "David Christiansen bidirectional type checking." |
| [Kovacs — *elaboration-zoo*](https://github.com/AndrasKovacs/elaboration-zoo) | Code | GitHub repo with small, runnable bidirectional type checkers in Haskell. Concrete implementations trump prose. |

---

## 3. Linear and Affine Types

**What March does:** `linear` = used exactly once; `affine` = used at most once. Ownership transfer, safe mutation, statically-verified resource cleanup.

| Resource | Kind | Notes |
|---|---|---|
| Girard — *Linear Logic* (1987) | Paper | The origin. Proof-theoretic; gives you the "why." ScienceDirect open archive — no standalone free PDF. |
| Wadler — *Linear Types Can Change the World!* (1990) | Paper | More accessible than Girard. Author's page has PostScript only: https://homepages.inf.ed.ac.uk/wadler/papers/linear/linear.ps |
| Walker — *Substructural Type Systems* in ATTAPL, Ch. 1 | Book | Covers linear, affine, and relevant types uniformly. |
| [Bernardy et al. — *Linear Haskell* (POPL 2018)](https://arxiv.org/abs/1710.09756) | Paper | Retrofitting linearity into a functional language. Very relevant to March's design. |
| Willsey — *A Gentle Introduction to Linear Types* | Blog | Accessible blog post, no prior PL theory needed. Search: "gentle introduction linear types" on lobste.rs. |
| [*Rust Book*, Ch. 4 — Ownership](https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html) | Docs | The most widely-read practical treatment of linear/affine types without the jargon. |

---

## 4. Algebraic Data Types and Pattern Matching

**What March does:** Sum types with capitalized constructors, product types as records, exhaustiveness checking, guards.

| Resource | Kind | Notes |
|---|---|---|
| Pierce — *TAPL*, Ch. 11 & 23 | Book | Products, sums, recursive types. |
| [Maranget — *Warnings for Pattern Matching* (JFP 2007)](http://moscova.inria.fr/~maranget/papers/warn/warn.pdf) | Paper | The algorithm behind exhaustiveness checking in most ML compilers. |
| Scott & Ramsey — *When Do Match-Compilation Heuristics Matter?* (2000) | Paper | Decision trees vs. backtracking automata for compiling match. Search on citeseer. |
| Yallop — *Practical Pattern Matching* (talk, OCaml 2016) | Talk | Accessible explanation of how OCaml compiles pattern matching. Available on YouTube. |
| [*OCaml Manual* — Variant types and pattern matching](https://v2.ocaml.org/api/) | Docs | The closest production language to March's ADT design. |

---

## 5. Typeclasses / Interfaces

**What March does:** `interface` + `impl`, conditional instances, associated types, coherence (no orphan instances).

| Resource | Kind | Notes |
|---|---|---|
| [Wadler & Blott — *How to Make Ad-hoc Polymorphism Less Ad Hoc* (POPL 1989)](https://dl.acm.org/doi/pdf/10.1145/75277.75283) | Paper | The original typeclass paper. Short and clear. Read this first. |
| [Jones — *A System of Constructor Classes* (FPCA 1993)](https://www.cs.tufts.edu/comp/150GIT/archive/mark-jones/fpca93.pdf) | Paper | Higher-kinded typeclasses; background for `Collection(f)` style interfaces. |
| [Oliveira et al. — *Type Classes as Objects and Implicits* (OOPSLA 2010)](https://infoscience.epfl.ch/server/api/core/bitstreams/aa4aca97-f310-447a-b12f-7e9232e30c02/content) | Paper | Connects typeclasses to implicit arguments. |
| Kmett — *Type Classes vs. The World* (talk, 2014) | Talk | Excellent talk on typeclass design tradeoffs. Available on YouTube. |
| [Yorgey — *The Typeclassopedia* (Haskell Wiki, 2009)](https://wiki.haskell.org/Typeclassopedia) | Blog/Wiki | Walks through Haskell's core typeclasses. More applied than theoretical. |
| [Rust Reference — *Traits*](https://doc.rust-lang.org/reference/items/traits.html) | Docs | How Rust's trait system works in practice; the implementation most similar to March's. |

---

## 6. Module Systems and Signatures

**What March does:** `mod`/`sig` separation; signatures have their own content hash; downstream caches depend on sigs, not impls.

| Resource | Kind | Notes |
|---|---|---|
| [Leroy — *Manifest Types, Modules, and Separate Compilation* (POPL 1994)](https://xavierleroy.org/publi/manifest-types-popl.pdf) | Paper | Theory behind ML-style signatures and separate compilation. Directly relevant to March's sig-hash design. |
| Harper & Pierce — *Design Considerations for ML-Style Module Systems* in ATTAPL, Ch. 8 | Book | The authoritative survey. Explains why March chose interfaces over functors. |
| [Rossberg — *1ML — Core and Modules United* (ICFP 2015)](https://people.mpi-sws.org/~rossberg/papers/Rossberg%20-%201ML%20--%20Core%20and%20modules%20united.pdf) | Paper | Unifying core and module levels; interesting for understanding the design space March opted out of. |
| [Leroy — *A Modular Module System* (JFP 2000)](https://xavierleroy.org/publi/modular-modules-jfp.pdf) | Paper | More digestible than the POPL 1994 paper; practical implementation focus. |
| [OCaml Manual — *Module System*](https://v2.ocaml.org/manual/modules.html) | Docs | The practical reference. |

---

## 7. Session Types

**What March does:** Binary session types on `Chan(P, e)` values; protocol descriptions verified at compile time; epoch-stamped channels for failure handling.

| Resource | Kind | Notes |
|---|---|---|
| [Honda — *Types for Dyadic Interaction* (CONCUR 1993)](https://citeseerx.ist.psu.edu/document?repid=rep1&type=pdf&doi=2a73e90ccc6b4c646768a25571ea6e02203613d8) | Paper | The original session types paper. |
| [Honda et al. — *Language Primitives and Type Discipline for Structured Communication-Based Programming* (ESOP 1998)](https://www.di.fc.ul.pt/~vv/papers/honda.vasconcelos.kubo_language-primitives.pdf) | Paper | Closer to a practical language design. |
| [Wadler — *Propositions as Sessions* (ICFP 2012)](https://homepages.inf.ed.ac.uk/wadler/papers/propositions-as-sessions/propositions-as-sessions.pdf) | Paper | Connects session types to linear logic via Curry-Howard. Beautiful paper. |
| [Honda et al. — *Multiparty Asynchronous Session Types* (POPL 2008)](https://www.doc.ic.ac.uk/~yoshida/multiparty/multiparty.pdf) | Paper | The MPST paper March defers to post-v1. Essential reading when you get there. |
| [Lindley & Morris — *A Semantics for Propositions as Sessions* (ESOP 2015)](https://jgbm.github.io/pubs/lindley-esop15-propositions.pdf) | Paper | Refines Wadler's approach; more implementation-oriented. |
| Lindley — *Talk: Propositions as Sessions* (2012) | Talk | The companion talk to Wadler's paper; clearer than reading the paper alone. Search on YouTube. |
| [Ancona et al. — *Behavioral Types in Programming Languages* (Foundations and Trends, 2016)](https://iris.unito.it/bitstream/2318/1610205/1/2500000031-Ancona-Vol3-PGL-031.pdf) | Survey | A readable survey of all behavioral type approaches including session types. Good map of the landscape. |

---

## 8. Actor Model and Capability Security

**What March does:** Share-nothing actors, `Pid(a)`, `Cap(A, e)` unforgeable capabilities, capability-secure messaging (no ambient authority).

| Resource | Kind | Notes |
|---|---|---|
| Hewitt et al. — *A Universal Modular ACTOR Formalism* (IJCAI 1973) | Paper | The original actors paper. Historical. Search citeseer. |
| Miller — *Robust Composition* (PhD thesis, 2006) | Thesis | The object-capability model thesis; the intellectual foundation for `Cap`. Search "Mark Miller Robust Composition thesis" — freely available. |
| [Miller et al. — *Capability Myths Demolished* (2003)](https://srl.cs.jhu.edu/pubs/SRL2003-02.pdf) | Paper | Short paper debunking capability misconceptions. Read before implementing. |
| Armstrong — *Making Reliable Distributed Systems in the Presence of Software Errors* (PhD thesis, 2003) | Thesis | The Erlang/OTP thesis. Highly readable. Search "Joe Armstrong PhD thesis Erlang" — freely available. |
| Mark Miller — *The Object-Capability Model* (talk, Strange Loop 2013) | Talk | The best accessible introduction to capability security. Available on YouTube. |
| [*The E Language* website](https://erights.org) | Docs | E is the primary reference implementation of object-capabilities. |
| Armstrong — *Programming Erlang*, Ch. 23 (Error Handling in Concurrent Programs) | Book | Practical treatment of how Erlang's supervision actually works. |

---

## 9. Supervision Trees and Fault Tolerance

**What March does:** `one_for_one`/`one_for_all`/`rest_for_one`; epoch-stamped capabilities; protocol epochs (epochs-design.md).

| Resource | Kind | Notes |
|---|---|---|
| Armstrong et al. — *Concurrent Programming in Erlang* (1996) | Book | Part II on OTP is most relevant. The original description of supervision trees. |
| [Tasharofi et al. — *Why Do Scala Developers Mix the Actor Model with Other Concurrency Models?* (ECOOP 2013)](http://publish.illinois.edu/science-of-security-lablet/files/2014/06/Why-Do-Scala-Developers-Mix-the-Actor-Model-with-other-Concurrency-Models.pdf) | Paper | Empirical study of actor failure modes; useful for understanding what March's design prevents. |
| Virding — *A History of Erlang* (HOPL 2020) | Paper | How Erlang's reliability model evolved from practice, not theory. Search ACM DL. |
| [*Akka Documentation* — Supervision and Fault Tolerance](https://doc.akka.io/docs/akka/current/typed/fault-tolerance.html) | Docs | The most widely-read practical description of supervision trees outside Erlang. |
| [Fred Hebert — *Learn You Some Erlang*, Ch. 18 (Supervisors)](https://learnyousomeerlang.com/supervisors) | Book/Web | Free online. The clearest practical introduction to OTP supervision. |

---

## 10. Perceus Reference Counting and FBIP

**What March does:** Non-linear heap values managed by Perceus RC; FBIP allows functional updates to reuse memory in-place.

| Resource | Kind | Notes |
|---|---|---|
| [Reinking et al. — *Perceus: Garbage Free Reference Counting with Reuse* (PLDI 2021)](https://www.microsoft.com/en-us/research/uploads/prod/2021/06/perceus-pldi21.pdf) | Paper | **Mandatory reading.** This is the exact algorithm March uses. |
| [Lorenzen & Leijen — *Reference Counting with Frame-Limited Reuse* (Haskell Sym. 2022)](https://www.microsoft.com/en-us/research/wp-content/uploads/2021/11/flreuse-tr-v1.pdf) | Paper | Extends FBIP; discusses the "frame-limited" variant. |
| [Ullrich & de Moura — *Counting Immutable Beans* (IFL 2019)](https://arxiv.org/abs/1908.05647) | Paper | Lean 4's RC design, closely related to Perceus. |
| Leijen — *Koka: Programming with Row-polymorphic Effect Types* (MSFP 2014) | Paper | Koka is where Perceus originated; gives language context. Search "Daan Leijen Koka MSFP 2014." |
| [*Koka Language Website*](https://koka-lang.github.io) | Docs | Reference with documentation on Perceus and FBIP. |
| Leijen — *Perceus: An Introduction* (Microsoft Research blog) | Blog | The author's own accessible write-up. Easier entry than the PLDI paper. Search: "Daan Leijen Perceus blog." |

---

## 11. Defunctionalization

**What March does:** Higher-order functions compiled to a tagged union + `apply` dispatch; eliminates heap-allocated closures and indirect calls.

| Resource | Kind | Notes |
|---|---|---|
| [Reynolds — *Definitional Interpreters for Higher-Order Programming Languages* (1972, reprinted 1998)](https://homepages.inf.ed.ac.uk/wadler/papers/papers-we-love/reynolds-definitional-interpreters-1998.pdf) | Paper | The original paper introducing defunctionalization. |
| [Danvy & Nielsen — *Defunctionalization at Work* (PPDP 2001)](https://www.brics.dk/RS/01/23/BRICS-RS-01-23.pdf) | Paper | Practical treatment; interactions with CPS transforms and partial evaluation. |
| Danvy — *On Evaluation Contexts, Continuations, and the Rest of the Computation* (talk) | Talk | Danvy's accessible lectures on defunctionalization are on YouTube. |
| Nielsen — *A Study of Defunctionalization and Continuation-Passing Style* (PhD thesis, 2003) | Thesis | Thorough if you want depth. Search BRICS technical reports. |
| Krishnaswami — *Defunctionalization* (blog post) | Blog | Short, clear post connecting defunctionalization to Scott encodings. Search: "Neel Krishnaswami defunctionalization." |

---

## 12. Whole-Program Monomorphization

**What March does:** All polymorphic functions specialized to concrete type arguments; no runtime dictionaries; cached by (function hash, type args).

| Resource | Kind | Notes |
|---|---|---|
| [Tarditi et al. — *TIL: A Type-Directed Optimizing Compiler for ML* (PLDI 1996)](https://www.cs.cmu.edu/~rwh/papers/til/pldi96.pdf) | Paper | Classic ML-to-native compiler; monomorphization as a key pass. |
| Fluet & Weeks — *Contification Using Dominators* (ICFP 2001) | Paper | MLton paper; MLton is the reference implementation of whole-program monomorphization for ML. Search ACM DL. |
| [*MLton Compiler* — Design docs](http://mlton.org/References.attachments/060916-mlton.pdf) | Docs | Practical notes on the monomorphization strategy March emulates. |
| [Russ Cox — *Go Data Structures: Interfaces*](https://research.swtch.com/interfaces) | Blog | Explains the dictionary-passing approach as contrast; helps you understand what monomorphization avoids. |

---

## 13. Type-Level Naturals (Sized Types)

**What March does:** `Vector(n, a)`, `Matrix(m, n, a)`; type-level `+` and `*`; constraint solver for nat equations; deliberately not full dependent types.

| Resource | Kind | Notes |
|---|---|---|
| [Hughes et al. — *Proving the Correctness of Reactive Systems Using Sized Types* (POPL 1996)](https://dl.acm.org/doi/pdf/10.1145/237721.240882) | Paper | Original sized types paper — types indexed by natural numbers. |
| [Brady et al. — *Inductive Families Need Not Store Their Indices* (TYPES 2003)](http://www.e-pig.org/downloads/indfam.pdf) | Paper | How to compile indexed types without runtime overhead. |
| [Eisenberg et al. — *Dependently Typed Programming with Singletons* (Haskell Sym. 2012)](https://www.seas.upenn.edu/~sweirich/papers/haskell12.pdf) | Paper | Haskell approach to type-level naturals; illuminates what March does (and doesn't) do. |
| [Kuper — *Intro to Dependent Types* (blog series)](http://composition.al) | Blog | Accessible series on dependent types, with Idris examples. Good background for understanding what March deliberately avoids. |
| [*Idris 2 Tutorial* — Dependent Types](https://idris2.readthedocs.io) | Docs | Hands-on: what full dependent types look like in practice. Useful contrast. |

---

## 14. Query-Based / Demand-Driven Compiler Architecture

**What March does:** Compilation as a graph of memoized queries; incremental recompilation; content-addressed results.

| Resource | Kind | Notes |
|---|---|---|
| [Konat et al. — *PIE: A Domain-Specific Language for Interactive Software Development Pipelines* (Programming 2018)](https://arxiv.org/abs/1803.10197) | Paper | Formalizes the demand-driven build model. |
| Erdweg et al. — *Towards Language-Independent Incremental Builds* (2015) | Paper | Theoretical framing of demand-driven builds. Search "Erdweg incremental builds 2015." |
| [*The Rust Compiler's Query System*](https://rustc-dev-guide.rust-lang.org/query.html) | Docs | The most concrete description of the architecture March is emulating. |
| [*Salsa* — documentation and design notes](https://salsa-rs.github.io/salsa/) | Docs/Blog | The framework Rust's incremental compiler is built on. |
| Matsakis — *Salsa: Incremental Recompilation* (RustConf 2019) | Talk | The best accessible explanation of query-based compilation. Available on YouTube. |

---

## 15. Content-Addressed Code

**What March does:** Every definition identified by hash of its AST; names are aliases; signatures have separate hashes; no dependency conflicts.

| Resource | Kind | Notes |
|---|---|---|
| [Chiusano — *Unison: A New Approach to Distributed Programming*](https://www.unison-lang.org/learn/) | Blog/Docs | Unison is the existence proof. The design docs are the primary resource. |
| [*Unison Language Reference* — Names are not the thing](https://www.unison-lang.org/docs/the-big-idea/) | Docs | The specific doc on how content-addressing changes what "naming" means. |
| Lamport — *The Part-Time Parliament* (TOCS 1998) | Paper | Content addressing in distributed consensus. Search "Lamport Part-Time Parliament" — freely available on Lamport's website. |

---

## 16. Error Recovery and Typed Holes

**What March does:** Parse/type errors become typed holes; holes infer their expected type from bidirectional checking; user-written `?` uses the same mechanism.

| Resource | Kind | Notes |
|---|---|---|
| Norell — *Dependently Typed Programming in Agda* (AFP 2008) | Paper | Agda's interactive development via holes is the archetype. Search "Norell Dependently Typed Programming Agda AFP 2008." |
| [Haack & Wells — *Type Error Slicing in Implicitly Typed Higher-Order Languages* (ESOP 2003)](http://www.macs.hw.ac.uk/~jbw/papers/Haack+Wells:Type-Error-Slicing-in-Implicitly-Typed-Higher-Order-Languages:ESOP-2003.pdf) | Paper | Which sub-expressions are responsible for a type error. Foundational for provenance tracking. |
| [Heeren et al. — *Helium, for Learning Haskell* (Haskell Workshop 2003)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/helium.pdf) | Paper | Helium compiler's improved type error messages — the applied side. |
| [GHC — *Typed Holes* (User's Guide)](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/typed_holes.html) | Docs | The Haskell implementation; closest to what March targets. |
| [*Agda Documentation* — Interactive Proof Development](https://agda.readthedocs.io) | Docs | Shows what programming with holes feels like in practice. |

---

## 17. Provenance Tracking in Type Errors

**What March does:** Every type constraint carries a reason chain; errors report "expected X because of Y, found Z because of W."

| Resource | Kind | Notes |
|---|---|---|
| [Heeren — *Top Quality Type Error Messages* (PhD thesis, 2005)](https://dspace.library.uu.nl/bitstream/handle/1874/7297/?sequence=7) | Thesis | The most thorough treatment of principled type error reporting. |
| Yang et al. — *Improved Type Error Messages for Constraint-Based Type Inference* (IFL 2000) | Paper | How constraint graphs can explain type errors. PostScript only: http://www.macs.hw.ac.uk/~jbw/papers/Yang+Michaelson+Trinder+Wells:Improved-Type-Error-Reporting:IFL-2000-draft-proceedings.ps.gz |
| [Vytiniotis et al. — *OutsideIn(X): Modular Type Inference with Local Assumptions* (JFP 2011)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/02/jfp-outsidein.pdf) | Paper | GHC's constraint-based inference; the architecture March's error reporting builds on. |
| Czaplicki — *Compiler Errors for Humans* (blog, 2015) | Blog | Evan Czaplicki's writing on designing good error messages; practical framing of what provenance is trying to achieve. Search: "Elm compiler error messages Czaplicki." |

---

## 18. FFI Design and Capability-Based Safety

**What March does:** Per-library `Cap(LibC)` capabilities; foreign pointers as `linear Ptr(a)`; `unsafe` blocks; explicit `CRepr` marshaling.

| Resource | Kind | Notes |
|---|---|---|
| [Furr & Foster — *Polymorphic Type Inference for the JNI* (ESOP 2006)](https://www.cs.tufts.edu/~jfoster/papers/esop06.pdf) | Paper | Type-safe FFI across language boundaries. |
| [Fluet et al. — *Monadic Regions* (JFP 2006)](https://www.cs.cornell.edu/people/fluet/research/rgn-monad/JFP06/jfp06.pdf) | Paper | Region-based resource management; contrast with March's linear types approach. |
| [*Rustonomicon* — FFI and `unsafe`](https://doc.rust-lang.org/nomicon/ffi.html) | Docs | The most widely-read practical treatment of safe FFI with linear types. |
| [Maffeis et al. — *Object Capabilities and Isolation of Untrusted Web Applications* (IEEE S&P 2010)](https://theory.stanford.edu/~ataly/Papers/sp10.pdf) | Paper | Capability confinement formalized; relevant to the `extern` capability model. |

---

## 19. Representation Polymorphism / Unboxed Types

**What March does:** After monomorphization, the compiler chooses boxed vs. unboxed representations; linearity checking happens before representation is decided.

| Resource | Kind | Notes |
|---|---|---|
| [Leroy — *Unboxed Objects and Polymorphic Typing* (POPL 1992)](https://xavierleroy.org/publi/unboxed-polymorphism.pdf) | Paper | Classic paper on the tension between polymorphism and unboxed representations in ML. |
| [Peyton Jones & Launchbury — *Unboxed Values as First Class Citizens* (FPCA 1991)](https://www.microsoft.com/en-us/research/wp-content/uploads/1991/01/unboxed-values.pdf) | Paper | GHC's approach; directly relevant to March's design. |
| [Eisenberg & Peyton Jones — *Levity Polymorphism* (PLDI 2017)](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/levity-pldi17.pdf) | Paper | The modern GHC formalization of representation polymorphism. |
| [*GHC User's Guide* — Representation polymorphism](https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/representation_polymorphism.html) | Docs | Implementation notes. |

---

## Books (Cross-Cutting)

| Book | What it covers for March |
|---|---|
| Pierce — *Types and Programming Languages* (TAPL, 2002) | Foundational textbook. Covers most topics above at introductory–intermediate depth. Free PDF widely available. |
| Pierce (ed.) — *Advanced Topics in Types and Programming Languages* (ATTAPL, 2005) | Graduate-level follow-up. Chapters on linear types, module systems, and type inference are directly relevant. |
| [Harper — *Practical Foundations of Mathematics for Programming Languages* (PFPL, 2016)](https://www.cs.cmu.edu/~rwh/pfpl/) | The most rigorous type-theoretic foundations. Dense. Free online. |
| Appel — *Modern Compiler Implementation in ML* (1998) | The compiler implementation book. March is in OCaml but the structure maps cleanly. |
| Aho et al. — *Compilers: Principles, Techniques, and Tools* (Dragon Book, 2006) | Classical compiler theory. Less relevant to March's type-system-heavy design but essential background. |
| [Minsky & Madhavapeddy — *Real World OCaml*](https://dev.realworldocaml.org) | Free online. The practical guide to OCaml — March's implementation language. |
