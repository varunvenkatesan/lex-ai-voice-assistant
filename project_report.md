# Project Report: Lex AI Voice Assistant

## Abstract
The Lex AI Voice Assistant is an innovative cross-platform mobile application developed using Flutter. It aims to deliver a personalized, conversational artificial intelligence experience by integrating real-time voice interactions (Speech-to-Text and Text-to-Speech) with a reactive, interactive Live2D avatar. The application provides users with an empathetic and visually engaging virtual companion capable of handling casual conversation, answering complex queries, and managing user schedules through advanced reminder and notification systems. With a cloud infrastructure powered by Supabase, the app ensures secure authentication and real-time data sync, bridging the gap between utilitarian voice assistants and highly personalized virtual companions.

---

## Chapter 1: Introduction

### 1.1 About Project
The Lex AI project was conceived to revolutionize the way users interact with virtual assistants on their mobile devices. Traditional voice assistants are often perceived as disembodied and impersonal. Lex bridges this gap by offering a fully animated Live2D avatar that reacts to the conversation dynamically, creating a profound sense of presence. The scope of the project encompasses voice recognition, voice synthesis, cloud-based data tracking, local alarm scheduling, and high-performance UI rendering frameworks.

### 1.2 Project Plan
The development followed an agile methodology, split across the following key phases:
1. **Requirements Gathering & UI/UX Prototyping:** Designing the app interface and defining user interaction flows.
2. **Core Foundation:** Implementing the Flutter frontend structure, user authentication via Supabase, and navigation routes.
3. **Voice & AI Integration:** Connecting Speech-to-Text (STT) and Text-to-Speech (TTS) capabilities alongside natural language processing APIs.
4. **Live2D Avatar Engine:** Building native platform channels to support Live2D rendering models (e.g., IceGirl) onto the Flutter canvas.
5. **Auxiliary Features:** Implementing robust local notifications and timezone-aware scheduling for the reminders service.
6. **Testing & Deployment:** Conducting extensive unit, integration, and user-acceptance testing across Android and iOS emulators and physical devices.

### 1.3 Organization
The file structure is organized systematically:
- **`lib/screens/`**: UI implementations (e.g., `chat_screen.dart`, `login_screen.dart`, `reminders_screen.dart`, `settings_screen.dart`).
- **`lib/services/`**: Core business logic and external integrations (`supabase_service.dart`, `reminder_service.dart`).
- **`lib/models/`**: Data models definitions.
- **`lib/widgets/`**: Reusable UI components.
- **`assets/`**: Local storage for Live2D models, audio, UI images, and application branding.

---

## Chapter 2: Problem Definition & Feasibility

### 2.1 Problem Definition
Currently, most smart assistants lack emotional expressiveness and visual presence. Users often find themselves interacting with an inanimate interface lacking character or distinct identity. Furthermore, setting up smart environments requires complex, fragmented toolsets. Lex solves this by delivering context-aware conversations integrated directly with an animated avatar simulating emotion, realistic physics, and eye-tracking.

### 2.2 Feasibility Study
- **Technical Feasibility:** Flutter provides high-fidelity, high-performance cross-platform rendering (60-120 FPS). Integrating native C++ Live2D libraries is achievable via Platform Channels / MethodChannels. Supabase provides an easy-to-implement Backend-as-a-Service (BaaS). The technical stack is highly feasible.
- **Economic Feasibility:** Leveraging open-source frameworks (Flutter, Dart) and free-tier capabilities of cloud platforms (Supabase) minimizes the development and server setup overhead drastically.
- **Operational Feasibility:** The intuitive, gesture-based UI combined with a conversational user guide allows end-users to adopt the application without a steep learning curve.

---

## Chapter 3: System Requirements

### 3.1 Software Requirements
- **Frontend Framework:** Flutter 3.22+ and Dart SDK 3.4+.
- **Backend Service:** Supabase (PostgreSQL, Auth, Storage).
- **Libraries & Dependencies:** `flutter_tts`, `speech_to_text`, `livekit_client`, `supabase_flutter`, `flutter_local_notifications`, `timezone`, `google_fonts`.
- **Target OS:** Android 8.0+ / iOS 13+.

### 3.2 Functional Requirements
- **Authentication:** Users must be able to securely sign up, log in, and log out.
- **Voice Interactions:** The system must accurately capture user's voice (STT) and synthetically output the AI's response (TTS).
- **Avatar Simulation:** The system must render a Live2D character that idles uniquely and performs specific animations (gestures, lip-sync) correlated with user actions.
- **Reminders & Tasks:** Users must be able to schedule future alarms, receive persistent local notifications, and interact with an overlay system when alarms trigger.
- **Personalization:** Users can modify the app appearance, settings, and behavior.

### 3.3 Non-Functional Requirements
- **Performance:** Avatar animations must run smoothly without delaying the user interaction or blocking the main thread.
- **Scalability:** The backend database should support a growing user base managing massive amounts of chat history.
- **Availability:** Offline functionality for viewing previous alarms and reading earlier chats even when disconnected.

---

## Chapter 4: System Design

### 4.1 Architecture
The system employs a standard **Client-Server Architecture** augmented by **Native Platform Integration** for specific modules.
- **Client (Flutter App):** Manages user state, UI rendering, device integrations (Microphone/Speaker, Notifications).
- **Server (Supabase REST / GraphQL):** Manages relational database interactions for account info, configs, and chat logging.
- **Native Bridges:** Uses Android (Kotlin/Java) and iOS (Swift/Objective-C) Method Channels to handle Live2D rendering instances efficiently using native OS bindings.

### 4.2 Data Flow Diagram (DFD)
1. User activates microphone.
2. Device records audio --> `speech_to_text` translates audio to text.
3. Text query --> Processed by `ChatScreen` state & sent to AI Processing Backend.
4. AI Backend -> Returns conversational Response.
5. `flutter_tts` reads response text aloud.
6. Concurrently, `AnimationController` intercepts response context to trigger suitable Live2D motion files.

### 4.3 Unified Modeling Language (UML) Perspectives
- **Use Case:**
  - *Actors:* Primary User, System Cloud API.
  - *Cases:* Login User, Conduct Voice Chat, Set Reminder, Change Avatar Model, View About/Settings.
- **Sequence:**
  - Login Request -> Supabase Controller -> Auth Node -> Database Validation -> Returns Session Token.

### 4.4 Entity-Relationship (ER) Schema Overview
The primary database relationships implemented in Supabase include:
- **Users Table:** UUID (Primary Key), Email, Created_At.
- **Profiles Table:** User UUID (Foreign Key), Username, Preferences, Avatar Settings.
- **Reminders Table:** ReminderID, User UUID, Title, Timestamp, Is_Completed.
- **Chats Table:** SessionID, User UUID, Prompt, AI_Response, Timestamp.

---

## Chapter 5: Implementation

The implementation phase required assembling core Flutter architectural patterns. State management primarily handles updates to UI components asynchronously, relying heavily on `Future`, `Stream`, and Provider/Notifier architectures.

### Key Implementation Modules:
- **`AnimationController.dart`**: Oversees the Live2D character transitions. It features complex logic handling multi-step sequences—for instance, initializing a delayed sequence on app-start (e.g., 2 minutes idle delay) followed by randomized loop cycles (e.g., Facepalm, Peace Sign) mixed with dynamic responsiveness when the user starts speaking.
- **`SupabaseService.dart`**: Implements Singleton pattern to establish the PostgreSQL client, abstracting all backend CRUD constraints within modular getter/setter functions.
- **`ReminderService.dart`**: Maps native OS alarm and local notification APIs into Dart. It accounts for OS-specific battery optimizations and Doze modes on Android.

---

## Chapter 6: Testing

### 6.1 Unit Testing
Focused heavily on individual logic models, testing state-change outcomes and configuration parsers (`model_config.dart`). Checks were built to assure Live2D motion JSON structures parse correctly within Dart environments.

### 6.2 Integration Testing
Ensured seamless interaction among discrete subsystems. Key verification parameters included:
- Verifying the token expiry behavior mapping correctly from Supabase to Flutter's user session state.
- Asserting the transition flow between `AnimationController`, `Text-To-Speech (TTS)` and native bridges.

### 6.3 System Testing
End-to-End manual testing scenarios conducted to guarantee user satisfaction:
- *Scenario A:* Successfully initiating a voice chat on 3G network conditions to measure API timeout/response degradation.
- *Scenario B:* Validating scheduled reminders triggering precisely via push notifications, bringing app to foreground with the custom overlay `reminder_overlay_screen.dart`.

---

## Chapter 7: Conclusion & Future Enhancements

### 7.1 Conclusion
The development of Lex AI successfully demonstrates that an engaging, virtual-assistant experience can be built utilizing modern cross-platform technologies. The robust combination of Flutter, Native Platform Channels (Live2D), and an enterprise backend (Supabase) results in an application that is technically resilient and remarkably user-friendly. The application achieved its goals: rendering immersive visual AI while securing performance.

### 7.2 Future Enhancements
- **On-Device LLM Constraints:** Investigating integration with low-parameter on-device language models (like Llama-3 8B optimized) to reduce API latency.
- **Expanded Live2D Marketplace:** Allowing community designers to upload custom avatars, backgrounds, and voice models.
- **Wearable Extension:** Porting reminder structures and companion status into watchOS and WearOS targets.
- **Vision Capabilities:** Leveraging the device camera (`livekit_client`) to allow the avatar to react to user facial expressions.

---

## Appendix
*Placeholder for UI and Technical Screenshots*
- Figure A: Splash & Login Screen
- Figure B: Primary Chat Interface & Live2D Avatar
- Figure C: Reminders & Overlay
- Figure D: Settings & Personalization panel

---

## Bibliography
1. Flutter Official Documentation - *https://flutter.dev/docs*
2. Supabase Documentation & Quickstarts - *https://supabase.com/docs*
3. Live2D Cubism SDK Manuals - *https://docs.live2d.com*
4. Dart Packages (Pub.dev) - *https://pub.dev*
