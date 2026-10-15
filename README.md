# Mini PACS on AWS — Orthanc + OHIF

EC2 한 대에 **Orthanc**(DICOM 서버, DICOMweb)와 **OHIF Viewer v3**를 Docker Compose로 올리는 미니 프로젝트입니다.
인프라는 Terraform으로 만듭니다.

```
 브라우저 ──HTTP:80──▶ [EC2 · Amazon Linux 2023]
 (내 IP만 허용)          nginx (basic auth)
                          ├─ /          ─▶ ohif     (OHIF Viewer 정적 앱)
                          └─ /orthanc/  ─▶ orthanc  (REST, DICOMweb, Orthanc Explorer 2)
                                                └─ docker volume → EBS gp3 (암호화)
 관리자 접속: SSM Session Manager (SSH 키/22번 포트 없음)
 basic auth 비밀번호: SSM Parameter Store (SecureString)
```

![OHIF viewer](docs/ohif-viewer.png)

OHIF와 Orthanc가 같은 origin(`/`, `/orthanc/`) 아래에 있으므로 CORS 설정이 필요 없습니다.

## 구성 파일

| 경로 | 내용 |
|---|---|
| `docker/docker-compose.yml` | orthanc, ohif, nginx 3개 서비스 |
| `docker/nginx/default.conf` | 리버스 프록시 + basic auth, `/healthz` |
| `docker/ohif/app-config.js` | OHIF 데이터소스 → `/orthanc/dicom-web` |
| `docker/ohif/nginx.conf.template` | OHIF 이미지 내장 nginx 설정 교체 (IPv6 없는 호스트에서 크래시 방지) |
| `terraform/` | 보안그룹, IAM(SSM), Parameter Store, EC2, EIP |
| `scripts/make_sample_dicom.py` | 테스트용 합성 CT(구 팬텀) 생성 — 실제 환자 데이터 불필요 |
| `scripts/upload.sh` | 폴더의 `.dcm`을 Orthanc에 업로드 |

## 1. 로컬에서 먼저 실행 (선택)

```bash
cd docker
printf 'admin:%s\n' "$(printf 'testpass12345' | openssl passwd -apr1 -stdin)" > nginx/.htpasswd
HTTP_PORT=8080 docker compose up -d

pip install pydicom numpy
python3 ../scripts/make_sample_dicom.py /tmp/sample
PACS_URL=http://localhost:8080 PACS_PASSWORD=testpass12345 ../scripts/upload.sh /tmp/sample
```

http://localhost:8080 (OHIF), http://localhost:8080/orthanc/ui/app/ (Orthanc Explorer 2)

## 2. AWS에 배포

사전 준비: AWS CLI 자격증명(`aws sts get-caller-identity` 성공), Terraform ≥ 1.5

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
# allowed_cidrs 에 내 IP 입력:  curl -s https://checkip.amazonaws.com
# basic_auth_password 를 12자 이상으로 변경
terraform init
terraform apply
```

출력되는 `ohif_url`로 접속합니다. 부트스트랩(Docker 설치 + 이미지 pull)에 **3~5분** 정도 걸립니다.
진행 상황은:

```bash
$(terraform output -raw ssm_session_command)     # SSM으로 접속 (Session Manager 플러그인 필요)
sudo tail -f /var/log/pacs-bootstrap.log
sudo docker compose -f /opt/pacs/docker-compose.yml ps
```

샘플 데이터 업로드:

```bash
PACS_URL=http://$(terraform output -raw public_ip) PACS_PASSWORD='<비밀번호>' ../scripts/upload.sh /tmp/sample
```

OHIF 화면 상단의 **Upload** 버튼으로 브라우저에서 바로 올릴 수도 있습니다.

## 3. 정리 (비용 발생 중지)

```bash
terraform destroy
```

대략적인 비용(서울 리전, 온디맨드): t3.small ≈ $0.026/h, gp3 30GB ≈ $2.9/월, 실행 중인 인스턴스에 붙은 EIP/퍼블릭 IPv4 ≈ $0.005/h.
→ 하루 종일 켜두면 약 $0.8. 실습이 끝나면 꼭 destroy 하세요.

## 보안 주의

- 이 구성은 **실습용**입니다. **실제 환자 데이터(PHI)를 올리지 마세요.**
- HTTP + basic auth이므로 보안그룹으로 접근 IP를 반드시 제한하세요 (`allowed_cidrs`).
- Orthanc 자체 인증은 꺼져 있고, nginx 뒤 내부 네트워크에서만 접근 가능합니다.
  DICOM 포트(4242)는 `dicom_allowed_cidrs`를 지정할 때만 열립니다.

## 다음 단계 아이디어

- **HTTPS**: 도메인 + ALB(ACM 인증서) 또는 CloudFront 앞단 추가, 혹은 nginx 대신 Caddy로 자동 인증서
- **스토리지**: Orthanc S3 플러그인(`orthancteam/orthanc` 이미지에 포함)으로 DICOM 파일을 S3에 저장
- **DB**: 인덱스를 RDS PostgreSQL로 분리 (`ORTHANC__POSTGRESQL__*`)
- **인증**: Keycloak + Orthanc authorization 플러그인으로 사용자/권한 관리
- **백업**: EBS 스냅샷을 AWS Backup으로 스케줄링
