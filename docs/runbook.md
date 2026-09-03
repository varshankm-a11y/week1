# Production Operations Runbook & Architecture Documentation

## System Metadata
* **Cluster Name:** `demo-eks`
* **Target Region:** `us-east-1`
* **Application Namespaces:** `demo-apps`, `test-apps`, `prod-apps`
* **Monitoring Namespace:** `monitoring` (Prometheus, Grafana, Alertmanager)
* **Logging Namespace:** `logging` (Elasticsearch, Kibana, Fluent Bit)
* **CI/CD Workflow:** `.github/workflows/03-k8s-observability-deploy.yaml`

---

## 1. System Architecture Diagram

```text
===================================================================================================================================
                                                  AWS CLOUD / REGION (us-east-1)
===================================================================================================================================
                                                                 │
                                                       [ EKS Worker Nodes ]
                                                                 │
┌────────────────────────────────────────────────────────────────┴────────────────────────────────────────────────────────────────┐
│                                                      AMAZON EKS CLUSTER                                                         │
│                                                          (demo-eks)                                                             │
│                                                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ NAMESPACE: demo-apps / test-apps / prod-apps                                                                              │  │
│  │                                                                                                                           │  │
│  │   [ K8s Ingress ] ──► [ K8s Service (ClusterIP) ] ──► [ Application Pod (prod-app) ]                                     │  │
│  │                                                                │                                                          │  │
│  │                                                                ├─ Image: Amazon ECR / nginx fallback                      │  │
│  │                                                                ├─ HPA (autoscaling/v2): Min 1 | Max 3                      │  │
│  │                                                                ├─ Security: RBAC Roles & Network Policies Enforced        │  │
│  │                                                                └─ Config: ConfigMap & Secret Mounted                      │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ NAMESPACE: monitoring                                                                                                     │  │
│  │                                                                                                                           │  │
│  │   [ Prometheus Stack ]                                                                                                    │  │
│  │        ├── Scrapes Pod & Node Metrics                                                                                     │  │
│  │        ├── Grafana (Dashboards via ConfigMap)                                                                             │  │
│  │        └── Alertmanager (Route Rules & Synthetic Alert Inject Endpoint)                                                   │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ NAMESPACE: logging                                                                                                        │  │
│  │                                                                                                                           │  │
│  │   [ Fluent Bit (DaemonSet) ] ──(Tails Container Logs)──► [ Elasticsearch Master ] ──► [ Kibana UI ]                      │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                                 │
│  ┌───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐  │
│  │ NAMESPACE: kube-system                                                                                                    │  │
│  │                                                                                                                           │  │
│  │   [ Metrics Server ] (hostNetwork=true, kubelet-insecure-tls)                                                             │  │
│  │   [ CoreDNS / aws-node CNI / aws-auth ConfigMap ]                                                                        │  │
│  └───────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘  │
│                                                                                                                                 │
└────────────────────────────────────────────────────────────────┬────────────────────────────────────────────────────────────────┘
                                                                 │
                                                       CI/CD PIPELINE AUTOMATION
                                                                 │
    ┌────────────────────────────────────────────────────────────┴───────────────────────────────────────────────────────────┐
    │ GITHUB ACTIONS RUNNER (`03-k8s-observability-deploy.yaml`)                                                              │
    │                                                                                                                        │
    │   Step 3.1: Update Kubeconfig (AWS CLI)                                                                               │
    │   Step 3.2: Join Worker Nodes (aws-auth ConfigMap)                                                                     │
    │   Step 3.3: Install Metrics Server, Observability (Prometheus) & Logging Stack (ELK + Fluent Bit)                      │
    │   Step 3.4: Apply Base Setup, RBAC, Network Policies & Alert Rules                                                     │
    │   Step 3.5: Deploy App Workloads (ECR Image Lookup + Fallback, ConfigMap, Secret, Deployment, Service, HPA, Ingress) │
    │   Step 3.6: Verify Rollout Status & Auto-Rollback on Failure                                                           │
    │   Step 3.7: Validate Incident Alert Generation & Silence Routing Flow (curl to Alertmanager 9093)                     │
    └────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Standard Deployment Operations

### 2.1 Automated CI/CD Deployments
1. Navigate to **GitHub Actions** $ightarrow$ **`03 - K8s Cluster Config & App Deploy`**.
2. Click **Run workflow**.
3. Select the target environment (`demo`, `test`, or `prod`) and execute.

Execution sequence:
* **Step 3.1 & 3.2:** Updates local `kubeconfig` and syncs worker node IAM permissions (`aws-auth`).
* **Step 3.3 & 3.4:** Installs Metrics Server, Observability stack (Prometheus + ELK), RBAC, Network Policies, and Alert rules.
* **Step 3.5:** Resolves ECR image tags (with fallback to `nginx:alpine`) and deploys application manifests.
* **Step 3.6:** Verifies `kubectl rollout status` within 180 seconds.
* **Step 3.7:** Injects a synthetic critical alert into Alertmanager (`9093`) and validates auto-silencing.

### 2.2 Manual CLI Emergency Deployment Procedure
In the event of a GitHub Actions runner outage, execute the deployment manually from an authenticated terminal:

```bash
# 1. Export target environment variables
export ENVIRONMENT="prod" # Options: demo, test, prod
export TARGET_NS="${ENVIRONMENT}-apps"
export AWS_REGION="us-east-1"
export EKS_CLUSTER_NAME="demo-eks"

# 2. Update cluster credentials
aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME

# 3. Apply application manifests
kubectl create ns $TARGET_NS --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f eks/k8s/app/configmap.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/secret.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/resource-limits.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/deployment.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/service.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/hpa.yaml -n $TARGET_NS
kubectl apply -f eks/k8s/app/ingress.yaml -n $TARGET_NS

# 4. Verify deployment status
kubectl rollout status deployment/prod-app -n $TARGET_NS --timeout=180s
```

---

## 3. Automated & Manual Rollback Protocols

### 3.1 Automated Pipeline Rollback
During Step 3.6, if `prod-app` fails to achieve `1/1 Ready` status within 180 seconds, the workflow executes the following fallback logic automatically:
```bash
kubectl rollout undo deployment/prod-app -n ${TARGET_NS} || kubectl delete deployment/prod-app -n ${TARGET_NS}
```

### 3.2 Manual Rollback Execution
To roll back a bad application update manually:

1. **Inspect Deployment Revision History:**
   ```bash
   kubectl rollout history deployment/prod-app -n prod-apps
   ```

2. **Roll Back to Immediately Preceding Revision:**
   ```bash
   kubectl rollout undo deployment/prod-app -n prod-apps
   ```

3. **Roll Back to a Specific Target Revision:**
   ```bash
   kubectl rollout undo deployment/prod-app -n prod-apps --to-revision=2
   ```

4. **Verify Rollback Completion:**
   ```bash
   kubectl rollout status deployment/prod-app -n prod-apps
   ```

---

## 4. Scaling & Workload Capacity Management

### 4.1 Horizontal Pod Autoscaling (HPA)
Application scaling is governed by `autoscaling/v2` tracking an 80% CPU utilization threshold.

* **Check HPA Health & Utilization:**
  ```bash
  kubectl get hpa prod-app-hpa -n prod-apps
  ```

* **Inspect Detailed HPA Metrics:**
  ```bash
  kubectl describe hpa prod-app-hpa -n prod-apps
  ```

### 4.2 Emergency Manual Capacity Scaling
To bypass autoscaling constraints during high-traffic incidents:

```bash
# Temporarily scale deployment replicas
kubectl scale deployment prod-app -n prod-apps --replicas=3
```

---

## 5. Log Investigation & Troubleshooting

### 5.1 CLI Real-Time Log Tailing
```bash
# Tail live logs for active application pods
kubectl logs -f -l app=prod-app -n prod-apps --tail=100

# Inspect logs from a previously crashed container instance
kubectl logs -l app=prod-app -n prod-apps --previous
```

### 5.2 Centralized Logging via ELK Stack
To query historical logs via Kibana:

1. **Port-Forward Kibana UI to Local Machine:**
   ```bash
   kubectl port-forward svc/kibana-kibana 5601:5601 -n logging
   ```
2. Open `http://localhost:5601` in a browser.
3. Navigate to **Discover** and use the `fluent-bit-app-logs-*` index pattern.

---

## 6. Dashboards & Incident Alerting

### 6.1 Monitoring Dashboards (Grafana)
1. **Port-Forward Grafana Service:**
   ```bash
   kubectl port-forward svc/prometheus-grafana 3000:80 -n monitoring
   ```
2. Open `http://localhost:3000` (Credentials: `admin` / `prom-operator`).

### 6.2 Alertmanager Incident Management
To inspect or silence active alerts:

1. **Port-Forward Alertmanager Service:**
   ```bash
   kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring
   ```

2. **Query Active Alerts:**
   ```bash
   curl -s "http://localhost:9093/api/v2/alerts?filter=alertname%3DKubernetesPodNotReady"
   ```

3. **Create a Maintenance Silence Rule:**
   ```bash
   NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
   END=$(date -u -d "+1 hour" +"%Y-%m-%dT%H:%M:%SZ")

   curl -X POST "http://localhost:9093/api/v2/silences"      -H 'Content-Type: application/json'      -d "{
       "matchers": [
         {"name": "alertname", "value": "KubernetesPodNotReady", "isRegex": false}
       ],
       "startsAt": "$NOW",
       "endsAt": "$END",
       "createdBy": "OnCall-Engineer",
       "comment": "Silencing alert during planned maintenance window"
     }"
   ```

---

## 7. Common Failure Modes & Incident Recovery

### Incident 1: `FailedScheduling` (Insufficient CPU/Memory)
* **Symptom:** Pod remains in `Pending` state with `Warning FailedScheduling`.
* **Resolution Steps:**
  1. Check node capacity: `kubectl top nodes`
  2. Clear stale pods: `kubectl delete pods -n demo-apps --all --force --grace-period=0`
  3. Uninstall heavy logging releases if node memory is completely exhausted: `helm uninstall elasticsearch -n logging`

### Incident 2: `ImagePullBackOff` or `ErrImagePull`
* **Symptom:** Pod status stays stuck in `ImagePullBackOff`.
* **Resolution Steps:**
  1. Check pod events: `kubectl describe pod -l app=prod-app -n prod-apps`
  2. Verify ECR repository: `aws ecr describe-images --repository-name prod-app-repo --region us-east-1`
  3. Force deployment fallback image: `kubectl set image deployment/prod-app prod-app=nginx:alpine -n prod-apps`
