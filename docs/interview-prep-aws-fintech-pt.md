# Prep de entrevista — Senior DevOps (AWS / EKS / Fintech-Crypto)

> Empresa: fintech/crypto global, em alta. Vaga: Senior DevOps Engineer. Foco: **AWS, EKS, Terraform, CI/CD, segurança, compliance, reliability**. Atua com eng/security/legal, lidera iniciativas, melhora observability e incident response, **mentora juniors**. Contractor, remoto, até 70k/ano.
>
> **A vaga otimiza para SEGURANÇA + COMPLIANCE + CONFIABILIDADE.** Lidere por aí.

---

## 1. Pitch de abertura (~60–90s)
"Sou DevOps sênior com foco em AWS e Kubernetes, **CKA**, atuando também em multi-cloud (AWS + GCP). Meu projeto âncora é uma plataforma EKS 100% em Terraform: cluster privado com **secrets cifrados via KMS**, **IRSA** para identidade sem chave, rede multi-AZ com VPC endpoints, entregue por 5 pipelines no GitHub Actions com **auth keyless via OIDC**. Estruturei em 2 camadas (rede/workload) com ambientes hml/prod isolados. Opero workloads com Helm e Kustomize. Pra uma empresa crypto, meu foco natural é onde segurança, least-privilege e auditabilidade encontram a operação."

---

## 2. Seu stack AWS — saiba explicar cada item de cabeça

| Área | O que você tem | 1 frase pra defender |
|---|---|---|
| **EKS cluster** | endpoint privado, control-plane logging, OIDC provider | "Superfície mínima; logs de auditoria do control plane ligados" |
| **Secrets** | **envelope encryption via KMS** (`encryption_config` resources=secrets) | "Secrets do etcd cifrados com chave KMS gerenciada" |
| **Identidade** | **IRSA** (IAM Roles for Service Accounts via OIDC) | "Pods assumem IAM role por SA — zero credencial estática no pod" |
| **Rede** | VPC, subnets privadas multi-AZ (1a/1b), **VPC endpoints**, bastion | "Nós privados; tráfego pra AWS via endpoints, sem sair pra internet" |
| **Compute** | managed node groups, EKS addons (vpc-cni, coredns, kube-proxy, etc.) | "Node groups gerenciados; addons como código" |
| **Workload** | AWS Load Balancer Controller (Helm + IRSA) | "Ingress AWS-native via ALB controller com role dedicada" |
| **State** | backend **S3** (bootstrap) | "Remote state versionado, isolado por ambiente" |
| **Estrutura** | 2 camadas (foundation/workload) + hml/prod | "Blast radius por camada; ambientes isolados" |
| **CI/CD** | 5 pipelines, **OIDC keyless**, gate **Trivy**, **terraform test** | "Apply gated, sem chave estática, scan de IaC fail-closed" |

---

## 3. Histórias STAR (decore Ação + número/detalhe)

**1. IRSA — identidade sem chave**
- S/T: pods precisavam de acesso a serviços AWS (S3, ELB) sem credencial embutida.
- A: configurei OIDC provider do EKS + IAM roles assumidas por service account (IRSA).
- R: zero chave estática em pod; least-privilege por workload.

**2. Envelope encryption de secrets com KMS** *(ouro pra crypto)*
- S/T: secrets do Kubernetes ficam em texto no etcd por padrão.
- A: ativei `encryption_config` (resources=["secrets"]) com chave KMS dedicada.
- R: secrets cifrados em repouso com chave gerenciada/auditável.

**3. CI/CD keyless via OIDC**
- S/T: evitar access keys da AWS em secret do GitHub.
- A: GitHub Actions assume IAM role via OIDC federation; role por ambiente.
- R: nenhuma credencial de longa duração; rotação automática (tokens curtos).

**4. Endpoint EKS privado + exceção controlada pro CI** *(trade-off de sênior)*
- S/T: control plane privado, mas o runner do GitHub é externo à VPC.
- A: mantive `endpoint_private_access`; expus o público restrito por `public_access_cidrs`, documentado no `.trivyignore` com justificativa.
- R: operável pelo CI sem abrir mão da postura — e a exceção é rastreável.

**5. Topologia de state: 2 camadas + S3 + multi-AZ**
- S/T: um state único = blast radius da plataforma inteira.
- A: separei foundation/workload, state em S3 por ambiente, subnets multi-AZ.
- R: deploy incremental, isolamento de falha, HA de rede.

**6. Shift-left security (Trivy + terraform test)**
- S/T: pegar misconfig antes do apply.
- A: gate Trivy fail-closed (HIGH/CRITICAL) + testes nativos com mock provider no PR.
- R: vulnerabilidade barrada no PR, não em produção.

---

## 4. Ângulo FINTECH/CRYPTO (o coração da vaga)

Lidere com a tríade: **cripto + least-privilege + auditabilidade**.

- **Em repouso:** KMS (secrets do EKS), EBS/S3 com KMS.
- **Em trânsito:** TLS no LB; mTLS via service mesh como evolução.
- **Identidade:** IRSA (pods), OIDC (CI) — princípio do menor privilégio em tudo.
- **Superfície:** endpoint privado, VPC endpoints, nós privados, security groups restritos.
- **Auditoria:** control-plane logging; CloudTrail; (evolução: GuardDuty, AWS Config, Security Hub).

**Ponte pra compliance (frase pronta):**
> "Os controles que implementei — encryption com KMS, audit trail, least-privilege via IRSA, segregação de ambientes, IaC revisável — mapeiam diretamente pros controles de **SOC 2** e **PCI-DSS**. Eu trabalharia com security e legal pra traduzir cada requisito de compliance em um control técnico versionado e auditável, e usaria **AWS Config/Security Hub** pra evidência contínua."

Conceitos crypto-específicos pra ter na ponta: **gestão de chaves (KMS, HSM/CloudHSM)**, **segregação de duties**, **least-privilege rigoroso**, **immutable audit logs**, **secrets rotation**, **supply-chain (assinatura de imagem, SBOM)**.

---

## 5. Os 3 GAPS — tenha 1 resposta pronta pra cada

**A) Observability (o mais importante de preparar)**
> "Instrumentaria com **kube-prometheus-stack** (Prometheus, Grafana, Alertmanager) ou **CloudWatch Container Insights**; métricas **RED** (Rate/Errors/Duration) e **USE** (Utilization/Saturation/Errors); **SLOs com error budget**; alertas no Alertmanager → **PagerDuty/Opsgenie**. Logs centralizados (Loki/CloudWatch/ELK), tracing com OpenTelemetry."
> Prova de mentalidade: "No meu projeto GCP já configurei alert policies (error rate, latência p99, disco do SQL)."

**B) Incident response**
> "Runbooks versionados, on-call com escala, classificação por severidade, **postmortem blameless**, e métricas de **MTTD/MTTR**. Foco em reduzir toil e em detecção antes do cliente perceber."

**C) Mentoria / liderança (é vaga sênior!)**
> "Documento o **porquê** das decisões (READMEs, `terraform-docs`), escrevo **testes como contrato** que ensinam o comportamento esperado, e faço onboarding por pairing. Já escrevi artigos técnicos explicando trade-offs — gosto de elevar o time, não só entregar."

---

## 6. Reliability — pontos pra soltar
- **HA:** multi-AZ (subnets 1a/1b), managed node groups.
- **Escala:** HPA (pods) + Cluster Autoscaler/Karpenter (nodes).
- **Resiliência:** PodDisruptionBudget, requests/limits, liveness/readiness probes, topology spread.
- **DR:** backup de state (S3 versionado), estratégia de restore, evolução pra multi-region.
- **Mudança segura:** deploy gated com plan salvo, rollback via GitOps/Helm.

---

## 7. Perguntas prováveis (com bullets de resposta)

**Técnicas**
- *Secrets num EKS?* → KMS envelope + IRSA + External Secrets/Secrets Manager.
- *CI autentica na AWS sem chave?* → OIDC assume-role, role por ambiente.
- *Terraform multi-ambiente?* → 2 camadas, backend S3, env dirs, remote state.
- *Como dá acesso de pod a S3?* → IRSA (IAM role por SA), não node role.
- *Como protege o control plane?* → endpoint privado + authorized CIDRs + logging.
- *Atualização de versão do EKS sem downtime?* → upgrade control plane → node groups com surge/drain, PDBs, blue/green de node pool.

**Sistema/Design**
- *Desenhe uma plataforma EKS segura e observável pra fintech.* → VPC privada multi-AZ + VPC endpoints; EKS privado + KMS + IRSA; ALB + WAF; kube-prometheus + Alertmanager; ESO p/ secrets; GitOps (ArgoCD); Config/Security Hub p/ compliance.

**Comportamentais (STAR)**
- *Trade-off difícil?* → endpoint privado vs. CI público.
- *Incidente e como agiu?* → (prepare 1, mesmo pequeno, com MTTR e postmortem).
- *Como mentora?* → docs do "porquê" + testes + pairing.
- *Discordou de um time (security/dev)?* → equilíbrio segurança vs. velocidade.

---

## 8. Estudar HOJE À NOITE (refresh rápido, 1–2h)
- [ ] **IRSA**: como o OIDC do EKS + trust policy + `eks.amazonaws.com/role-arn` funcionam (saber explicar o fluxo).
- [ ] **KMS**: envelope encryption, rotação de chave, diferença de chave gerenciada vs. CMK.
- [ ] **kube-prometheus / SLO**: RED/USE, error budget, Alertmanager (você tem CKA — só refrescar).
- [ ] **Incident response**: severidade, runbook, postmortem blameless, MTTD/MTTR.
- [ ] **AWS Well-Architected** (6 pilares) — citar "Security" e "Reliability" com naturalidade.
- [ ] **Compliance**: o que é SOC 2 (tipo II) e PCI-DSS em 1 frase cada.
- [ ] **EKS upgrade & autoscaling** (Karpenter vs Cluster Autoscaler).

---

## 9. Perguntas pra VOCÊ fazer (sinaliza senioridade)
- "Quais frameworks de compliance vocês precisam atender (SOC 2, PCI-DSS, ISO 27001)?"
- "Como está hoje a observability e o processo de on-call/incident response?"
- "Qual o maior desafio atual de reliability/escala da plataforma?"
- "Como o time de infra colabora com security e legal no dia a dia?"
- "Multi-region / DR já é realidade ou roadmap?"
- "Como vocês fazem gestão de chaves e secrets em escala?"

---

## 10. Lembretes finais
1. **Sempre** cite o **trade-off** junto da decisão — é o que define sênior.
2. Lidere pela **segurança/compliance** (é uma crypto) e conecte cada control técnico a um objetivo de negócio (confiança, auditoria, redução de risco).
3. Os gaps (observability, incident, compliance-framework) **não escondem** — mostre que conhece o caminho.
4. Inglês: tenha o pitch e as 6 histórias fluindo em **EN** também (time global).
5. **Você é forte aqui.** O risco é travar nos 3 gaps — por isso tem 1 resposta pronta pra cada.
6. Contractor 70k/ano = bruto, sem benefícios; tenha clareza da sua taxa-alvo ao falar de comp.
