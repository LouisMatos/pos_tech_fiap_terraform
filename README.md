# pos_tech_fiap_terraform

Infra do cluster EKS (VPC, control plane, node group) + bancos gerenciados (RDS, DocumentDB, Amazon MQ) usados pelos microsserviços pedido/pagamento/producao.

## Ambientes

3 ambientes (dev/hom/prod), 1 conta AWS só, diferenciados por nome/tag/tfvars em `envs/`.

## Uso contra AWS real

```bash
terraform init -backend-config=envs/hom-backend.hcl   # ou prod-backend.hcl
terraform workspace select -or-create hom               # ou prod
terraform plan  -var-file=envs/hom.tfvars
terraform apply -var-file=envs/hom.tfvars
```

Para `dev` sem backend remoto (state local, grátis):
```bash
terraform init
terraform apply -var-file=envs/dev.tfvars
```

O bucket S3 + tabela DynamoDB de lock usados pelo backend remoto são criados uma única vez, manualmente, por `bootstrap/` (ver `bootstrap/main.tf`).

## Dev na conta de testes

Runbook do ambiente dev (conta `896328389222`, us-east-1). Decisões em `.prd-implementacoes/2026-11-22-infra-dev-enxuta/` do workspace.

```bash
export AWS_DEFAULT_REGION=us-east-1
export AWS_BUDGET_EMAIL=<seu-email>              # opcional: sem ele o budget de US$50/mês não é criado
./scripts/deploy-dev-fresh-account.sh --yes      # infra: VPC, EKS, RDS, DynamoDB, Lambda, API Gateway, LBC
./scripts/deploy-services-dev.sh                 # build arm64, secrets, RabbitMQ, 3 serviços, smoke
echo destroy | ./scripts/destroy-dev-fresh-account.sh   # apaga tudo, inclusive dados das RDS e do Mongo
```

- Pré-requisitos: `terraform`, `aws`, `kubectl`, `helm`, `docker buildx` (Docker Desktop aberto), `jq`, `gh` autenticado. GNU sed/grep não são mais necessários.
- `envs/dev.tfvars` é ignorado pelo git (`*.tfvars`): nodes `t4g.small` (arm64), `enable_mq=false`, `enable_documentdb=false`, nodes numa AZ só. RabbitMQ e MongoDB rodam no cluster.
- Os dois scripts de deploy podem ser rodados de novo: retomam do state local.
- Custo estimado: ~US$5,1/dia (~US$152,56/mês, on-demand us-east-1, não medido); o control plane do EKS é US$2,43/dia fixo. Rode o destroy ao terminar os testes.
- Memória: 2× `t4g.small` ficam em ~90% com os 3 serviços (requests de 256Mi). Precisando de mais, `desired = 3` no `auto_scale_options` (~+US$12,26/mês).

## Uso local contra LocalStack

**Importante**: LocalStack não emula EKS, RDS, DocumentDB nem Amazon MQ. Só `module.network` (VPC/subnets/IGW/NAT) é testável aqui — o resto exige AWS real.

```bash
docker compose -f docker-compose.localstack.yml up -d
terraform init
terraform apply -target=module.network -var-file=envs/dev-local.tfvars -var="localstack_enabled=true" -auto-approve
# ... validar via aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs ...
terraform destroy -target=module.network -var-file=envs/dev-local.tfvars -var="localstack_enabled=true" -auto-approve
docker compose -f docker-compose.localstack.yml down
```

Teste funcional real dos serviços (Spring Boot + RabbitMQ/DB) continua via os `docker-compose.yml` de cada repo de serviço — LocalStack aqui só valida a sintaxe/semântica do Terraform a custo zero.
