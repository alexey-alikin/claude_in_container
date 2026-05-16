# example project

This folder is a placeholder so the multi-project workflow has something to demo against. Try it out:

```bash
./claude.sh shell example
```

When you're ready to use the repo for real, either:

- delete this folder and create your own with `./claude.sh new <your-name>`, or
- keep it around for quick experiments

Anything you put in `projects/<name>/` is bind-mounted into the container at `/workspace`. Each project gets its own Claude context — sessions in different projects don't see each other.

`projects/*` is gitignored from the parent repo (except this `example/` folder, which is whitelisted so it ships with clones). You can `git init` inside your own project folders to give them independent history.
