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

## The connection status indicator

`ConnectedDevice` is the small indicator in the top right of most screens: the
radio's short name, the link icon, the MQTT icon and the RX/TX lights.

It is full. Do not add controls to it, and do not add toolbar buttons beside it
in `topBarTrailing`. The space is a status readout, not an action bar, and on a
phone in the narrow width it is already close to overflowing — anything more
either crowds the name or pushes the indicator off.

New actions belong where the thing they act on lives: on the node's row or its
detail screen, in a section on the relevant settings page, or in the Tools
screen. If an action seems to need the top right of every screen, that is worth
questioning rather than designing around.
