# Pack — Search

Pull when the change touches a search box, query endpoint, or relevance/filter/pagination. Search fails at two ends: interpreting weird input, and ranking results. Relevance is the primary quality signal.

## Input handling (negative)
- [ ] Empty query → helpful state (trending/popular or a clear message), never an error or blank page
- [ ] Special characters (`@ # $ % ^ & * " '`) → handled, no crash, no broken results
- [ ] SQL injection (`' OR 1=1 --`) and HTML/JS injection → neutralised server-side (`runtime`: observe the response, not the code)
- [ ] Unicode / emoji / non-Latin scripts → correct results or graceful handling
- [ ] Excessively long query (500+ chars) → bounded, no crash
- [ ] Query with special chars survives **URL state** round-trip (encode/decode) when shared/reloaded

## Results quality
- [ ] Relevance ranking: most-relevant first; exact > partial > synonym (assert order explicitly)
- [ ] Typo tolerance / fuzzy matching within a sensible edit distance ("Samsong" → Samsung)
- [ ] Zero-results page offers alternatives/spelling help/navigation — not a dead end
- [ ] Filters + search combine correctly; pagination is consistent (no dupes/missing across pages)

## Performance
- [ ] Response within budget (e.g. <2s basic query); record the measured number
- [ ] Repeated query → cache consistent (same results), no staleness bug; stable under concurrent load

> Sources: search-testing guides (BugBug, Katalon, BrowserStack), QASkills search-quality tester.
