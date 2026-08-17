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
