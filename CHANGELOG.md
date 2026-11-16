# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [4.2.0] - 2026-11-16

### Added
- Purchase suggestion notices (ACCEPTED, REJECTED, ORDERED, AVAILABLE and other suggestion statuses) can now be sent through MessageBee using the new `suggestion` template key.
- Interlibrary loan notices to patrons (ILL_PICKUP_READY, ILL_REQUEST_UNAVAIL and ILL_REQUEST_UPDATE) can now be sent through MessageBee using the new `ill_request` template key.
- Payment and writeoff receipts (ACCOUNT_PAYMENT and ACCOUNT_WRITEOFF) can now be sent through MessageBee using the new `credit` template key, along with the fees each one paid off.
- Recall pickup notices (PICKUP_RECALLED_ITEM) can now be sent through MessageBee using the new `recall` template key.
- Curbside pickup notices (NEW_CURBSIDE_PICKUP) can now be sent through MessageBee using the new `curbside_pickup` template key.
- Article request notices (AR_REQUESTED, AR_PENDING, AR_PROCESSING, AR_COMPLETED and AR_CANCELED) can now be sent through MessageBee using the new `article_request` template key.
- Booking notices (BOOKING_CONFIRMATION, BOOKING_MODIFICATION and BOOKING_CANCELLATION) can now be sent through MessageBee using the new `booking` template key.

## [4.1.4] - 2026-10-15

### Fixed
- The "skip overdue phone notices for patrons with an sms number or email address" option now works. It never skipped anything, so patrons with an email address or sms number were also called about their overdues.
- Overdue letter codes are now read from the circulation rules on Koha 26.06 and later, where Bug 10190 removed the overduerules table. Until now the plugin died on every run there.

## [3.1.0] - 2022-05-19
- Add patron/account_balance to the JSON data
- Wrap most logic in try/catch to keep crashes from allowing messagebee yaml to be emailed by Koha

## [3.0.0] - 2022-05-19
- Update JSON data structure

## [0.0.1] - 2021-06-30
### Added
- Initial commit!

[Unreleased]: https://github.com/bywatersolutions/koha-plugin-message-bee/compare/v4.2.0...HEAD
[4.2.0]: https://github.com/bywatersolutions/koha-plugin-message-bee/compare/v4.1.4...v4.2.0
[4.1.4]: https://github.com/bywatersolutions/koha-plugin-message-bee/compare/v4.1.3...v4.1.4
