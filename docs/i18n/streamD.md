# Stream D — i18n keys (데이터·온디바이스 AI·분석)

스트림 D(Rate 예측 · 이상탐지 · AI 추세요약)에서 추가한 사용자 노출 문자열 키 8개국어 표.
**리더(Hyemi)가 통합 시 각 `Resources/{lang}.lproj/Localizable.strings` 에 병합**한다.
스트림 격리 원칙상 본 스트림은 `Localizable.strings` 를 직접 수정하지 않는다 — 키 누락 시 iOS 는 key 자체를 폴백 표시(graceful).

- 언어: ko(default) · en · ja · zh-Hans · zh-Hant · fr · es · hi
- 포맷 인자: `%d`=정수, `%.1f`/`%.2f`=소수. 순서·개수 유지 필수.
- amplitude(진폭) 미언급(Hard Rule 9 무관). rate/추세/beat error 만.

---

## 1. forecast.* — Rate Drift 예측 (TrendChartView ghost 선 범례)

`forecast.legend.projected` 인자: `%d`=외삽 일수(예 90), `%.1f`=예측 rate(s/d).
`forecast.legend.a11y` 인자: `%d`=일수, `%.1f`=예측 rate, `%.1f`=± 신뢰폭.

| key | ko | en | ja | zh-Hans | zh-Hant | fr | es | hi |
|---|---|---|---|---|---|---|---|---|
| forecast.legend.projected | %d일 후 %.1f s/d 예상 | %dd: ~%.1f s/d | %d日後 約%.1f s/d | %d天后约%.1f s/d | %d天後約%.1f s/d | À %dj : ~%.1f s/d | En %dd: ~%.1f s/d | %d दिन: ~%.1f s/d |
| forecast.legend.a11y | 추세로 보면 %d일 후 약 %.1f초/일, 오차범위 ±%.1f초/일 예상 | Trend projects about %.1f s/d in %d days, margin ±%.1f s/d | 推移では%d日後に約%.1f秒/日、誤差±%.1f秒/日の見込み | 按趋势%d天后约为%.1f秒/天，误差±%.1f秒/天 | 依趨勢%d天後約為%.1f秒/天，誤差±%.1f秒/天 | La tendance projette environ %.1f s/j dans %d jours, marge ±%.1f s/j | La tendencia proyecta unos %.1f s/d en %d días, margen ±%.1f s/d | रुझान के अनुसार %d दिन में लगभग %.1f से/दिन, मार्जिन ±%.1f से/दिन |

> 주의: en/es 의 `%d`·`%.1f` 위치가 ko/ja 와 다르다(언어 어순). 인자 **개수·타입은 동일**, 순서만 문장에 맞게 둠 — Swift `String(format:)` 는 위치 인자(`%1$d`)를 명시하지 않으면 등장 순서로 매칭하므로, 표의 각 셀은 **(일수, rate)** 순서를 유지해야 한다. 위 표는 모두 (일수 → rate) 순서 보존.

---

## 2. anomaly.* — 이상탐지 카드 (StatsView 전용)

`anomaly.delta` 인자: `%.1f`=과거 중앙값 rate(s/d), `%.1f`=신규 측정 rate(s/d). (순서: baseline → latest)

| key | ko | en | ja | zh-Hans | zh-Hant | fr | es | hi |
|---|---|---|---|---|---|---|---|---|
| anomaly.eyebrow | 이상 감지 | ANOMALY | 異常検知 | 异常检测 | 異常偵測 | ANOMALIE | ANOMALÍA | असामान्यता |
| anomaly.reason.magnetization.title | 갑자기 빨라졌어요 | Suddenly running fast | 急に進みが速く | 突然变快 | 突然變快 | Soudain en avance | De repente adelanta | अचानक तेज़ |
| anomaly.reason.magnetization.body | 최근 측정이 평소보다 크게 빨라졌습니다. 자성화(자석 노출)가 흔한 원인이에요. 디마그네타이저로 해소되는지 확인해 보세요. | Your latest reading runs much faster than usual. Magnetization (magnet exposure) is a common cause — a demagnetizer often fixes it. | 直近の計測が普段よりかなり速くなっています。磁気帯び（磁石への接触）がよくある原因です。除磁器で改善するか確認してください。 | 最近一次测量比平时快很多。磁化（接触磁铁）是常见原因，消磁器通常可解决。 | 最近一次測量比平時快很多。磁化（接觸磁鐵）是常見原因，消磁器通常可解決。 | Votre dernière mesure avance bien plus que d'habitude. La magnétisation (exposition à un aimant) est une cause fréquente — un démagnétiseur la corrige souvent. | Tu última medición adelanta mucho más de lo habitual. La magnetización (exposición a imanes) es una causa común; un desmagnetizador suele solucionarlo. | आपकी हालिया रीडिंग सामान्य से काफ़ी तेज़ है। चुम्बकीकरण (चुंबक के संपर्क) एक आम कारण है — डीमैग्नेटाइज़र अक्सर इसे ठीक करता है। |
| anomaly.reason.shock.title | 갑자기 느려졌어요 | Suddenly running slow | 急に進みが遅く | 突然变慢 | 突然變慢 | Soudain en retard | De repente atrasa | अचानक धीमा |
| anomaly.reason.shock.body | 최근 측정이 평소보다 크게 느려졌습니다. 충격이나 윤활유 마름이 원인일 수 있어요. 며칠 더 측정해 추세를 확인해 보세요. | Your latest reading runs much slower than usual. A shock or dried lubricant may be the cause — measure over a few more days to confirm the trend. | 直近の計測が普段よりかなり遅くなっています。衝撃や潤滑油の劣化が原因かもしれません。数日かけて推移を確認してください。 | 最近一次测量比平时慢很多。可能由撞击或润滑油干涸引起，建议再测几天确认趋势。 | 最近一次測量比平時慢很多。可能由撞擊或潤滑油乾涸引起，建議再測幾天確認趨勢。 | Votre dernière mesure retarde bien plus que d'habitude. Un choc ou un lubrifiant desséché peut être en cause — mesurez encore quelques jours pour confirmer. | Tu última medición atrasa mucho más de lo habitual. Un golpe o lubricante seco puede ser la causa; mide unos días más para confirmar. | आपकी हालिया रीडिंग सामान्य से काफ़ी धीमी है। झटका या सूखा स्नेहक कारण हो सकता है — रुझान पुष्टि हेतु कुछ दिन और मापें। |
| anomaly.reason.beat_error.title | 비트 에러 급증 | Beat error spiked | ビートエラー急増 | 同步误差骤增 | 同步誤差驟增 | Erreur de battement | Pico de error de ritmo | बीट एरर बढ़ा |
| anomaly.reason.beat_error.body | 최근 측정의 비트 에러가 갑자기 커졌습니다. 탈진기나 밸런스에 충격이 있었을 수 있어요. 지속되면 워치메이커 상담을 권합니다. | The beat error in your latest reading jumped sharply. The escapement or balance may have taken a knock — if it persists, consult a watchmaker. | 直近の計測でビートエラーが急に大きくなりました。脱進機やテンプに衝撃があった可能性があります。続くようなら時計技師にご相談ください。 | 最近一次测量的同步误差骤然增大。擒纵机构或摆轮可能受过冲击，若持续请咨询制表师。 | 最近一次測量的同步誤差驟然增大。擒縱機構或擺輪可能受過衝擊，若持續請諮詢製錶師。 | L'erreur de battement de votre dernière mesure a bondi. L'échappement ou le balancier a pu subir un choc — si cela persiste, consultez un horloger. | El error de ritmo de tu última medición se disparó. El escape o el volante pudo recibir un golpe; si persiste, consulta a un relojero. | आपकी हालिया रीडिंग में बीट एरर तेज़ी से बढ़ा। एस्केपमेंट या बैलेंस को झटका लगा हो सकता है — बना रहे तो वॉचमेकर से परामर्श लें। |
| anomaly.delta | 평소 %.1f → 이번 %.1f s/d | Usual %.1f → now %.1f s/d | 通常 %.1f → 今回 %.1f s/d | 平时 %.1f → 本次 %.1f s/d | 平時 %.1f → 本次 %.1f s/d | Habituel %.1f → maint. %.1f s/d | Normal %.1f → ahora %.1f s/d | सामान्य %.1f → अब %.1f s/d |
| anomaly.disclaimer | 한 번의 측정으로 단정하지 마세요. 참고용 안내입니다. | One reading isn't conclusive — this is guidance only. | 1回の計測で断定しないでください。参考情報です。 | 单次测量不能定论，此为参考提示。 | 單次測量不能定論，此為參考提示。 | Une seule mesure n'est pas concluante — à titre indicatif. | Una sola medición no es concluyente; solo orientativo. | एक माप निर्णायक नहीं — यह केवल मार्गदर्शन है। |

---

## 3. aitrend.* — AI 추세 요약 카드 (StatsView 전용, on-device)

source 라벨 + 룰 폴백 헤드라인/본문 + 면책. (LLM 응답 텍스트 자체는 동적이라 키 불필요.)

| key | ko | en | ja | zh-Hans | zh-Hant | fr | es | hi |
|---|---|---|---|---|---|---|---|---|
| aitrend.source.ai | AI 추세 요약 | AI TREND | AI推移要約 | AI趋势摘要 | AI趨勢摘要 | TENDANCE IA | TENDENCIA IA | AI रुझान |
| aitrend.source.rule | 추세 요약 | TREND | 推移要約 | 趋势摘要 | 趨勢摘要 | TENDANCE | TENDENCIA | रुझान |
| aitrend.source.loading | 추세 분석 중… | Analyzing… | 分析中… | 分析中… | 分析中… | Analyse… | Analizando… | विश्लेषण… |
| aitrend.loading.body | 측정 추세를 분석하고 있어요. | Analyzing your measurement trend. | 計測の推移を分析しています。 | 正在分析测量趋势。 | 正在分析測量趨勢。 | Analyse de la tendance de vos mesures. | Analizando la tendencia de tus mediciones. | आपके माप के रुझान का विश्लेषण हो रहा है। |
| aitrend.fallback.good.headline | 안정적인 흐름 ✨ | Steady trend ✨ | 安定した推移 ✨ | 趋势稳定 ✨ | 趨勢穩定 ✨ | Tendance stable ✨ | Tendencia estable ✨ | स्थिर रुझान ✨ |
| aitrend.fallback.watch.headline | 변화가 보여요 👀 | Some change 👀 | 変化あり 👀 | 有所变化 👀 | 有所變化 👀 | Un changement 👀 | Hay cambios 👀 | बदलाव दिख रहा 👀 |
| aitrend.fallback.service.headline | 점검을 고려하세요 🔧 | Consider a service 🔧 | 点検を検討 🔧 | 建议检修 🔧 | 建議檢修 🔧 | Envisagez un service 🔧 | Considera un servicio 🔧 | सर्विस पर विचार करें 🔧 |
| aitrend.fallback.body.stable | 최근 측정들이 비슷한 값으로 모이고 있어요. 지금 상태를 잘 유지하고 있습니다. | Your recent readings cluster around a similar value — the watch is holding steady. | 直近の計測が近い値に揃っています。状態は安定して維持されています。 | 最近的测量集中在相近数值，走时保持稳定。 | 最近的測量集中在相近數值，走時保持穩定。 | Vos mesures récentes se regroupent autour d'une même valeur — la montre reste stable. | Tus mediciones recientes se agrupan en un valor similar; el reloj se mantiene estable. | आपकी हालिया रीडिंग एक जैसे मान के पास हैं — घड़ी स्थिर बनी है। |
| aitrend.fallback.body.gaining | 최근 측정들이 점점 빨라지는 추세예요. 며칠 더 지켜보며 흐름을 확인해 보세요. | Your recent readings are trending faster. Keep watching over a few more days to confirm the direction. | 直近の計測は次第に速くなる傾向です。数日かけて推移を確認してください。 | 最近测量呈逐渐变快趋势，建议再观察几天确认方向。 | 最近測量呈逐漸變快趨勢，建議再觀察幾天確認方向。 | Vos mesures récentes accélèrent. Observez quelques jours de plus pour confirmer. | Tus mediciones recientes tienden a adelantar. Obsérvalo unos días más para confirmar. | आपकी हालिया रीडिंग तेज़ होती जा रही हैं। दिशा पुष्टि हेतु कुछ दिन और देखें। |
| aitrend.fallback.body.losing | 최근 측정들이 점점 느려지는 추세예요. 며칠 더 지켜보며 흐름을 확인해 보세요. | Your recent readings are trending slower. Keep watching over a few more days to confirm the direction. | 直近の計測は次第に遅くなる傾向です。数日かけて推移を確認してください。 | 最近测量呈逐渐变慢趋势，建议再观察几天确认方向。 | 最近測量呈逐漸變慢趨勢，建議再觀察幾天確認方向。 | Vos mesures récentes ralentissent. Observez quelques jours de plus pour confirmer. | Tus mediciones recientes tienden a atrasar. Obsérvalo unos días más para confirmar. | आपकी हालिया रीडिंग धीमी होती जा रही हैं। दिशा पुष्टि हेतु कुछ दिन और देखें। |
| aitrend.disclaimer.ai | 기기 내 AI가 요약했어요. 측정 데이터는 외부로 전송되지 않습니다. | Summarized by on-device AI. Your measurement data never leaves your iPhone. | 端末内AIによる要約です。計測データは外部に送信されません。 | 由设备端AI生成，测量数据不会外传。 | 由裝置端AI生成，測量資料不會外傳。 | Résumé par l'IA sur l'appareil. Vos données de mesure ne quittent pas votre iPhone. | Resumido por IA en el dispositivo. Tus datos de medición nunca salen del iPhone. | डिवाइस के AI द्वारा सारांश। आपका माप डेटा iPhone से बाहर नहीं जाता। |
| aitrend.disclaimer.rule | 측정 추세를 기준으로 요약했어요. 참고용 안내입니다. | Summarized from your measurement trend — guidance only. | 計測の推移をもとに要約しました。参考情報です。 | 依据测量趋势生成，仅供参考。 | 依據測量趨勢生成，僅供參考。 | Résumé d'après la tendance de vos mesures — à titre indicatif. | Resumido según tu tendencia de medición; solo orientativo. | माप रुझान के आधार पर सारांश — केवल मार्गदर्शन। |
