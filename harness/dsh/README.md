# dsh config

Nothing dsh reads lives in this folder. That is deliberate: dsh reads
`settings.yaml` under `$DSH_HOME`, which defaults to `~/.dsh`, and Orion must
not touch a user's own dsh setup. How Orion runs it is in `docs/HARNESS.md`.

So the app gives dsh a private home of its own:

```
~/Orion/
  agent/            the sandbox dsh runs in, and nothing above it
    .dsh/           DSH_HOME for our runs only
      settings.yaml provider, model, apiKeyEnv
      .env          DP_ORION_KEY, mode 0600 on POSIX
  logs/
    tools.jsonl     every tool call, per docs/HARNESS.md
```

`DshConfigWriter` in `lib/features/harness/data/dsh/` writes those two files
when the user hits "Use on Orion" in the Providers screen. `DshRuntime` then
spawns:

```
npx -y @deepseek-ai/dsh --profile headless "<task>"
```

with `DSH_HOME` pointed at the folder above, the working directory set to
`~/Orion/agent`, and `DSH_PERMISSION_MODE=workspace-write` so dsh stays in it.

Nothing in `~/Orion` is in this repository, and no key is ever passed on a
command line.
