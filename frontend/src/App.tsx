import { useCallback, useEffect, useState, type FormEvent } from "react";
import { call, onEvent } from "@/lib/bridge";

type Greeting = { id: number; name: string };

function messageOf(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

export default function App() {
  const [greetings, setGreetings] = useState<Greeting[]>([]);
  const [name, setName] = useState("");
  const [error, setError] = useState("");

  // A rejected call (the backend threw) shows its message inline.
  const load = useCallback(
    () =>
      call<Greeting[]>("list-greetings").then(
        (list) => {
          setGreetings(list);
          setError("");
        },
        (e) => setError(messageOf(e)),
      ),
    [],
  );

  // Run an action, then reload the list.
  const run = useCallback(
    async (action: () => Promise<unknown>) => {
      try {
        await action();
      } catch (e) {
        setError(messageOf(e));
        return;
      }
      await load();
    },
    [load],
  );

  useEffect(() => {
    void load();
  }, [load]);

  // File > Clear Greetings: the menu emits, this does the work.
  useEffect(() => {
    return onEvent("menu:clear-greetings", () => {
      void run(() => call("clear-greetings"));
    });
  }, [run]);

  function add(e: FormEvent) {
    e.preventDefault();
    void run(async () => {
      await call("add-greeting", name);
      setName("");
    });
  }

  return (
    <main className="mx-auto max-w-md p-6 text-neutral-900 dark:text-neutral-100">
      <h1 className="mb-4 text-2xl font-semibold">Greetings</h1>
      <form onSubmit={add} className="flex gap-2">
        <input
          value={name}
          onChange={(e) => setName(e.target.value)}
          placeholder="Name"
          autoFocus
          className="min-w-0 flex-1 rounded border border-neutral-300 bg-transparent px-3 py-1.5 dark:border-neutral-700"
        />
        <button
          type="submit"
          className="rounded bg-neutral-900 px-3 py-1.5 text-white dark:bg-neutral-100 dark:text-neutral-900"
        >
          Add
        </button>
      </form>
      {error && <p className="mt-2 text-sm text-red-600">{error}</p>}
      <ul className="mt-4 space-y-1">
        {greetings.map((g) => (
          <li key={g.id}>Hello, {g.name}!</li>
        ))}
      </ul>
    </main>
  );
}
