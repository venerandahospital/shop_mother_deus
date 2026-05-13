# Changelog

All notable changes to this project are tracked in this file.

## [Unreleased]

### Added
- Modern auth flow with signup and direct navigation to main app after login/signup.
- Currency symbol support via settings (default `USh`) across dashboard, sales, inventory/items, and history.
- Sales cart flow for multi-item receipts with real-time totals.
- Optional partial-payment flow in sales with:
  - amount received,
  - auto-all-received option,
  - client selection for debt creation when balance exists.
- Clients module:
  - clients database/table and model,
  - clients list page with search,
  - add/edit client dialog,
  - debt indicator per client,
  - client details page with top summary card and pay action,
  - tabbed sections (`Orders`, `Payments`).
- Debts module enhancements:
  - grouped list by client,
  - pay popup with partial/full repayment,
  - automatic balance reduction,
  - payment status feedback.
- Debt payment tracking:
  - `debt_payments` table/model,
  - payment history page.
- Stock receiving enhancements:
  - separate receive stock page,
  - total cost input,
  - auto-computed unit cost (`total / quantity`),
  - receipt records persisted in `stock_receipts`,
  - receive records list/table screen.
- Reorder module:
  - reorder page listing items at/below reorder level,
  - suggested reorder quantity.
- Dashboard drawer (hamburger menu) for quick navigation.
- Dashboard card navigation:
  - Today's sales -> Sales history,
  - Outstanding debts -> Debts,
  - Reorder -> Reorder page,
  - Active store -> Stores.
- Sales history improvements:
  - one receipt card per sale with line items,
  - totals (total/paid/balance),
  - color coding (amount received green, balance red),
  - date range filter + quick chips (`Today`, `This week`, `This month`, `All`).
- Search bars:
  - clients page (fixed at top while list scrolls),
  - items page.

### Changed
- Rebranded visible `Inventory` labels to `Items` in key UI locations.
- Quick actions on dashboard updated to business flow (including Clients and Receive).
- Back-button behavior improved with exit prompt on main navigation.
- Sales/customer display standardized to uppercase client names in client-related views.

### Fixed
- Dashboard stat card overflow/layout issues.
- "Today sales" calculation reliability using local date key matching.
- Login keyboard overflow behavior.
- Client save/load issues caused by missing `clients` table:
  - migration safety in upgrade path,
  - `onOpen` table safety creation.
- Receive stock dialog lifecycle issue causing framework assertion during save.
- Lint/cleanup adjustments after UI and flow refactors.

---

## Notes for future updates
- Add each new change under `Unreleased` using: `Added`, `Changed`, `Fixed`.
- When making a release, move `Unreleased` entries to a versioned section, e.g.:
  - `## [1.1.0] - 2026-03-13`
