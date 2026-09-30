# README footer

Every BlackBearReloaded repository ends its README with the same Credits,
License, Disclaimer and AI assistance sections. They sit between the
`bbr-footer` markers and are generated from `template.md`, with per-repository
settings in `repos.toml`. Credits specific to a repository belong in its
`THIRD_PARTY_NOTICES.md`, not in the footer.

To change the wording, edit `template.md` or `repos.toml`, then run the sync
against a directory that holds one clone of each repository:

```bash
python3 scripts/readme-footer/sync.py ~/repos
python3 scripts/readme-footer/sync.py --check ~/repos
```

The first command rewrites each footer and appends one where it is missing.
`--check` changes nothing and exits 1 if any footer is out of date. Commit the
result in each repository.

To add a repository, give it a `[repos.<name>]` table in `repos.toml`.
