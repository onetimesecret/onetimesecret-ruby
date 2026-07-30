# Releasing

This client is published to RubyGems as **`onetime`**, the same gem name used
by the 2012–2013 command-line tool. That history matters:

- The newest release on RubyGems today is **0.5.1 (2013-02-12)** — the old
  `drydock`-based CLI, a completely different program with a different API
  surface. It is not this library.
- Anyone running `gem install onetime` before 1.0.0 is published gets that
  2013 gem. That is why `README.md` currently documents a **tagged git
  install** and warns about the version boundary.
- Once 1.0.0 is on RubyGems, `gem "onetime", "~> 1.0"` resolves to this
  client. The `~> 1.0` constraint is what keeps a resolver from falling back
  to 0.5.1, so the README asks for it explicitly.

Until the RubyGems push happens, **do not tell integrators to pin
`branch: master`** — pin a tag. A moving branch is how a customer ends up
running an untested commit.

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

If the gem name is ever moved to `onetimesecret` (open question in
`docs/modernization-plan.md` §9), the trusted publisher and the README's
install instructions both have to be updated.

## Cutting a release

1. Make sure `master` is green in CI.
2. Set the version in `lib/onetime/version.rb` (single source of truth — the
   gemspec reads it, and the release workflow checks the tag against it).
3. Update `CHANGES.txt`: replace the `(unreleased …)` marker on the top
   section with the release date.
4. Commit: `git commit -am "Release 1.0.0"`.
5. Tag and push:

   ```sh
   git tag -a v1.0.0 -m "onetime 1.0.0"
   git push origin master
   git push origin v1.0.0
   ```

6. The tag push runs `Release`, which verifies the tag/version match, runs the
   tests, builds the gem, pushes it to RubyGems, and creates the GitHub
   release.
7. Verify: `gem info onetime --remote` shows 1.0.0, and
   `gem install onetime -v 1.0.0` works in a clean environment.
8. Update `README.md` to the published-gem instructions (drop the "not yet on
   RubyGems" callout, keep the `~> 1.0` constraint and the 0.5.x warning).

## Versioning

SemVer. The 1.0 line is a clean break from 0.5.x with no compatibility shim,
so 0.5.x users are treated as new adopters, not upgraders.
