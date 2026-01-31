# 📟 Pager Chat

> **The 90s are calling. They left a text.**

**Pager Chat** is a retro-styled, cross-platform messaging application built with **Flutter** and **Firebase**. It mimics the aesthetic and "fire-and-forget" simplicity of 90s pagers while delivering modern real-time performance.

![Flutter](https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/firebase-%23039BE5.svg?style=for-the-badge&logo=firebase)
![Android](https://img.shields.io/badge/Android-3DDC84?style=for-the-badge&logo=android&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-0078D6?style=for-the-badge&logo=windows&logoColor=white)
![Web](https://img.shields.io/badge/Web-4285F4?style=for-the-badge&logo=google-chrome&logoColor=white)

---

## ✨ Features

* **🎨 Authentic Retro UI:** High-contrast neon green text on a black background (`#050505`), inspired by EL (electroluminescent) displays.
* **🔒 Anonymous "Pager IDs":** No phone numbers or emails required. Users are identified solely by a unique 6-digit Pager ID.
* **⚡ Real-Time Messaging:** Powered by **Cloud Firestore** streams for instant delivery.
* **⏱️ "Oops" Undo:** A dedicated 5-second timer allows you to "delete" a message for everyone before it is permanently finalized.
* **🔔 Smart Notifications:**
    * **Android:** Local push notifications when the app is in the background.
    * **Windows/Web:** Optimized handling to prevent crashes on non-mobile platforms.
    * **Presence Detection:** Notifications are muted if you are currently looking at the active chat.
* **🚀 Cross-Platform:** Single codebase running natively on Android, Windows Desktop, and Web (PWA).

---

## 📸 Screenshots

| Login Screen | Chat List | Message Screen |
|:---:|:---:|:---:|
| *(Add screenshot here)* | *(Add screenshot here)* | *(Add screenshot here)* |

---

## 🛠️ Tech Stack

* **Framework:** Flutter (Dart)
* **Backend:** Firebase (Firestore)
* **State Management:** `setState` & StreamSubscriptions (optimized for performance)
* **Key Packages:**
    * `cloud_firestore`: Real-time database.
    * `shared_preferences`: Local storage for contacts and cached messages.
    * `flutter_local_notifications`: Handling background alerts.
    * `google_fonts`: For that retro monospace look.

---

## 🚀 Getting Started

### Prerequisites
1.  [Flutter SDK](https://docs.flutter.dev/get-started/install) installed.
2.  **Visual Studio 2022** (with C++ Desktop workload) for Windows builds.
3.  **Firebase CLI** installed (`npm install -g firebase-tools`).

### Installation

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/samuelmdileep/Pagerchat.git](https://github.com/samuelmdileep/Pagerchat.git)
    cd Pagerchat
    ```

2.  **Install dependencies:**
    ```bash
    flutter pub get
    ```

3.  **Configure Firebase:**
    You must connect the app to your own Firebase project.
    ```bash
    flutterfire configure
    ```
    *Select Android, Windows, and Web when prompted.*

4.  **Run the app:**
    * **Android:** `flutter run` (Ensure emulator/device is connected)
    * **Windows:** `flutter run -d windows`
    * **Web:** `flutter run -d chrome`

---

## 📦 Building for Production

### Android (APK)
```bash
flutter build apk --release
