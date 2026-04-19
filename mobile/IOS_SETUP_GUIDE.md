# دليل تشغيل بصوتك على iPhone — من الماك ميني

> خطوات كاملة لتشغيل الأبلكيشن على iPhone الخاص بك باستخدام الماك ميني في البيت. مش محتاج Codemagic ولا خدمات سحابية — كل حاجة محلياً وأسرع.

---

## 📋 قبل ما تبدأ — احفظ الحاجات دي معاك

- [ ] Bundle IDs الأبلكيشن:
  - الأبلكيشن الرئيسي: `com.bisawtak.bisawtak`
  - Share Extension: `com.bisawtak.bisawtak.ShareExtension`
- [ ] Apple ID الخاص بحساب المطورين (اللي دفعت عليه 100$)
- [ ] iPhone مع كابل USB-C أو Lightning
- [ ] Backend URL: `https://voice.neojeen.com` (شغّال، مش محتاج تغيير)

---

## 1️⃣ إعداد الماك ميني (أول مرة فقط)

### 1.1 ثبّت Xcode

```bash
# افتح App Store على الماك → ابحث عن Xcode → Install
# الحجم كبير (~15GB) ممكن ياخد ساعة
```

بعد التثبيت، افتح Xcode مرة واحدة عشان يكمّل الـ setup:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
```

### 1.2 ثبّت Flutter

```bash
# باستخدام Homebrew
brew install --cask flutter

# أو تحميل مباشر من https://docs.flutter.dev/get-started/install/macos
```

تأكد إنه شغّال:
```bash
flutter --version
flutter doctor
```

### 1.3 ثبّت CocoaPods (iOS dependency manager)

```bash
sudo gem install cocoapods
# أو: brew install cocoapods
```

### 1.4 سجّل Developer Account في Xcode

1. افتح Xcode
2. **Xcode → Settings → Accounts**
3. دوس **+** → **Apple ID**
4. دخّل الـ Apple ID الخاص بحساب المطورين
5. تأكد إنه ظهر تحت **Teams** إنه "Team (Apple Developer Program)" مش "Personal Team"

---

## 2️⃣ جهّز المشروع على الماك ميني

### 2.1 انسخ المشروع

```bash
# لو مرفوع على GitHub:
git clone <repo-url>
cd bsoutk/mobile

# أو نقله بـ USB/AirDrop من الويندوز
```

### 2.2 نزّل الـ dependencies

```bash
cd mobile
flutter pub get

# iOS pods
cd ios
pod install
cd ..
```

> **ملاحظة:** لو `pod install` فشل، جرّب:
> ```bash
> cd ios && pod repo update && pod install && cd ..
> ```

---

## 3️⃣ إعداد Apple Developer Portal (متصفح على أي جهاز)

> دي خطوات لازم تتعمل مرة واحدة فقط.

### 3.1 سجّل Bundle IDs

ادخل https://developer.apple.com/account/resources/identifiers/list

1. دوس **+** (أيقونة زرقاء)
2. اختار **App IDs** → **Continue** → **App** → **Continue**
3. الأول، سجّل الأبلكيشن الرئيسي:
   - **Description:** `Bisawtak App`
   - **Bundle ID:** Explicit → `com.bisawtak.bisawtak`
   - **Capabilities:** فعّل اللي محتاجه:
     - [x] **Sign In with Apple** (مهم، الأبلكيشن بيستخدمها)
     - [x] **Push Notifications** (اختياري لو بتستخدمها)
     - [x] **App Groups** (محتاجة للـ Share Extension)
   - اضغط **Continue** → **Register**

4. كرّر للـ Share Extension:
   - **Description:** `Bisawtak Share Extension`
   - **Bundle ID:** Explicit → `com.bisawtak.bisawtak.ShareExtension`
   - **Capabilities:** [x] **App Groups**

### 3.2 اعمل App Group (للمشاركة بين الأبلكيشن والـ extension)

https://developer.apple.com/account/resources/identifiers/list/applicationGroup

1. **+** → **App Groups**
2. Description: `Bisawtak Shared`
3. Identifier: `group.com.bisawtak.bisawtak`
4. **Register**

ارجع لكل Bundle ID من اللي سجلتهم فوق، ربطهم بالـ App Group ده.

### 3.3 اعمل App Record في App Store Connect

ادخل https://appstoreconnect.apple.com/apps

1. **+** → **New App**
2. Platforms: **iOS**
3. Name: `بصوتك`
4. Primary Language: `Arabic`
5. Bundle ID: اختار `com.bisawtak.bisawtak` من القايمة
6. SKU: `bisawtak-ios-01` (أي قيمة فريدة)
7. **Create**

---

## 4️⃣ افتح المشروع في Xcode واضبط الـ Signing

### 4.1 افتح الـ workspace (مش الـ project!)

```bash
cd mobile/ios
open Runner.xcworkspace
```

> ⚠️ **مهم جداً:** لازم تفتح `Runner.xcworkspace` مش `Runner.xcodeproj`. لو فتحت الـ project هيفشل البناء.

### 4.2 اضبط Team و Signing للـ Runner target

1. في Xcode، اختار **Runner** من شجرة الـ navigator على اليسار
2. في الـ editor الأوسط، اختار target **Runner**
3. روح تاب **Signing & Capabilities**
4. فعّل **Automatically manage signing**
5. **Team:** اختار الـ team بتاع حساب المطورين بتاعك
6. **Bundle Identifier:** تأكد إنه `com.bisawtak.bisawtak`
7. Xcode هيعمل Provisioning Profile تلقائياً — انتظر شوية

### 4.3 كرّر للـ ShareExtension target

1. من نفس المكان، اختار target **ShareExtension**
2. **Signing & Capabilities**
3. **Team:** نفس الـ team
4. **Bundle Identifier:** `com.bisawtak.bisawtak.ShareExtension`

### 4.4 أضف App Group لكل target

لكل من الـ Runner والـ ShareExtension:
1. تاب **Signing & Capabilities**
2. اضغط **+ Capability** → اختار **App Groups**
3. فعّل `group.com.bisawtak.bisawtak`

### 4.5 لو ظهر خطأ "Failed to register bundle identifier"

معناه الـ Bundle ID مسجّل قبل كده على حساب تاني. حل:
- غيّر الـ Bundle ID في `ios/Runner.xcodeproj/project.pbxproj` لحاجة فريدة زي `com.yourname.bisawtak`
- سجّله في Apple Developer
- عدّل الـ App record في App Store Connect

---

## 5️⃣ شغّل الأبلكيشن على iPhone

### 5.1 جهّز الـ iPhone

1. على الـ iPhone: **Settings → Privacy & Security → Developer Mode → ON**
2. الـ iPhone هيعيد التشغيل
3. وصّل الـ iPhone بالماك بالكابل
4. على الـ iPhone لما يظهر **Trust This Computer?** → **Trust**
5. دخّل الـ passcode

### 5.2 تأكد إن Flutter شايف الـ iPhone

```bash
cd mobile
flutter devices
```

المفروض تشوف اسم الـ iPhone في القايمة.

### 5.3 شغّل الأبلكيشن

```bash
flutter run -d "<iPhone name>"
# أو بدون -d لو الـ iPhone هو الجهاز الوحيد المتصل:
flutter run
```

> **أول مرة ياخد 5-10 دقايق** عشان Xcode يبني الـ native code ويوقّع.

### 5.4 لو ظهر خطأ "Untrusted Developer" على الـ iPhone

على الـ iPhone:
1. **Settings → General → VPN & Device Management**
2. تحت **Developer App**، اختار الـ team بتاعك
3. **Trust "<Team Name>"** → **Trust**
4. رجع للـ home screen وافتح الأبلكيشن

---

## 6️⃣ توزيع على TestFlight (اختياري لو عايز تختبر من غير الكابل)

### 6.1 اعمل Archive

في Xcode:
1. من الـ toolbar فوق، اختار الجهاز **Any iOS Device (arm64)**
2. **Product → Archive**
3. انتظر ~5-10 دقايق

### 6.2 ارفع لـ App Store Connect

1. لما يخلص الـ Archive، هتفتح نافذة **Organizer**
2. اختار الـ archive → **Distribute App**
3. **App Store Connect** → **Upload**
4. سيب كل الـ options على الـ default
5. Xcode هيرفع تلقائياً (~5-15 دقيقة)

### 6.3 فعّل TestFlight

1. ادخل https://appstoreconnect.apple.com/apps
2. اختار بصوتك → تاب **TestFlight**
3. انتظر الـ build يظهر (ممكن ياخد 10-30 دقيقة عشان Apple يعمل processing)
4. لما يظهر، ضيف **Compliance Information** (سؤال عن encryption → اختار "No")
5. **Internal Testing** → اعمل Group → ضيف نفسك/أي tester بالإيميل
6. اضغط **Add Build** لتفعيل الـ build للـ group

### 6.4 ثبّت TestFlight على الـ iPhone

1. من App Store، نزّل **TestFlight**
2. سجّل دخول بنفس الإيميل
3. هتلاقي بصوتك في القايمة → **Install**

---

## 🔧 حل المشاكل الشائعة

| المشكلة | الحل |
|---|---|
| `pod install` فشل | `cd ios && pod repo update && pod install` |
| `CocoaPods not installed` | `sudo gem install cocoapods` |
| Signing errors في Xcode | امسح `~/Library/Developer/Xcode/DerivedData` وأعد فتح Xcode |
| iPhone مش ظاهر في `flutter devices` | - افصل الكابل وأعد توصيله<br>- على الـ iPhone: Trust This Computer<br>- جرّب كابل تاني (data cable مش charging only) |
| "No account for team" | Xcode → Settings → Accounts → Download Manual Profiles |
| Build بطيء جداً | خلّي عندك RAM 8GB+ مفضي، اقفل Chrome والبرامج التقيلة |
| "Sign in with Apple" مش شغّالة | تأكد إن Capability مفعّلة في Apple Developer Portal **و** Xcode |

---

## 📝 قبل ما ترفع production للـ App Store

- [ ] غيّر AdMob IDs من test IDs للـ real IDs في:
  - `ios/Runner/Info.plist` (مفتاح `GADApplicationIdentifier`)
  - `lib/config/constants.dart`
- [ ] ضيف App Icon حقيقي (1024×1024)
- [ ] ضيف Launch Screen
- [ ] اكتب App Description + Keywords + Screenshots في App Store Connect
- [ ] اكتب Privacy Policy URL (مطلوبة)
- [ ] Privacy labels في App Store Connect (بتقول الأبلكيشن بياخد إيه بيانات)

---

## 🚀 ملخص الأوامر (بعد الإعداد الأول)

من الماك ميني، في أي وقت عايز تحدّث الأبلكيشن:

```bash
cd ~/projects/bsoutk
git pull
cd mobile
flutter pub get
cd ios && pod install && cd ..
flutter run    # للتجربة السريعة على الـ iPhone المتصل
```

للرفع على TestFlight:
```bash
flutter build ipa --release
# أو من Xcode: Product → Archive → Distribute
```

---

## 📞 الخطوة التالية لما ترجع

1. اتأكد Xcode + Flutter متثبتين على الماك ميني (الخطوات في القسم 1)
2. ابدأ من **القسم 3** (Apple Developer Portal) — ده اللي هتاخد معظم الوقت
3. رجع للمشروع واتبع القسم 4 و 5

**الوقت المتوقع:** 1-2 ساعة أول مرة، بعد كده أي تحديث دقايق.
