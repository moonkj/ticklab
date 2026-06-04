# 스트림 C — 커뮤니티 활성화 · 신규 로컬라이즈 키

위클리 테마 챌린지 · 브랜드 태그 부활 · 댓글 알림에서 추가된 사용자 노출 문자열.
Localizable.strings 직접 수정 금지(리더가 일괄 반영) — 아래 8개국어 표를 SSOT 로 사용.

키 네이밍: `community.*`. ko 가 default. 측정/거래/시세 문구 없음(브랜드명·테마명만 메타 수준).

| key | ko | en | es | fr | hi | ja | zh-Hans | zh-Hant |
|---|---|---|---|---|---|---|---|---|
| community.theme.eyebrow | 이번 주 테마 | This Week's Theme | Tema de la semana | Thème de la semaine | इस सप्ताह की थीम | 今週のテーマ | 本周主题 | 本週主題 |
| community.theme.participate | 참여하기 | Join | Participar | Participer | भाग लें | 参加する | 参与 | 參與 |
| community.theme.post_toggle | 이번 주 테마로 게시 | Post to this week's theme | Publicar en el tema de la semana | Publier dans le thème de la semaine | इस सप्ताह की थीम में पोस्ट करें | 今週のテーマに投稿 | 发布到本周主题 | 發佈到本週主題 |
| community.brand.picker.title | 브랜드 태그 (선택) | Brand tag (optional) | Etiqueta de marca (opcional) | Tag de marque (facultatif) | ब्रांड टैग (वैकल्पिक) | ブランドタグ（任意） | 品牌标签（可选） | 品牌標籤（選填） |
| community.brand.picker.note | 내 컬렉션 브랜드만 선택할 수 있어요 | Only brands from your collection | Solo marcas de tu colección | Uniquement les marques de votre collection | केवल आपके संग्रह के ब्रांड | コレクションのブランドのみ | 仅限你收藏中的品牌 | 僅限你收藏中的品牌 |
| community.brand.feed.empty | 이 브랜드의 게시물이 아직 없어요 | No posts for this brand yet | Aún no hay publicaciones de esta marca | Aucune publication pour cette marque | इस ब्रांड की अभी कोई पोस्ट नहीं | このブランドの投稿はまだありません | 该品牌还没有帖子 | 此品牌還沒有貼文 |
| community.notif.comment | 회원님의 게시물에 댓글을 남겼습니다 | Someone commented on your post | Alguien comentó tu publicación | Quelqu'un a commenté votre publication | किसी ने आपकी पोस्ट पर टिप्पणी की | あなたの投稿にコメントがつきました | 有人评论了你的帖子 | 有人留言了你的貼文 |

## 적용 가이드

- 8개 `Resources/<lang>.lproj/Localizable.strings` 에 위 키를 추가(형식: `"key" = "value";`).
- `community.notif.like` / `community.notif.follow` 는 기존 키(추가 불필요) — `Notice.Kind.localizationKey` 가 참조만 함.
- ko 가 default 언어이므로 누락 시 ko 값으로 폴백되도록 ko 부터 반영.

## 비고 (정책)

- 브랜드 칩은 **내 컬렉션 브랜드 화이트리스트**에서만 선택(시세·모델명·연락처 입력 불가) → 거래유도 차단.
- 위클리 테마/브랜드 모두 측정 데이터(rate/amplitude/serial/구매가) 미전송. 전송은 브랜드명 1개(메타) 한정.
- 서버 SQL(`docs/community/weekly_theme.sql`, `brand_tag.sql`)은 **미배포** 상태여도 클라가 graceful degrade
  (테마 배너 미표시·brand 정상·theme_id 컬럼 거절 시 1회 재시도로 게시 보존).
