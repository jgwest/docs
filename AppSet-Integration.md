The goal of this document is as an outline, a proposal, and an opportunity to gather requirements and discuss integration options with the Argo CD contributors and community.

Requirements:
- ApplicationSet code will live in the same Git repo as Argo CD

## Integrating ApplicationSet controller with Argo CD

### 1) Code quality: quality of life improvements
- `go fmt` the code, and use a GitHub action to keep it that way (Done: https://github.com/argoproj-labs/applicationset/pull/62)
- Fix lint errors, using same ruleset as Argo's, add a GH action to prevent this from regressing (Waiting for merge: https://github.com/argoproj-labs/applicationset/pull/63)
- Add a `go test` GitHub action to AppSet project to catch regressions.
- Reorganize code packages so they will merge nicely with Argo CD codebase (Note: this may blow up outstanding appset PRs!)

### 2) Implement any remaining functionality that blocks the merge
- *Open question*: will `ApplicationSet` controller run in the same OS process (and StatefulSet replica) as Argo CD's application controller?
    - If running within same OS process/statefulset, need to add support for application controller's horizontal scaling
    - My take: I could argue it either way, but suggest keeping them separate for now, and reconsider after integration is complete (will need a new `Deployment` for AppSet controller in the mean time)    
- I'm not aware of any outstanding bugs that are severe enough to block integration (but that's what testing is for, below)
- *Open question*: how many of the remaining proposal items do we want to handle before we merge?
    - Currently implemented generators: cluster, list, git directory
    - In progress: git files discovery (https://github.com/argoproj-labs/applicationset/pull/45), but it currently uses Argo CD's Git client util directly (which calls `git` CLI), rather than interacting with git via repo-server
    - My take: It sounds like some folks are already using ApplicationSet controller in their own environments, which is a testament to the functionality that is already in place. I don't think any of the outstanding functionality needs to block integration.


### 3) Code quality: testing
- Identify gaps in unit tests and fill them
- Implement E2E test framework
    - Waiting review/merge: https://github.com/argoproj-labs/applicationset/pull/66
    - Fully based on Argo CD's existing BDD-style framework, `Context --When--> Actions --Then--> Consequences` (etc)
- Add a GitHub action that runs E2E tests (akin to Argo CD's GH action, waiting review/merge: https://github.com/argoproj-labs/applicationset/pull/66)
- Implement additional E2E tests for existing appset functionality (cluster generator, list generator, git directory generator)
- Manual testing to catch outstanding pre-integration bugs

### 4) Final pre-integration work
- Standardize AppSet's `go.mod` with latest Argo CD release, and keep them in sync
- In a fork/branch of Argo CD repo:
    - Move AppSet code to appropriate location within new codebase
    - Add AppSet CRD manifests, but keep them in a 'staging' folder not included in the default Argo CD install
    - Update `Dockerfile` as needed
    - Add feature flags to AppSet code (see below)
    - Ensure it builds, and existing Argo CD tests still pass
    - Manual testing to catch outstanding post-integration bugs
    - Raise a PR, and proceed to staged merger steps, below


### 5) Integration: staged merger with Argo CD

Avoid big bang integration by moving code to Argo CD incrementally, with a feature flag, with appset unit/e2e tests in place

- Add appset code to the Argo CD codebase, but behind a feature flag
    - Argo CD unit/E2E tests should continue to pass
    - Ensure the appset unit tests don't run with existing tests, by eg grepping them out of the test list in argo makefile
- Add a new github action that ONLY runs the appset unit tests (w/ feature flag enabled)
    - GitHub action should run, but should NOT fail the CI build on test failure (it is expected they may fail until we have polished them)
    - Once integrated, get it passing
- Add a new github action that ONLY runs the appset E2E unit tests (w/ feature flag enabled)
    - GitHub action should likewise not fail the build on test failure
    - Once integrated, get it passing
- Once the appset code is fully integrated, and the standalone appset unit tests are passing:
    - Enable the tests, and allow them to fail the build on failure... fix failures
- Once the the tests are passing consistently:
    - Do a final smoke test and enable the feature flag in the product, and add the appset CRDs to the default install
- Finally, remove the feature flag supporting code

### 6) Add product documentation (for inclusion in Argo CD's user/operator docs)
- Document the implemented generators, provide working examples based on argocd example repo
- Note: Make it clear that these features are currently experimental
- Add the AppSet documentation into Argo CD's user docs


### 7) Post-integration
- Discuss and implement the remaining ApplicationSet proposal items
    - Git directories (in progress, https://github.com/argoproj-labs/applicationset/pull/45)
    - Generator filter expressions
    - Templates within generators (overriding the spec-level template)
- CLI integration with Argo CD
    - Something along the lines of `argocd appset (list/create/delete/edit/etc)`
- UI integration with Argo CD
    - Provide the user a "10,000 ft view" of Applications managed by an Application Set
- Many good ideas in the AppSet proposal for subsequent future work
- New features! 🎉
