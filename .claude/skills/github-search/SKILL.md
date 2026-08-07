---
name: github-search
description: Search GitHub for repositories, code, issues, pull requests, commits, and users. Use this skill whenever the user asks to find, look up, or search for something "on GitHub" — a repo, a package, a code snippet or function, an open issue, a pull request, a commit, or a user/org — even if they don't say the word "search" (e.g. "is there a library for X on GitHub", "find where this function is used across GitHub", "any open issues about this error", "who wrote this commit"). Prefer the GitHub MCP server's search tools when connected; fall back to the `gh` CLI when it isn't.
---

# GitHub Search

Find things on GitHub — repos, code, issues, PRs, commits, users — by picking the
right tool and query syntax rather than guessing at a URL or scraping search results
by hand.

## Which interface to use

Two ways to search are available depending on the environment. Check which one you
have before starting:

1. **GitHub MCP server** (tools prefixed `mcp__github__...`, e.g.
   `mcp__github__search_code`, `mcp__github__search_repositories`,
   `mcp__github__search_issues`, `mcp__github__search_pull_requests`,
   `mcp__github__search_commits`, `mcp__github__search_users`). If these tools are
   available (check the tool list, or use ToolSearch with a query like
   `"select:mcp__github__search_code"` if they're deferred), prefer them — they
   return structured JSON and don't require a local shell or authentication setup.
2. **`gh` CLI fallback**. If the MCP server isn't connected, use `gh search ...`
   subcommands via Bash. This requires `gh` to be installed and authenticated
   (`gh auth status`) — if it isn't, tell the user rather than trying to scrape
   `github.com` search pages over HTTP.

Both interfaces speak the same underlying GitHub search query syntax (qualifiers
like `repo:`, `language:`, `is:open`, etc.) — see `references/search-syntax.md` for
the full cheat sheet. Getting the qualifiers right matters more than which
interface you use, since a vague query returns noise regardless of tool.

## Choosing list vs. search

If the MCP server is available: use `list_*` tools (`list_issues`,
`list_pull_requests`, `list_branches`, `list_commits`, `list_releases`, `list_tags`)
for simple, broad retrieval within a *known* repo — "show me open PRs in repo X".
Use `search_*` tools when you have specific criteria, keywords, or need to search
*across* repos — "find PRs that touch `auth.py`", "find repos using this library".
Search tools accept the full GitHub qualifier syntax; list tools take simple
filters (state, branch, etc.) and no free-text query.

## Workflow

1. **Clarify scope.** Is this a search within one repo, across an org, or across
   all of GitHub? Narrow with `repo:owner/name`, `org:name`, or `user:name`
   whenever the user's intent implies a scope — an unscoped search across all of
   GitHub is usually too noisy to be useful for code search in particular.
2. **Build the query** using qualifiers from `references/search-syntax.md` rather
   than plain keywords alone. E.g. for "find open issues about a timeout bug in
   this repo": `repo:owner/name is:issue is:open timeout` — not just `timeout`.
3. **Run the search** with the appropriate tool:
   - Repos: `mcp__github__search_repositories` or `gh search repos`
   - Code: `mcp__github__search_code` or `gh search code`
   - Issues: `mcp__github__search_issues` (or `list_issues` if scoped to one known
     repo with no keyword) or `gh search issues`
   - Pull requests: `mcp__github__search_pull_requests` or `gh search prs`
   - Commits: `mcp__github__search_commits` or `gh search commits`
   - Users/orgs: `mcp__github__search_users` or `gh search users`
4. **Paginate in small batches** (5-10 results at a time) rather than pulling
   hundreds of results into context. If the MCP tools expose a `minimal_output`
   flag and full detail isn't needed, set it — a list of titles/URLs is often
   enough to answer the user's question, and full bodies can be fetched
   individually for the one or two results that matter.
5. **Summarize, don't dump.** Present the handful of results that actually answer
   the question (title, repo, URL, one-line relevance note) instead of pasting raw
   API output.

## gh CLI examples

```bash
# Repositories
gh search repos "violin practice tracker" --language=python --sort=stars --limit 10

# Code (requires at least one qualifier beyond free text for most searches)
gh search code "practice session" --repo owner/name
gh search code "def transpose" --language=python

# Issues / PRs
gh search issues "MIDI import fails" --repo owner/name --state=open
gh search prs --repo owner/name --state=open --author=someuser

# Commits
gh search commits "fix tempo detection" --repo owner/name

# Users
gh search users "violin" --location="San Francisco"
```

Run `gh search <subcommand> --help` for the full flag list if a query needs a
qualifier not shown above — don't guess at flag names.

## Notes

- GitHub's code search only indexes the default branch of repos with reasonably
  recent activity, and needs at least one qualifier for most non-trivial queries —
  a bare keyword search over all of GitHub code will often error out or return
  nothing useful. Scope with `repo:`, `org:`, `language:`, `path:`, or `extension:`.
- For "does this exist as a GitHub Action / package / library" type questions,
  `search_repositories` / `gh search repos` sorted by stars is usually the fastest
  path to a good answer.
- If a user pastes a `github.com` search or repo URL, you can often translate it
  directly into a query (the URL's `q=` parameter is the search query) rather than
  re-deriving it from scratch.
