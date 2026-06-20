# OnetimeSecret Ruby Client

The official Ruby client for the [OnetimeSecret](https://onetimesecret.com)
API. Share sensitive information through a link that can only be viewed once.

- **Zero runtime dependencies** — built entirely on the Ruby standard library
  (`net/http`, `uri`, `json`), so it drops into any environment without pulling
  transitive gems.
- **Supports API v1 and v2** — pick a version per client; the same resource
  methods work across both.
- **Ruby 3.1+**.

> The `onetime` command-line tool has moved to a separate `onetime-cli` gem so
> that this library stays dependency-free.

## Installation

```sh
gem install onetime
```

Or in a Gemfile:

```ruby
gem "onetime"
```

## Quick start

```ruby
require "onetime"

client = Onetime::Client.new(
  username:    "you@example.com",          # your account email
  api_token:   ENV["ONETIME_API_TOKEN"],   # API token from your account page
  api_version: :v2,                        # :v1 or :v2 (default :v2)
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

### Configuration

| Option         | Default                        | Notes                                   |
|----------------|--------------------------------|-----------------------------------------|
| `base_url`     | `https://onetimesecret.com`    | Override for self-hosted installs       |
| `api_version`  | `:v2`                          | `:v1` or `:v2`                          |
| `username`     | `ENV["ONETIME_CUSTID"]`        | Account email                           |
| `api_token`    | `ENV["ONETIME_APIKEY"]`        | API token                               |
| `timeout`      | `30`                           | Read timeout (seconds)                  |
| `open_timeout` | `10`                           | Connect timeout (seconds)               |
| `max_retries`  | `2`                            | Retries for idempotent (GET) requests   |

`base_url` also reads `ENV["ONETIME_HOST"]`.

Clients are thread-safe: they hold only configuration and a stateless
transport, opening a fresh connection per request.

## Anonymous and guest usage

A client created without credentials is anonymous and can use public and guest
endpoints:

```ruby
guest = Onetime::Client.new(api_version: :v2)            # no credentials
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

> v1 serializes all fields as strings; v2 nests data under `record`/`details`.
> See the [API docs](https://docs.onetimesecret.com/) for response shapes.

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
| `Onetime::ForbiddenError` | 403 / `Forbidden`, `GuestRoutesDisabled` |
| `Onetime::EntitlementError` | `EntitlementRequired` (see `#entitlement`) |
| `Onetime::NotFoundError` | 404 / `RecordNotFound` |
| `Onetime::RateLimitError` | 429 / `LimitExceeded` (see `#retry_after`) |
| `Onetime::ServerError` | 5xx |
| `Onetime::TransportError` / `TimeoutError` | network failures |

All inherit from `Onetime::Error`.

## Migrating from 0.5.x

The legacy `Onetime::API` interface still works (now backed by the new
transport, no HTTParty required) and defaults to API v1:

```ruby
require "onetime/api"
api = OT::API.new("you@example.com", "APITOKEN")
api.get("/status")
api.post("/generate", passphrase: "secret")
api.response.code
```

New code should prefer `Onetime::Client`.

## Development

```sh
bundle install
rake test
```

## License

See [LICENSE.txt](LICENSE.txt).
