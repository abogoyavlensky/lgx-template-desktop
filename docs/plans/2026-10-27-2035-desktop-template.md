# lgx desktop template Implementation Plan

> **For agentic workers:** Use executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two things.
- Make lgx stream the output of `:sh` and `:run` task steps live, and give them the terminal's stdin.
- Turn this empty repo into `lgx-template-desktop`, a minimal but practical template that `lgx new` scaffolds. It produces a macOS-first desktop app: a let-go backend on Wails v3 and a Vite + React + Tailwind frontend, with an nREPL inside the running app, a native build and an unsigned `.app` package.

**Tech Stack:** let-go (`.lg`) managed by lgx 0.5.3 (0.5.2 plus the streaming fix); letgo-packages `wails`, `nrepl`, `sqlite`, `ragtime`; integrant; HoneySQL; Vite 8, React 19, TypeScript, Tailwind v4, oxlint; GitHub Actions; mise.

**Two repos:** Task 0 works in `/home/agent/Projects/lgx`. It opens a PR, merges it once CI passes, and releases lgx 0.5.3. The user authorized the release, including the tag push. Tasks 1–10 work in this repo on `master`, using the released lgx 0.5.3 from mise.

---

## Design

### Where it comes from

The template copies patterns from three projects. Read them when a task points at them:

- **Quel** (`/home/agent/Projects/quel`) is the shipped macOS app this template is cut down from. It supplies the native build, the frontend setup (`frontend/vite.config.ts`, `src/lib/bridge.ts`), `scripts/dev.sh`, `scripts/package-macos.sh`, the dev loop (`src/quel/dev.lg`), the system lifecycle (`src/quel/system.lg`) and the entry point (`src/quel/app.lg`).
- **wails-tasks** (`/home/agent/Projects/lgx/examples/wails-tasks`) is a smaller app with the same shape and sqlite through HoneySQL (`src/tasks/db.lg`, `migrations.lg`, `api.lg`, `menu.lg`, and its tests).
- **lgx-template-web** (`gh repo clone abogoyavlensky/lgx-template-web /tmp/tplweb/web`) is the sibling template. Match its README style, the `.cljfmt.edn` / `.clj-kondo` / `.gitattributes` files, the `fmt` / `lint` / `check` tasks, the greetings demo and the `projectname` conventions.

### How `lgx new` treats this repo

`lgx new my-app -t https://github.com/abogoyavlensky/lgx-template-desktop` clones the repo and copies **every tracked file** into the new project (`/home/agent/Projects/lgx/lgx/new.lg`, `render!`):

- File contents: every literal `projectname` becomes the hyphenated name (`my-app`).
- Path segments: every `projectname` becomes the underscored name (`src/my_app/`).
- Binary files survive this unchanged. A PNG round-trip through `slurp`, `str/replace` and `spit` was checked to be byte-identical.

So:

- Every place that should carry the app's name uses `projectname` literally: namespaces, the binary name, the data dir, the window title, the bundle ID, `package.json` `name`.
- Nothing in the repo may be specific to this template's own development. **This plan file is removed in the last task**, because `docs/plans/` would otherwise be copied into every new project. Its history stays in git.
- `lgx new` prints `lgx run` as the next step, and `lgx run` must work on a fresh project. `resources/public` is build output (gitignored), so `run` is overridden to build the frontend first.

### lgx: stream task steps (Task 0)

Today lgx runs a `:sh` step with `os/sh "sh" "-c" cmd` (`lgx/tasks.lg`, `run-sh-step!`) and a `:run` step through `runner/invoke-lg!`, which uses `os/sh` too. Both capture the child's stdout and stderr and replay them only after it exits, and neither connects stdin. A `:task` step and `lgx run` already stream: they go through `runner/exec-interactive!` (`lgx/runner.lg`), which runs `os/exec*` with inherited stdio and the tty workaround for let-go 1.13.0.

The fix routes both step kinds through that same path:
- `run-sh-step!` returns `(runner/exec-interactive! "sh" ["-c" cmd])`.
- `run-run-step!` gets `[bin args]` from `runner/lg-invocation!` and returns `(runner/exec-interactive! bin args)`. `lg-invocation!` becomes public. `exec-lg-interactive!` can't be used here because it calls `os/exit`, and a task has to continue with its next step.
- Exit codes, the step header line, `LGX_RUN` handling and the stop-at-first-failure behaviour don't change.

`invoke-lg!` and `run-lg!` stay as they are for `lgx test` and `lgx build`, which need captured output. Docs that describe the replay change in the same PR: `README.md` (~line 660), `docs/ARCHITECTURE.md` (the `:sh` bullet ~line 674 and the "task `:run` steps still use the captured `os/sh` path" sentence ~line 259), and the header comment in `lgx/tasks.lg`.

### Scripts stay bash

`scripts/dev.sh` and `scripts/package-macos.sh` are bash, ported from Quel with few changes. Quel's versions have already shipped, and bash's `set -m` process groups and `trap` cleanup are what make `lgx dev` reliable. let-go can't start a background process on macOS (`os/spawn` is Linux-only). Tasks run them as `:sh` steps, which stream after Task 0.

### Decisions (settled in discussion)

- **The native build, with let-go pinned to a commit.** `:targets {:bin {:target :native ...}}` compiles the program to Go, which gives an ordinary Mach-O binary that can be codesigned. An `lg -b` binary with bytecode appended fails strict codesign validation (Quel's plan, `docs/plans/2026-10-24-1428-macos-homebrew-release.md`). The native build needs `lg compile -module/-import`, which is not in let-go 1.13.0. Pin `:lg-version "18df3ad5c033cbf8f214c7d2a09e97f78a642510"`, the commit Quel ships with, and add a comment saying to bump it to the first let-go release that contains it. lgx 0.5.2 is the first lgx with native builds of this kind. The template pins 0.5.3 for the streaming fix.
- **Scripts stay bash, as in Quel**; see "Scripts stay bash".
- **The entry point is `src/projectname/app.lg`, not `main.lg`.** `lg compile` rejects a namespace whose last segment is `main`. Nothing may require the entry namespace, because it ends in `(when-not *compiling-aot* (-main))`.
- **Frontend: Vite + React + TypeScript + Tailwind v4 + oxlint.** No shadcn, state library, vitest or Playwright. Keep Quel's `vite.config.ts` essentials: output to `../resources/public`, port 5173 with `strictPort`, and the HMR websocket aimed straight at Vite.
- **nREPL inside the app**, as in Quel. It starts under `lgx run` / `lgx dev` (which set `LGX_RUN`), never in a built binary. The README gets a short section on how it works.
- **SQLite + ragtime + HoneySQL**, with the web template's greetings demo.
- **Packaging: an unsigned `.app` only.** `lgx package-macos` builds natively for Apple Silicon and assembles `dist/projectname.app` (icon, `Info.plist`). It has no signing, notarization, release workflow, Homebrew tap, `verify-macos` or release-script tests. The README points to Quel's `docs/RELEASE.md` and its workflows as the worked example of a signed release.
- **CI: Linux only, in Wails' server mode** (`CGO_ENABLED=0 GOFLAGS=-tags=server`). It runs `lgx check`, then `lgx build`, which also proves that the native build compiles; Quel did this on Linux. There is no macOS job.
- **A basic placeholder icon** (1024×1024 PNG).

### Decisions made in planning (open to veto)

- **Names that need a human touch stay `projectname`, with a comment where to change them.** That covers the app display name, the bundle ID `com.example.projectname` and the window title. `lgx new` can't capitalise a name or invent a reverse-DNS prefix. `scripts/package-macos.sh` holds `APP_NAME`, `BUNDLE_ID`, `EXECUTABLE` and `MACOS_MIN` at its top, and `Info.plist` is a template with `@APP_NAME@`, `@BUNDLE_ID@`, `@EXECUTABLE@`, `@VERSION@` and `@MACOS_MIN@`. The two `projectname` uses in `system.lg` carry the same comment.
- **The version lives in a `VERSION` file** (`0.1.0`), as in Quel, so the README's pointer to Quel's release scripts applies without changes.
- **Menu events: the menu emits and the frontend does the work** (Quel's pattern, `src/quel/menu.lg`). File > Clear Greetings (`CmdOrCtrl+Shift+Backspace`) emits `menu:clear-greetings`. The page listens and calls the `clear-greetings` handler. This shows menu → event → frontend → handler in one item, and the menu component needs only the app.
- **The frontend dependencies are installed when missing.** A `fe-deps` task runs `npm --prefix frontend ci` only when `frontend/node_modules` is absent. `fe-build`, `lint` and `scripts/dev.sh` use it, so `lgx run`, `lgx build`, `lgx check` and `lgx dev` all work on a fresh project. To resync after `package-lock.json` changes, run `npm --prefix frontend ci` (the README says so).
- **`scripts/dev.sh` runs `lgx lgx:run`**, not `lgx run`. Under the dev server the frontend comes from Vite, so the `run` override's frontend build would be wasted time.
- **The database path is `DB_PATH` when set, otherwise `<w/data-dir "projectname">/projectname.db`.** `w/data-dir` creates the directory. The variable name matches the web template, and the tests point it at a temp file.

### Backend shape

integrant starts these components in dependency order. `projectname.system/system*` (a `defonce` atom) holds the running system:

| Key | Is | Depends on |
|---|---|---|
| `:projectname.db/conn` | the sqlite connection, migrated on init, closed on halt | |
| `:projectname.api/handlers` | the frontend's handlers, registered by var over the connection | the connection |
| `:projectname.shell/app` | the Wails application (`:assets "public"`, `:on-shutdown` → `stop!`) | |
| `:projectname.shell/window` | the main window | the app |
| `:projectname.menu/menu` | the application menu | the app |
| `:projectname.dev/loop` | the nREPL and the asset watcher, under `lgx run` only | the window |

- **`app.lg`**: `-main` starts the system, blocks in `w/run!`, which must run on the main thread, and calls `system/stop!` in a `finally`. A start failure prints the chain of causes and exits 1. An error value returned from `w/run!` exits 1. Copy Quel's `src/quel/app.lg`.
- **`system.lg`**: Quel's `start!` (halts the partly built system when an init fails) and `stop!` (race-safe through the `halted*` promise), with this template's `config`.
- **`api.lg`**: three handlers, each taking the connection first and then the JavaScript arguments:
  - `list-greetings` returns at most 10 rows, newest first.
  - `add-greeting` takes a name, trims it, throws `ex-info "A greeting needs a name."` when it is blank, and returns the row.
  - `clear-greetings` returns the number of rows deleted.

  The `handlers` map goes from the name string to the var. Its init-key registers `(partial v db)` with `w/handler!` and returns the set of names.
- **`dev.lg`**: Quel's `src/quel/dev.lg`, renamed. It includes the "resources/public is missing" error, adjusted to suggest `lgx fe-build` or `lgx dev`.

### Frontend shape

- `src/lib/bridge.ts`: Quel's 18-line `call(name, ...args)` and `onEvent(name, fn)` over `@wailsio/runtime`.
- `src/App.tsx`: one component.
  - It loads greetings on mount, has a name input with an Add button (Enter submits), and shows "Hello, {name}!" rows.
  - A rejected call shows the error message inline.
  - It subscribes to `menu:clear-greetings` (cleaned up on unmount); the handler calls `clear-greetings` and reloads.
  - Tailwind utility classes, light and dark through `prefers-color-scheme` (Tailwind v4's default `dark:` variant).
- `src/main.tsx`: StrictMode root. `src/index.css`: `@import "tailwindcss";`.

### Testing

- **Backend** (`lgx test`; on Linux without GTK, prefix `CGO_ENABLED=0 GOFLAGS=-tags=server`):
  - db queries and migrations against a temp sqlite file;
  - the api handlers as plain functions (trimming, blank name rejected, `handlers` values are vars);
  - the menu spec (plain data, every `:on-click` goes through a var, `w/check-menu` accepts it);
  - the system config (keys and refs, `DB_PATH` override, `stop!` with nothing running, a failed start halts what it built);
  - `dev?` reading `LGX_RUN`.
- **Frontend**: `tsc -b` (inside `npm run build`) and oxlint. No unit tests (YAGNI for a template).
- **End to end, on this Linux box**: scaffold a fresh project from the committed template with `lgx new … -t file://…`. Run `lgx check` and `lgx build` there, then run the app in server mode and drive the bridge and the nREPL over HTTP (Task 10).
- **lgx**: its unit tests and `tests/e2e.sh`, plus new e2e scenarios that prove `:sh` and `:run` steps stream and read stdin.
- **macOS (manual, on the user's Mac)**: `lgx dev` opens a window and HMR works; the menu item clears the list; `lgx build && ./bin/<name>`; `lgx package-macos && open dist/<name>.app`. This box has no GTK or macOS, so record these as pending, not passed.

## File Structure

```
lgx-template-desktop/
├── .github/workflows/checks.yml  Linux server-mode CI: fe-deps, lgx check, lgx build
├── .clj-kondo/config.edn         from the web template (os/io builtins)
├── .cljfmt.edn                   from the web template
├── .gitattributes                *.lg linguist-language=Clojure
├── .gitignore                    bin/ dist/ resources/public/ frontend/node_modules/ *.db .nrepl-port .tmp/ editor dirs
├── .mise.toml                    go, node, lgx 0.5.3, cljfmt, clj-kondo (no lg: :lg-runtime :built)
├── LICENSE                       MIT, from the web template
├── README.md                     quickstart, dev loop, nREPL, layout, build/package, server mode, releases → Quel
├── VERSION                       0.1.0
├── lgx.edn                       paths, :main, let-go pin, native :bin target, deps, tasks
├── build/macos/Info.plist        bundle metadata template (@…@ placeholders)
├── build/macos/icon.png          1024×1024 placeholder icon
├── scripts/dev.sh                Vite dev server + app with FRONTEND_DEVSERVER_URL (from Quel)
├── scripts/package-macos.sh      native arm64 build → dist/projectname.app (from Quel, trimmed)
├── src/projectname/app.lg        entry point (start, run, stop)
├── src/projectname/system.lg     integrant config, start!/stop!, system*
├── src/projectname/shell.lg      ::app and ::window components
├── src/projectname/db.lg         ::conn component + greeting queries
├── src/projectname/migrations.lg ragtime history (001-create-greetings)
├── src/projectname/api.lg        handlers, registered by var
├── src/projectname/menu.lg       menu spec + install!
├── src/projectname/dev.lg        nREPL + asset watcher under lgx run
├── test/projectname/db_test.lg
├── test/projectname/api_test.lg
├── test/projectname/menu_test.lg
├── test/projectname/system_test.lg
├── test/projectname/dev_test.lg
└── frontend/
    ├── package.json, package-lock.json
    ├── index.html                title projectname, #root, /src/main.tsx
    ├── vite.config.ts            from Quel, minus the vitest block
    ├── tsconfig.json, tsconfig.app.json, tsconfig.node.json   from Quel
    ├── .oxlintrc.json            from Quel
    ├── .gitignore                node_modules (mirrors Quel's frontend/.gitignore)
    └── src/main.tsx, App.tsx, index.css, lib/bridge.ts
```

---

### Task 0: lgx streams `:sh` and `:run` task steps

Work in `/home/agent/Projects/lgx`. The design section "lgx: stream task steps" explains the change.

**Files:**
- Modify: `lgx/tasks.lg` (`run-sh-step!`, `run-run-step!`, header comment), `lgx/runner.lg` (make `lg-invocation!` public; drop the `-` and update its docstring)
- Modify: `README.md` (~line 660), `docs/ARCHITECTURE.md` (~lines 259 and 674)
- Test: `tests/e2e.sh` (new scenarios after Scenario 15), `test/lgx/tasks_test.lg` if it asserts on the replay

- [x] **Step 1: Branch.** Run: `cd /home/agent/Projects/lgx && git switch master && git pull --ff-only && git switch -c stream-task-steps`

- [x] **Step 2: Write the failing e2e scenarios** in `tests/e2e.sh`, in the style of Scenarios 13–15 (`$proj_t`, `LGX_HOME="$home_t"`):
  - **`:sh` streams.** The task is `{:sh "echo first; sleep 3; echo second"}`. Run `lgx` in the background with stdout going to a temp file. After about 1 s the file contains `first` but not `second`; after the process exits it has both. (Today the file stays empty until exit.)
  - **`:sh` reads stdin.** The task is `{:sh "read x; echo got $x"}`, and `echo hi | lgx <task>` prints `got hi`.
  - **`:run` streams.** Write `s.lg` doing `(println "first") (sleep 3000) (println "second")`, give the task `{:run "s.lg"}`, and use the same timing check as the first scenario.
  - **`:run` reads stdin.** `r.lg` does `(println "got" (read-line))`; `echo hi | lgx <task>` prints `got hi`.
  - **Exit codes still propagate.** `{:sh "exit 7"}` exits 7. Skip this if Scenario 16 already covers it.

- [x] **Step 3: Run them to see them fail.**
  Run: `make build && LGX=$PWD/bin/lgx bash tests/e2e.sh 2>&1 | tail -20` (check the top of `tests/e2e.sh` for how it picks the binary, and use that).
  Expected: the new streaming and stdin scenarios FAIL; the rest pass.

- [x] **Step 4: Implement** as the design describes. Keep `invoke-lg!` and `run-lg!` for `test`/`build`.

- [x] **Step 5: Run every lgx test.**
  Run: `make build && make test` (or the repo's test command from its Makefile/README), then the e2e command from Step 3.
  Expected: everything passes, the new scenarios included.

- [x] **Step 6: Update the docs** listed under Files, so nothing claims that `:sh`/`:run` output is buffered and replayed. Per lgx's AGENTS.md, docs change in the same PR.

- [x] **Step 7: Commit, push, open a PR.**
  `git commit -am "Stream :sh and :run task steps and connect stdin"`, then `git push -u origin stream-task-steps` and `gh pr create --base master --fill`. Link the PR to this thread with the t3 `link_pull_request` tool.

- [x] **Step 8: Merge once CI passes.** Run `gh pr checks --watch`; every check must pass (`test.yml`). Fix any failures on the branch first. Then merge the way earlier PRs were merged, as one squashed commit with `(#N)` in the subject: `gh pr merge --squash --delete-branch`. Then `git switch master && git pull --ff-only`.

- [x] **Step 9: Release 0.5.3.** The user authorized this, including the tag push. Follow the existing pattern (`ce0fc90 Bump version to 0.5.2`):
  1. Set `(def version "0.5.3")` in `lgx.lg`.
  2. `git commit -am "Bump version to 0.5.3" && git push origin master`.
  3. `make release`, which tags `v0.5.3` and pushes the tag.
  4. Watch the release workflow until it finishes green: `gh run list --workflow release.yml --json databaseId,headBranch,event -q '.[] | select(.headBranch=="v0.5.3") | .databaseId'` picks the run for the tag; then `gh run watch <id> --exit-status`.

  Expected: `gh release view v0.5.3` lists the platform archives and `checksums.txt`, and the workflow's tap step committed `lgx 0.5.3` to the Homebrew tap. If the workflow fails, stop and report. Don't delete or re-push tags without asking the user.

- [x] **Step 10: Install the release.** Run: `mise install lgx@0.5.3` (with the template's `.mise.toml` alias `github:abogoyavlensky/lgx`, or `mise install github:abogoyavlensky/lgx@0.5.3`), then `mise exec lgx@0.5.3 -- lgx --version`.
  Expected: `lgx 0.5.3`. Tasks 1–10 use this lgx through the template's `.mise.toml`.

> Deviation (Task 0): new e2e scenarios are 181-183 (the file runs to Scenario 180; the "after Scenario 15" pointer was stale). The exit-code scenario was skipped because Scenario 16 covers `:sh`; a `:run` exit-code scenario (183) was added instead. The streaming check polls for `first` for up to 3.5 s against a 5 s child instead of a fixed 1 s sleep.
> Deviation (Task 0): PR #71 was merged after CI went green (watched via T3's PR watch, not `gh pr checks --watch`). No codex review ran for Task 0, because the change was already merged and released through lgx's own CI.
> Result (Task 0): PR https://github.com/abogoyavlensky/lgx/pull/71 merged as b45936d; release https://github.com/abogoyavlensky/lgx/releases/tag/v0.5.3 (workflow green, tap updated); `lgx 0.5.3` installed via mise.

### Task 1: Project config and tooling

> Deviation: the work is on branch `desktop-template` (the executing-plans skill creates a branch), not `master`. `lgx new -t file://…` clones the checked-out branch, so scaffolding still works. The template must be merged to `master` before the `https://` URL in the README works.

**Files:**
- Create: `.mise.toml`, `lgx.edn`, `.gitignore` (replace the empty one), `.gitattributes`, `.cljfmt.edn`, `.clj-kondo/config.edn`, `LICENSE`, `VERSION`

- [ ] **Step 1: Copy the sibling files.** Clone the web template (`gh repo clone abogoyavlensky/lgx-template-web /tmp/tplweb/web -- --depth 1` if `/tmp/tplweb/web` is missing). Copy `.cljfmt.edn`, `.clj-kondo/config.edn`, `.gitattributes` and `LICENSE` unchanged. Write `VERSION` containing `0.1.0`.

- [ ] **Step 2: `.mise.toml`.** Use the web template's layout and comment about why `lg` is absent. Tools: `go = "1.27"`, `node = "24"`, `lgx = "0.5.3"`, and `cljfmt` and `clj-kondo` at the web template's pins, with the same `[tool_alias]` entries.

- [ ] **Step 3: `.gitignore`.** Merge the web template's list with Quel's: `bin/`, `dist/`, `resources/public/`, `frontend/node_modules/`, `*.db`, `*.lgb`, `.nrepl-port`, `.nrepl-history`, `.tmp/`, `.DS_Store`, `.idea/`, `.lsp/`, `.vscode`, `.calva`, `.clj-kondo/.cache/`, `.env`.

- [ ] **Step 4: `lgx.edn`.** Keep Quel's comment style: one short comment per non-obvious entry.
  - `:paths ["src"]`, `:resource-paths ["resources"]`, `:main "src/projectname/app.lg"` (with the comment on why it isn't `main`).
  - `:lg-runtime :built`, `:lg-version "18df3ad5c033cbf8f214c7d2a09e97f78a642510"` with the comment: a let-go `main` commit, because the native build needs `lg compile -module` / `-import`, newer than 1.13.0; bump to the first release that has them.
  - `:targets {:bin {:target :native :out "bin/projectname" :go/build-tags ["production"]}}`, with Quel's comment on native and production.
  - `:deps`, at the tags Quel uses: `abogoyavlensky/letgo-wails` `wails-v0.3.0`, `abogoyavlensky/letgo-nrepl` `nrepl-v0.1.0`, `abogoyavlensky/letgo-sqlite` `sqlite-v0.3.0`, `abogoyavlensky/letgo-ragtime` `ragtime-v0.3.0` (all `:deps/root` into `https://github.com/abogoyavlensky/letgo-packages`), `dev.weavejester/dependency` `1.0.1`, `dev.weavejester/integrant` `1.0.1`, and `com.github.seancorfield/honeysql` `v2.7.1479`.
  - `:tasks`:

    ```clojure
    fe-deps  {:doc "Install the frontend's npm packages if they are missing"
              :do {:sh "test -d frontend/node_modules || npm --prefix frontend ci"}}
    fe-build {:doc "Build the frontend into resources/public"
              :do [{:task fe-deps} {:sh "npm --prefix frontend run build"}]}
    fe-watch {:doc "Rebuild the frontend on every change (the window reloads under lgx run)"
              :do [{:task fe-deps} {:sh "npm --prefix frontend run watch"}]}
    dev      {:doc "Run the app with the frontend from Vite's dev server (HMR)"
              :do {:sh "bash scripts/dev.sh"}}
    run      {:doc "Build the frontend, then run the app (nREPL inside)"
              :do [{:task fe-build} {:task [lgx:run :args/rest]}]}
    build    {:doc "Build the frontend, then the native binary"
              :do [{:task fe-build} {:task lgx:build}]}
    package-macos {:doc "Build dist/projectname.app (unsigned) on an Apple Silicon Mac"
                   :do {:sh "bash scripts/package-macos.sh"}}
    fmt      ;; the web template's, unchanged (fix | check)
    lint     {:doc "Lint the backend (clj-kondo) and the frontend (oxlint)"
              :do [{:sh "find src test -type f -name '*.lg' -print0 | xargs -0 clj-kondo --lint"}
                   {:task fe-deps}
                   {:sh "npm --prefix frontend run lint"}]}
    check    {:doc "Run all checks"
              :do [{:sh "lgx fmt check"} {:sh "lgx lint"} {:task fe-build} {:sh "lgx test"}]}
    ```

    lgx runs a string `:sh` value through `sh -c` (`lgx/lgx/tasks.lg`, `run-sh-step!`), so `||` works as written. Don't switch to the vector form: it shell-quotes each item. Leave out the web template's `release` task.

    With Task 0, every step kind streams, so `lgx dev`, `lgx fe-watch` and `lgx package-macos` show live output.

- [ ] **Step 5: Validate.**
  Run: `mise trust && mise install && lgx --version && lgx info`
  Expected: `lgx 0.5.3`, and the tasks listed with no config validation errors. (`lgx info` may start building the runtime, which can take minutes the first time.)

- [ ] **Step 6: Commit.** `git add -A && git commit -m "Project config: lgx.edn, mise, formatter and linter"`

### Task 2: Database and migrations

**Files:**
- Create: `src/projectname/migrations.lg`, `src/projectname/db.lg`
- Test: `test/projectname/db_test.lg`

- [ ] **Step 1: Write `migrations.lg`.** Copy the web template's `src/projectname/migrations.lg` (`migrations`, `migrate!`, `rollback!`). The single migration is `001-create-greetings`: `id integer primary key`, `name text not null`.

- [ ] **Step 2: Write the failing tests** in `db_test.lg`, modelled on wails-tasks' `test/tasks/db_test.lg`:
  - a public `with-conn` helper that opens a temp sqlite file, migrates it and deletes it afterwards;
  - add, then list, returns the row with `:id` and `:name`;
  - the list is newest first and capped at 10;
  - `clear-greetings!` deletes everything and returns the count;
  - `rollback!` then `migrate!` works, so the migration's down step is valid.

- [ ] **Step 3: Run them to see them fail.**
  Run: `CGO_ENABLED=0 GOFLAGS=-tags=server lgx test`
  Expected: FAIL (`projectname.db` is missing).

- [ ] **Step 4: Write `db.lg`.** Base it on the web template's `db.lg`: the `::conn` init-key, which opens, migrates, and closes the connection again if migration throws (wails-tasks' version); the `::conn` halt-key, which closes; `list-greetings`; `add-greeting!`, which uses `RETURNING`. Add `clear-greetings!`, which returns `:sql/update-count`.

- [ ] **Step 5: Run the tests.**
  Run: `CGO_ENABLED=0 GOFLAGS=-tags=server lgx test`
  Expected: PASS.

- [ ] **Step 6: Commit.** `git add -A && git commit -m "Greetings table and queries over sqlite"`

### Task 3: API handlers

**Files:**
- Create: `src/projectname/api.lg`
- Test: `test/projectname/api_test.lg`

- [ ] **Step 1: Write the failing tests** (pattern: wails-tasks `test/tasks/api_test.lg`, reusing `with-conn` from `db_test`):
  - `add-greeting` trims the name;
  - a blank name throws a message containing "name";
  - `clear-greetings` returns the count and empties the list;
  - every value in `api/handlers` is a var, and the keys are exactly `#{"list-greetings" "add-greeting" "clear-greetings"}`.

- [ ] **Step 2: Run them to see them fail.** Run: `CGO_ENABLED=0 GOFLAGS=-tags=server lgx test`. Expected: FAIL.

- [ ] **Step 3: Write `api.lg`.** Follow the design's API shape. Keep wails-tasks' comments on why handlers are registered by var.

- [ ] **Step 4: Run the tests.** Same command. Expected: PASS.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "Frontend handlers, registered by var"`

### Task 4: Shell, menu, dev loop, system and entry point

**Files:**
- Create: `src/projectname/shell.lg`, `src/projectname/menu.lg`, `src/projectname/dev.lg`, `src/projectname/system.lg`, `src/projectname/app.lg`
- Test: `test/projectname/menu_test.lg`, `test/projectname/system_test.lg`, `test/projectname/dev_test.lg`

- [ ] **Step 1: Write the failing tests.**
  - `menu_test.lg` (pattern: Quel's `test/quel/menu_test.lg` and wails-tasks' `every-on-click-is-hot`):
    - the spec is a vector;
    - exactly one `:on-click`, and with `with-redefs` on `menu/clear-greetings!` the click calls the redefined fn with the env;
    - `w/check-menu` accepts the spec once `(w/new-app {:name "projectname-test"})` exists.
  - `system_test.lg` (pattern: Quel's `test/quel/system_test.lg`):
    - the config names exactly the six keys in the design;
    - the window, menu and dev loop refs point where the design says;
    - `DB_PATH` set to a temp path shows up in `[:projectname.db/conn :path]`;
    - `stop!` with nothing running returns nil;
    - a failed start halts what it built;
    - `ig/init` of `[:projectname.api/handlers]` with `DB_PATH` set to a temp file starts the db and the handlers without a window (wails-tasks' `the-handlers-start-over-a-migrated-db`), then halts.
  - `dev_test.lg`: wails-tasks' `dev-only-under-lgx-run`, unchanged apart from the namespace.

- [ ] **Step 2: Run them to see them fail.** Run: `CGO_ENABLED=0 GOFLAGS=-tags=server lgx test`. Expected: FAIL.

- [ ] **Step 3: Write `shell.lg`.** Quel's `src/quel/shell.lg` with the namespace renamed.

- [ ] **Step 4: Write `menu.lg`.** Base it on Quel's `src/quel/menu.lg`, trimmed down:
  - `reporting`;
  - one `emitter`-made `clear-greetings!` emitting `menu:clear-greetings`;
  - `spec` with `{:role :app-menu}`, a File menu (Clear Greetings with `:accelerator "CmdOrCtrl+Shift+Backspace"` and `:on-click (partial #'clear-greetings! env)`, a separator, `{:role :quit}`), then `{:role :edit-menu}` and `{:role :window-menu}`;
  - `install!`;
  - the `::menu` init-key.

  Keep the header comment showing how to rebuild the menu from the nREPL.

- [ ] **Step 5: Write `dev.lg`.** Quel's `src/quel/dev.lg`, renamed. Change the missing-frontend message to suggest `lgx fe-build` or `lgx dev`.

- [ ] **Step 6: Write `system.lg`.** Quel's `src/quel/system.lg` structure (`system*`, `halted*`, `start!`, `stop!`), with this config:
  - `:projectname.db/conn {:path (db-path)}`, where `db-path` is `DB_PATH` when not blank, else `(str (w/data-dir "projectname") "/projectname.db")`;
  - `:projectname.api/handlers {:db (ig/ref :projectname.db/conn)}`;
  - `:projectname.shell/app {:name "projectname" :description "A let-go desktop app" :assets "public" :quit-on-last-window-closed true :on-shutdown (fn [] (stop!))}`;
  - `:projectname.shell/window {:app … :title "projectname" :width 900 :height 640 :min-width 480 :min-height 400}`;
  - `:projectname.menu/menu {:app …}`;
  - `:projectname.dev/loop {:window …}`.

  Comment the name and title: "the display name; change it to your app's (e.g. "My App")".

- [ ] **Step 7: Write `app.lg`.** Quel's `src/quel/app.lg`, renamed (`fail!` prints `projectname: …`), ending with `(when-not *compiling-aot* (-main))`.

- [ ] **Step 8: Run the tests.** Run: `CGO_ENABLED=0 GOFLAGS=-tags=server lgx test`. Expected: PASS.

- [ ] **Step 9: Format and lint the backend.**
  Run: `cljfmt fix && cljfmt check && find src test -type f -name '*.lg' -print0 | xargs -0 clj-kondo --lint`
  Expected: no diffs, and no lint errors (warnings that are let-go builtins: extend `.clj-kondo/config.edn` the way the web template does).

- [ ] **Step 10: Commit.** `git add -A && git commit -m "Wails shell, menu, dev loop and system wiring"`

### Task 5: Frontend

**Files:**
- Create: `frontend/package.json`, `frontend/package-lock.json`, `frontend/index.html`, `frontend/vite.config.ts`, `frontend/tsconfig.json`, `frontend/tsconfig.app.json`, `frontend/tsconfig.node.json`, `frontend/.oxlintrc.json`, `frontend/.gitignore`, `frontend/src/main.tsx`, `frontend/src/App.tsx`, `frontend/src/index.css`, `frontend/src/lib/bridge.ts`

- [ ] **Step 1: `package.json`.**
  - `"name": "projectname-frontend"`, private, `"type": "module"`.
  - Scripts: `dev` (`vite`), `build` (`tsc -b && vite build`), `watch` (`vite build --watch`), `lint` (`oxlint`).
  - Dependencies: `react`, `react-dom`, and `@wailsio/runtime` pinned **exactly** to Quel's `3.0.0-beta.30`, the Wails version wails-v0.3.0 speaks.
  - devDependencies: `vite`, `@vitejs/plugin-react`, `typescript`, `@types/react`, `@types/react-dom`, `@types/node`, `tailwindcss`, `@tailwindcss/vite`, `oxlint`, at Quel's ranges (`/home/agent/Projects/quel/frontend/package.json`).

- [ ] **Step 2: Config files.** Copy Quel's `tsconfig.json`, `tsconfig.app.json`, `tsconfig.node.json`, `.oxlintrc.json` and `frontend/.gitignore`. Then write `vite.config.ts` from Quel's: import `defineConfig` from `vite` (not `vitest/config`), drop the `test` block and `chunkSizeWarningLimit`, and keep the alias, `base: "/"`, the `server` block with its comment, and `build.outDir: "../resources/public"` with `emptyOutDir: true`. `index.html`: Quel's, with `<title>projectname</title>`.

- [ ] **Step 3: Source.** `src/lib/bridge.ts` is Quel's file verbatim. Write `src/index.css`, `src/main.tsx` and `src/App.tsx` as the design's frontend shape describes. Keep `App.tsx` small, about 80 lines. Give effects braced bodies, the rule from Quel's AGENTS.md.

- [ ] **Step 4: Install, build, lint.**
  Run: `npm --prefix frontend install && npm --prefix frontend run build && npm --prefix frontend run lint`
  Expected: `package-lock.json` is written, `resources/public/index.html` and `resources/public/assets/*` exist, and oxlint reports 0 errors.

- [ ] **Step 5: Commit** (`resources/public` stays untracked). `git add -A && git commit -m "Vite, React and Tailwind frontend over the Wails bridge"`

### Task 6: Dev script

**Files:**
- Create: `scripts/dev.sh`

- [ ] **Step 1: Write `scripts/dev.sh`** from Quel's `scripts/dev.sh`:
  - replace the `fe-install` line with `"$LGX" fe-deps`;
  - start the app with `"$LGX" lgx:run`, adding a comment that the `run` task's frontend build isn't needed under Vite;
  - keep the process-group handling, the port-in-use check and the wait-for-Vite loop.

  Make it executable.

- [ ] **Step 2: Check it in server mode, both ways it can stop.**
  1. Start `CGO_ENABLED=0 GOFLAGS=-tags=server WAILS_SERVER_PORT=8765 lgx dev` in the background, with output to a log.
  2. While it runs, the log already shows Vite's banner (streaming, from Task 0).
  3. Once it answers, `curl -fs http://localhost:8765/ | grep -q '/@vite/client'` succeeds and `.nrepl-port` exists.
  4. Kill the app's `lg` process to imitate closing the window (find it with `pgrep -af 'app.lg'`). Then `lgx dev` exits, and `curl -fs localhost:5173` fails because the trap stopped Vite.
  5. Start it again and send SIGINT to `lgx dev`'s process: nothing is left running (`pgrep -f vite` and `pgrep -af 'app.lg'` are empty).

  Expected: all of the above hold. If item 5 can't be driven from this harness, record it as a manual check rather than claiming it.

- [ ] **Step 3: Commit.** `git add -A && git commit -m "lgx dev: the app with Vite's dev server"`

### Task 7: macOS packaging

**Files:**
- Create: `build/macos/Info.plist`, `build/macos/icon.png`, `scripts/package-macos.sh`

- [ ] **Step 1: `Info.plist`.** Quel's `build/macos/Info.plist` with placeholders:
  - `CFBundleIdentifier` → `@BUNDLE_ID@`;
  - `CFBundleName` and `CFBundleDisplayName` → `@APP_NAME@`;
  - `CFBundleExecutable` and `CFBundleIconFile` → `@EXECUTABLE@`;
  - versions → `@VERSION@`, `LSMinimumSystemVersion` → `@MACOS_MIN@`;
  - drop `LSApplicationCategoryType`.

- [ ] **Step 2: Placeholder icon.** Generate a 1024×1024 RGBA PNG with a throwaway Go program in `/tmp` (stdlib `image`, `image/png`): a rounded square with a neutral two-tone gradient and a simple centred mark, transparent outside the rounded square, roughly following macOS icon-grid margins. Write it to `build/macos/icon.png`, and don't commit the generator.
  Verify: `file build/macos/icon.png` → `PNG image data, 1024 x 1024, 8-bit/color RGBA`.

- [ ] **Step 3: `scripts/package-macos.sh`.** Merge Quel's `scripts/package-macos.sh` and the parts of `macos-common.sh` it uses into one script:
  - At the top, an edit-me block: `APP_NAME="projectname"` (comment: the display name, e.g. "My App"), `BUNDLE_ID="com.example.projectname"` (comment: change to your reverse-DNS ID before you sign), `EXECUTABLE="projectname"`, `MACOS_MIN="15.0"`.
  - Then `die`, `read_version` (trims `VERSION`, requires MAJOR.MINOR.PATCH) and `require_apple_silicon`.
  - The body is Quel's: the cgo and server-tag guards, the deployment-target exports, `lgx build` teed to `dist/build.log` with the "built for newer" check, `sips`/`iconutil` into `dist/projectname.icns`, then a fresh `dist/$APP_NAME.app`, with the plist rendered by `sed` replacing all five placeholders and checked with `plutil -lint`.
  - Drop the `frontend/node_modules` check: `lgx build` runs `fe-deps`.
  - The final message names `open "dist/$APP_NAME.app"` and points to Quel's RELEASE.md for signing.

  Make it executable.

- [ ] **Step 4: Check what Linux can check.**
  1. `bash -n scripts/package-macos.sh && bash -n scripts/dev.sh` (one file per call: extra names are arguments, not checked), and `shellcheck` on both if it is installed.
  2. `lgx package-macos; echo "exit=$?"` stops at once with "needs an Apple Silicon Mac" and `exit=1`.
  3. The plist `sed` line, run by hand on `build/macos/Info.plist` with sample values: no `@` placeholders are left, and `python3 -c "import plistlib,sys; plistlib.loads(sys.stdin.buffer.read())"` accepts the output.

  Expected: all three. Record "package-macos not run end to end: needs a Mac" for the final report.

- [ ] **Step 5: Commit.** `git add -A && git commit -m "lgx package-macos: an unsigned .app around the native build"`

### Task 8: CI

**Files:**
- Create: `.github/workflows/checks.yml`

- [ ] **Step 1: Write `checks.yml`.**
  - Triggers: `push` to `master`, `pull_request`.
  - `concurrency` cancels superseded runs. `permissions: contents: read`.
  - One `ubuntu-latest` job with `env: CGO_ENABLED: "0"`, `GOFLAGS: -tags=server` and Quel's comment on why both are needed.
  - Steps: `actions/checkout@v7`, `jdx/mise-action@v5`, and `actions/cache@v6` over `~/.cache/go-build`, `~/go/pkg/mod`, `~/.lgx/runtimes` and `~/.npm`, keyed on `.mise.toml`, `lgx.edn` and `frontend/package-lock.json` (Quel's `ci.yml`).
  - Then `lgx fe-deps`, `lgx check`, and `lgx build` with the comment "proves the native build compiles".

- [ ] **Step 2: Validate the YAML.**
  Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/checks.yml'))" 2>/dev/null || ruby -ryaml -e "YAML.load_file('.github/workflows/checks.yml')"`
  Expected: no error. (Use `actionlint` if it is installed.)

- [ ] **Step 3: Run the CI commands locally, exactly as CI does.**
  Run: `CGO_ENABLED=0 GOFLAGS=-tags=server bash -c 'lgx fe-deps && lgx check && lgx build && ls -l bin/projectname'`
  Expected: all pass, and `bin/projectname` exists. lgx reports the project namespaces lowered to Go.

- [ ] **Step 4: Commit.** `git add -A && git commit -m "CI: checks and the native build in Wails' server mode"`

### Task 9: README

**Files:**
- Create: `README.md`

- [ ] **Step 1: Write the README** in the web template's voice and order. Use /writing-clearly. Sections:
  1. **Title and one-paragraph pitch**: a let-go desktop app on Wails v3, React frontend, sqlite; the bullet list of libraries (wails, nrepl, sqlite, ragtime, HoneySQL, integrant, Vite/React/Tailwind).
  2. **Quickstart**: `lgx new myapp -t https://github.com/abogoyavlensky/lgx-template-desktop`, `cd myapp`, `mise trust && mise install`, `lgx run`. Note that the first run builds a custom `lg` (Wails, sqlite, let-go pinned to a commit) and takes a few minutes.
  3. **Prerequisites**: Quel's platform table (macOS: Xcode CLT; Linux: `libgtk-4-dev libwebkitgtk-6.0-dev` + C compiler, with the window itself not yet verified on Linux; Windows not supported).
  4. **Development**: the command table (`lgx dev`, `lgx run`, `lgx fe-watch`, `lgx test`, `lgx fmt`, `lgx lint`, `lgx check`, `lgx build`, `lgx package-macos`), plus the note to run `npm --prefix frontend ci` after `package-lock.json` changes.
  5. **REPL in the running app**: short; this is the user's explicit ask. Cover:
     - `lgx run` and `lgx dev` start an nREPL inside the app process (`projectname.dev`), on a free port written to `.nrepl-port`, so your editor connects to the live app;
     - handlers and menu clicks are registered through vars, so re-evaluating a `defn` changes what the next click runs, with no restart;
     - `@projectname.system/system*` is the running system, a two-line example;
     - rebuild the menu with `(projectname.menu/install! (:projectname.menu/menu @projectname.system/system*))`;
     - changing `config` or an `init-key` needs a restart;
     - a built binary has no nREPL.
  6. **Layout**: a tree like the web template's, with a one-line role per file.
  7. **How it fits together**: the component table from the design, plus one sentence on `app.lg` and `w/run!`.
  8. **Build and package**: `lgx build` (native, embeds `resources/`, `production` tag); `lgx package-macos` → `dist/<name>.app`, unsigned (Gatekeeper: right-click → Open); where to set the display name and bundle ID (top of `scripts/package-macos.sh`, `system.lg`); the let-go pin and when to bump it.
  9. **Without a desktop**: server mode for Linux and CI (`CGO_ENABLED=0 GOFLAGS=-tags=server lgx run`, `WAILS_SERVER_PORT`); menus and dialogs do nothing there.
  10. **Releases**: not included. For a signed, notarized macOS release with GitHub Actions and a Homebrew cask, follow Quel: link `https://github.com/abogoyavlensky/quel` and its `docs/RELEASE.md`, `.github/workflows/release.yml` and `scripts/`. `VERSION` is already in place for it.
  11. **Conventions that bite** (3–5 bullets from Quel's AGENTS.md):
      - register by var;
      - nothing requires the entry namespace;
      - no `with-redefs` / `alter-var-root` in app code (the native build);
      - `os/getenv` returns `""`, so check with `str/blank?`;
      - React effects with braced bodies.

- [ ] **Step 2: Check every command and path in the README** against the files that exist (`lgx help` lists the tasks).

- [ ] **Step 3: Commit.** `git add -A && git commit -m "README"`

### Task 10: Verify a fresh scaffold end to end, then remove the plan

**Files:**
- Modify: this plan (record results), then delete `docs/`

- [ ] **Step 1: Scaffold from the committed template.**
  Run: `rm -rf /tmp/scaffold && mkdir /tmp/scaffold && cd /tmp/scaffold && lgx new my-app -t file:///home/agent/Projects/lgx-template-desktop`
  Expected: `Created my-app`, with next step `lgx run`. If `lgx new` rejects `file://`, push nothing. Instead `git clone` the repo to `/tmp/tpl-src`, run the scaffold from that URL form, and note it.

- [ ] **Step 2: Check the substitution.**
  Run: `cd /tmp/scaffold/my-app && grep -rn projectname . --exclude-dir=node_modules; ls src test`
  Expected: no `projectname` left; `src/my_app/` and `test/my_app/`; namespaces `my-app.*`; `docs/plans/` present (it is removed in Step 6, which is why).

- [ ] **Step 3: Check and build the scaffold exactly as CI does.**
  Run: `CGO_ENABLED=0 GOFLAGS=-tags=server bash -c 'mise trust && lgx fe-deps && lgx check && lgx build && ls -l bin/my-app'`
  Expected: all pass.

- [ ] **Step 4: Drive the running app in server mode.**
  1. Start `CGO_ENABLED=0 GOFLAGS=-tags=server WAILS_SERVER_PORT=8766 DB_PATH=/tmp/scaffold/test.db lgx run` in the background (the `run` override builds the frontend first).
  2. Wait for `curl -fs http://localhost:8766/` and for `.nrepl-port`.
  3. Call the bridge with the request shape from Quel's `scripts/server-mode.sh` (`call`): `add-greeting ["  Ada "]` returns `"name":"Ada"`; `list-greetings []` lists it; `add-greeting [" "]` answers with the "needs a name" message; `clear-greetings []` returns `1`.
  4. nREPL: `python3 /home/agent/Projects/letgo-packages/nrepl/test/nrepl/client.py "$(cat .nrepl-port)" "(alter-var-root #'my-app.api/list-greetings (constantly (fn [_] [{:id 0 :name \"redefined\"}])))"`. The next `list-greetings` call returns `redefined`.
  5. Stop the app, check that no `lg` process is left, and that `.nrepl-port` is removed.

  Expected: every check passes.

- [ ] **Step 5: Run the built binary on its own.**
  Run: `cd /tmp && DB_PATH=/tmp/scaffold/bin.db WAILS_SERVER_PORT=8767 /tmp/scaffold/my-app/bin/my-app &`, then `curl -fs http://localhost:8767/ | grep -q '<div id="root">'` and an `add-greeting` bridge call.
  Expected: the embedded frontend is served from an unrelated directory, the call works, and no `.nrepl-port` is written. Stop it.

- [ ] **Step 6: Record the results and remove the plan from the template.** Every file in this repo is copied into new projects, so `docs/` must not ship. Add a short "Verification" note to the final report covering:
  - what passed (Tasks 0, 6, 8, 10);
  - the merged lgx PR URL;
  - what is pending on a Mac: `lgx dev` window and HMR, Ctrl+C cleanup if Task 6 couldn't drive it, menu clear, `lgx build` + run, `lgx package-macos` + `open dist/my-app.app`;
  - the lgx 0.5.3 release URL (Task 0).

  Then run: `git rm -r docs && git commit -m "Remove the implementation plan from the template"`. The plan stays in git history.
  Expected: `git ls-files | grep -c '^docs/'` prints `0`.

- [ ] **Step 7: Scaffold the final template once more.**
  Run: `rm -rf /tmp/scaffold2 && mkdir /tmp/scaffold2 && cd /tmp/scaffold2 && lgx new my-app -t file:///home/agent/Projects/lgx-template-desktop && test ! -e my-app/docs && echo clean`
  Expected: `clean`.
