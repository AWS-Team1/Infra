# 테스트 DB bootstrap AWS root

`boa-test-eks`의 DB bootstrap Job에 필요한 테스트 전용 Secret 컨테이너, IAM Role과
EKS Pod Identity Association을 관리한다. Secret 값은 Terraform이 관리하지 않는다.

적용 순서는 `aws-test-core → aws-test-rds/aws-test-eks → aws-test-db-bootstrap`이다.
적용 후 `../scripts/prepare-test-secrets.sh`를 실행하면 기존 `/boa` DB/JWT 값과 새 테스트
RDS master 값을 `/boa-test` Secret에 출력 없이 복사한다.

전체 절차는 [../TEST_ENVIRONMENT.md](../TEST_ENVIRONMENT.md)를 따른다.
