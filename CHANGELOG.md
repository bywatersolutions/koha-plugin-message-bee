# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Fixed
- The "skip overdue phone notices for patrons with an sms number or email address" option now works. It never skipped anything, so patrons with an email address or sms number were also called about their overdues.

## [3.1.0] - 2022-05-19
- Add patron/account_balance to the JSON data
- Wrap most logic in try/catch to keep crashes from allowing messagebee yaml to be emailed by Koha

## [3.0.0] - 2022-05-19
- Update JSON data structure

## [0.0.1] - 2021-06-30
### Added
- Initial commit!
