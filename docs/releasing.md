# Releasing

## Package and repository names

- **`onetimesecret`** is the canonical RubyGem beginning with version 0.7.0.
- **`onetime`** is a dependency-only compatibility package beginning with
  version 0.7.0. It contains no implementation files and directs users to
  `onetimesecret`.
- **`onetime-ruby`** remains the repository name for the Ruby SDK. Repository
  names and RubyGems package names do not need to match.

The Ruby namespace remains `Onetime`. The canonical package supports both
`require "onetimesecret"` and the legacy `require "onetime"` load path.

## Version history and migration

`onetime` 0.6.0 was the final implementation release under the shortened
package name. The canonical package starts at `onetimesecret` 0.7.0. Existing
applications should replace:

```ruby
gem "onetime", "~> 0.6"
```

with:

```ruby
gem "onetimesecret", "~> 0.7.0"
```

The `onetime` 0.7 compatibility package depends on `onetimesecret`, so users
with compatible version constraints can transition without conflicting library
files. Exact pins and `~> 0.6.0` constraints require a manual Gemfile update.

## One-time setup: Trusted Publishing

`.github/workflows/release.yml` authenticates with RubyGems over OIDC, so no
API key lives in this repository.

### Canonical package

Because `onetimesecret` is a new package, create a pending trusted publisher
from the RubyGems profile before its first release:

1. Gem name: `onetimesecret`.
2. Repository owner: `onetimesecret`.
3. Repository: `onetime-ruby`.
4. Workflow filename: `release.yml`.
5. Environment: `rubygems.org`.

After the first successful push, RubyGems converts the pending publisher into a
normal trusted publisher and adds its creator as a gem owner.

### Compatibility package

The existing `onetime` trusted publisher must continue to point to:

1. Repository: `onetimesecret/onetime-ruby`.
2. Workflow filename: `release.yml`.
3. Environment: `rubygems.org`.

A single workflow may be trusted by both packages.

### GitHub environment

In GitHub Settings → Environments, gate the `rubygems.org` environment:

- Restrict deployment tags to `v*` and `onetime-v*`.
- Add required reviewers when a human release gate is desired.

Referencing an environment from a workflow creates it without protection.
Configure these rules before releasing. The environment name is compared as a
plain string with the OIDC token claim, so the workflow and both RubyGems
publisher records must match exactly.

## Cutting a canonical release

1. Make sure `main` is green in CI.
2. Set the version in `lib/onetime/version.rb`.
3. Update `CHANGES.txt` with the release date and notes.
4. Confirm the compatibility package dependency range remains appropriate.
5. Commit the release changes.
6. Tag and push:

   ```sh
   git tag -a v0.7.0 -m "onetimesecret 0.7.0"
   git push origin main
   git push origin v0.7.0
   ```

The tag runs the canonical release job, which checks the tag against
`Onetime::VERSION`, runs the test suite, builds the gem, and pushes it to
RubyGems.

Verify:

```sh
gem info onetimesecret --remote
gem install onetimesecret -v 0.7.0
```

## Cutting a compatibility release

Publish the canonical version first. Then:

1. Set the literal version and `onetimesecret` dependency requirement in
   `compat/onetime/onetime.gemspec`.
2. Confirm `onetimesecret` at the required version is available from RubyGems.
3. Commit any compatibility-package changes.
4. Tag and push with the compatibility prefix:

   ```sh
   git tag -a onetime-v0.7.0 -m "onetime compatibility package 0.7.0"
   git push origin onetime-v0.7.0
   ```

The compatibility release job checks the prefixed tag against the stub gemspec,
builds the dependency-only gem from `compat/onetime`, and pushes it to
RubyGems.

Verify:

```sh
gem info onetime --remote
gem install onetime -v 0.7.0
```

The install must bring in `onetimesecret`, display the migration message, and
continue to support `require "onetime"`.

## Versioning

The client remains below 1.0 until its API surface has settled. Keep canonical
and compatibility versions aligned when publishing a redirect release. Do not
publish implementation files in the `onetime` compatibility package.
