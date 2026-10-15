# 저장소 작업 안내

현재 NOMA는 요구사항과 구현 설계를 정리한 단계입니다. 문서 변경은 실제 구현·실행·검증이 끝난 것처럼 표현하지 않습니다.

## 브랜치

`main`에서 작업 목적에 맞는 브랜치를 만들고, 이름은 소문자 영문과 하이픈을 사용합니다.

| 접두사 | 용도 | 예시 |
| --- | --- | --- |
| `docs/` | 문서·설계 설명 | `docs/repository-guide` |
| `feat/` | 기능 추가 | `feat/issuance-flow` |
| `fix/` | 오류 수정 | `fix/receipt-token-expiry` |
| `chore/` | 도구·설정·유지보수 | `chore/dev-environment` |

문서 작업 예시:

```sh
git switch main
git pull --ff-only origin main
git switch -c docs/your-topic
```

## 커밋

Conventional Commits 형식으로 변경 목적을 기록합니다. 브랜치 접두사는 이 저장소의 작업 규칙이며, 커밋 형식과 별도로 적용합니다.

```text
<type>(<optional scope>): <description>
```

- `docs`: 설명·문서 변경
- `feat`: 기능 추가
- `fix`: 오류 수정
- `refactor`: 동작을 유지하는 구조 변경
- `test`: 검증 코드 변경
- `chore`: 도구·설정·유지보수

예시:

```text
docs(repo): add repository overview and contribution guide
docs(auth): clarify recovery session permissions
feat(wallet): add credential receipt flow
```

호환성을 깨는 변경은 type/scope 뒤에 `!`를 붙이거나 커밋 본문에 `BREAKING CHANGE:`와 영향을 설명합니다. 실제 DDL이나 API 계약을 바꾸는 경우에는 변경 영향과 마이그레이션 필요 여부도 기록합니다. 문서 수정과 관련 없는 변경은 같은 커밋에 섞지 않습니다.

## 문서 변경 기준

- 제품 목적·공개 데이터·화면 범위는 [REQUIREMENTS.md](REQUIREMENTS.md)를 수정합니다.
- 인증·API·수명 주기·운영 정책은 [v1 구현 결정서](docs/V1-DECISIONS.md)를 수정합니다.
- 저장 구조 변경은 [초기 DDL](docs/schema.mysql.sql)과 결정서를 함께 확인합니다. DDL로 강제하지 않는 조건은 서비스 불변 조건으로 명시합니다.
- 문서 위치·구현 상태·시작 방법이 바뀌면 [README](README.md)도 갱신합니다.
- 규격의 버전과 초안 여부를 구분하고, 새로 추가하거나 변경한 외부 기술 주장에는 공식 자료를 확인합니다.
- 인증 비밀·복구 파일·실제 사용자 정보·운영 설정 값은 문서 예시나 이미지에도 넣지 않습니다.

## 검토와 검증

문서만 바꾸는 경우에는 다음을 확인합니다.

- 상대 링크·문서 앵커·이미지 경로가 유효한가?
- 요구사항·결정서·DDL의 필드, 인증 조건, 보존 기간이 일치하는가?
- 코드 블록과 표가 올바르게 표시되는가?
- 계획과 실제 완료한 검증을 구분했는가?
- 관련 없는 파일이나 비밀이 변경에 포함되지 않았는가?

변경 확인에는 다음 명령을 사용할 수 있습니다.

```sh
git diff --check
git diff --stat
git diff
git status --short
```

DDL 또는 서비스 동작이 바뀌면 문서 검토만으로 검증을 완료했다고 하지 않습니다. 실제 MySQL 실행과 관련 기능 검증 결과를 기록하고, 수행하지 못한 검증은 명시합니다. 전체 완료 기준은 [결정서 11절](docs/V1-DECISIONS.md#11-스키마와-구현-검증)을 따릅니다.

## 푸시와 변경 설명

검토한 파일을 명시적으로 stage하고 Conventional Commits 형식으로 커밋한 뒤 작업 브랜치를 푸시합니다.

```sh
git add README.md CONTRIBUTING.md
git commit -m "docs(repo): add repository overview and contribution guide"
git push -u origin docs/your-topic
```

Pull Request를 만들 때는 변경 목적, 최종 변경 내용, 검증 결과와 미검증 사항을 적습니다. `main` 반영은 검토 후 진행합니다.
