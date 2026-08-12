# Artefato de entrevista — "Módulo de onboarding de data ingestion pipeline" (AssureSoft)

> Objetivo: transformar o gap *"nunca fiz data ingestion"* numa **proposta concreta**.
> A tese: o onboarding de um pipeline de cliente é, do lado DevOps, um problema de
> **identidade least-privilege + isolamento + deploy declarativo repetível** — e isso
> é exatamente o que a plataforma EKS deste repo já resolve. O que falta é
> **parametrizar por cliente** e **entregar via GitOps (Argo CD)**.

---

## 1. O problema, em uma frase

Cada cliente novo tem uma fonte de dados própria (um bucket S3 cross-account, uma
API, um tópico Kafka). Onboarding técnico = **ligar essa fonte à plataforma de forma
segura, isolada e repetível** — sem configurar IAM, rede e deploy na mão a cada cliente.

## 2. Princípios de design (os mesmos do repo)

1. **Identidade sem chave estática** — cada pipeline de cliente assume uma IAM role
   por **IRSA**, com acesso só à fonte daquele cliente. (mesmo padrão do
   `aws-load-balancer-controller`).
2. **Isolamento por tenant** — um **namespace por cliente**, secrets isolados, network
   policy. Blast radius de um cliente nunca alcança outro.
3. **Repetível como código** — onboarding = aplicar um **módulo Terraform** + um
   **Application do Argo CD** parametrizados por `customer_id`. Não há passo manual.
4. **Least-privilege na fonte** — a policy concede `s3:GetObject` só no
   `arn:...:<bucket-do-cliente>/*`, não em `*`.

## 3. Forma do módulo Terraform (espelha o IRSA que já existe no repo)

`workload/modules/customer-ingestion/` — uma instância por cliente:

```hcl
# variables.tf
variable "customer_id"     { type = string }              # ex: "acme"
variable "source_bucket_arn" { type = string }            # bucket S3 do cliente (pode ser cross-account)
variable "oidc"            { type = string }              # OIDC provider do cluster (igual ao ALB module)
variable "project_name"    { type = string }
variable "tags"            { type = map(any) }

# iam.tf  — MESMA estrutura do aws_controller_role, mas escopada ao cliente
resource "aws_iam_role" "ingestion" {
  name = "${var.project_name}-ingestion-${var.customer_id}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/oidc.eks.${data.aws_region.current.region}.amazonaws.com/id/${var.oidc}" }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          # trava a role ao SA do NAMESPACE do cliente — isolamento por tenant
          "oidc.eks.${data.aws_region.current.region}.amazonaws.com/id/${var.oidc}:sub" = "system:serviceaccount:cust-${var.customer_id}:ingestion"
          "oidc.eks.${data.aws_region.current.region}.amazonaws.com/id/${var.oidc}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = merge(var.tags, { Name = "ingestion-${var.customer_id}" })
}

# policy.tf — acesso SÓ à fonte daquele cliente (least-privilege real)
resource "aws_iam_role_policy" "read_source" {
  role = aws_iam_role.ingestion.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [var.source_bucket_arn, "${var.source_bucket_arn}/*"]
    }]
  })
}

# namespace.tf — isolamento de tenant + SA anotado com a role (padrão do repo)
resource "kubernetes_namespace" "tenant" {
  metadata { name = "cust-${var.customer_id}" }
}
resource "kubernetes_service_account" "ingestion" {
  metadata {
    name      = "ingestion"
    namespace = kubernetes_namespace.tenant.metadata[0].name
    annotations = { "eks.amazonaws.com/role-arn" = aws_iam_role.ingestion.arn }
  }
}
```

Onboarding de um cliente novo = **3 linhas** num `customers.tf` (ou um `for_each`
sobre um mapa de clientes):

```hcl
module "acme" {
  source            = "./modules/customer-ingestion"
  customer_id       = "acme"
  source_bucket_arn = "arn:aws:s3:::acme-exports"
  oidc              = data.terraform_remote_state.foundation.outputs.oidc
  project_name      = var.project_name
  tags              = var.tags
}
```

## 4. O lado Argo CD (o que conecta ao stack da vaga)

O Terraform cria a **identidade e o isolamento**; o **Argo CD** entrega o **pipeline
em si** de forma declarativa. Padrão **app-of-apps** parametrizado por cliente:

```yaml
# um Application por cliente — gerado por ApplicationSet a partir do mapa de clientes
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata: { name: customer-ingestion }
spec:
  generators:
    - list:
        elements:
          - customer: acme
          - customer: globex
  template:
    metadata: { name: "ingestion-{{customer}}" }
    spec:
      source:
        repoURL: <git-do-pipeline>
        path: charts/ingestion
        helm:
          parameters:
            - { name: customerId,    value: "{{customer}}" }
            - { name: serviceAccount, value: ingestion }   # SA com a role IRSA
      destination: { namespace: "cust-{{customer}}" }
      syncPolicy: { automated: { selfHeal: true, prune: true } }
```

**Resultado:** adicionar um cliente = adicionar uma linha no `ApplicationSet` + uma no
mapa do Terraform. Argo reconcilia, faz `selfHeal` em drift, e dá rollback por
`git revert`. Onboarding **auditável e repetível**, não um ticket manual.

## 5. Fronteira de responsabilidade (deixe explícito na entrevista)

| Camada | Quem faz | O que o DevOps entrega |
|---|---|---|
| Lógica do pipeline (parse, transform, schema) | Data Eng | — |
| **Identidade least-privilege à fonte** | **DevOps** | IRSA role escopada ao bucket do cliente |
| **Isolamento de tenant** | **DevOps** | namespace + network policy + secrets isolados |
| **Conexão segura a fonte externa** | **DevOps** | VPC endpoint / cross-account role / PrivateLink |
| **Deploy repetível** | **DevOps** | módulo Terraform + ApplicationSet do Argo |
| **Secrets do cliente** (API keys) | **DevOps** | External Secrets + Secrets Manager / KMS |

## 6. Roteiro de fala (30–40s)

> "Eu nunca operei um pipeline de ingestion específico, mas a parte que é DevOps eu
> já construí: no meu projeto, **IRSA** dá identidade least-privilege por workload sem
> chave estática. Pra onboarding de cliente, eu escaparia uma IAM role por cliente —
> acesso só ao bucket dele — amarrada por OIDC ao **service account de um namespace
> dedicado**, então um cliente nunca alcança os dados de outro. Empacotaria isso num
> **módulo Terraform parametrizado por `customer_id`** e entregaria o pipeline via um
> **ApplicationSet do Argo CD**: adicionar um cliente vira uma linha no mapa, com sync
> automático, self-heal e rollback por git. Onboarding deixa de ser ticket manual e
> vira deploy declarativo e auditável."

## 7. Se aprofundarem — respostas de bolso

- **Fonte cross-account?** A trust policy do cliente confia na minha ingestion role;
  combino IRSA (pod→role A) com `sts:AssumeRole` (role A→role do cliente). Dois saltos,
  cada um least-privilege.
- **Segredos do cliente (API key em vez de bucket)?** External Secrets Operator
  sincroniza de Secrets Manager pro namespace do cliente; nada em texto no git.
- **Isolamento de verdade?** NetworkPolicy default-deny no namespace + ResourceQuota
  pra um cliente não consumir o cluster inteiro (noisy neighbor).
- **Escala (centenas de clientes)?** O `for_each`/ApplicationSet já é O(linha por
  cliente); o gargalo vira IAM role quota e densidade de namespace → eventualmente
  conta/cluster por tier de cliente.
</content>
</invoke>
