---
name: codebase-memory
description: "Use the codebase knowledge graph for structural code queries and call/dependency tracing. This skill should be used when exploring architecture, finding functions, tracing callers or callees, analyzing impact, or writing graph and Cypher queries."
---

# Codebase Memory — Knowledge Graph Tools

Use MCP knowledge-graph tools for structural code discovery before falling back to grep or raw file search.

Use this skill when the task is about code structure rather than string matching: finding functions or classes, tracing callers or callees, understanding dependencies, exploring architecture, estimating impact, or writing Cypher queries against the graph.

Prefer this workflow:
1. Confirm the target project is indexed with `list_projects`.
2. Inspect available node and edge types with `get_graph_schema` when the graph shape is unclear.
3. Locate candidate symbols with `search_graph`.
4. Trace relationships with `trace_path`.
5. Read exact implementations with `get_code_snippet`.
6. Use `query_graph` only when built-in graph search or tracing is insufficient.

Fall back to `search_code` or grep only for string literals, config values, log messages, or non-code files that are not represented well in the graph.

## Quick Decision Matrix

| Question | Tool call |
|----------|----------|
| Who calls X? | `trace_path(direction="inbound")` |
| What does X call? | `trace_path(direction="outbound")` |
| Full call context | `trace_path(direction="both")` |
| Find by name pattern | `search_graph(name_pattern="...")` |
| Dead code | `search_graph(max_degree=0, exclude_entry_points=true)` |
| Cross-service edges | `query_graph` with Cypher |
| Impact of local changes | `detect_changes()` |
| Risk-classified trace | `trace_path(risk_labels=true)` |
| Text search | `search_code` or Grep |

## Exploration Workflow
1. Run `list_projects` to confirm the repository is indexed.
2. Run `get_graph_schema` to understand node and edge types when needed.
3. Run `search_graph(label="Function", name_pattern=".*Pattern.*")` to find candidate code.
4. Run `get_code_snippet(qualified_name="project.path.FuncName")` to read exact source.

## Tracing Workflow
1. Run `search_graph(name_pattern=".*FuncName.*")` to discover the exact symbol name.
2. Run `trace_path(function_name="FuncName", direction="both", depth=3)` to trace callers and callees.
3. Run `detect_changes()` to map a git diff to affected symbols when impact matters.

## Quality Analysis
- Dead code: `search_graph(max_degree=0, exclude_entry_points=true)`
- High fan-out: `search_graph(min_degree=10, relationship="CALLS", direction="outbound")`
- High fan-in: `search_graph(min_degree=10, relationship="CALLS", direction="inbound")`

## 14 MCP Tools
`index_repository`, `index_status`, `list_projects`, `delete_project`,
`search_graph`, `search_code`, `trace_path`, `detect_changes`,
`query_graph`, `get_graph_schema`, `get_code_snippet`, `get_architecture`,
`manage_adr`, `ingest_traces`

## Edge Types
CALLS, HTTP_CALLS, ASYNC_CALLS, IMPORTS, DEFINES, DEFINES_METHOD,
HANDLES, IMPLEMENTS, OVERRIDE, USAGE, FILE_CHANGES_WITH,
CONTAINS_FILE, CONTAINS_FOLDER, CONTAINS_PACKAGE

## Cypher Examples (for query_graph)
```
MATCH (a)-[r:HTTP_CALLS]->(b) RETURN a.name, b.name, r.url_path, r.confidence LIMIT 20
MATCH (f:Function) WHERE f.name =~ '.*Handler.*' RETURN f.name, f.file_path
MATCH (a)-[r:CALLS]->(b) WHERE a.name = 'main' RETURN b.name
```

## Gotchas
1. `search_graph(relationship="HTTP_CALLS")` filters nodes by degree — use `query_graph` with Cypher to see actual edges.
2. `query_graph` has a 200-row cap — use `search_graph` with degree filters for counting.
3. `trace_path` needs exact names — use `search_graph(name_pattern=...)` first.
4. `direction="outbound"` misses cross-service callers — use `direction="both"`.
5. Results default to 10 per page — check `has_more` and use `offset`.
