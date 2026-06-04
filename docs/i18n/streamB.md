# 스트림 B — 신규 로컬라이즈 키 (성장·수익화·리텐션)

스트림 B 작업에서 추가된 사용자 노출 문자열의 8개국어 번역 레퍼런스.

- `Localizable.strings` 는 이 스트림에서 직접 수정하지 않음(병렬 충돌·parity 테스트 보호).
  대신 코드에서 `String(localized: "<key>", defaultValue: "<ko>")` 형태로 호출하므로,
  키가 strings 에 없어도 ko 기본값으로 graceful 하게 표시된다.
- 통합 담당(Hyemi)이 추후 아래 표를 8개 `*.lproj/Localizable.strings` 에 일괄 반영하면
  각 로케일 번역이 적용된다. (반영 시 `LocalizationParityTests` 는 8개 로케일 동시 추가 필요.)
- 포맷 인자: `%d`=정수, `%@`/`%1$@`/`%2$@`=문자열(위치 지정). 순서 보존 필수.

## 기능 1 — 연간 무료 트라이얼 노출 (`PurchaseView`)

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| paywall.trial.badge | %1$@ 무료 체험 후 %2$@ | %2$@ after %1$@ free trial | %2$@ tras prueba gratis de %1$@ | %2$@ après %1$@ d'essai gratuit | %1$@ के मुफ्त परीक्षण के बाद %2$@ | %1$@の無料体験後%2$@ | %1$@免费试用后%2$@ | %1$@免費試用後%2$@ |
| paywall.trial.cta | 무료 체험 시작 | Start Free Trial | Iniciar prueba gratis | Démarrer l'essai gratuit | मुफ्त परीक्षण शुरू करें | 無料体験を始める | 开始免费试用 | 開始免費試用 |
| paywall.trial.legal | %@ 무료 체험이 끝나면 자동으로 유료 구독이 시작되며, 언제든 취소할 수 있어요. | After your %@ free trial, the paid subscription begins automatically. Cancel anytime. | Tras la prueba gratis de %@, la suscripción de pago comienza automáticamente. Cancela cuando quieras. | Après votre essai gratuit de %@, l'abonnement payant démarre automatiquement. Annulez à tout moment. | %@ के मुफ्त परीक्षण के बाद, सशुल्क सदस्यता स्वतः शुरू हो जाती है। कभी भी रद्द करें। | %@の無料体験が終了すると有料サブスクが自動的に開始されます。いつでも解約できます。 | %@免费试用结束后将自动开始付费订阅，可随时取消。 | %@免費試用結束後將自動開始付費訂閱，可隨時取消。 |
| paywall.trial.unit.day | 일 | -day | -día | -jour | दिन | 日間 | 天 | 天 |
| paywall.trial.unit.week | 주 | -week | -semana | -semaine | सप्ताह | 週間 | 周 | 週 |
| paywall.trial.unit.month | 개월 | -month | -mes | -mois | माह | か月 | 个月 | 個月 |
| paywall.trial.unit.year | 년 | -year | -año | -an | वर्ष | 年間 | 年 | 年 |

> 단위 키는 `trialPeriodText` 가 `"<value><unit>"` 로 결합한다(예 ko: `7일`, en: `7-day`).
> 영문/유럽어는 하이픈 접두 표기를 사용해 `7-day free trial` 처럼 자연스럽게 읽히도록 했다.

## 기능 2 — Paywall 데이터 미리보기 (`PurchaseView`)

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| paywall.preview.watch.title | 내 컬렉션 | Your collection | Tu colección | Votre collection | आपका संग्रह | あなたのコレクション | 我的收藏 | 我的收藏 |
| paywall.preview.watch.body | %d개의 시계를 기록 중이에요. 무료 등록 한도에 도달했어요. | You're tracking %d watches — you've reached the free registration limit. | Tienes %d relojes registrados: alcanzaste el límite gratuito. | Vous suivez %d montres — vous avez atteint la limite gratuite. | आप %d घड़ियाँ ट्रैक कर रहे हैं — मुफ्त सीमा पूरी हो गई। | %d本の時計を記録中。無料登録の上限に達しました。 | 你正在记录 %d 块手表，已达到免费注册上限。 | 你正在記錄 %d 隻手錶，已達免費註冊上限。 |
| paywall.preview.measure.title | 내 측정 기록 | Your measurements | Tus mediciones | Vos mesures | आपके माप | あなたの測定記録 | 我的测量记录 | 我的測量記錄 |
| paywall.preview.measure.count_label | 총 측정 | Total | Total | Total | कुल | 合計 | 总测量 | 總測量 |
| paywall.preview.measure.body | 오늘 무료 측정 한도에 도달했어요. 무제한으로 계속 추적해 보세요. | You've hit today's free measurement limit. Keep tracking without limits. | Alcanzaste el límite de mediciones gratis de hoy. Sigue midiendo sin límites. | Vous avez atteint la limite de mesures gratuites du jour. Continuez sans limite. | आज की मुफ्त माप सीमा पूरी हो गई। बिना सीमा ट्रैक करते रहें। | 本日の無料測定の上限に達しました。無制限で記録を続けましょう。 | 已达到今日免费测量上限。无限制继续追踪。 | 已達今日免費測量上限。無限制繼續追蹤。 |

## 기능 3 — 측정 Streak (`TodayView`)

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| streak.chip.label | %d일 연속 측정 | %d-day measuring streak | Racha de %d días midiendo | %d jours de mesure d'affilée | %d दिन से लगातार माप | %d日連続で測定中 | 连续测量 %d 天 | 連續測量 %d 天 |
| streak.chip.best | 최고 %d일 | Best %d | Récord %d | Record %d | सर्वश्रेष्ठ %d | 最高%d日 | 最佳 %d 天 | 最佳 %d 天 |
