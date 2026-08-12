# Artefato de entrevista — Estrutura do repo de config GitOps (app-of-apps)

> Contexto: o Argo CD já foi instalado pelo bootstrap (provider Helm no Terraform,
> camada `workload`). A partir daqui, **tudo** entra no cluster por GitOps: o Argo
> puxa deste repo. A pipeline (CI) commita aqui; ela não toca mais o cluster.
> Ver [[assuresoft-customer-onboarding-pipeline-pt]] para o módulo de onboarding.

---

## 1. Princípio: uma raiz, muitas folhas (app-of-apps)

O Terraform aplica **uma única** Application no bootstrap — a *root app*. Ela aponta
pra uma pasta de Applications, e cada uma instala um componente. Adicionar um tool
novo = adicionar um arquivo nessa pasta e commitar. O Argo reconcilia o resto.

```
Terraform (bootstrap) ──aplica──▶ root-app ──aponta──▶ apps/*.yaml ──cada uma──▶ um componente
        (uma vez)                  (app-of-apps)         (Applications)         (chart + values)
```

## 2. Layout do repositório

Repo **separado** do código de infra (fonte da verdade do GitOps):

```
gitops-config/
├── bootstrap/
│   └── root-app.yaml                 # a ÚNICA Application aplicada pelo Terraform
│
├── projects/
│   └── platform.yaml                 # AppProject: limita repos/destinos/RBAC do Argo
│
├── apps/                             # app-of-apps: 1 Application por componente
│   ├── cert-manager.yaml
│   ├── external-secrets.yaml
│   ├── aws-load-balancer-controller.yaml
│   ├── kube-prometheus-stack-crds.yaml   # CRDs isolados (wave anterior)
│   ├── kube-prometheus-stack.yaml        # o operator (wave posterior)
│   └── customer-ingestion.yaml           # ApplicationSet multi-tenant (onboarding)
│
└── components/                       # o "o quê": chart refs, values, manifests de CRD
    ├── cert-manager/values.yaml
    ├── external-secrets/values.yaml
    ├── kube-prometheus-stack/values.yaml
    └── monitoring/                   # CRs (Prometheus, Grafana dashboards, alert rules)
        └── ...
```

**Por que separar `apps/` (o "onde/ordem") de `components/` (o "o quê"):** as
Applications carregam só a metadata do Argo (projeto, destino, sync wave, sync
options). Os valores de chart e manifests ficam em `components/`. Trocar a versão de
um chart é uma mudança em um arquivo, sem mexer na orquestração.

## 3. A root app (o único ponto de entrada do bootstrap)

```yaml
# bootstrap/root-app.yaml  — aplicada pelo Terraform após o helm_release do Argo
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
spec:
  project: platform
  source:
    repoURL: https://github.com/<org>/gitops-config.git
    targetRevision: main
    path: apps                       # ← aponta pra pasta inteira de Applications
    directory: { recurse: true }
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  syncPolicy:
    automated: { selfHeal: true, prune: true }
```

Daqui pra frente, **qualquer** componente novo é um arquivo em `apps/` — o Argo
detecta e sincroniza sozinho. Nunca mais se aplica nada à mão.

## 4. O AppProject (guard-rail de segurança)

```yaml
# projects/platform.yaml — limita o que o GitOps pode fazer (least-privilege do Argo)
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata: { name: platform, namespace: argocd }
spec:
  sourceRepos: ["https://github.com/<org>/gitops-config.git",
                "https://charts.jetstack.io",
                "https://prometheus-community.github.io/helm-charts"]   # allowlist de fontes
  destinations:
    - { server: https://kubernetes.default.svc, namespace: "*" }
  clusterResourceWhitelist:
    - { group: "apiextensions.k8s.io", kind: CustomResourceDefinition } # permite CRD explicitamente
```

## 5. O ponto central: ORDENAÇÃO de CRDs com sync waves

CRD tem que existir **antes** do operator que o usa, senão o operator quebra no boot.
Argo resolve isso com `argocd.argoproj.io/sync-wave` (menor = primeiro):

| Wave | O que entra | Por quê |
|---|---|---|
| `-2` | AppProject, namespaces | fundação; tudo depende deles |
| `-1` | **CRDs** (cert-manager, prometheus-operator, ESO) | precisam existir antes dos operators |
| `0` | operators/controllers (consomem os CRDs) | só sobem com os CRDs presentes |
| `1` | **CRs** (Certificate, Prometheus, ExternalSecret) | só válidos depois do operator rodar |

### Exemplo — kube-prometheus-stack (o caso clássico de dor com CRD)

CRDs do Prometheus Operator são **enormes** e estouram o limite de 262 KB do apply
client-side. Por isso: **isolar os CRDs numa Application própria** + `ServerSideApply`.

```yaml
# apps/kube-prometheus-stack-crds.yaml  — CRDs sozinhos, wave anterior
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack-crds
  namespace: argocd
  annotations: { argocd.argoproj.io/sync-wave: "-1" }
spec:
  project: platform
  source:
    repoURL: https://github.com/prometheus-community/helm-charts.git
    targetRevision: kube-prometheus-stack-XX.Y.Z
    path: charts/kube-prometheus-stack/charts/crds/crds
  destination: { server: https://kubernetes.default.svc, namespace: monitoring }
  syncPolicy:
    automated: { selfHeal: true, prune: false }   # prune:false → nunca apaga CRD por acidente
    syncOptions:
      - ServerSideApply=true                       # CRD grande não cabe no apply client-side
      - SkipDryRunOnMissingResource=true
```

```yaml
# apps/kube-prometheus-stack.yaml  — o operator, wave 0, com CRDs do chart desligados
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
  namespace: argocd
  annotations: { argocd.argoproj.io/sync-wave: "0" }
spec:
  project: platform
  source:
    repoURL: https://prometheus-community.github.io/helm-charts
    chart: kube-prometheus-stack
    targetRevision: XX.Y.Z
    helm:
      valueFiles: [$values/components/kube-prometheus-stack/values.yaml]
      parameters:
        - { name: crds.enabled, value: "false" }   # CRD é dono da Application acima, não do chart
  # ... destination + syncPolicy
```

> A regra de ouro: **um único dono por CRD.** Ou o chart instala o CRD, ou a
> Application de CRD instala — nunca os dois (um sobrescreve o outro a cada sync).

### cert-manager / external-secrets (caso mais simples)

Esses publicam os CRDs via `installCRDs: true`/`crds.enabled` no próprio chart. Aí
basta **um** Application com sync wave `-1` (ou deixar o chart instalar os CRDs e
pôr os CRs que você cria em wave `1`). Não precisa isolar — só os CRDs gigantes
(prometheus-operator, Gatekeeper, Crossplane) justificam Application separada.

## 6. Migrar o ALB controller (que hoje é Terraform) pra cá

Seu `aws-load-balancer-controller` vive na camada `workload` (Helm + IRSA). No
modelo GitOps ele vira uma Application — **mas a IAM role/IRSA fica no Terraform**
(é recurso AWS, não do cluster). Fronteira:

- **Terraform:** cria a IAM role IRSA + output do role ARN. (continua dono disso)
- **Argo Application:** instala o chart, recebendo o role ARN via Helm parameter.

```yaml
# apps/aws-load-balancer-controller.yaml
helm:
  parameters:
    - { name: serviceAccount.annotations.eks\.amazonaws\.com/role-arn, value: <arn-do-terraform> }
    - { name: clusterName, value: <cluster> }
```

> Isso responde "Terraform ou Argo?": **identidade/infra AWS no Terraform; o que roda
> dentro do cluster no Argo.** A costura é o role ARN passado como parâmetro.

## 7. Onboarding multi-tenant entra aqui como ApplicationSet

A Application `apps/customer-ingestion.yaml` é o `ApplicationSet` do doc de
onboarding ([[assuresoft-customer-onboarding-pipeline-pt]]): adicionar cliente =
uma linha no gerador, o Argo cria a Application daquele cliente sozinho.

## 8. Roteiro de fala (30s)

> "Repo de config separado do código de infra. O Terraform aplica **uma** root app no
> bootstrap; ela é app-of-apps e aponta pra uma pasta de Applications, uma por
> componente. CRD eu ordeno com **sync waves** — CRDs em wave -1, operators em 0, CRs
> em 1 — e os CRDs grandes, tipo prometheus-operator, vão numa Application isolada com
> **ServerSideApply** porque estouram o apply client-side. Regra fixa: um dono por
> CRD. Adicionar um tool ou um cliente vira um commit; o Argo reconcilia, com selfHeal
> e rollback por git revert."
</content>
