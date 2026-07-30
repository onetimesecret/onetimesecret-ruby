# OnetimeSecret Ruby Client

The official Ruby client for the [OnetimeSecret](https://onetimesecret.com)
API. Share sensitive information through a link that can only be viewed once.

The gem is **`onetime`**. This repository, **`onetime-ruby`**, is the Ruby SDK
in the OnetimeSecret SDK family — each language has its own repository, and the
repository name is not the package name.

- **Zero runtime dependencies** — built entirely on the Ruby standard library
  (`net/http`, `uri`, `json`), so it drops into any environment without pulling
  transitive gems.
- **Supports API v1 and v2** — pick a version per client. The same resource
  methods exist for both, but each version returns its own response shape (they
  are different APIs; the client does not normalize them). **v1 is deprecated**
  and included only because the service still serves it — use v2 for new work.
- **Ruby 3.1+**.

> The `onetime` command-line tool has moved to a separate `onetime-cli` gem so
> that this library stays dependency-free.

## Installation

> [!WARNING]
> **Do not run `gem install onetime` yet.** The newest `onetime` release on
> RubyGems is still **0.5.1 (2013)** — the old command-line tool, whose API
> surface has nothing in common with this one. 0.6.0 is not published there
> yet, so a bare `gem install onetime` gets you that 2013 release and nothing
> in this README will work.

Until 0.6.0 is published, install from a **tagged** commit — not from a moving
branch:

```ruby
# Gemfile
gem "onetime", github: "onetimesecret/onetime-ruby", tag: "v0.6.0"
```

Tags are listed on the [releases
page](https://github.com/onetimesecret/onetime-ruby/releases) — if `v0.6.0`
does not resolve, 0.6.0 has not been tagged yet, so use the newest tag shown
there. Pinning `branch: "master"` works but ships whatever landed last; pin a
tag.

Once 0.6.0 is on RubyGems this becomes:

```ruby
gem "onetime", "~> 0.6"   # the constraint matters: 0.5.x is the 2013 CLI
```

Maintainers: see [docs/releasing.md](docs/releasing.md).

## Quick start

```ruby
require "onetime"

client = Onetime::Client.new(
  base_url:     "https://us.onetimesecret.com", # your region's API host (required)
  organization: "on1abc23def",                  # organization extid, not a UUID (see below)
  api_token:    ENV["ONETIME_API_TOKEN"],       # API token from your account page
  api_version:  :v2,                            # :v1 or :v2 (default :v2)
)

# Conceal a secret you already have
res = client.secrets.conceal(secret: "hunter2", ttl: 3600, passphrase: "pw")
res.dig("record", "receipt", "identifier")  # the receipt (creator) key
res.dig("record", "secret", "identifier")   # the secret (recipient) key

# Generate a random secret server-side
client.secrets.generate(ttl: 86_400)

# Reveal (consume) a secret — one-time only
secret = client.secrets.reveal("abc123secretkey", passphrase: "pw")
secret.dig("record", "secret_value")

# Service status (works on v1 and v2)
client.status
```

### Authentication

Authentication uses HTTP Basic, where the **organization extid** is the
username and your **API token** is the password.

> [!IMPORTANT]
> The `organization` value is the **organization extid** — a short identifier
> that begins with `on`, for example `on1abc23def`. It is **not a UUID.**
>
> UUIDs (`018f3c9e-7b1a-4c2d-9f8e-2a1b3c4d5e6f`) are internal record ids. They
> show up in API payloads, database rows, and admin tooling, and they look
> authoritative, which is exactly why they get pasted here. They are not
> credentials and will never authenticate.

| Value | Use as `organization`? | Where it comes from |
|---|---|---|
| `on1abc23def` | **Yes** | Bottom of the user menu when signed in — click the copy button next to the `on…` identifier |
| `018f3c9e-7b1a-4c2d-9f8e-2a1b3c4d5e6f` | No — internal record UUID | API response bodies, admin tooling, database ids |
| `you@example.com` | No — that was the 0.5.x `custid` | Your login email; not used for API auth since 0.6 |

The client checks the format at construction, so the wrong identifier fails
immediately instead of at the first request:

```ruby
Onetime::Client.new(
  base_url:     "https://us.onetimesecret.com",
  organization: "018f3c9e-7b1a-4c2d-9f8e-2a1b3c4d5e6f",
  api_token:    ENV["ONETIME_API_TOKEN"],
)
# => Onetime::ConfigurationError: organization "018f3c9e-..." looks like an
#    internal record UUID, not an organization extid. UUIDs appear in API
#    payloads and admin tooling but are not credentials. Your organization
#    extid is the "on…" identifier at the bottom of the user menu when you are
#    signed in (there is a copy button next to it). Pass it as organization: or
#    set ONETIME_ORG_EXTID.
```

#### When credentials are silently ignored

Some server versions accept a request carrying unusable credentials and create
the secret **anonymously** instead of returning 401. The call succeeds, you get
a working link, and it never appears in your organization's account.

The client watches for that: when a client with credentials receives a record
the server marked as anonymous, it warns once (to `logger` if you passed one,
otherwise `$stderr`). Guest-route calls (`guest: true`) are exempt, since being
ownerless is the point of those. Control it with `on_unowned:`:

```ruby
Onetime::Client.new(..., on_unowned: :raise)   # :warn (default), :raise, :ignore
# raises Onetime::UnownedResponseError; #response holds the successful response
```

### Base URL (required)

`base_url` must be the API host for your region, your self-hosted domain, or
your custom domain. There is no default: deployments are region-isolated for
data sovereignty, so the client cannot guess one for you.

Regional API hosts:

| Region | Host |
|---|---|
| United States | `https://us.onetimesecret.com` |
| Europe | `https://eu.onetimesecret.com` |
| United Kingdom | `https://uk.onetimesecret.com` |
| Canada | `https://ca.onetimesecret.com` |
| Aotearoa New Zealand | `https://nz.onetimesecret.com` |

> The apex `onetimesecret.com` is the company website, not an API host, and
> is rejected with a helpful error.

### Configuration

| Option         | Default                                       | Notes                                   |
|----------------|-----------------------------------------------|-----------------------------------------|
| `base_url`     | — (**required**)                              | Region/self-hosted/custom domain        |
| `api_version`  | `:v2`                                          | `:v1` or `:v2`                          |
| `organization` | `ENV["ONETIME_ORG_EXTID"]`                     | Organization extid (`on...`)            |
| `api_token`    | `ENV["ONETIME_API_TOKEN"]`                     | API token                               |
| `timeout`      | `30`                                           | Read timeout (seconds)                  |
| `open_timeout` | `10`                                           | Connect timeout (seconds)               |
| `max_retries`  | `2`                                            | Retries for idempotent (GET) requests   |
| `on_unowned`   | `:warn`                                        | `:warn`, `:raise` or `:ignore` — see [above](#when-credentials-are-silently-ignored) |

Environment fallbacks: `base_url` ← `ONETIME_BASE_URL`; `organization` ←
`ONETIME_ORG_EXTID`; `api_token` ← `ONETIME_API_TOKEN`.

Clients are thread-safe: they hold only configuration and a stateless
transport, opening a fresh connection per request.

## Anonymous and guest usage

A client created without credentials is anonymous and can use public and guest
endpoints:

```ruby
guest = Onetime::Client.new(base_url: "https://us.onetimesecret.com")  # no credentials
guest.secrets.conceal(secret: "no account needed", guest: true)
```

## Resources

### `client.secrets`

| Method | v1 | v2 |
|---|----|----|
| `conceal(secret:, ttl:, passphrase:, recipient:, share_domain:)` | yes | yes |
| `generate(ttl:, passphrase:, recipient:, share_domain:)` | yes | yes |
| `reveal(key, passphrase:, continue:)` | yes | yes |
| `show(key)` | — | yes |
| `status(key)` | — | yes |
| `status_list(keys)` | — | yes |

`conceal` is also available as `share`. `reveal`/`show` accept either a bare
key or a full secret URL.

### `client.receipts`

| Method | v1 | v2 |
|---|----|----|
| `show(key)` | yes | yes |
| `recent` | yes | yes |
| `burn(key, passphrase:, continue:)` | yes | yes |
| `update(key, memo:)` | — | yes |

### Meta

`client.status` (v1 & v2), `client.version` / `client.supported_locales`
(v2 only), `client.authcheck` (v1 only).

## Responses

Resource methods return an `Onetime::Response` with indifferent (String or
Symbol) key access:

```ruby
res = client.secrets.conceal(secret: "hi")
res["record"]                                   # Hash
res.dig(:record, :secret, :secret_value)        # deep access
res.success?                                     # 2xx?
res.http_status                                  # Integer
res.to_h                                         # the parsed body
```

The response shape is the API's, unchanged. v1 and v2 differ on purpose —
v1 returns flat, all-string fields; v2 nests data under `record`/`details`
with richer typing — and the client does not reconcile them. Read the
[API docs](https://docs.onetimesecret.com/) for the shape of the version
you target.

## Errors

HTTP errors (status >= 400) raise typed exceptions following the API's
ADR-013 error contract (`{ error:, error_type:, ... }`):

```ruby
begin
  client.secrets.reveal("missing")
rescue Onetime::NotFoundError => e
  e.message      # human-readable message ("error" field)
  e.error_type   # machine-readable type ("RecordNotFound")
  e.http_status  # 404
rescue Onetime::RateLimitError => e
  e.retry_after
rescue Onetime::APIError => e
  # any other API error
end
```

| Exception | When |
|---|---|
| `Onetime::BadRequestError` | 400 / `FormError` (see `#field`) |
| `Onetime::AuthenticationError` | 401 |
| `Onetime::AccountRequiredError` | the operation needs an authenticated account (`requires_account`); subclasses `AuthenticationError`, keeps `#field` |
| `Onetime::ForbiddenError` | 403 / `Forbidden`, `GuestRoutesDisabled` |
| `Onetime::EntitlementError` | `EntitlementRequired` (see `#entitlement`) |
| `Onetime::NotFoundError` | 404 / `RecordNotFound` |
| `Onetime::RateLimitError` | 429 / `LimitExceeded` (see `#retry_after`) |
| `Onetime::ServerError` | 5xx |
| `Onetime::TransportError` / `TimeoutError` | network failures |
| `Onetime::ConfigurationError` | bad `base_url`, wrong `organization` format, incomplete credentials (raised at construction) |
| `Onetime::UnownedResponseError` | a *successful* response the server recorded as anonymous, with `on_unowned: :raise` |

All inherit from `Onetime::Error`.

`AccountRequiredError` exists because the service reports "this needs an
account" inside a `400` form-error body (`field: "requires_account"`). Mapping
that to `BadRequestError` sent people auditing their request payload for a
problem that was never there, so it gets its own class under
`AuthenticationError`:

```ruby
begin
  client.secrets.conceal(secret: "hi")
rescue Onetime::AccountRequiredError => e
  e.field        # "requires_account" — preserved
  e.http_status  # whatever the server sent (400 today)
end
```

## Development

```sh
bundle install
rake test
```

## License

See [LICENSE.txt](LICENSE.txt).
