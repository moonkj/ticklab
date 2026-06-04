# 스트림 A — 신규 Localizable.strings 키 (측정 UX·접근성·햅틱)

팀장이 8개 언어 `Localizable.strings` 에 일괄 반영. 스트림 A 는 strings 파일을 직접 수정하지 않음.

- `meas.a11y.*` — VoiceOver 측정 진행/완료/실패 음성 안내(UIAccessibility.post). `meas.a11y.completed_grade` 는 `%@` = 신뢰도 등급(A/B/C/F).
- `meas.failhelp.*` — 측정 실패 복구 체크리스트 카드(마지막 진단 기반 ✓/✗ + 권장 액션). `*.a11y.*` 는 ✓/✗ 아이콘의 VoiceOver 대체 텍스트.

## VoiceOver 진행 안내 (meas.a11y.*)

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
|-----|----|----|----|----|----|----|---------|---------|
| meas.a11y.measuring | 측정 중 | Measuring | Midiendo | Mesure en cours | माप जारी है | 測定中 | 测量中 | 測量中 |
| meas.a11y.analyzing | 분석 중 | Analyzing | Analizando | Analyse en cours | विश्लेषण जारी है | 解析中 | 分析中 | 分析中 |
| meas.a11y.completed | 측정 완료 | Measurement complete | Medición completada | Mesure terminée | माप पूर्ण | 測定完了 | 测量完成 | 測量完成 |
| meas.a11y.completed_grade | 측정 완료, %@등급 | Measurement complete, grade %@ | Medición completada, grado %@ | Mesure terminée, note %@ | माप पूर्ण, ग्रेड %@ | 測定完了、評価%@ | 测量完成，评级 %@ | 測量完成，評級 %@ |
| meas.a11y.failed | 측정 실패 | Measurement failed | La medición falló | Échec de la mesure | माप विफल | 測定失敗 | 测量失败 | 測量失敗 |

## 실패 복구 체크리스트 (meas.failhelp.*)

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
|-----|----|----|----|----|----|----|---------|---------|
| meas.failhelp.title | 점검 항목 | Checklist | Lista de comprobación | Liste de vérification | जाँच सूची | チェック項目 | 检查项 | 檢查項 |
| meas.failhelp.mic.label | 마이크 | Microphone | Micrófono | Microphone | माइक्रोफ़ोन | マイク | 麦克风 | 麥克風 |
| meas.failhelp.mic.action | 마이크가 소리를 받지 못했어요. iPhone 하단 마이크가 가려지지 않았는지 확인하세요. | The microphone isn't picking up sound. Make sure the iPhone's bottom mic isn't covered. | El micrófono no capta sonido. Asegúrate de que el micrófono inferior del iPhone no esté tapado. | Le microphone ne capte pas de son. Vérifiez que le micro inférieur de l'iPhone n'est pas obstrué. | माइक्रोफ़ोन ध्वनि नहीं पकड़ रहा है। सुनिश्चित करें कि iPhone का निचला माइक ढका न हो। | マイクが音を拾えていません。iPhone 下部のマイクが塞がれていないか確認してください。 | 麦克风未拾取到声音。请确认 iPhone 底部麦克风未被遮挡。 | 麥克風未拾取到聲音。請確認 iPhone 底部麥克風未被遮擋。 |
| meas.failhelp.signal.label | 신호 세기 | Signal strength | Intensidad de señal | Force du signal | सिग्नल शक्ति | 信号強度 | 信号强度 | 訊號強度 |
| meas.failhelp.signal.action | 신호가 약해요. 케이스백(시계 뒷면)을 iPhone 하단 마이크에 더 단단히 밀착하세요. | Signal is weak. Press the case back (watch rear) more firmly against the iPhone's bottom mic. | La señal es débil. Presiona el fondo de la caja (parte trasera del reloj) con más firmeza contra el micrófono inferior del iPhone. | Le signal est faible. Appuyez le fond du boîtier (dos de la montre) plus fermement contre le micro inférieur de l'iPhone. | सिग्नल कमज़ोर है। केसबैक (घड़ी का पिछला हिस्सा) को iPhone के निचले माइक पर और मज़बूती से दबाएँ। | 信号が弱いです。ケースバック（時計の裏蓋）を iPhone 下部のマイクにもっとしっかり押し当ててください。 | 信号较弱。请将表背（手表背面）更紧地贴在 iPhone 底部麦克风上。 | 訊號較弱。請將錶背（手錶背面）更緊地貼在 iPhone 底部麥克風上。 |
| meas.failhelp.quiet.label | 조용한 환경 | Quiet surroundings | Entorno silencioso | Environnement calme | शांत वातावरण | 静かな環境 | 安静环境 | 安靜環境 |
| meas.failhelp.quiet.action | 주변이 시끄러워요. 더 조용한 곳에서 다시 측정하세요. | The surroundings are noisy. Try again in a quieter place. | El entorno es ruidoso. Vuelve a intentarlo en un lugar más silencioso. | L'environnement est bruyant. Réessayez dans un endroit plus calme. | आसपास शोर है। किसी शांत जगह पर फिर से माप लें। | 周囲が騒がしいです。より静かな場所で再測定してください。 | 周围环境嘈杂。请在更安静的地方重新测量。 | 周圍環境嘈雜。請在更安靜的地方重新測量。 |
| meas.failhelp.generic.label | 신호 없음 | No signal | Sin señal | Aucun signal | कोई सिग्नल नहीं | 信号なし | 无信号 | 無訊號 |
| meas.failhelp.generic.action | 시계를 조용한 곳에 놓고 iPhone 하단 마이크를 케이스백에 밀착한 뒤 다시 시도하세요. | Place the watch in a quiet spot, hold the iPhone's bottom mic against the case back, and try again. | Coloca el reloj en un lugar silencioso, apoya el micrófono inferior del iPhone contra el fondo de la caja e inténtalo de nuevo. | Placez la montre dans un endroit calme, maintenez le micro inférieur de l'iPhone contre le fond du boîtier et réessayez. | घड़ी को शांत जगह पर रखें, iPhone के निचले माइक को केसबैक पर लगाएँ और फिर से प्रयास करें। | 時計を静かな場所に置き、iPhone 下部のマイクをケースバックに押し当てて再度お試しください。 | 将手表放在安静处，把 iPhone 底部麦克风贴在表背上后重试。 | 將手錶放在安靜處，把 iPhone 底部麥克風貼在錶背上後重試。 |
| meas.failhelp.bluetooth | AirPods/블루투스 마이크가 사용 중입니다. 시계 소리를 들으려면 iPhone 내장 마이크로 전환하세요. | A Bluetooth mic (AirPods etc.) is in use. Switch to the iPhone's built-in microphone to hear the watch. | Se está usando un micrófono Bluetooth (AirPods, etc.). Cambia al micrófono integrado del iPhone para oír el reloj. | Un micro Bluetooth (AirPods, etc.) est utilisé. Passez au microphone intégré de l'iPhone pour entendre la montre. | Bluetooth माइक (AirPods आदि) उपयोग में है। घड़ी सुनने के लिए iPhone के अंतर्निहित माइक्रोफ़ोन पर स्विच करें। | Bluetooth マイク（AirPods など）を使用中です。時計の音を拾うには iPhone 内蔵マイクに切り替えてください。 | 正在使用蓝牙麦克风（AirPods 等）。请切换到 iPhone 内置麦克风以拾取手表声音。 | 正在使用藍牙麥克風（AirPods 等）。請切換到 iPhone 內建麥克風以拾取手錶聲音。 |
| meas.failhelp.wired | 외장 마이크가 사용 중입니다. iPhone 내장 마이크로 전환하면 더 정확해요. | An external mic is in use. Switching to the iPhone's built-in microphone is more accurate. | Se está usando un micrófono externo. Cambiar al micrófono integrado del iPhone es más preciso. | Un micro externe est utilisé. Passer au microphone intégré de l'iPhone est plus précis. | बाहरी माइक उपयोग में है। iPhone के अंतर्निहित माइक्रोफ़ोन पर स्विच करना अधिक सटीक है। | 外部マイクを使用中です。iPhone 内蔵マイクに切り替えるとより正確です。 | 正在使用外接麦克风。切换到 iPhone 内置麦克风更准确。 | 正在使用外接麥克風。切換到 iPhone 內建麥克風更準確。 |
| meas.failhelp.a11y.ok | 정상 | OK | Correcto | Correct | ठीक है | 正常 | 正常 | 正常 |
| meas.failhelp.a11y.fix | 확인 필요 | Needs attention | Requiere atención | À vérifier | ध्यान देने योग्य | 要確認 | 需检查 | 需檢查 |
