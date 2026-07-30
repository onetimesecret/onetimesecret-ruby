# Releasing

Names, kept straight:

- **`onetime`** is the gem, on RubyGems. That name is correct and settled — it
  is not changing.
- **`onetime-ruby`** is this repository: the Ruby SDK of the OnetimeSecret SDK
  family, one per language. The repository name is not the package name, so
  never write `gem "onetime-ruby"`.

The gem's history matters for the install instructions:

- The release before 0.6.0 is **0.5.1 (2013-02-12)** — the old `drydock`-based
  command-line tool. Same gem, but an API surface with nothing in common with
  the current one.
- `gem "onetime", "~> 0.6"` is therefore the documented form: the constraint is
  what keeps a resolver from falling back to 0.5.1. The README says so
  explicitly, and it is worth repeating in support threads.

**Never tell integrators to pin `branch: master`** — point them at a released
version. A moving branch is how a customer ends up running an untested commit,
which is exactly the thread that produced this document.

## One-time setup: Trusted Publishing

`.github/workflows/release.yml` authenticates with RubyGems over OIDC, so no
API key lives in this repository. Configure the trusted publisher once, as an
owner of the gem:

1. Go to <https://rubygems.org/gems/onetime/trusted_publishers> → **Create**.
2. Repository: `onetimesecret/onetime-ruby`.
3. Workflow filename: `release.yml`.
4. Environment: `rubygems`.
5. In GitHub, create the matching `rubygems` environment
   (Settings → Environments) and add whatever reviewers/branch restrictions
   you want gating a publish.

Note the asymmetry in the steps above, since it is easy to fumble: the trusted
publisher is registered against the **gem** (`onetime`) but points at the
**repository** (`onetime-ruby`).

## Cutting a release

1. Make sure `master` is green in CI.
2. Set the version in `lib/onetime/version.rb` (single source of truth — the
   gemspec reads it, and the release workflow checks the tag against it).
3. Update `CHANGES.txt`: replace the `(unreleased …)` marker on the top
   section with the release date.
4. Commit: `git commit -am "Release 0.6.0"`.
5. Tag and push:

   ```sh
   git tag -a v0.6.0 -m "onetime 0.6.0"
   git push origin master
   git push origin v0.6.0
   ```

6. The tag push runs `Release`, which verifies the tag/version match, runs the
   tests, builds the gem, pushes it to RubyGems, and creates the GitHub
   release.
7. Verify: `gem info onetime --remote` shows 0.6.0, and
   `gem install onetime -v 0.6.0` works in a clean environment.
8. Check that `README.md`'s install section still matches what is published —
   the version constraint it asks for, and the 0.5.x caveat.

## Versioning

SemVer, continuing the gem's existing 0.x line. 0.6.0 is a clean break from
0.5.x with no compatibility shim, so 0.5.x users are new adopters rather than
upgraders — but the version stays below 1.0 until the API surface has settled.
