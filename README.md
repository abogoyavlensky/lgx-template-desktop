# projectname

A let-go desktop app: a [Wails v3](https://github.com/wailsapp/wails) window with a React
frontend, a sqlite database, and an nREPL inside the running app.

- [Wails](https://github.com/wailsapp/wails) opens the native window and bridges the frontend to let-go handlers
- [nrepl](https://github.com/abogoyavlensky/letgo-packages) starts an nREPL inside the app while you develop
- [sqlite](https://github.com/abogoyavlensky/letgo-packages) is the database, and [ragtime](https://github.com/weavejester/ragtime) runs the schema migrations
- [HoneySQL](https://github.com/seancorfield/honeysql) builds the queries as data
- [integrant](https://github.com/weavejester/integrant) wires the database, the handlers, the window, the menu and the dev loop
- [Vite](https://vite.dev), [React](https://react.dev) and [Tailwind](https://tailwindcss.com) build the frontend

The app is a greetings list: type a name, press Add, and the page lists the
ten newest greetings. File > Clear Greetings empties the list. It is small on
purpose. Replace the greetings with your own feature and keep the wiring.

Wails and the sqlite driver are Go packages, so `lgx.edn` sets
`:lg-runtime :built` and lgx builds the `lg` it runs on. That needs the Go
toolchain on `PATH` (mise installs it).

## Quickstart

Scaffold a project from this template with [lgx](https://github.com/abogoyavlensky/lgx)
and run it:

```bash
lgx new myapp -t https://github.com/abogoyavlensky/lgx-template-desktop
cd myapp
mise trust && mise install
lgx run
```

The first run builds a custom `lg` (Wails, sqlite, and a let-go pinned to a
commit) and takes a few minutes. Every run after that is a cache hit.

## Prerequisites

| Platform | Needs |
|---|---|
| macOS | Xcode Command Line Tools (`xcode-select --install`). Apple Silicon for `lgx package-macos`. |
| Linux | A C compiler, `libgtk-4-dev` and `libwebkitgtk-6.0-dev`. The window itself is not verified on Linux. Without the headers, see [Without a desktop](#without-a-desktop). |
| Windows | Not supported. |

[mise](https://mise.jdx.dev/getting-started.html) installs Go, Node, lgx,
cljfmt and clj-kondo at the versions in `.mise.toml`.

## Development

```bash
lgx --help
lgx dev            # the app, with the frontend from Vite's dev server (HMR)
lgx run            # build the frontend, then run the app (nREPL inside)
lgx fe-watch       # rebuild the frontend on every change; the window reloads
lgx test
lgx fmt            # lgx fmt check to only check
lgx lint           # clj-kondo for the backend, oxlint for the frontend
lgx check          # fmt check + lint + frontend build + test, what CI runs
lgx build          # frontend, then bin/projectname (native, resources embedded)
lgx package-macos  # dist/projectname.app, unsigned, on an Apple Silicon Mac
```

`lgx dev` starts Vite on port 5173 and the app on top of it. Edits to the
frontend apply in place and keep React state. Backend code changes go through
the nREPL (below). Closing the window, or pressing Ctrl+C, stops both.

`lgx run`, `lgx build` and `lgx check` install the frontend's npm packages
when `frontend/node_modules` is missing. After `frontend/package-lock.json`
changes, resync with `npm --prefix frontend ci`.

`DB_PATH` overrides where the database lives. By default it is
`projectname.db` in the app's data directory (`~/Library/Application Support/projectname`
on macOS, `~/.config/projectname` on Linux).

## REPL in the running app

`lgx run` and `lgx dev` start an nREPL inside the app process
(`projectname.dev`). It listens on a free port and writes the port to
`.nrepl-port`, so your editor connects to the live app, with its window,
database and menu.

- The frontend's handlers and the menu clicks are registered by var. Re-evaluate a
  `defn` and the next call or click runs the new code, with no restart.
- `@projectname.system/system*` is the running system, a map from integrant key
  to component:

  ```clojure
  (keys @projectname.system/system*)
  (projectname.db/list-greetings (:projectname.db/conn @projectname.system/system*))
  ```

- To rebuild the menu after editing `projectname.menu/spec`:

  ```clojure
  (projectname.menu/install! (:projectname.menu/menu @projectname.system/system*))
  ```

- Changing `config` in `projectname.system`, or an `init-key`, needs a restart.
- A built binary has no nREPL. The dev loop starts only when `lgx run` or `lgx dev`
  sets `LGX_RUN`.

## Layout

```
projectname/
│
├── lgx.edn                      project config: paths, :main, the let-go pin, the native
│                                :bin target, deps (wails, nrepl, sqlite, ragtime,
│                                honeysql, integrant), tasks
├── .mise.toml                   go, node, lgx, cljfmt, clj-kondo pins (no lg: lgx builds it)
├── VERSION                      the app's version, read by scripts/package-macos.sh
│
├── src/projectname/             the app, one integrant component per file
│   ├── app.lg                   entry point: start the system, run the Wails loop, stop
│   ├── system.lg                config map + start!/stop!, the running system in system*
│   ├── shell.lg                 ::app and ::window, the Wails application and its window
│   ├── db.lg                    ::conn sqlite open + migrate on init, HoneySQL queries
│   ├── migrations.lg            ragtime history (001-create-greetings)
│   ├── api.lg                   ::handlers, what the frontend calls, registered by var
│   ├── menu.lg                  the application menu as data, and install!
│   └── dev.lg                   ::loop nREPL + asset watcher, under lgx run only
│
├── test/projectname/            db, api, menu, system and dev tests
│
├── frontend/                    Vite + React + TypeScript + Tailwind, built into resources/public
│   ├── src/App.tsx              the greetings page
│   ├── src/lib/bridge.ts        call(name, ...args) and onEvent(name, fn) over @wailsio/runtime
│   └── vite.config.ts           output dir, dev server port, HMR websocket
│
├── scripts/
│   ├── dev.sh                   Vite + the app with FRONTEND_DEVSERVER_URL (lgx dev)
│   └── package-macos.sh         native build -> dist/projectname.app (lgx package-macos)
│
├── build/macos/                 Info.plist template and the placeholder icon.png
├── .github/workflows/checks.yml Linux CI in server mode: lgx check, then lgx build
├── .cljfmt.edn                  formatter config
└── .clj-kondo/config.edn        let-go's built-in namespaces and its catch form
```

## How it fits together

integrant starts these components in dependency order and halts them in
reverse. `projectname.system/system*` holds the running system.

| Key | Is | Depends on |
|---|---|---|
| `:projectname.db/conn` | the sqlite connection, migrated on init, closed on halt | |
| `:projectname.api/handlers` | the frontend's handlers, registered by var over the connection | the connection |
| `:projectname.shell/app` | the Wails application | |
| `:projectname.shell/window` | the main window | the app |
| `:projectname.menu/menu` | the application menu | the app |
| `:projectname.dev/loop` | the nREPL and the asset watcher, under `lgx run` only | the window |

`projectname.app/-main` starts the system, then blocks in `w/run!`, which must
run on the main thread. It halts the system when `w/run!` returns.

A click on Add travels like this:

```
App.tsx ──call("add-greeting", name)──▶ Wails bridge ──▶ api.lg ──▶ db.lg ──HoneySQL──▶ sqlite
   ▲
   └──onEvent("menu:clear-greetings")── menu.lg ◀── File > Clear Greetings
```

The menu only emits an event. The page listens and calls the `clear-greetings`
handler, so the work stays in one place.

## Build and package

`lgx build` builds the frontend, then compiles the app to Go and links it into
`bin/projectname`. The frontend in `resources/` is embedded in the binary, and
the `production` build tag drops Wails' devtools. A native binary like this
can be codesigned, which an `lg -b` binary cannot.

`lgx package-macos` builds that binary for Apple Silicon and assembles
`dist/projectname.app` with an icon and an `Info.plist`. The bundle is
unsigned, so Gatekeeper blocks a first launch: right-click the app and choose
Open.

Make the names yours before you share the app:

- `scripts/package-macos.sh` has `APP_NAME` (the name in the Dock, e.g. "My App"),
  `BUNDLE_ID` (change `com.example.projectname` to your reverse-DNS ID),
  `EXECUTABLE` and `MACOS_MIN` at the top.
- `src/projectname/system.lg` has the app name and the window title.
- `build/macos/icon.png` is a placeholder. Replace it with a 1024×1024 PNG.

`lgx.edn` pins let-go to a commit, because the native build needs
`lg compile -module` and `-import`, which are newer than let-go 1.13.0. Bump
`:lg-version` to the first let-go release that has them.

## Without a desktop

On Linux without GTK4 and WebKitGTK, and in CI, run Wails in server mode. The
app serves the page over HTTP instead of opening a window:

```bash
CGO_ENABLED=0 GOFLAGS=-tags=server lgx run     # http://localhost:8080
CGO_ENABLED=0 GOFLAGS=-tags=server lgx test
```

`WAILS_SERVER_PORT` moves the port. Menus and dialogs do nothing in server
mode. Both variables are needed, because a few Wails packages gate on
`linux && cgo` without a `!server` guard.

## Releases

This template has no release pipeline. For a signed and notarized macOS
release with GitHub Actions and a Homebrew cask, follow
[Quel](https://github.com/abogoyavlensky/quel), a shipped app this template is
cut down from: its `docs/RELEASE.md`, `.github/workflows/release.yml` and
`scripts/`. `VERSION` is already in place for it.

## Conventions that bite

- Register handlers and menu clicks by var (`#'f`, `(partial #'f env)`), so
  redefining them from the nREPL takes effect without a restart.
- `projectname.app` is the entry script and ends in
  `(when-not *compiling-aot* (-main))`. Nothing may require it. Components live
  in other namespaces.
- No `with-redefs` or `alter-var-root` in application code, and no runtime data
  loaded from `resources/`. Both keep the native build possible.
- `os/getenv` returns `""` for an unset variable, and `""` is truthy. Check with
  `str/blank?`.
- Give React effects braced bodies: `useEffect(() => { el.scrollIntoView() }, ...)`.
  An arrow that returns a Promise hands React a "cleanup" it crashes on.
