# Releasing

## Gem name and repository name

- **`onetime`** is the gem, on RubyGems. That name is correct and settled — it
  is not changing.
- **`onetime-ruby`** is this repository: the Ruby SDK of the OnetimeSecret SDK
  family, one per language. The repository name is not the package name, so
  never write `gem "onetime-ruby"`.

## Version history and install instructions

Prior to 0.6.0 there was a long gap to the next most recent release which is 
**0.5.1 (2013-02-12)**, the old `drydock`-based command-line tool: the same 
gem. Consequently, all documentation references `gem "onetime", "~> 0.6"`, as 
this pessimistic constraint is what prevents package resolvers from falling 
back to the obsolete 0.5.1 release.


## One-time setup: Trusted Publishing

`.github/workflows/release.yml` authenticates with RubyGems over OIDC, so no
API key lives in this repository. Configure the trusted publisher once, as an
owner of the gem:

1. Go to <https://rubygems.org/gems/onetime/trusted_publishers> → **Create**.
2. Repository: `onetimesecret/onetime-ruby`.
3. Workflow filename: `release.yml`.
4. Environment: `rubygems.org`.
5. In GitHub (Settings → Environments), gate the matching `rubygems.org`
   environment: restrict its deployment branches to `main` and the `v*` tags,
   and add required reviewers if you want a human in the loop. Do this even
   though the environment appears on its own — referencing a name in a
   workflow auto-creates it *unprotected*, so an environment that exists is
   not evidence that anything is gating it.

   This is the only control on the release job. That job holds `id-token:
   write` (it mints a RubyGems publishing token) and `contents: write`, and
   it runs on any `v*` tag, from any ref, until a branch policy says
   otherwise.

Note the asymmetry in the steps above: the trusted publisher is registered
against the **gem** (`onetime`) but points at the **repository**
(`onetime-ruby`).

The environment name is compared as a plain string against the OIDC token's
`environment` claim, so `environment:` in `release.yml` and the RubyGems
record must agree character for character. A mismatch fails the publish step
with `No trusted publisher configured for this workflow found ... for
audience rubygems.org` — the `rubygems.org` there is the *audience* claim,
which is always that value and is not the environment.

## Cutting a release

1. Make sure `main` is green in CI.
2. Set the version in `lib/onetime/version.rb` (single source of truth — the
   gemspec reads it, and the release workflow checks the tag against it).
3. Update `CHANGES.txt`: replace the `(unreleased …)` marker on the top
   section with the release date.
4. Commit: `git commit -am "Release 0.6.0"`.
5. Tag and push:

   ```sh
   git tag -a v0.6.0 -m "onetime 0.6.0"
   git push origin main
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
