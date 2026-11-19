# Terraform backing services

**Objective:** optionally deploy Storage, Cosmos DB for NoSQL and Azure AI
Search in a separate resource group before deploying the private Foundry
project. This directory is a separate Terraform root with its own state and
workspaces; it does not deploy Foundry.

The parent [Foundry Terraform guide](../README.md#reproduce-with-separately-created-backing-services)
shows the two-stage plan/apply workflow. Its first helper deploys this root;
the second reads the `backing_resources` output and passes those resource IDs
to the Foundry root. Private endpoints for these services are created in the
Foundry stage.

If the services already exist, this root is not required: supply the existing
resource IDs to the Foundry root instead. Do not import or switch ownership of
an existing deployment without a state migration plan.

| File | Purpose |
|---|---|
| `main.tf` | Backing services, resource group and resource ID outputs |
| `variables.tf` | Deployment inputs |
| `versions.tf` | Terraform and provider requirements |
| `terraform.tfvars.example` | Example inputs; copy outside version control |
| `tests/` | Terraform contracts for this root |
