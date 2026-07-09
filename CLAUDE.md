<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan:
`specs/015-site-planner-outbound/plan.md` (feature: Site Planner Outbound Coverage Estimate).
<!-- SPECKIT END -->

## Active Technologies
- Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`) + SwiftUI, WebKit (`WKWebView`, `WKUserScript`, `WKScriptMessageHandler`) — new to this feature, no existing WKWebView usage in the codebase to follow as precedent (confirm during implementation) (015-site-planner-outbound)
- SwiftData for existing config entities read at prefill time (no writes); the estimate result reuses the existing file-based `MapDataManager` storage (`MapData/user_uploaded/` + `upload_history.json`) unchanged — no new persisted entity (015-site-planner-outbound)

## Recent Changes
- 015-site-planner-outbound: Added Swift (latest stable), Swift Concurrency (`async`/`await`, `@MainActor`) + SwiftUI, WebKit (`WKWebView`, `WKUserScript`, `WKScriptMessageHandler`) — new to this feature, no existing WKWebView usage in the codebase to follow as precedent (confirm during implementation)
