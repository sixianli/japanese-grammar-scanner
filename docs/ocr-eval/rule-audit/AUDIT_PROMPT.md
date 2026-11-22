# Task: judge whether regex matches of Japanese grammar points are real uses of that grammar

Context: an iOS app scans Japanese textbook pages and highlights grammar points using hand-written regex rules (one or more per grammar point). We need to measure each rule's precision: when a rule fires, is the highlighted span really an instance of that grammar point (in the sense a learner would want explained)?

Input: a JSON file (path given below) — a list of grammar points. Each item has:
- `id`, `title` (Japanese form), `gloss`, `senses` (Chinese descriptions of the senses this grammar point covers),
- `total_matches` (how many times the rule fired across 95 real textbook pages),
- `samples`: up to 5 random matches, each as `left context【matched span】right context` (from human transcriptions of real pages, so the text itself is correct Japanese; ignore 〓 = unreadable char).

For EVERY sample decide `true` (this span is genuinely this grammar point, in one of its senses) or `false` (accidental match: e.g. the characters appear but as part of another word, a different particle function, a different construction, a page number/list marker, etc.). Be strict but fair: judge as a Japanese teacher would — if a learner tapped this highlight, would the explanation of this grammar point be the right one to show?

Then for each grammar point where any sample is false, write a short `problem` (what kind of false matches, in Chinese) and, when you can, a concrete `fix` idea (in Chinese, e.g. "require preceding verb て-form", "exclude when followed by 、", "drop the loose second pattern"). Do not write regexes unless obvious; ideas are enough.

Output: write a JSON file (path given below) as an object: `{ "<id>": {"judgments": [true, false, ...] (same order as samples), "problem": "...", "fix": "..."} }`. Include every id from the input (problem/fix may be empty strings when all true). Then reply with one line: number of ids, number of samples, number judged false.

Do not modify any other file. Do not run git.
