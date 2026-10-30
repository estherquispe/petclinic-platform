# Rollback Runbook — Petclinic Platform

**Last Updated:** 2026-10-29
**Purpose:** Documented rollback procedures for failed deployments. CD is handled by ArgoCD (GitOps); rollback means reverting the desired image tag so ArgoCD syncs the previous known-good version. No kubectl/helm in CI.

## Table of Contents

1. [GitOps Rollback (revert image tag commit)](#procedure-1-gitops-rollback-revert-image-tag-commit)
2. [ArgoCD Rollback (previous sync)](#procedure-2-argocd-rollback-previous-sync)
3. [Emergency Fallback (kubectl rollout undo)](#procedure-3-emergency-fallback-kubectl-rollout-undo)
4. [Verification](#verification)
5. [Related Documents](#related-documents)

---

## Procedure 1: GitOps Rollback (revert image tag commit)

**When:** A deployed image is broken and the fix is to go back to the previously deployed tag. Preferred method — change is versioned in Git, ArgoCD performs the sync.

**Who:** Developer or on-call engineer with write access to `helm-values/` in the platform repo.

**Time:** ~5–10 minutes

**Steps:**

1. Identify the bad commit:
   ```bash
   git -C /home/esther/Documentos/DevOps/spring-petclinic/petclinic-platform log --oneline -- helm-values/
   ```
   Look for `ci: update image tags to {sha} (...)`.

2. Revert the tag-update commit (creates a new commit restoring the previous tag):
   ```bash
   git -C /home/esther/Documentos/DevOps/spring-petclinic/petclinic-platform revert <bad-commit-sha>
   git -C /home/esther/Documentos/DevOps/spring-petclinic/petclinic-platform push origin main
   ```

3. Confirm ArgoCD detected the change:
   ```bash
   argocd app list --prefix petclinic
   ```
   or check the ArgoCD UI — the app should show OutOfSync → syncing to the previous image tag.

**Verify:**
- `git log --oneline -3 -- helm-values/` shows the revert commit at HEAD.
- ArgoCD application reports Healthy/Synced with the previous image tag.
- Service endpoints respond (check via ingress or port-forward to the service).

**Rollback:** Not applicable — this is itself a rollback. To re-apply the bad image, create a new tag-update commit via CI (repository_dispatch) rather than un-reverting.

---

## Procedure 2: ArgoCD Rollback (previous sync)

**When:** ArgoCD already synced a bad tag and you need to roll back to a previous successful sync without touching Git immediately (e.g., revert commit pending).

**Who:** On-call engineer with ArgoCD UI/CLI access.

**Time:** ~2–5 minutes

**Steps:**

1. Open the ArgoCD UI → select the affected `petclinic-*` application.
2. Click **History & Rollback** → choose the previous **Successful** sync revision → **Rollback**.
3. Alternatively via CLI:
   ```bash
   argocd app history petclinic-{env}-{service}
   argocd app rollback petclinic-{env}-{service} {revision}
   ```

**Verify:**
- Application status returns to Healthy/Synced.
- Running pods use the previous image tag:
  ```bash
  kubectl -n petclinic-{env} rollout history deploy/{service}
  kubectl -n petclinic-{env} get deploy/{service} -o jsonpath='{.spec.template.spec.containers[*].image}'
  ```

**Rollback:** Follow-up with Procedure 1 so Git matches the cluster state (otherwise the next CI tag update will re-deploy the bad image).

---

## Procedure 3: Emergency Fallback (kubectl rollout undo)

**When:** ArgoCD is unavailable or the sync is stuck and an immediate pod rollback is required. This is a cluster-side change only — it drifts from Git and must be followed by Procedure 1.

**Who:** Cluster admin with kubectl access to the EKS cluster.

**Time:** ~2–5 minutes

**Steps:**

1. Update kubeconfig for the target environment:
   ```bash
   aws eks update-kubeconfig --region us-east-1 --name petclinic-{env}-eks
   ```

2. Roll back the deployment:
   ```bash
   kubectl -n petclinic-{env} rollout undo deploy/{service}
   kubectl -n petclinic-{env} rollout status deploy/{service} --timeout=300s
   ```

3. To target a specific revision:
   ```bash
   kubectl -n petclinic-{env} rollout undo deploy/{service} --to-revision={n}
   ```

**Verify:**
- `kubectl -n petclinic-{env} rollout status deploy/{service}` completes successfully.
- Pods are running with the previous image and the service responds to health checks:
  ```bash
  kubectl -n petclinic-{env} get pod -l app.kubernetes.io/name={service}
  ```

**Rollback:** Immediately run Procedure 1 (revert the bad image tag commit in Git) so ArgoCD no longer considers the cluster out of sync and re-deploys the bad image on next sync.

---

## Verification (all procedures)

After any rollback, confirm:

- [ ] ArgoCD application: Healthy and Synced (or expected OutOfSync pending Git revert).
- [ ] Pods running the previous image tag (`kubectl get deploy -o jsonpath='{...image}'`).
- [ ] Service reachable: health endpoint responds (`/actuator/health` via ingress or port-forward).
- [ ] No pending ArgoCD sync operations that would re-deploy the bad image.

---

## Related Documents

- [Jira Backlog — PETPLAT-54: Implement rollback strategy](jira-backlog.md#PETPLAT-54)
- [Technical Spec — CI/CD Pipeline](technical-spec.md#cicd-pipeline)
- [Technical Spec — GitOps with ArgoCD](technical-spec.md#gitops-with-argocd)
- [Runbook — Day-to-day operations](runbook.md)