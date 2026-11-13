# dsh config

Nothing dsh reads lives in this folder. Orion gives dsh a home of its own and
never touches the user's own `~/.dsh`:

```
~/Orion/
  agent/
    .dsh/                   DSH_HOME for Orion's runs only
      profiles/headless/
        cordis.patch.yml    provider, model and the desktop MCP servers
      .env                  DP_ORION_KEY, mode 0600 on POSIX
  logs/
    tools.jsonl             every tool call, per docs/HARNESS.md
```

`DshConfigWriter` in `lib/features/harness/data/dsh/` writes both files when a
provider is chosen in the app and again before each task. `DshRuntime` then
runs

```
npx -y @deepseek-ai/dsh@0.2.2-rc.1 --profile headless --permission-mode danger-full-access --approval-policy never -
```

with the task on stdin and the user's home folder as the working directory.
The agent has full access there and asks nobody; the board's approval mode
decides whether a task runs at all. See docs/HARNESS.md, "The PC agent".

Nothing in `~/Orion` is in this repository, and no key is ever passed on a
command line.
