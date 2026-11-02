# CI/CD 설정 가이드 (CodeCommit → CodeBuild → CodeDeploy → EC2)

## 전체 흐름

```
개발자 git push
   ↓
CodeCommit (코드 저장)
   ↓  CodePipeline이 변경 감지
CodeBuild  (npm ci → test → build, buildspec.yml)
   ↓  결과물(zip)을 S3에 저장
CodeDeploy (EC2에 복사 → 패키지 설치 → PM2로 실행, appspec.yml)
   ↓
EC2에서 서비스 실행 (기본 3000번 포트)
```

## 전제 조건

1. `package.json`에 `build` 스크립트(선택)와 운영 서버를 띄우는 `start` 스크립트가 있어야 합니다.
2. `start`가 개발 서버(`react-scripts start`, `vite` 등)라면 운영용으로 바꿔야 합니다.
   - React만 있는 경우 예: `"start": "serve -s build -l 3000"` (`serve` 패키지를 dependencies에 추가)
3. `npm test`가 실패하면 배포가 멈춥니다. 테스트가 없다면 기본 `"test": "echo Error ... && exit 1"`을 지우세요.
4. `package-lock.json`이 커밋되어 있어야 합니다(`npm ci`에 필요).
5. 리전은 서울(`ap-northeast-2`), EC2 OS는 Amazon Linux 2023으로 가정합니다.

## 1단계: 파일을 CodeCommit 저장소에 추가

이 브랜치의 다음 파일을 CodeCommit 프로젝트 **최상위 폴더**에 복사한 뒤 커밋하고 push합니다.

```
buildspec.yml
appspec.yml
scripts/env.sh
scripts/stop_server.sh
scripts/install_dependencies.sh
scripts/start_server.sh
scripts/validate_service.sh
```

스크립트에 실행 권한이 있어야 합니다.

```bash
chmod +x scripts/*.sh
git add buildspec.yml appspec.yml scripts/
git update-index --chmod=+x scripts/*.sh   # Windows에서 작업할 때 필요
git commit -m "Add CodePipeline CI/CD config"
git push
```

## 2단계: IAM 역할 2개 만들기

| 역할 이름(예시) | 신뢰 대상 | 연결할 정책 |
|---|---|---|
| `segebank-ec2-role` | EC2 | `AmazonEC2RoleforAWSCodeDeploy`, `AmazonSSMManagedInstanceCore` |
| `segebank-codedeploy-role` | CodeDeploy | `AWSCodeDeployRole` |

CodeBuild와 CodePipeline 역할은 각 서비스에서 생성할 때 "새 서비스 역할 생성"을 선택하면 자동으로 만들어집니다.

## 3단계: EC2 준비

1. EC2 → 인스턴스 → 작업 → 보안 → **IAM 역할 수정**에서 `segebank-ec2-role`을 연결합니다.
2. 인스턴스에 태그를 추가합니다: `Name = segebank` (CodeDeploy가 배포 대상을 찾을 때 사용)
3. 보안 그룹에서 서비스 포트(3000, 또는 Nginx를 쓴다면 80/443)를 엽니다.
4. EC2에 접속해서 아래 명령을 한 번 실행합니다.

```bash
# Node.js 20, PM2, CodeDeploy 에이전트 설치
sudo dnf install -y nodejs20 ruby wget
sudo alternatives --install /usr/bin/node node /usr/bin/node-20 1 || true
sudo alternatives --install /usr/bin/npm npm /usr/bin/npm-20 1 || true
node -v && npm -v

sudo npm install -g pm2
pm2 startup systemd -u ec2-user --hp /home/ec2-user   # 출력되는 sudo 명령을 그대로 실행

cd /tmp
wget https://aws-codedeploy-ap-northeast-2.s3.ap-northeast-2.amazonaws.com/latest/install
chmod +x ./install
sudo ./install auto
sudo systemctl status codedeploy-agent   # active (running) 확인
```

> Node 설치 방식(패키지 이름, alternatives 경로)은 OS 버전에 따라 다를 수 있습니다. `node -v`가 v20으로 나오는지 꼭 확인하세요.

## 4단계: CodeDeploy 만들기

1. CodeDeploy → 애플리케이션 → **애플리케이션 생성**
   - 이름: `segebank`, 컴퓨팅 플랫폼: **EC2/온프레미스**
2. **배포 그룹 생성**
   - 이름: `segebank-prod`
   - 서비스 역할: `segebank-codedeploy-role`
   - 배포 유형: 현재 위치(In-place)
   - 환경 구성: Amazon EC2 인스턴스, 태그 `Name = segebank`
   - 에이전트 설치: **안 함**(3단계에서 설치함)
   - 로드 밸런서: 사용 안 함(서버가 1대인 경우)

## 5단계: CodePipeline 만들기

1. CodePipeline → **파이프라인 생성** → 사용자 지정 파이프라인 빌드
2. 소스: **AWS CodeCommit**, 저장소와 브랜치(`main` 등) 선택, 변경 감지는 EventBridge(권장)
3. 빌드: **AWS CodeBuild** → **프로젝트 생성**
   - 환경 이미지: 관리형 이미지, Amazon Linux, Standard, 최신 이미지
   - 빌드 사양: **buildspec 파일 사용**
4. 배포: **AWS CodeDeploy**, 애플리케이션 `segebank`, 배포 그룹 `segebank-prod`
5. 생성하면 첫 실행이 자동으로 시작됩니다.

## 6단계: 확인

```bash
# EC2에서
pm2 status
curl http://localhost:3000/
```

이후에는 CodeCommit에 push할 때마다 자동으로 빌드되고 배포됩니다.

## 오류가 났을 때 확인할 순서

| 실패 단계 | 확인할 곳 | 자주 있는 원인 |
|---|---|---|
| Source | CodePipeline 화면 | 브랜치 이름 오타 |
| Build | CodeBuild → 빌드 기록 → 로그 | `package-lock.json` 없음, 테스트 실패, Node 버전 미지원 |
| Deploy (시작 전 실패) | CodeDeploy → 배포 → 이벤트 | 에이전트 미설치/중지, EC2 IAM 역할 없음, 태그 불일치 |
| Deploy (스크립트 실패) | EC2 `/var/log/aws/codedeploy-agent/codedeploy-agent.log` | 스크립트 실행 권한 없음, `node`/`pm2`를 찾지 못함 |
| ValidateService | EC2에서 `pm2 logs segebank` | `start` 스크립트 오류, 포트 불일치 |

## 운영·보안 주의사항

1. DB 비밀번호 같은 비밀 정보는 코드에 넣지 말고 **SSM Parameter Store**나 **Secrets Manager**에 저장하세요.
2. 운영 환경에서는 3000번 포트를 직접 열기보다 **Nginx(80/443) → 3000** 구조와 HTTPS를 권장합니다.
3. 서버가 2대 이상이 되면 배포 그룹에 로드 밸런서를 연결해 무중단 배포를 구성하세요.
4. CodeDeploy 결과물이 S3에 계속 쌓이므로, S3 수명 주기 규칙으로 오래된 파일을 정리하세요.
