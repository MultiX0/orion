---
paths:
  - "wakeword/**"
  - "firmware/components/orion_wakeword/models/**"
---

# Wake word rules

The pipeline, datasets and measures are in `wakeword/README.md`.

- Training runs in WSL2 or Linux, with its own Python 3.11 or 3.12 venv. Venvs, datasets, features and checkpoints stay out of git (`~/orion_ww` in WSL, or the gitignored `wakeword/data/` and `wakeword/work/`). Commit scripts, the README, the shipped `.tflite` with its `.json` manifest, and the small test clips.
- Long runs go in a detached `tmux` session. WSL kills processes started by a `wsl.exe` call when it returns, and `nohup` does not help.
- `*.sh` stays LF (`wakeword/.gitattributes`).
- Never compare file times across the WSL and Windows boundary; select checkpoints by name.
- The Fish key comes from `.env` and is never printed. Generation uses the free `s2.1-pro-free` TTS model.
- Report both measures for any model you propose: false rejection and confusable false accepts on the holdout, and false accepts per hour on ambient audio, plus the silence and noise checks. Synthetic numbers overstate real recall; say so.
- A new model keeps the previous one for rollback and ships as a microWakeWord v2 pair: window 5, feature step 10, a measured cutoff, an arena size that allocates on the board.
- The generated audio carries mixed dataset licenses; the trained model is for non-commercial personal use.
