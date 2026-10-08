# BreatheRoute coursework delivery plan

Submission deadline provided by the student: **31 October 2026**. This plan is based on the supplied 2026 assessment, marking rubric, proposal, feature photograph and lecturer feedback. It is a working checklist, not a promise of a mark or evidence of lecturer approval.

## What the rubric rewards

| Component | Weight | Evidence needed |
| --- | ---: | --- |
| Prototype and MVP approval | 10% | Full high-fidelity journeys, credible scope, lecturer approval. Prototype quality is 4 of these 10 marks. |
| MVP and viva | 20% | Approved core features, two permitted platform features, central real external integration, a smooth flow, and ability to explain the implementation. |
| Advanced iOS SDK | 20% | Deeply integrated, relevant SDK work. Multiple well-integrated features support the highest band. |
| Tests, accessibility and documentation | 15% | Meaningful Swift Testing suite, VoiceOver, Dynamic Type, inclusive flows, report and LO1–LO4 reflections. |
| Above and Beyond | 25% | Creativity, architecture, multiple integrated features, genuine iPhone/iPad adaptation, complete error and empty states. The rubric states that the 29 raw subcomponent marks are capped at 25. |
| Tutorial 4 | 10% | Separate in-class evolving game app, its required platform features, Git history and in-lab explanation. BreatheRoute does not replace this work. |

Components 1–3 are mandatory: zero in any results in module failure. A 70%+ target requires strong delivery across these categories; it cannot be inferred from a feature count.

## Current scope and gaps

| Area | Current state | Work before claiming completion |
| --- | --- | --- |
| Visual design | Redesigned screens, a shared visual system and native navigation | Review each journey on small iPhone, large text, dark mode and iPad; refresh Figma to match the app |
| Authentication | Local profile and device-authentication app lock | Firebase registration, sign-in/out, password reset and session restoration |
| Air-quality API | Real OpenWeather response verified on 7 October; key stored in the development iPhone simulator's Keychain; clearer credential/quota/network errors | Test failure paths; add cache, freshness policy and request reuse |
| Routing | Place search, walking directions, alternatives, distance-based sampling, coverage-aware scoring | Validate available walking directions in the demonstration area; handle equal routes and add segment readings/legend |
| Route pollution overlays | Selected route uses one colour | Persist segment readings and draw lower/moderate/higher/missing segments with equivalent text descriptions |
| Active walk | Foreground GPS distance and observed dose; gap handling | Background tracking, session recovery, route deviation and final completeness status |
| HealthKit | Optional recent heart/respiratory samples displayed on-device | Further integration must have a defensible model and a clear effect on the user journey; current context display alone is limited advanced evidence |
| Persistence | Core Data trip and symptom CRUD | Test reopening, corrupt/error cases and linked-record deletion; add versioned migrations and richer route records |
| Notifications | Scheduled local daily check-in | In-walk pollution/exposure awareness alerts, cooldown and in-app fallback; confirm whether the lecturer requires remote push/APNs |
| Firebase/Firestore | Not integrated | Configure a project; implement owner-only rules, account-scoped data, summary-only sync, retries, deletions and conflicts |
| Symptoms/history | Notes, linked walks, date filters, details and sharing | Expand daily/weekly insights and restored-summary/incomplete states without causal claims |
| Accessibility | Semantic labels, system text styles, non-colour selection indicators, Reduce Motion-aware buttons | Complete real VoiceOver walkthrough, largest text sizes, contrast and touch-target checks |
| Unit testing | Eight Swift Testing functions of exposure core | Inject testable services; test persistence, sampling, ranking/ties, parsing, sync and tracking edges |
| iPad | Sidebar and wider dashboard/planner composition; closing/reopening the sidebar verified after a navigation-bar fix | Verify landscape, narrow multitasking, keyboard interaction and explanation for LO1 |

## Advanced features to prioritise

The student has requested new ideas beyond the existing feature list and proposed geofencing with pollution circles and alternative paths. See [NEW_FEATURES.md](NEW_FEATURES.md) for the prioritised pollution-aware geofencing/rerouting workflow, API limitations, acceptance criteria and optional forecast/Core Motion/Live Activity extensions. These are proposals, not implemented or approved features; use that document to revise scope before treating them as submission commitments.

1. **MapKit + Core Location as the core advanced integration.** Alternative route geometry, meaningful segment sampling, a textual pollution legend, tracking quality, deviation and lifecycle recovery. A hardcoded demo map does not count as live integration.
2. **Spoken route and active-walk summaries.** On-demand text-to-speech is already present. Add current-trip summaries and clear stop controls; ensure optional speech never conflicts with VoiceOver.
3. **App Intents / Shortcuts.** A useful extension is “Open route planning” and “Add a symptom note” opening directly into the appropriate flow. Implement only after the core journey is reliable, with state/authentication handling.
4. **On-device speech input for notes, if time permits.** Keep text entry fully available; handle unsupported locales, microphone/speech permissions, cancellation and transcript review. Verify on-device recognition support before advertising it.
5. **A WidgetKit summary, if time remains.** Show an honest latest-reading timestamp or no-data state and deep-link to planning. Avoid stale “live” claims.

VoiceOver and Dynamic Type are baseline accessibility evidence for Component 4. Text-to-speech is useful but should not be presented as a replacement for a comprehensive advanced SDK integration. Avoid remote LLM/chatbot additions: the supplied advanced-component guidance requires AI/ML features to run on-device.

## Work schedule

| Dates | Milestone | Exit condition |
| --- | --- | --- |
| 7–10 October | Agree revised MVP and visual design | Lecturer-approved scope; the complete core journey demonstrated in the redesigned app/prototype |
| 11–16 October | Finish API, accounts and persistence | Real environmental data, Firebase account flow, account-isolated summaries, relaunch and network-failure checks |
| 17–22 October | Deepen the advanced workflow | Segment overlays, background/recovery policy, walk alerts and one useful advanced extension working together |
| 23–27 October | Validation and assessment evidence | Swift Testing suite, accessibility audit, iPhone/iPad proof, permission/error-state evidence and limitations recorded |
| 28–30 October | Report, recording, viva and release | Report accurately describes implemented work; reproducible build, narrated recording, private repository access and final commit identified |
| 31 October | Submit | LMS documents, source/resources zip, repository URL, final commit hash and narrated recording supplied as required |

Treat this as a suggested sequence; adjust to the actual approved MVP. Do not leave backend setup or physical-device testing until the last day.

## Visual design acceptance

- Warm neutral backgrounds, deep green primary surfaces, restrained lime and lavender accents.
- Serif screen headings, readable system body text, consistent spacing and touch targets.
- Maps and dose/time/distance comparisons get the emphasis in the planning flow.
- Demo, stale, partial, missing and live data are clearly distinguished.
- New users see an intentional empty state with a useful action, never fabricated history.
- iPad uses a sidebar and wider compositions; it should support a real workflow rather than simply stretch phone cards.
- Native navigation, sheets, date pickers, share sheets and system permission prompts retain familiar behaviour.

## Demonstration and viva evidence

Record the actual implementation, not just Figma. Demonstrate onboarding, genuine API data, a route comparison, an active walk or honestly labelled simulator replay, a saved trip, a linked note, persistence after relaunch, permissions declined, offline/error behaviour, speech, VoiceOver and an adapted iPad layout.

Be able to explain units, missing samples, coverage, model assumptions, the difference between concentration and dose, Core Data, account isolation, sync conflicts, framework permissions, thread isolation, background lifecycle and what each unit test proves. Use meaningful incremental Git commits. Do not fabricate a development history, test result, completed feature or grade.

The final report should include: problem/target audience, approved scope, architecture, core and advanced workflows, UI decisions, API/data handling, verification evidence, challenges and limitations, LO1–LO4 reflection, references and an accurate AI-assistance declaration.

## Setup information still needed

- Firebase project has not yet been created, as confirmed by the student on 7 October. Follow `FIREBASE_SETUP.md`; the iOS bundle identifier is `MANKumara.BreathRoute`.
- OpenWeather key supplied and configured on the development iPhone simulator. Real API data verified at a simulated public Colombo location. Other devices require their own Keychain setup.
- Physical test device and Apple signing-team availability.
- Confirmed approved MVP and the lecturer's interpretation of notifications and the updated AI-assistance rules.

## Sources

- `iOS_CW_Assessment_2026.pdf`, especially pp. 2, 4–10 and 13.
- `iOS_CW_Marking_Rubric_2026 (2).docx`, all six component tables.
- `Breathe_Route_Proposal_Submission.docx`, proposed scope and data handling.
- The supplied feature photograph and Figma BreatheRoute file.
- Apple HIG: https://developer.apple.com/design/human-interface-guidelines/
- OpenWeather API: https://openweathermap.org/api/air-pollution
