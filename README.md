# ai-accelerator-tenants

External tenant workloads for [ai-accelerator](https://github.com/GeraldSP/ai-accelerator) cluster overlays.

## Tenants

| Tenant | Path | Purpose |
|--------|------|---------|
| `lab-infra` | `lab-infra/namespaces/overlays/summit-connect-chile` | AVX512 CPU MachineSet (`m6i.4xlarge`) + GPU MachineSet (`g5.2xlarge` A10G for RHAIIS) + storage expectations |
| `helpdesk-email-triage-demo` | `helpdesk-email-triage-demo/namespaces/overlays/summit-connect-chile` | Helpdesk email triage with RHAII 3.5 CPU (vendored from [rh-ai-quickstart/helpdesk-email-triage](https://github.com/rh-ai-quickstart/helpdesk-email-triage)) |
| `aiops-sandboxed-agent-fleet` | `aiops-sandboxed-agent-fleet/namespaces/overlays/summit-connect-chile` | AIOps OpenShell/OpenClaw fleet + in-cluster OpenShift AI LLM (`aiops-llm` on GPU) |

Pointer Applications in the core repo (`tenants/<id>/remote/`) sync these paths via Argo CD.

## Vendor note

`helpdesk-email-triage-demo/vendor/` contains a copy of the upstream `deploy/openshift` tree plus `sample_emails` (relocated under the `rhaii-demo` overlay so Kustomize loadRestrictor succeeds in Argo CD). Refresh by re-copying from upstream when needed.

`aiops-sandboxed-agent-fleet` does **not** vendor Helm charts (OCI + Grafana deps). The deploy Job clones upstream at a pinned commit and runs `scripts/deploy.sh`. Bump `UPSTREAM_REF` in `namespaces/base/deploy/job.yaml` when refreshing.

## Hugging Face secret (helpdesk) — gitignored

Token lives in `helpdesk-email-triage-demo/namespaces/base/secrets/hf-token.env`
(listed in `.gitignore`; never commit). Argo CD does not sync this secret.

```bash
cp helpdesk-email-triage-demo/namespaces/base/secrets/hf-token.env.example \
   helpdesk-email-triage-demo/namespaces/base/secrets/hf-token.env
# edit HF_TOKEN=...
chmod +x helpdesk-email-triage-demo/scripts/apply-hf-secret.sh
./helpdesk-email-triage-demo/scripts/apply-hf-secret.sh
```

## Inference (AIOps fleet) — in-cluster by default

Argo syncs `nemoclaw-inference` pointing at the OpenShift AI InferenceService:

`http://aiops-llm-predictor.aiops-inference.svc.cluster.local:8000/v1`

- GPU: lab-infra `g5.2xlarge` (A10G), taint `nvidia.com/gpu`
- Model: Llama 3.1 8B Instruct FP8 modelcar (`aiops-llm`), auth disabled
- No NVIDIA `nvapi` key required for the default path

Optional remote override (gitignored `inference.env`):

```bash
cp aiops-sandboxed-agent-fleet/namespaces/base/secrets/inference.env.example \
   aiops-sandboxed-agent-fleet/namespaces/base/secrets/inference.env
# edit for NIM / OpenAI / etc.
./aiops-sandboxed-agent-fleet/scripts/apply-inference-secret.sh
```
