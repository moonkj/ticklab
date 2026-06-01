# 제안 "FastRatePipeline" 알고리즘 — 팀 검토 판정

> 2026-06-02. 다른 세션에서 생성된 고속 측정 알고리즘 제안(30초 autocorrelation → 5~8초 IOI+Kalman).
> 이 폴더는 **검토용 보관(미통합)**. 빌드에 포함되지 않음. 팀 에이전트 2명(DSP 정확성 / 통합·검증) 독립 검토.

## 판정: 현 상태로는 NO-GO (채택 불가). 목표는 타당, 구현은 비viable.

두 검토가 독립적으로 같은 결론에 도달.

### 치명적 문제
1. **컴파일 불가** — 존재하지 않는 API 4개 참조:
   - `AudioSource.chunks`(async) → 실제는 콜백 `start(onBuffer:)`/`stop()`.
   - `MovementDatabase.bestMatch(for:)` → 실제는 `movement(id:)` + `watch.customBph ?? movement?.bph ?? 28800`.
   - `BandPassFilter(centerHz:qFactor:)` → 실제는 `(sampleRate:lowCutoff:highCutoff:)`.
   - `EnvelopeExtractor.peakAmplitude(_:)` → 실제는 `process(_:) -> [Float]`만 존재.
2. **onset 시각 50/100ms 청크 양자화 = 치명적.** onset 시각 = `chunkIndex*0.05`. rate 1 s/day = 11.6ppm ≈ 반주기 125ms의 ~1.45µs 해상도 필요 → 50ms 그리드는 ~3만배 부족. beat error(서브-ms)도 그리드 배수로만 나와 측정 불가. 기존 파이프라인은 48kHz parabolic 보간으로 ~0.02ms 해상도.
3. **median-IOI rate = 문서화된 +140 s/d 위상편향 재도입.** 프로젝트가 이미 폐기하고 autocorrelation(`rawBph`)으로 전환한 그 방식. (DSPPipeline 주석 + MEMORY "rate 는 무조건 rawBph". 편향은 필터 group delay + 비대칭 피크라 systematic → median/MAD로 안 걸러짐.)
4. **Goertzel 타깃 주파수 오류(옥타브).** `bph/7200`=4Hz(틱+톡 전체 사이클)인데 실제 onset은 8Hz(`bph/3600`). 게다가 envelope 아닌 band-pass 캐리어에 적용(파라미터명만 envelope). 테스트가 4Hz 신호를 생성해 통과를 위장.
5. **Kalman 거짓 확신.** variance는 랜덤 산포만 추적 → 입력이 systematic 편향이면 "수렴·고신뢰"로 **확신에 찬 오답**을 보고(무측정보다 위험).
6. **테스트가 위험 경로를 전혀 검증 안 함.** 완벽한 onset 시각을 직접 주입해 오디오→envelope→청크→onset 경로를 우회. fixture/엔드투엔드 없음 → **Hard Rule #1 위반**.
7. 성능(30→5-8초)·정확도 주장 모두 미검증. AudioCapture 50ms 변경은 기존 파이프라인 회귀 위험. live waveform/metrics 스트림 없음(Hard Rule #4·UI 깨짐).

### 살릴 만한 좋은 아이디어
- **조기 종료(수렴 시)** — 측정시간 단축 목표 자체는 타당.
- **Goertzel BPH 사전선별**(O(N), 후보 6개) — 단, `bph/3600`을 **envelope**에 적용 + 옥타브 disambiguation 시.
- **적응형 임계(p75×1.8) + BPH 비례 refractory** — 기존 고정 30ms보다 개선.
- **MAD outlier rejection** — 구현 정확.

### viable해지려면 (두 검토 합의)
1. **샘플 해상도 onset 타이밍**: 청크로 coarse 검출 후 48kHz parabolic 보간(기존 `BeatDetector.refineTimestamps` 재사용). 청크 그리드 금지.
2. **rate는 autocorrelation 주기(`rawBph`) 또는 보정 타임스탬프 LSQ 기울기**(`LinearRegressionRate`). median-IOI 금지(편향 제거 + MEMORY 규칙 준수).
3. **Goertzel = `bph/3600` on envelope** + 반/배주파수 가드.
4. **신뢰도 = 교차추정 일치 + residual RMS + cross-window delta**(기존 `ReliabilityGrade` 기계 활용). Kalman variance 단독 금지.
5. **실제 API 정합**(콜백 AudioSource, movement(id:)+customBph, 실제 BandPass init, 실제 envelope op). 중복 상수 `standardBPHs` vs `standardBPHCandidates` 정리.
6. **플래그 게이트 프로토타입**(기존 DSPPipeline 기본 유지). 공유 `AudioCapture.chunkFrames` 변경 금지 — per-instance 파라미터. live waveform/metrics 스트림 보존(Hard Rule #4).
7. **fixture A/B**(SyntheticSignal clean/noisy/drift/asymmetric/unknown-BPH 전 경로) + **기기 A/B**(iPhone Air + IWC 레퍼런스) vs 현재. 위상편향 회귀 0 확인 후에만 기본 전환. Hard Rule #1/#10.

### 결론
현 제안 그대로는 **속도도 못 내고(컴파일 불가) 정확도는 오히려 후퇴(편향 재도입)**. 다만 "빠른 측정" 목표는 **좋은 아이디어(조기종료·Goertzel 사전선별·적응 onset)를 기존의 올바른 rate 추정기(autocorrelation rawBph) + 샘플해상도 타이밍 위에** 얹으면 달성 가능. 처음부터 다시 통합하는 수준의 작업이며, fixture/기기 A/B로 현재 대비 우월함을 증명한 뒤 플래그로 전환해야 함.
