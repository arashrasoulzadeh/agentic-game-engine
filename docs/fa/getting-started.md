# شروع سریع

از هیچ تا یک بازی در حال اجرا، در حدود پنج دقیقه.

## پیش‌نیازها

| نیاز | نسخه | بررسی |
|---|---|---|
| Flutter SDK (شامل Dart) | Dart `^3.9.0` | `flutter --version` |
| Git | هر نسخه‌ی اخیر | `git --version` |

Git لازم است چون پروژه‌ها از طریق وابستگی git به موتور وصل می‌شوند، نه pub.dev.

## ۱. نصب CLI

```bash
dart pub global activate --source git \
  https://github.com/arashrasoulzadeh/zarvan.git \
  --git-path packages/zarvan_cli
```

اگر هشدار PATH دیدید، `~/.pub-cache/bin` را به `PATH` اضافه کنید.

## ۲. ساخت پروژه

```bash
zarvan create my_game                           # پلتفرمر
zarvan create my_war --template strategy_game   # استراتژی نوبتی
zarvan create bakery --template idle_game       # بازی idle
```

سپس:

```bash
cd my_game
flutter run
```

## ۳. دستورهای روزمره

```bash
zarvan upgrade --ref main                     # جلو بردن نسخه‌ی موتور
zarvan lint assets/levels/main.level.json     # اعتبارسنجی سطح
zarvan project open .                         # سپس project.problems
```

## ادامه

- [مفهوم ZARVAN](concept.md) · [معماری](architecture.md) · [API عامل](agent-api.md)
- راهنمای کامل و آموزش‌ها (انگلیسی): [Getting started](../getting-started.md) · [Tutorials](../tutorials/README.md)
