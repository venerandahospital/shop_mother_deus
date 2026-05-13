# Shop / POS (Flutter)

Flutter application for retail and inventory: sales, stock, clients, expenses, and optional sync with a **mother** device over HTTP. This project replaced an earlier lab-app template; the codebase under `lib/` is the shop system, not laboratory forms.

## Features (overview)

- **Authentication**: login, signup, password recovery, remote roles where configured
- **Inventory**: items, categories, stores, barcodes, stock receipts, adjustments, transfers
- **Sales**: cart, drafts, history, debts, client accounts, loans, services
- **Business**: dashboard, expenses, assets, packaging, subscriptions, backups
- **Local data**: SQLite via `LocalDbService`; optional **mother API** for thin clients / sync

## Project structure (high level)

```
lib/
├── main.dart                 # App entry
├── navigation/               # Routing (e.g. app_router.dart)
├── models/                   # Item, Sale, Client, Store, Debt, …
├── services/               # local_db_service, auth_service, mother API, settings, …
├── screens/                # UI screens (sales, inventory, clients, settings, …)
├── widgets/                # Shared UI (drawer, nav, cards, …)
├── utils/                  # Formatting, barcode helpers, …
└── search/                 # Item search helpers
```

Paths and filenames evolve; use your IDE or `dir lib /s` to browse the current tree.

## Run locally

```bash
flutter pub get
flutter run
```

Configure shop name, currency, and remote API URLs in **Settings** inside the app (and any env-specific constants your build uses).

## Notes

- The Dart package name in `pubspec.yaml` may still be `lab_app` from the original template; that does not affect store builds but can be renamed later if you want the package identifier to match the shop product.
