# API عامل: `Behavior` و `WorldView`

جعبه‌ی ایمنی که به یک عامل (اسکریپت، قانون‌محور، یا مبتنی بر LLM) اجازه می‌دهد یک موجودیت را در زمان اجرا هدایت کند، بدون هیچ راهی برای خراب‌کردن وضعیت جهان.

## چرا جعبه‌ی ایمن؟

اگر یک Behavior می‌توانست `World` را آزادانه تغییر دهد، یک باگ یا یک فراخوانی بد LLM می‌توانست ناوردایی‌های سیستم‌های دیگر را بشکند. پس Behavior هرگز `World` واقعی را نمی‌بیند؛ فقط یک `WorldView` فقط‌خواندنی دارد و تنها می‌تواند با برگرداندن یک `Action` تغییری **پیشنهاد** دهد. `AISystem` آن را روی جهان واقعی اعمال می‌کند.

```text
Behavior.decide(WorldView, EntityId self) -> Action
                                               |
                                               v
                                  AISystem: action.apply(world)
```

## سه راه برای کنش

1. **مغز یک موجودیت (بی‌درنگ):** پیاده‌سازی `Behavior`.
2. **بازیکن (نوبتی):** خواندن جهان به‌صورت JSON و ارسال `Order` با `submitOrder`.
3. **نویسنده/اپراتور:** عملیات روی MCP، REST، JSON-RPC یا CLI (`zarvan`).

## قواعد

- هرگز storeها را از بیرون system مالک آن‌ها تغییر ندهید.
- پیش از نوشتن بخوانید؛ پیش از اجرا اعتبارسنجی کنید (`zarvan lint`، `project.problems`).
- از `world.random` و گام ثابت استفاده کنید؛ از زمان ساعت دیواری در شبیه‌سازی استفاده نکنید.

مرجع کامل (انگلیسی): [The agent API](../concepts/agent-api.md) · [Operations](../reference/operations.md) · [For AI agents](../guides/for-ai-agents.md)
