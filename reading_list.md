# March Language — PLT Reading List

A map from March's major language features to foundational papers, books, and articles. Intended as a self-directed PLT curriculum organized around the language you're building.

Each section pairs the academic source with something more approachable — a blog post, a talk, or documentation.

---

## 1. Hindley-Milner Type Inference

**What March does:** Core type inference; type variables, let-polymorphism, unification.

| Resource | Kind | Notes |
|---|---|---|
| Milner, R. — *A Theory of Type Polymorphism in Programming* (1978) | Paper | The original HM paper. Dense but worth reading. |
| Damas & Milner — *Principal Type-Schemes for Functional Programs* (POPL 1982) | Paper | The "Algorithm W" paper — the practical formulation most implementations follow. |
| Cardelli, L. — *Basic Polymorphic Typechecking* (1987) | Paper | Gentler exposition of Algorithm W with worked examples. Best entry point to the literature. |
| Pierce, B. — *TAPL*, Ch. 22–23 | Book | The standard textbook treatment. |
| Heeren et al. — *Generalizing Hindley-Milner Type Inference Algorithms* (2002) | Paper | Reformulates HM as constraint generation + solving; maps directly to modern compiler structure. |
| Nystrom, R. — *Crafting Interpreters*, Ch. 30 (Type Inference) | Book/Web | Free online. The most readable step-by-step walk through implementing HM inference. https://craftinginterpreters.com |
| Poly blog — *Write You a Type Inferencer* | Blog | A worked Haskell implementation of Algorithm W with clear prose. Search: "Write You A Haskell type inference" (Diehl). |

---

## 2. Bidirectional Type Checking

**What March does:** At annotated positions, the expected type flows inward ("checking mode") rather than being inferred bottom-up.

| Resource | Kind | Notes |
|---|---|---|
| Pierce & Turner — *Local Type Inference* (TOPLAS 2000) | Paper | The foundational paper. Distinguishes "infer" from "check" modes. |
| Dunfield & Krishnaswami — *Bidirectional Typing* (CSUR 2021) | Paper | Comprehensive modern survey. Read after Pierce & Turner. |
| Dunfield & Pfenning — *Tridirectional Typechecking* (POPL 2004) | Paper | Extends to refinement types; shows where the technique goes. |
| Christiansen, D. — *Bidirectional Type Checking* | Blog | Blog post with diagrams and worked examples. Very accessible. Search: "David Christiansen bidirectional type checking." |
| Kovacs, A. — *elaboration-zoo* | Code | GitHub repo with small, runnable bidirectional type checkers in Haskell. Concrete implementations trump prose. https://github.com/AndrasKovacs/elaboration-zoo |

---

## 3. Linear and Affine Types

**What March does:** `linear` = used exactly once; `affine` = used at most once. Ownership transfer, safe mutation, statically-verified resource cleanup.

| Resource | Kind | Notes |
|---|---|---|
| Girard, J.-Y. — *Linear Logic* (1987) | Paper | The origin. Proof-theoretic; gives you the "why." |
| Wadler, P. — *Linear Types Can Change the World!* (1990) | Paper | More accessible than Girard; shows the PL application directly. Best entry point. |
| Walker, D. — *Substructural Type Systems* in ATTAPL, Ch. 1 | Book | Covers linear, affine, and relevant types uniformly. |
| Bernardy et al. — *Linear Haskell* (POPL 2018) | Paper | Retrofitting linearity into a functional language. Very relevant to March's design. |
| Willsey, M. — *A Gentle Introduction to Linear Types* | Blog | Accessible blog post, no prior PL theory needed. Search: "gentle introduction linear types" or look on lobste.rs. |
| *Rust Book*, Ch. 4 — Ownership | Docs | Free online. The most widely-read practical treatment of linear/affine types without the jargon. https://doc.rust-lang.org/book/ch04-00-understanding-ownership.html |

---

## 4. Algebraic Data Types and Pattern Matching

**What March does:** Sum types with capitalized constructors, product types as records, exhaustiveness checking, guards.

| Resource | Kind | Notes |
|---|---|---|
| Pierce, B. — *TAPL*, Ch. 11 & 23 | Book | Products, sums, recursive types. |
| Maranget, L. — *Warnings for Pattern Matching* (JFP 2007) | Paper | The algorithm behind exhaustiveness checking in most ML compilers. |
| Scott & Ramsey — *When Do Match-Compilation Heuristics Matter?* (2000) | Paper | Decision trees vs. backtracking automata for compiling match. |
| Yallop, J. — *Practical Pattern Matching* (talk, OCaml 2016) | Talk | Accessible explanation of how OCaml compiles pattern matching. Available on YouTube. |
| *OCaml Manual* — Variant types and pattern matching | Docs | The closest production language to March's ADT design. https://v2.ocaml.org/api/ |

---

## 5. Typeclasses / Interfaces

**What March does:** `interface` + `impl`, conditional instances, associated types, coherence (no orphan instances).

| Resource | Kind | Notes |
|---|---|---|
| Wadler & Blott — *How to Make Ad-hoc Polymorphism Less Ad Hoc* (POPL 1989) | Paper | The original typeclass paper. Short and clear. Read this first. |
| Jones, M.P. — *A System of Constructor Classes* (FPCA 1993) | Paper | Higher-kinded typeclasses; background for `Collection(f)` style interfaces. |
| Oliveira et al. — *Type Classes as Objects and Implicits* (OOPSLA 2010) | Paper | Connects typeclasses to implicit arguments. |
| Kmett, E. — *Type Classes vs. The World* (talk, 2014) | Talk | Excellent talk on typeclass design tradeoffs. Available on YouTube. |
| Yorgey, B. — *The Typeclassopedia* (Haskell Wiki, 2009) | Blog/Wiki | Walks through Haskell's core typeclasses. More applied than theoretical. https://wiki.haskell.org/Typeclassopedia |
| Rust Reference — *Traits* | Docs | How Rust's trait system works in practice; the implementation most similar to March's. https://doc.rust-lang.org/reference/items/traits.html |

---

## 6. Module Systems and Signatures

**What March does:** `mod`/`sig` separation; signatures have their own content hash; downstream caches depend on sigs, not impls.

| Resource | Kind | Notes |
|---|---|---|
| Leroy, X. — *Manifest Types, Modules, and Separate Compilation* (POPL 1994) | Paper | Theory behind ML-style signatures and separate compilation. Directly relevant to March's sig-hash design. |
| Harper & Pierce — *Design Considerations for ML-Style Module Systems* in ATTAPL, Ch. 8 | Book | The authoritative survey. Explains why March chose interfaces over functors. |
| Rossberg, A. — *1ML — Core and Modules United* (ICFP 2015) | Paper | Unifying core and module levels; interesting for understanding the design space March opted out of. |
| Leroy, X. — *A Modular Module System* (JFP 2000) | Paper | More digestible than the POPL 1994 paper; practical implementation focus. |
| OCaml Manual — *Module System* | Docs | The practical reference. https://v2.ocaml.org/manual/modules.html |

---

## 7. Session Types

**What March does:** Binary session types on `Chan(P, e)` values; protocol descriptions verified at compile time; epoch-stamped channels for failure handling.

| Resource | Kind | Notes |
|---|---|---|
| Honda, K. — *Types for Dyadic Interaction* (CONCUR 1993) | Paper | The original session types paper. |
| Honda et al. — *Language Primitives and Type Discipline for Structured Communication-Based Programming* (ESOP 1998) | Paper | Closer to a practical language design. |
| Wadler, P. — *Propositions as Sessions* (ICFP 2012) | Paper | Connects session types to linear logic via Curry-Howard. Beautiful paper. |
| Honda et al. — *Multiparty Asynchronous Session Types* (POPL 2008) | Paper | The MPST paper March defers to post-v1. Essential reading when you get there. |
| Lindley, S. — *Talk: Propositions as Sessions* (2012) | Talk | The companion talk to Wadler's paper; clearer than reading the paper alone. Search on YouTube. |
| Ancona et al. — *Behavioral Types in Programming Languages* (NOW Foundations and Trends, 2016) | Survey | A readable survey of all behavioral type approaches including session types. Good map of the landscape. |
| *Session Types for Rust* blog (Betten, 2021) | Blog | Shows what session types look like implemented in a real language. Search: "session types Rust implementation." |

---

## 8. Actor Model and Capability Security

**What March does:** Share-nothing actors, `Pid(a)`, `Cap(A, e)` unforgeable capabilities, capability-secure messaging (no ambient authority).

| Resource | Kind | Notes |
|---|---|---|
| Hewitt et al. — *A Universal Modular ACTOR Formalism* (IJCAI 1973) | Paper | The original actors paper. Historical. |
| Miller, M.S. — *Robust Composition* (PhD thesis, 2006) | Thesis | The object-capability model thesis; the intellectual foundation for `Cap`. Freely available online. |
| Miller et al. — *Capability Myths Demolished* (2003) | Paper | Short paper debunking capability misconceptions. Read before implementing. |
| Armstrong, J. — *Making Reliable Distributed Systems...* (PhD thesis, 2003) | Thesis | The Erlang/OTP thesis. Highly readable; supervision trees, isolation, the BEAM philosophy. |
| Mark Miller — *The Object-Capability Model* (talk, Strange Loop 2013) | Talk | The best accessible introduction to capability security. Available on YouTube. |
| *The E Language* website | Docs | E is the primary reference implementation of object-capabilities. https://erights.org |
| Programming Erlang, Armstrong — Ch. 23 (Error Handling in Concurrent Programs) | Book | Practical treatment of how Erlang's supervision actually works. |

---

## 9. Supervision Trees and Fault Tolerance

**What March does:** `one_for_one`/`one_for_all`/`rest_for_one`; epoch-stamped capabilities; protocol epochs (epochs-design.md).

| Resource | Kind | Notes |
|---|---|---|
| Armstrong et al. — *Concurrent Programming in Erlang* (1996) | Book | Part II on OTP is most relevant. The original description of supervision trees. |
| Tasharofi et al. — *Why Do Scala Developers Mix the Actor Model with Other Concurrency Models?* (ECOOP 2013) | Paper | Empirical study of actor failure modes; useful for understanding what March's design prevents. |
| Virding, R. — *A History of Erlang* (HOPL 2020) | Paper | How Erlang's reliability model evolved from practice, not theory. |
| *Akka Documentation* — Supervision and Fault Tolerance | Docs | The most widely-read practical description of supervision trees outside Erlang. https://doc.akka.io/docs/akka/current/typed/fault-tolerance.html |
| Fred Hebert — *Learn You Some Erlang* Ch. 18 (Supervisors) | Book/Web | Free online. The clearest practical introduction to OTP supervision. https://learnyousomeerlang.com/supervisors |

---

## 10. Perceus Reference Counting and FBIP

**What March does:** Non-linear heap values managed by Perceus RC; FBIP allows functional updates to reuse memory in-place.

| Resource | Kind | Notes |
|---|---|---|
| Reinking et al. — *Perceus: Garbage Free Reference Counting with Reuse* (PLDI 2021) | Paper | **Mandatory reading.** This is the exact algorithm March uses. |
| Lorenzen & Leijen — *Reference Counting with Frame-Limited Reuse* (Haskell Sym. 2022) | Paper | Extends FBIP; discusses the "frame-limited" variant. |
| Ullrich & de Moura — *Counting Immutable Beans* (IFL 2019) | Paper | Lean 4's RC design, closely related to Perceus. |
| Leijen, D. — *Koka: Programming with Row-polymorphic Effect Types* (MSFP 2014) | Paper | Koka is where Perceus originated; gives language context. |
| *Koka Language Website* | Docs | The Koka reference with documentation on Perceus and FBIP. https://koka-lang.github.io |
| Leijen, D. — *Perceus: An Introduction* (blog post, Microsoft Research) | Blog | The author's own accessible write-up. Easier entry than the PLDI paper. Search: "Daan Leijen Perceus blog." |

---

## 11. Defunctionalization

**What March does:** Higher-order functions compiled to a tagged union + `apply` dispatch; eliminates heap-allocated closures and indirect calls.

| Resource | Kind | Notes |
|---|---|---|
| Reynolds, J.C. — *Definitional Interpreters for Higher-Order Programming Languages* (ACM 1972) | Paper | The original paper introducing defunctionalization. |
| Danvy & Nielsen — *Defunctionalization at Work* (PPDP 2001) | Paper | Practical treatment; interactions with CPS transforms and partial evaluation. |
| Danvy, O. — *On Evaluation Contexts, Continuations, and the Rest of the Computation* (talk) | Talk | Danvy's accessible lectures on defunctionalization are on YouTube. |
| Nielsen, L.R. — *A Study of Defunctionalization and Continuation-Passing Style* (PhD thesis, 2003) | Thesis | Thorough if you want depth. |
| *Defunctionalization* — Neel Krishnaswami's blog | Blog | Short, clear blog post connecting defunctionalization to Scott encodings. Search: "Neel Krishnaswami defunctionalization." |

---

## 12. Whole-Program Monomorphization

**What March does:** All polymorphic functions specialized to concrete type arguments; no runtime dictionaries; cached by (function hash, type args).

| Resource | Kind | Notes |
|---|---|---|
| Tarditi et al. — *TIL: A Type-Directed Optimizing Compiler for ML* (PLDI 1996) | Paper | Classic ML-to-native compiler; monomorphization as a key pass. |
| Fluet & Weeks — *Contification Using Dominators* (ICFP 2001) | Paper | MLton paper; MLton is the reference implementation of whole-program monomorphization for ML. |
| *MLton Compiler* — Design docs | Docs | Practical notes on the monomorphization strategy March emulates. http://mlton.org/References.attachments/060916-mlton.pdf |
| Russ Cox — *Go Data Structures: Interfaces* | Blog | Explains the dictionary-passing approach Go uses as contrast; helps you understand what monomorphization avoids. https://research.swtch.com/interfaces |

---

## 13. Type-Level Naturals (Sized Types)

**What March does:** `Vector(n, a)`, `Matrix(m, n, a)`; type-level `+` and `*`; constraint solver for nat equations; deliberately not full dependent types.

| Resource | Kind | Notes |
|---|---|---|
| Hughes et al. — *Proving the Correctness of Reactive Systems Using Sized Types* (POPL 1996) | Paper | Original sized types paper — types indexed by natural numbers. |
| Brady et al. — *Inductive Families Need Not Store Their Indices* (TYPES 2003) | Paper | How to compile indexed types without runtime overhead. |
| Eisenberg et al. — *Dependently Typed Programming with Singletons* (Haskell Sym. 2012) | Paper | Haskell approach to type-level naturals; illuminates what March does (and doesn't) do. |
| Lindsey Kuper — *Intro to Dependent Types* (blog series) | Blog | Accessible series on dependent types, with Idris examples. Good background for understanding what March deliberately avoids. http://composition.al |
| *Idris 2 Tutorial* — Dependent Types | Docs | Hands-on: what full dependent types look like in practice. Useful contrast. https://idris2.readthedocs.io |

---

## 14. Query-Based / Demand-Driven Compiler Architecture

**What March does:** Compilation as a graph of memoized queries; incremental recompilation; content-addressed results.

| Resource | Kind | Notes |
|---|---|---|
| Konat et al. — *PIE: A Domain-Specific Language for Interactive Software Development Pipelines* (SLE 2016) | Paper | Formalizes the demand-driven build model. |
| Erdweg et al. — *Towards Language-Independent Incremental Builds* (2015) | Paper | Theoretical framing of demand-driven builds. |
| *The Rust Compiler's Query System* | Docs | The most concrete description of the architecture March is emulating. https://rustc-dev-guide.rust-lang.org/query.html |
| *Salsa* — documentation and design notes | Docs/Blog | The framework Rust's incremental compiler is built on. https://salsa-rs.github.io/salsa/ |
| Matsakis, N. — *Salsa: Incremental Recompilation* (RustConf 2019) | Talk | The best accessible explanation of query-based compilation. Available on YouTube. |

---

## 15. Content-Addressed Code

**What March does:** Every definition identified by hash of its AST; names are aliases; signatures have separate hashes; no dependency conflicts.

| Resource | Kind | Notes |
|---|---|---|
| Chiusano, P. — *Unison: A New Approach to Distributed Programming* | Blog/Docs | Unison is the existence proof. The design docs are the primary resource. https://www.unison-lang.org/learn/ |
| *The Unison Language Reference* — Names are not the thing | Docs | The specific doc on how content-addressing changes what "naming" means. |
| Lamport, L. — *The Part-Time Parliament* (TOCS 1998) | Paper | Content addressing in distributed consensus — background for distributed actors sharing code by hash. |
| Aumasson, J.-P. — *Serious Cryptography*, Ch. 6 | Book | Accessible treatment of hash functions and what content-addressing actually guarantees. |

---

## 16. Error Recovery and Typed Holes

**What March does:** Parse/type errors become typed holes; holes infer their expected type from bidirectional checking; user-written `?` uses the same mechanism.

| Resource | Kind | Notes |
|---|---|---|
| Norell, U. — *Dependently Typed Programming in Agda* (AFP 2008) | Paper | Agda's interactive development via holes is the archetype. |
| Haack & Wells — *Type Error Slicing in Implicitly Typed Higher-Order Languages* (ESOP 2003) | Paper | Which sub-expressions are responsible for a type error. Foundational for provenance tracking. |
| Heeren et al. — *Helium, for Learning Haskell* (Haskell Workshop 2003) | Paper | Helium compiler's improved type error messages — the applied side. |
| GHC — *Typed Holes* (User's Guide) | Docs | The Haskell implementation; closest to what March targets. https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/typed_holes.html |
| *Agda Documentation* — Interactive Proof Development | Docs | Shows what programming with holes feels like in practice. https://agda.readthedocs.io |

---

## 17. Provenance Tracking in Type Errors

**What March does:** Every type constraint carries a reason chain; errors report "expected X because of Y, found Z because of W."

| Resource | Kind | Notes |
|---|---|---|
| Heeren, B. — *Top Quality Type Error Messages* (PhD thesis, 2005) | Thesis | The most thorough treatment of principled type error reporting. Freely available online. |
| Yang et al. — *Improved Type Error Messages for Constraint-Based Type Inference* (FLOPS 2000) | Paper | How constraint graphs can explain type errors. |
| Vytiniotis et al. — *OutsideIn(X): Modular Type Inference with Local Assumptions* (JFP 2011) | Paper | GHC's constraint-based inference; the architecture March's error reporting builds on. |
| *Elm Compiler* error messages blog posts (Czaplicki, 2015–) | Blog | Evan Czaplicki's writing on designing good error messages; practical framing of what provenance is trying to achieve. Search: "Elm compiler error messages design." |

---

## 18. FFI Design and Capability-Based Safety

**What March does:** Per-library `Cap(LibC)` capabilities; foreign pointers as `linear Ptr(a)`; `unsafe` blocks; explicit `CRepr` marshaling.

| Resource | Kind | Notes |
|---|---|---|
| Furr & Foster — *Polymorphic Type Inference for the JNI* (ESOP 2006) | Paper | Type-safe FFI across language boundaries. |
| Fluet et al. — *Monadic Regions* (JFP 2006) | Paper | Region-based resource management; contrast with March's linear types approach. |
| *Rust Reference* — FFI and `unsafe` | Docs | The most widely-read practical treatment of safe FFI with linear types. https://doc.rust-lang.org/nomicon/ffi.html |
| Maffeis et al. — *Object Capabilities and Isolation of Untrusted Web Applications* (IEEE S&P 2010) | Paper | Capability confinement formalized; relevant to the `extern` capability model. |

---

## 19. Representation Polymorphism / Unboxed Types

**What March does:** After monomorphization, the compiler chooses boxed vs. unboxed representations; linearity checking happens before representation is decided.

| Resource | Kind | Notes |
|---|---|---|
| Leroy, X. — *Unboxed Objects and Polymorphic Typing* (POPL 1992) | Paper | Classic paper on the tension between polymorphism and unboxed representations in ML. |
| Peyton Jones & Launchbury — *Unboxed Values as First Class Citizens* (FPCA 1991) | Paper | GHC's approach; directly relevant to March's design. |
| Eisenberg & Peyton Jones — *Levity Polymorphism* (PLDI 2017) | Paper | The modern GHC formalization of representation polymorphism. |
| *GHC Commentary* — Representation polymorphism | Docs | Implementation notes. https://ghc.gitlab.haskell.org/ghc/doc/users_guide/exts/representation_polymorphism.html |

---

## Books (Cross-Cutting)

| Book | What it covers for March |
|---|---|
| Pierce, B. — *Types and Programming Languages* (TAPL, 2002) | Foundational textbook. Covers most topics above at introductory–intermediate depth. Free PDF widely available. |
| Pierce, B. (ed.) — *Advanced Topics in Types and Programming Languages* (ATTAPL, 2005) | Graduate-level follow-up. Chapters on linear types, module systems, and type inference are directly relevant. |
| Harper, R. — *Practical Foundations of Mathematics for Programming Languages* (PFPL, 2016) | The most rigorous type-theoretic foundations. Dense. Free online at https://www.cs.cmu.edu/~rwh/pfpl/ |
| Appel, A. — *Modern Compiler Implementation in ML* (1998) | The compiler implementation book. March is in OCaml but the structure maps cleanly. |
| Aho et al. — *Compilers: Principles, Techniques, and Tools* (Dragon Book, 2006) | Classical compiler theory. Less relevant to March's type-system-heavy design but essential background. |
| Real World OCaml (Minsky, Madhavapeddy) | Free online. The practical guide to OCaml — March's implementation language. https://dev.realworldocaml.org |
