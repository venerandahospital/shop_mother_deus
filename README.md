# Lab Management Flutter App

A modern Flutter application for managing lab requests and entering lab results. This app connects to the same backend API as the Angular lab-mobile component.

## Features

- **Modern Login Page**: Beautiful gradient login screen with form validation
- **Lab Requests Drawer**: Side drawer with searchable list of all lab requests
- **Dynamic Forms**: Different forms appear based on the selected lab request type:
  - **MRDT Form**: For malaria test results
  - **Urinalysis Form**: Complete urinalysis report with chemical, microscopic, and physical examination sections
  - **CBC Form**: Complete Blood Count form with reference ranges
  - **Parasitology Stool Form**: For stool examination results
  - **General Form**: For other lab tests

## Project Structure

```
lib/
├── config/
│   └── api_config.dart          # API endpoint configurations
├── models/
│   ├── lab_request.dart          # Lab request model
│   ├── lab_report.dart           # General lab report model
│   ├── urinalysis_report.dart    # Urinalysis report model
│   ├── cbc_report.dart           # CBC report model
│   └── parasitology_stool_report.dart  # Parasitology stool report model
├── services/
│   ├── auth_service.dart         # Authentication service
│   └── api_service.dart          # API service for all endpoints
├── screens/
│   ├── login_screen.dart         # Login page
│   └── main_screen.dart          # Main screen with drawer and forms
├── widgets/
│   ├── lab_request_drawer.dart   # Drawer widget with lab requests list
│   └── forms/
│       ├── mrdt_form.dart         # MRDT form widget
│       ├── general_form.dart      # General lab form widget
│       ├── urinalysis_form.dart   # Urinalysis form widget
│       ├── cbc_form.dart          # CBC form widget
│       └── parasitology_stool_form.dart  # Parasitology stool form widget
└── main.dart                     # App entry point
```

## API Endpoints

The app connects to the following endpoints (configured in `lib/config/api_config.dart`):

- Base URL: `http://localhost:8080`
- Login: `POST /course/auth/user-login`
- Get Lab Requests: `GET /course/Patient-management/get-all-lab-procedures`
- Get Reports: Various endpoints for different report types
- Update Reports: Various endpoints for updating reports

## Setup Instructions

1. **Install Dependencies**:
   ```bash
   flutter pub get
   ```

2. **Configure API Base URL**:
   Edit `lib/config/api_config.dart` and update the `baseUrl` if your backend is running on a different address.

3. **Run the App**:
   ```bash
   flutter run
   ```

## Dependencies

- `http`: For API calls
- `provider`: For state management
- `shared_preferences`: For local storage (authentication tokens)
- `pdf` & `printing`: For PDF generation (future feature)

## Usage

1. **Login**: Enter your username and password to authenticate
2. **View Requests**: Open the drawer (menu icon) to see all lab requests
3. **Search**: Use the search bar in the drawer to filter requests
4. **Select Request**: Tap on a request to open the appropriate form
5. **Enter Results**: Fill in the form fields and save
6. **Logout**: Use the account menu in the app bar to logout

## Form Types

The app automatically determines which form to show based on:
- **Category**: "malaria test" → MRDT Form
- **Procedure Name**: 
  - "urinalysis" → Urinalysis Form
  - "cbc" or contains "cbc" → CBC Form
  - "parasitology stool" → Parasitology Stool Form
  - Others → General Form

## Notes

- The app stores authentication tokens locally using SharedPreferences
- All API calls include authentication headers when available
- Forms automatically load existing report data if available
- Success/error messages are displayed after saving reports
