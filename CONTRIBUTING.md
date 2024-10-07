# Contributing
## How to contribute to RSK

These are mostly guidelines, not rules. Use your best judgment, and feel free to propose changes to this document in a pull request.

### Code Reviews

Continued code reviews and audits are required for security. As such, we encourage interested security researchers to:

* Review our code, even if no contributions are planned.
* Publish their findings whichever way they choose, even if no particular bug or vulnerability was found. We can all learn from new sets of eyes and benefit from increased scrutiny.

### Code contributions

A code contribution process starts with someone identifying a need for writing code. If you're thinking about making your first contribution, we suggest you take a moment to get in touch and see how your idea fits in the development plan:

* Is it a bug in our [issue tracker](https://github.com/rsksmart/liquidity-bridge-contract/issues)?
* Is it a novel idea that should be proposed and discussed first?

#### Review process

Once you know what to do, it is important that you provide a full description of the proposed changes. You can also send a draft pull request if you already have code to show.

We make use of GitHub Checks to ensure all changes meet a certain criteria:

1. The `master` branch is protected and only changeable through pull requests
2. All unit tests must pass
3. A project maintainer must approve the pull request
4. An authorized merger must merge the pull request

Since this is a security-sensitive project, we encourage everyone to be proactive and participate in the review process. To help collaboration we propose adhering to these conventions:

* **Request changes** only for correctness and security issues.
* **Comment** when leaving feedback without explicit approval or rejection. This is useful for design and implementation discussions.
* **Approve** when changes look good from a correctness, security, design and implementation standpoint.

All unit and integration tests pass without loss of coverage (e.g can't remove tests without writing equivalent or better ones).

All code paths on new code must be unit tested, including sensible edge cases and expected errors. Exceptions to this rule must be justified (i.e. highly similar paths already tested) in written form in the PR description.

In order to ease review, it is expected that the code diff is maintained to a minimum. This includes things like not changing unrelated files, not changing names or reordering code when there isn't an evident benefit.

When automatic code quality and security checks are ready in the pipeline for external PRs, then the PR must pass all PR validations including code coverage (Sonar), code smells (Sonar), Security advisories (Sonar, LGTM).

## Style guidelines

### Pull request etiquette

* Separate your changes into multiple commits
* If your pull request gets too big, try to split it
* Each commit should at least compile, and ideally pass all unit tests
* Avoid merge commits, and always rebase your changes on top of `master`
