# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [4.0.0] - 2024-12-03
### Changed
- **BREAKING**: Renamed plugin from MessageBee to WebhookNotifications
- **BREAKING**: Replaced SFTP upload with HTTP webhook (OAuth2 + REST API)
- **BREAKING**: Changed YAML trigger from `messagebee: yes` to `webhook: yes`
- **BREAKING**: Renamed all environment variables from `MESSAGEBEE_*` to `WEBHOOK_*`
- Renamed API namespace from `/messagebee/` to `/webhook_notifications/`

### Added
- OAuth2 client credentials authentication flow
- Configurable payload format (full enriched data or minimal IDs only)
- Support for optional `customer-id` header via `WEBHOOK_CUSTOMER_ID` env var

### Removed
- SFTP upload functionality (replaced with HTTP POST)
- `Net::SFTP::Foreign` dependency

## [3.1.0] - 2022-05-19
- Add patron/account_balance to the JSON data
- Wrap most logic in try/catch to keep crashes from allowing messagebee yaml to be emailed by Koha

## [3.0.0] - 2022-05-19
- Update JSON data structure

## [0.0.1] - 2021-06-30
### Added
- Initial commit!
