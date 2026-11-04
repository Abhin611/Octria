# Product

<!-- impeccable:product-schema 1 -->

## Platform

adaptive

One product across Android, iOS and web, plus Windows, macOS and Linux desktop. Launch order: web and Android first, then iOS and desktop.

## Stack

Flutter (one codebase for every platform), Firebase Auth, Cloud Firestore, Cloud Functions, Firebase Cloud Messaging, Firebase Hosting, Google Drive API (`drive.file` scope), Gemini API free tier. Chosen in the planning document. Only the graph prototype is built so far, on sample data; Firebase, Drive and Gemini are not connected yet.

## Users

Students, teams and individuals running anything from an app build to exam prep, research, events or creative work. They use it alone or in groups of up to 10, at work or in their personal lives. No single audience segment outranks the others.

Their job: take a task they need to finish, see a realistic plan for it, know what to do next, and for groups, know who is doing what and what is blocking whom.

First users: Abhin tests first, then a team of friends.

## Product Purpose

Octria (renamed from Modus, and before that Pimeon) is a free, cross-platform app that turns any task into a classroom with an AI-generated roadmap of phases and steps, shown as an interactive node graph called Flowspace. Each person also gets Kanvas, a private infinite canvas for their own thinking, and Ofy, its AI: a voice and text helper that can answer, point at things on screen and act with approval.

Success means a new user understands their next step within seconds of opening a classroom, and the graph feels effortless on both phone and laptop. The graph decides whether people keep using the app.

## Positioning

Any task becomes a classroom with an AI-drafted plan shaped to the type of task (build, exam or study, research, event or creative), laid out as a node graph with a lane per member and dependencies across members. It is free to use, and files stay in users' own Google Drive.

Positioning against named alternatives has not been decided.

## Operating Context

- Used on phone, tablet, web and desktop, with gestures on touch devices and mouse and keyboard on larger screens.
- Core flow: create a task, choose Individual or Group, answer up to 5 AI follow-ups, edit the draft plan, then work through steps.
- People return to a group classroom after time away, and the "Since you were away" screen catches them up.
- Connects to Google Drive for files and GitHub for repos, issues, branches and commit activity.
- Progress saves continuously and works offline.

## Capabilities and Constraints

**Terminology:** classroom, master, co-master, member, phase, step, dependency, soft lock, suggestion, shared library, private library, "Since you were away", growth map, contribution record, Flowspace (the node graph page), Kanvas (a person's private canvas), Ofy (the AI that asks, shows and does), mock test (a mock exam or mock interview for one phase).

**In scope:**

- Sign-in with Google, GitHub or email. Profile with skills, resume and linked GitHub; AI extracts skills from a resume for the user to confirm.
- Classrooms: individual or group, invites by code or link, archive, reusable templates.
- AI planning: phases, steps, dependencies, estimates, skill-based work splitting, resource finding, re-planning and an in-classroom assistant. Dates are calculated from the deadline and hours per week, not guessed by the AI.
- Flowspace, the node graph: flows left to right or top to bottom, switchable; three zoom levels (phases as large cards with a progress ring each, steps, full step card), member lanes, phases as columns, status-coloured dependency arrows, critical path, focus on me, graph or timeline toggle, filters, minimap, completion feedback, and change badges.
- Steps: any step can be worked on in any order. Starting one with an unfinished dependency warns rather than blocks. Each step shows its description, checklist, skills, comments and study materials (files, links, videos, notes). Tapping a step listed under Needs or Unblocks always goes to that step.
- Collaboration: comments, suggestions the owner accepts or dismisses, handing your own step to any member, notifications.
- Tracking: dashboard, active-time tracking with a 5-minute idle timeout, planned vs actual hours including overtime, contribution record, growth map, PDF report export.
- Mock tests (build phase 4): each phase can end with a mock exam or mock interview generated from that phase's content, for any field. It's offered once a phase's steps are done, can be taken early or skipped, and never blocks the next phase. Results give a score, feedback on each answer and links to the steps worth revising. Each person sets their own difficulty (Easy, Medium or Hard), and the master can set one level for everyone until they clear it. Results are private by default, and each person can turn on sharing so everyone in the group can see theirs.
- Practice links (build phase 3): a Practice section in every classroom, reachable at any time, links to mock interview sites, question banks and coding practice. The AI suggests links and anyone can add their own. Octria stores no copied questions and has no code runner.
- Kanvas (build phase 3): a private infinite canvas per user with freehand and stylus drawing, sticky notes, text, checklists, diagrams with snapping connectors, and image, PDF, link and video cards. Boards live in folders with search, undo and redo, autosave and version history. An idea can become a classroom, a board can be pinned to a step, and boards can be shared read-only or editable. AI helpers tidy, clean up and summarise. Board data is JSON in Firestore (`users/{uid}/kanvas/{boardId}`), files go in the user's private Drive, and it uses the same canvas engine as Flowspace.
- Ofy, the AI (build phase 4): a floating mic on every screen with on-device speech to text. Ask answers questions, Show highlights a node or button with a pointer, Guide walks through multi-step cards, and Do performs actions after an Approve or Deny card, with an "always allow" option. Screens expose named addressable elements (`step:12`, `button:add-dependency`), Gemini returns JSON, and actions pass through the same Firestore rules. It can annotate a screenshot, or a shared screen on web and desktop. It does not click or type in other apps; a separate desktop agent is possible after launch. Free-tier limits apply.

**Constraints:**

- Every design choice keeps running costs near zero. AI results are cached, each user has a daily AI call limit, and files use the user's Drive rather than paid storage.
- Roles are enforced in Firestore Security Rules, not just hidden in the UI. The master controls everything; members control only their own steps.
- Group size is capped at 10. Master approval of finished steps can be turned on or off per classroom. All members can see each other's tracked hours.
- The graph is a custom Flutter canvas and must stay smooth at 500+ steps, including on low-end phones and Flutter web. Circular dependencies are refused with a clear message.
- Light and dark themes are required, with a switch for choosing between them.
- English only at launch.
- App store fees apply: one-time for Google Play, yearly for Apple.

**Undecided:**

- How to fund growth past the free quotas (options: donation link, paid "pro" tier for heavy AI use, users adding their own API key).

## Brand Commitments

Name: Octria, renamed from Modus and before that Pimeon. The AI is Ofy. No logo, voice guide or other brand assets exist yet.

One Apple-style look on every platform, chosen by the user over per-OS native chrome, and made of Apple-style glass by the user's request: translucent chrome floating over the canvas. It still honours Android's Back gesture and system settings. The graph must not feel overwhelming at first, or gamified or childish.

## Evidence on Hand

- [Octria planning document](docs/Octria_Planning_Document.pdf), also [online](https://claude.ai/artifact/9AjHJVH12FveWmRvfMVKnW): features, permissions, data model, AI pipelines, build phases and decisions. It is the fuller source for product detail.
- There are no users, testimonials, usage data, performance benchmarks, customers or press yet. Do not fabricate them. The only real-device checks so far are informal, reported by the builder: on 2026-11-04 the builder reported the phase 1 gate passed, with the glass build checked on a cheap Android phone and a laptop, and tried by at least 5 people. The 600-step sample plan also felt right on a Samsung Galaxy S23+. The exact number of testers and the phone's model aren't recorded, and there are no written results.

## Product Principles

1. **The graph comes first.** It gets the most design and build time, and is prototyped and tested with real users before other features.
2. **AI drafts, humans decide.** Every generated plan, split and skill list is an editable draft.
3. **Easy first.** A new user should understand their next step within seconds of opening a classroom.
4. **Warn, don't block.** People can work in any order; the product surfaces consequences rather than enforcing a sequence.
5. **Free to use.** Features must be able to run at near-zero cost.

## Accessibility & Inclusion

- A list view of the same plan serves screen readers and small screens as an equivalent to the graph.
- Node content changes with zoom level so text never becomes unreadable clutter.
- Resumes and time tracking are sensitive: the product needs a clear privacy policy and a way to delete all personal data. Never send another member's private data in an AI prompt.
- No formal accessibility standard has been set.
