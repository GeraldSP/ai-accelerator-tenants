# ai-accelerator-tenants

External tenant workloads for [ai-accelerator](https://github.com/GeraldSP/ai-accelerator) cluster overlays.

## Tenants

| Tenant | Path | Purpose |
|--------|------|---------|
| `lab-infra` | `lab-infra/namespaces/overlays/summit-connect-chile` | AVX512 CPU MachineSet (`m6i.4xlarge`) + storage expectations for RHAII |
| `helpdesk-email-triage-demo` | `helpdesk-email-triage-demo/namespaces/overlays/summit-connect-chile` | Helpdesk email triage with RHAII 3.5 CPU (vendored from [rh-ai-quickstart/helpdesk-email-triage](https://github.com/rh-ai-quickstart/helpdesk-email-triage)) |

Pointer Applications in the core repo (`tenants/<id>/remote/`) sync these paths via Argo CD.

## Vendor note

`helpdesk-email-triage-demo/vendor/` contains a copy of the upstream `deploy/openshift` tree plus `sample_emails` (relocated under the `rhaii-demo` overlay so Kustomize loadRestrictor succeeds in Argo CD). Refresh by re-copying from upstream when needed.

## One-time secret (helpdesk)

```bash
oc -n helpdesk-email-triage create secret generic hf-secret \
  --from-literal=HF_TOKEN='<your-huggingface-token>' \
  --dry-run=client -o yaml | oc apply -f -
```
