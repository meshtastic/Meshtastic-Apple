## Writing style

Keep explanations, PR descriptions, code comments, and commit messages short and plain.
Say what broke and what changed in ordinary words. No invented jargon,
no dramatized debugging stories, no bold-lead bullet lists that read like
marketing. Match how existing PRs in this repo are written (Summary /
What changed / Testing). If there's nothing worth saying, say nothing.

## Pull requests

One change per pull request, based on `main`.

Do not open stacked pull requests — a series where each one's base is the
previous one's branch. They cannot be reviewed or merged independently: taking
the third means taking the first two, the parts needing the most scrutiny sit
furthest down the chain, and closing anything in the middle strands the rest.
If a change only makes sense on top of another, wait for the first to merge and
then open the second against `main`.

Split work by what it does, not by how it was written. A bug fix that stands on
its own goes in its own pull request, not at the bottom of a larger series.

Keep a pull request small enough to review in one sitting. If it runs to
thousands of lines across dozens of files, it is doing more than one thing.

Describe the change in terms of what the app and the radio do. Parity with
another client is a reason to want a change, not a description of one.
