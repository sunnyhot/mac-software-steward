# Unified Maintenance Engine and Dashboard Design

## Context

Mac Software Steward is a native SwiftUI macOS utility that scans Applications,
Homebrew packages, and Mac App Store applications, plans upgrades, executes them,
verifies results, and exposes automation and recovery controls. The current product
already has a task-first sidebar, a maintenance status band, shared surface styles,
and state-driven motion. Its core behavior is mature, but the user experience is
still organized around individual pages rather than one complete maintenance run.

`StewardModel` currently owns scanning, plan preparation, concurrent command
execution, download acceleration, progress, verification, recovery, jobs, and a
large part of navigation state. That makes the existing behavior difficult to
reuse consistently from a new overview, the upgrade page, and daily inspection.

This design introduces a unified maintenance engine and a new default dashboard.
The chosen visual direction is **System Diagnostic Bench**: bright, restrained,
and trustworthy, with a continuous maintenance track that connects scanning,
assessment, execution, and verification.

## Confirmed Product Decisions

- The application opens on a new `维护总览` page in both standard and advanced
  modes.
- `开始智能维护` always starts from a new scan rather than executing a stale plan.
- A package runs automatically only when all of these conditions are true:
  - its assessed risk level is low;
  - `RiskAssessor` returns `allowAutomatic`;
  - its effective package policy is `automatic`.
- Medium- or high-risk executable items and `askFirst` items require confirmation.
- Remind-only, skipped, unavailable, pinned, or otherwise non-executable items are
  never silently promoted into the automatic queue.
- The scope remains software scanning, upgrades, automation, verification, and
  failure recovery. Uninstall cleanup, disk cleanup, login-item management, and
  system-security scanning are not added in this project.
- The selected implementation direction is a unified workflow engine, not a
  dashboard-only adapter around `StewardModel`.

## Goals

- Give the application one clear default entry point that answers:
  - Is this Mac's managed software healthy?
  - What can be handled automatically?
  - What needs confirmation or manual attention?
  - What happened during the most recent maintenance run?
- Make manual maintenance, the existing upgrade page, and daily inspection use the
  same plan classification and execution rules.
- Extract workflow responsibilities from `StewardModel` behind testable,
  Foundation-first interfaces.
- Preserve current scanning, download acceleration, concurrent upgrades,
  cancellation, verification, history, notifications, and recovery behavior while
  improving isolation between them.
- Refresh the whole visible interface around a consistent native macOS visual
  language without adding a UI framework or external dependency.
- Keep light mode, dark mode, keyboard navigation, and reduced motion first-class.

## Non-Goals

- Do not replace SwiftUI or `NavigationSplitView`.
- Do not add a web service, cloud account, telemetry service, or remote database.
- Do not add software uninstall or residual-file deletion.
- Do not add disk, startup-item, or operating-system security inspection.
- Do not change application self-update security or installation behavior.
- Do not make blocked packages executable through an override in the dashboard.
- Do not resume an operating-system command after the app has terminated.
- Do not delete legacy inspection and upgrade history during this migration.
- Do not modify generated icons or release artifacts.

## Approaches Considered

### Dashboard adapter

Add a dashboard presenter that projects the existing `StewardModel` state and
routes its main button to the existing upgrade plan. This is the smallest change,
but it does not create the requested low-risk automatic workflow and leaves daily
inspection, the upgrade page, and the dashboard with different orchestration.

### Dashboard orchestration layer

Add a dashboard-specific coordinator while retaining the current execution code in
`StewardModel`. This delivers the feature faster, but it creates a second workflow
owner and makes future recovery or policy changes harder to keep consistent.

### Unified maintenance engine — chosen

Extract planning, workflow state, execution, verification, recovery, and run
reporting into a shared engine. Keep `StewardModel` as a compatibility facade while
existing call sites migrate. This has the highest implementation cost, but gives
the dashboard, upgrade page, and daily inspection one behavioral contract and
creates smaller units that can be tested independently.

## Architecture

The engine is split into a Foundation-only workflow core and presentation adapters.
The background agent must remain free of SwiftUI, AppKit, and Combine dependencies.

```text
Dashboard / Upgrade Page / Daily Inspection
                  │
                  ▼
       MaintenanceEngineAdapter
       (GUI observable presentation)
                  │
                  ▼
       MaintenanceWorkflowCore
       scan → assess → plan → execute → verify → report
          │        │        │          │         │
          ▼        ▼        ▼          ▼         ▼
      RunLease   Scanner  Planner   Executor   Verifier
                                      │
                                      ▼
                            RecoveryCoordinator
```

### `MaintenanceWorkflowCore`

A Foundation-only coordinator that owns legal state transitions and invokes its
dependencies through protocols. It does not know about SwiftUI views or selected
tabs. The main application and background agent can both compile and reuse it.

Its state is represented by a value type rather than independent booleans:

```text
idle
  → scanning
  → assessing
  → executingAutomatic
  → awaitingConfirmation
  → executingConfirmed
  → verifying
  → completed(report)

Any active state may become cancelling, cancelled(report), or failed(error).
```

`awaitingConfirmation` is skipped when there are no confirmation items.
`executingAutomatic` is skipped when there are no automatic items. Package-level
failures are outcomes within a run; only a workflow-level failure moves the whole
engine to `failed`.

### `MaintenanceEngineAdapter`

The GUI-facing, main-actor observable object. It converts core events into
published dashboard state, package progress, dialogs, navigation affordances, and
notifications. It displays lease conflicts but does not implement locking with
GUI-only state.

The adapter initially mirrors compatible values back through `StewardModel` so
existing views can migrate independently. Once all callers use the adapter,
duplicated execution state is removed from `StewardModel`.

### `MaintenanceRunLease`

A Foundation-only cross-process lease shared by the GUI application and background
agent. It acquires a lock file atomically before scanning or executing and records
the run identifier, process identifier, process start time, trigger, and lease
creation time. A competing foreground action opens the active-run view; a
competing background agent run logs that maintenance is already active and exits
without scanning or upgrading.

On launch, the lease validates both process identity and start time so a reused PID
does not look active. A stale lease marks its associated non-terminal run as
interrupted before it is reclaimed. Terminal completion and orderly cancellation
release the lease.

### `MaintenancePlanner`

Builds one `MaintenancePlan` from a fresh `ScanResult`, `RiskAssessor`, and
`UpgradePolicyStore`. It uses explicit plan dispositions:

- `automatic`
  - the package is executable;
  - risk level is `low`;
  - automation decision is `allowAutomatic`;
  - effective policy is `automatic`.
- `confirmationRequired`
  - the package is executable; and
  - risk requires confirmation or effective policy is `askFirst`.
- `reminderOnly`
  - effective policy is `remindOnly`; or
  - an update-capable regular application has a manual checker but no safe command.
- `blocked`
  - effective policy is `skip`;
  - the source is unavailable;
  - the package is pinned or non-upgradeable;
  - risk assessment returns `blockExecution`.

A blocked item has no executable package or command. UI selection cannot convert a
blocked item into an executable item.

### `MaintenanceExecutor`

Owns command queues, the concurrency limit, cancellation tokens, package progress,
download acceleration, command output, and job completion. It extracts the
corresponding behavior from `StewardModel` without changing command semantics.

Independent package failures and timeouts are isolated. They produce package
outcomes and recovery actions while unrelated queued packages continue. A user
cancellation is different: it prevents new work from starting and asks every
active command to terminate.

### `MaintenanceVerifier`

Runs the existing post-upgrade verification behavior against the completed package
set. Verification results are recorded per package. A verification mismatch is
visible as a failed outcome even when the command exited successfully.

### `MaintenanceRecoveryCoordinator`

Builds recovery actions from existing failure analysis and
`RecoveryActionPlanner`. It may offer retry, rescan, open logs, copy a terminal
command, or open the relevant system settings. Automatic repair remains controlled
by the existing automation profile and allowlist.

### `MaintenanceDashboardPresenter`

Maps engine and persisted-run state into stable UI models:

- overall health title and supporting text;
- maintenance-track phases;
- managed-software, automatic, confirmation, and next-inspection metrics;
- priority task rows;
- current package progress;
- daily-inspection summary;
- most recent maintenance result;
- empty, partial-source, failed, cancelled, and completed states.

The presenter contains no command execution and can be tested without rendering a
SwiftUI view.

## Workflow and Data Flow

### Manual smart maintenance

1. The user chooses `开始智能维护`.
2. The workflow acquires the cross-process maintenance lease. If another run owns
   it, the GUI shows the active run instead of starting a duplicate.
3. The core requests a new scan and exposes real scan phases. It does not display a
   fabricated percentage when the scanner has no measurable progress.
4. Source results are assessed independently. A failed source blocks only its own
   items unless the scanner itself cannot produce a valid result.
5. `MaintenancePlanner` produces automatic, confirmation, reminder, and blocked
   groups.
6. The executor runs the automatic group with the configured concurrency limit.
7. Independent failures are recorded and do not stop other packages.
8. If confirmation items remain, the dashboard presents them after automatic work
   finishes. The user may run selected items or postpone all of them.
9. The verifier rechecks packages that ran.
10. Recovery actions are attached to failed or mismatched outcomes.
11. The run report is persisted and the dashboard switches to a completed,
    partial-success, cancelled, or failed summary.

### Daily inspection

Daily inspection uses the same scanner, planner, executor, verifier, and report
types, but it executes only the `automatic` group. It never attempts to display a
confirmation dialog. Confirmation, reminder, blocked, and failed items are exposed
through the persisted run, inbox, and existing notification policy.

### Existing upgrade page

The upgrade page remains available for detailed review. It consumes the same
`MaintenancePlan` and execution events. Starting work there uses the same global
lock and therefore cannot duplicate an active dashboard or daily run.

## Concurrency, Cancellation, and Recovery

- Exactly one maintenance workflow may hold the cross-process lease at a time.
- Manual smart maintenance, the upgrade page, foreground inspection, and the
  background agent all acquire the same lease before scanning or executing.
- When a foreground action finds an active lease, it shows the active-run state.
  When the background agent finds one, it logs the conflict and exits successfully
  without doing duplicate work.
- When the GUI loads reports written by the agent, it refreshes the dashboard rather
  than assuming ownership of the agent's completed run.
- Package execution respects `maxConcurrentUpgrades`.
- A package failure or timeout does not cancel unrelated work.
- User cancellation stops queue admission, cancels active tokens, and persists
  completed and cancelled package outcomes.
- A crash or forced termination does not attempt to resume shell commands. On the
  next launch, a stale cross-process lease causes its non-terminal run to be marked
  interrupted before the lease is reclaimed, and the next maintenance action
  starts with a new scan.
- Source failures produce actionable source-level recovery without executing a
  plan based on stale data for that source.

## Persistence and Migration

### `MaintenanceRunRecord`

The new versioned record contains:

- schema version and stable run identifier;
- trigger: manual smart maintenance, detailed manual upgrade, or daily inspection;
- start and finish timestamps;
- terminal status;
- scan summary and per-source availability;
- plan disposition for each visible item;
- command, verification, failure, and recovery outcome per executed package;
- counts used by the dashboard;
- references to related job and inbox records where available.

Records are stored atomically in:

```text
~/Library/Application Support/MacSoftwareSteward/maintenance-runs.json
```

The store retains a bounded newest-first history. A corrupt or unknown record does
not prevent the app from launching; the store reports the load problem and starts
with an empty readable history rather than executing any recovery command.

### Compatibility

- Existing `inspection-reports.json` and `upgrade-history.json` are never deleted.
- When the new store is empty, the dashboard may project the newest readable legacy
  records into a non-executable historical summary.
- During this implementation, completed workflows continue to write the legacy
  inspection and upgrade stores required by existing pages and exports.
- The automation data bundle gains an optional maintenance-run section and a
  backward-compatible schema update. Older bundles import with an empty
  maintenance-run collection.
- No legacy record is converted into a resumable workflow.

## Navigation and Information Architecture

Add `overview` to `AppTab` and make it the default and fallback tab.

Standard mode:

- `维护总览`
- `本机软件`
- `设置`

Advanced mode:

- `维护总览`
- `可升级`
- `本机软件`
- `自动化策略`
- `任务日志`
- `设置`

The dashboard is useful before the first scan: it presents a ready state and a
single `开始智能维护` action. It does not show zero values as if they were a
completed health assessment.

## Visual System

### Direction

The interface should feel like a native system diagnostic bench: calm enough for a
daily utility, but explicit about what the system is doing. The main visual
signature is the maintenance track showing scan, assessment, execution, and
verification as one connected process.

The UI does not use a marketing hero, decorative orbs, glass-heavy cards, or
constant ambient animation.

### Color tokens

- `Cloud Canvas` — `#F5F8FC`, the light-mode page canvas.
- `Console Sidebar` — `#EDF2F7`, a quiet navigation surface.
- `Instrument Surface` — `#FFFFFF`, primary panels and task rows.
- `Action Blue` — `#236FDF`, selection and executable primary actions.
- `Health Green` — `#2D9870`, verified health and successful outcomes.
- `Attention Orange` — `#D98A18`, confirmation and non-blocking attention.

Failures use the system semantic red rather than another hard-coded palette token.
Dark appearance derives canvas and surface fills from existing semantic
`AppSurfacePalette` roles, while preserving the functional meaning of blue, green,
orange, and red.

### Typography

- Page titles and health headlines use the system rounded display design with
  restrained weight.
- Body text uses the native system text face and macOS text sizes.
- Counts, durations, versions, progress, and command-like values use monospaced
  digits or the system monospaced design.
- Chinese UI copy remains primary; English uppercase labels are not introduced into
  the product UI.

### Dashboard layout

The dashboard scrolls as one page beneath the unified top rail:

1. Page heading and rescan action.
2. Health/status surface with the smart-maintenance action.
3. Four-phase maintenance track.
4. Metrics for managed software, automatic items, confirmation items, and next
   inspection.
5. Priority task list.
6. Automation and most-recent-run summary.

The layout becomes a single column at narrow window widths. Metrics wrap to two
columns before collapsing further. The design avoids nested scroll views and
card-in-card repetition.

### Whole-application polish

- Refine the sidebar around the new overview destination and keep settings quiet at
  the bottom.
- Keep the selected accent rail, hover distinction, and native split-view behavior.
- Align page headings, section spacing, filter bars, list rows, empty states,
  warnings, badges, and progress surfaces to shared spacing and surface tokens.
- Reuse shared SwiftUI modifiers and components instead of repeating raw colors and
  radii in page bodies.
- Preserve each page's information ownership; visual alignment does not move
  settings or diagnostics into unrelated pages.

### Motion

- The maintenance track animates only when its state advances.
- Scanning may use a restrained symbol rotation or pulse and phase-text transition.
- Package progress uses short opacity, offset, and progress transitions.
- Completion and failure enter once; they do not loop.
- Hover and selection remain short and subtle.
- Reduced-motion mode removes rotations, pulses, shimmers, and large transitions
  while preserving state through text, symbols, and color.

### Accessibility

- Status is never communicated by color alone.
- Controls keep visible keyboard focus and useful accessibility labels.
- Text may wrap rather than truncate critical failure or recovery instructions.
- Primary and secondary actions maintain comfortable macOS click targets.
- System semantic colors and materials preserve light/dark contrast.
- Confirmation sheets put initial focus on the review content, not the destructive
  or execution action.

## Error and Empty States

- Before the first scan: neutral ready state with `开始智能维护`.
- No updates: verified all-clear state with last-scan time.
- Partial source failure: available sources remain visible and safe; unavailable
  source items are blocked with a recovery action.
- Whole-scan failure: no plan executes, and the dashboard explains how to retry.
- Package failure: the package row shows the failure and recovery action while
  unrelated work continues.
- Verification mismatch: show that the command completed but the installed version
  could not be confirmed.
- Confirmation postponed: keep items in the dashboard's attention section without
  marking the run as failed.
- Cancellation: distinguish completed, cancelled, and never-started items.
- Interrupted previous run: show an interruption summary and require a new scan.

## Migration Sequence

1. Add Foundation-only workflow state, plan dispositions, protocol boundaries, and
   unit tests without changing existing callers.
2. Add the executor event contract and move queue, concurrency, cancellation, and
   package progress behavior behind it while `StewardModel` remains a facade.
3. Add verifier, recovery coordination, and the cross-process maintenance lease.
4. Add `MaintenanceRunStore`, legacy projections, dual writes, and bundle schema
   compatibility.
5. Connect the existing upgrade page and foreground inspection flows to the engine.
6. Connect the background agent to the Foundation-only workflow core.
7. Add the dashboard presenter, overview navigation, and dashboard UI.
8. Apply the shared visual polish to visible pages and remove migrated duplicate
   execution code from `StewardModel`.

Each step must leave the repository testable and buildable. No step combines an
unverified engine rewrite with the entire UI migration.

## Testing

### Unit tests

- Legal and illegal workflow state transitions.
- Plan classification across every combination of policy, risk level, automation
  decision, source availability, pinned state, and executable state.
- Confirmation items never entering the automatic queue.
- Blocked items never receiving executable commands.
- Cross-process lease acquisition, conflict handling, orderly release, stale-owner
  detection, and PID-reuse protection.
- Concurrency limits, independent package failure, timeout isolation, and user
  cancellation.
- Verification success and mismatch.
- Recovery action mapping.
- Run-record round trip, bounded history, interrupted-run handling, corrupt input,
  legacy projection, and data-bundle compatibility.
- Dashboard presenter models for ready, scanning, automatic execution, waiting for
  confirmation, partial success, failure, cancellation, and all-clear.
- Navigation visibility and fallback in standard and advanced modes.

### Repository verification

```bash
npm test
npm run build
```

### Manual QA

- Standard and advanced modes.
- Light and dark appearances.
- Normal and narrow window widths.
- Keyboard-only navigation and visible focus.
- Reduced-motion mode.
- First launch with no scan.
- All-clear scan.
- Automatic, confirmation, reminder, and blocked items in one plan.
- Partial Homebrew or App Store source failure.
- Concurrent execution with one package failure and one timeout.
- User cancellation.
- Verification mismatch and recovery actions.
- Relaunch after an interrupted run.
- Daily inspection followed by dashboard refresh.

## Acceptance Criteria

- The application defaults to `维护总览` in standard and advanced modes.
- One `开始智能维护` action performs a new scan, assesses risk, automatically
  executes only eligible low-risk automatic-policy packages, and verifies results.
- No medium-risk, high-risk, `askFirst`, reminder-only, skipped, pinned, blocked, or
  unavailable item executes without the required user decision.
- A package failure does not prevent independent packages from completing.
- Manual maintenance, the upgrade page, and daily inspection use the same plan
  classification and engine behavior appropriate to their interaction context.
- The final dashboard report clearly distinguishes success, partial success,
  failure, cancellation, postponed confirmation, and blocked work.
- Existing scanning, upgrade, acceleration, history, notification, self-update, and
  recovery tests continue to pass.
- The updated interface remains usable in light mode, dark mode, narrow windows,
  keyboard navigation, and reduced-motion mode.
- `npm test` and `npm run build` complete successfully.
