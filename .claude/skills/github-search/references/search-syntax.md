# GitHub Search Query Syntax

Qualifiers can be combined in one query, e.g. `repo:octocat/Hello-World is:pr is:open author:octocat "fix crash"`.
Free-text terms outside qualifiers are matched as keywords.

## Scope

| Qualifier | Meaning |
|---|---|
| `repo:owner/name` | Limit to one repository |
| `org:name` | Limit to one organization |
| `user:name` | Limit to one user's repos/content |

## Repositories (`search_repositories` / `gh search repos`)

| Qualifier | Meaning |
|---|---|
| `language:python` | Primary language |
| `stars:>100`, `stars:10..50` | Star count range |
| `forks:>10` | Fork count |
| `size:<1000` | Size in KB |
| `pushed:>2024-01-01` | Last push date |
| `created:>2023-01-01` | Creation date |
| `license:mit` | License identifier |
| `topic:machine-learning` | Repo topic |
| `is:public` / `is:private` | Visibility |
| `archived:false` | Exclude archived repos |

## Code (`search_code` / `gh search code`)

| Qualifier | Meaning |
|---|---|
| `language:javascript` | File language |
| `path:src/utils` | Path prefix |
| `extension:py` | File extension |
| `filename:package.json` | Exact filename |
| `size:>1000` | File size in bytes |

Code search requires at least one qualifier (`repo:`, `org:`, `language:`, etc.)
alongside free-text terms for most queries — plain keyword-only searches across
all of GitHub frequently fail or return empty results.

## Issues & Pull Requests (`search_issues`, `search_pull_requests` / `gh search issues`, `gh search prs`)

| Qualifier | Meaning |
|---|---|
| `is:issue` / `is:pr` | Type (when searching a combined endpoint) |
| `is:open` / `is:closed` | State |
| `is:merged` | Merged PRs only |
| `author:username` | Opened by |
| `assignee:username` | Assigned to |
| `mentions:username` | Mentions a user |
| `label:bug` | Has label |
| `milestone:"v1.0"` | Milestone |
| `comments:>5` | Comment count |
| `created:>2024-01-01` | Creation date |
| `updated:<2024-06-01` | Last update date |
| `closed:2024-01-01..2024-06-01` | Closed date range |
| `no:label` / `no:assignee` / `no:milestone` | Missing a field |
| `sort:` | Don't put this in the query string for MCP `search_*` tools — pass `sort`/`order` as separate parameters instead |

## Commits (`search_commits` / `gh search commits`)

| Qualifier | Meaning |
|---|---|
| `author:username` | Commit author |
| `committer:username` | Committer |
| `author-date:>2024-01-01` | Author date |
| `committer-date:>2024-01-01` | Commit date |
| `merge:true` / `merge:false` | Include/exclude merge commits |
| `hash:abc123` | Specific commit hash |

## Users (`search_users` / `gh search users`)

| Qualifier | Meaning |
|---|---|
| `type:user` / `type:org` | Account type |
| `location:city` | Profile location |
| `language:python` | Language of repos owned |
| `followers:>100` | Follower count |
| `repos:>10` | Public repo count |

## Date ranges

`YYYY-MM-DD`, with comparators `>`, `>=`, `<`, `<=`, or a range `A..B`. Omit
either side of a range for open-ended (`2024-01-01..*`).
