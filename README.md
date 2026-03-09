# 🧭 autokaji (어떡하지)
> **"뭐 먹지? 뭐 하지?"** 결정 장애를 겪는 당신을 위한 스마트한 라이프스타일 큐레이션 앱

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/firebase-%23039BE5.svg?style=for-the-badge&logo=firebase)
![Dart](https://img.shields.io/badge/dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-764ABC?style=for-the-badge&logo=redux&logoColor=white)

---

## 🌟 Overview
**autokaji(어떡하지)**는 매 순간 선택의 기로에서 고민하는 '결정 장애'인들을 위해 태어났습니다. 단순히 맛집을 찾는 것을 넘어, 유저의 취향과 실제 방문 기록을 기반으로 한 진정성 있는 추천 서비스를 제공합니다.

기존의 지도 앱들이 광고와 무분별한 저장 목록으로 복잡했다면, **autokaji**는 오직 당신의 **진짜 경험**에 집중합니다.

---

## ✨ Key Features

### 1. 🎲 스마트 추천 시스템 (Smart Recommendation)
- **뭐 먹지? / 뭐 하지?**: 기분에 따라 음식점과 놀 거리를 자유롭게 스위칭하여 추천받을 수 있습니다.
- **세분화된 카테고리**: 한식/일식/중식/양식은 물론, 귀찮을 때는 '밥/빵/면/고기' 키워드만으로도 완벽한 장소를 제안합니다.

### 2. 🗓️ 방문 기록 & 캘린더 (Visit History & Calendar)
- **진짜 내 기록**: 가고 싶은 곳이 아닌, **직접 방문한 곳**만 별점과 함께 기록하여 나만의 미식 지도를 만듭니다.
- **타임라인 뷰**: 캘린더를 통해 언제 어디에서 누구와 즐거운 시간을 보냈는지 한눈에 확인하세요.

### 3. 🗺️ 위치 기반 탐색 (Map Integration)
- **주변 탐색**: 현재 내 위치를 기반으로 검증된 장소들을 지도 위에서 바로 확인하세요.
- **길 찾기**: 마음에 드는 장소를 발견하면 즉시 지도 앱으로 연결되어 이동할 수 있습니다.

### 4. 👥 소셜 연동 & 온보딩 (Social & Onboarding)
- **간편 로그인**: Google, Kakao, Naver를 통한 1초 회원가입 및 로그인을 지원합니다.
- **개인화 프로필**: 나만의 프로필과 취향 정보를 관리하세요.

---

## 🛠 Tech Stack

- **Framework:** `Flutter` (3.9.2+)
- **State Management:** `Riverpod` (v2.6.1)
- **Backend:** `Firebase` (Auth, Firestore, Storage)
- **Maps:** `Google Maps SDK`, `Google Places API`
- **Design System:** Custom Design (Warm Coral & Deep Navy Palette)
- **Local Storage:** `Shared Preferences`, `flutter_dotenv`

---

## 📂 Project Structure

```text
lib/
├── models/         # 데이터 모델 (장소, 방문 기록 등)
├── providers/      # Riverpod 상태 관리 Logic
├── repositories/   # 외부 API 및 Firebase 통신 계층
├── screens/        # UI Screen (Auth, Home, Map, Calendar 등)
├── services/       # 공통 서비스 (장소 검색, 위치 권한 등)
├── theme/          # App Theme & Color Palette (Custom Design)
└── widgets/        # 재사용 가능한 UI 컴포넌트
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) installed
- [Firebase Project](https://console.firebase.google.com/) set up
- `.env` file for API Keys

### Installation
1. Repository 클론:
   ```bash
   git clone https://github.com/your-username/autokaji.git
   cd autokaji
   ```
2. 종속성 설치:
   ```bash
   flutter pub get
   ```
3. `.env` 파일 설정:
   ```env
   KAKAO_NATIVE_APP_KEY=your_key
   # 기타 필요한 API 키들을 추가하세요
   ```
4. 앱 실행:
   ```bash
   flutter run
   ```

---

## 🎨 Design System
**autokaji**는 따뜻하고 신뢰감 있는 사용자 경험을 위해 정교한 컬러 시스템을 사용합니다.
- **Primary:** `Warm Coral (#FF6B6B)` - 에너지와 식욕을 돋우는 메인 컬러
- **Secondary:** `Deep Navy (#2C3E50)` - 차분하고 신뢰감 있는 서브 컬러
- **Background:** `Soft Cream (#FFF8F0)` - 눈이 편안한 배경색

---

## 🔮 Roadmap
- [ ] 친구와 기록 공유하기 (Social Feed)
- [ ] 영수증 인증을 통한 방문 신뢰도 강화
- [ ] AI 기반 취향 분석 서비스 도입
- [ ] 다크 모드(Dark Mode) 완벽 지원

---

## 📄 License
Copyright © 2026 autokaji. All rights reserved.
