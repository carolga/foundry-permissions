# Infrastructure map

The repository contains two independent validation deployments. They have
different objectives and state; the Terraform deployment does not manage or
replace the Bicep environment.

## Terraform: private Foundry Standard Agent Setup

Start with [terraform/README.md](terraform/README.md). This deployment creates
a new private Foundry account and project with a project capability host. It
can create Storage, Cosmos DB and Azure AI Search together with Foundry, or
connect to existing services. It does not deploy HOA business logic.

```text
infra/terraform/                 Foundry deployment root and state
  backing-stores/                Optional separate backing-services root and state
  scripts/                       Plan/apply and private validation helpers
  tests/                         Terraform contracts and Python tests
```

The optional [backing-stores root](terraform/backing-stores/README.md) creates
the three data services first. The Foundry root then consumes their resource
IDs. For a single deployment, the Foundry root can instead create the stores
itself; externally managed stores are also supported.

Each Terraform root has its own state and workspaces. Files directly inside a
root belong to the same Terraform configuration; `backing-stores` is not a
module automatically included by the parent. Keep local state, variable files,
credentials and saved plans out of Git, and do not move or replace a state
without a deliberate migration.

## Bicep: multi-project permissions validation

The Bicep deployment validates project-level permissions and portal behavior
for two projects in one private Foundry account. Its entry points and support
folders are:

```text
infra/main.bicep                 Foundry account, projects and infrastructure
infra/access.bicep               Project access and role assignments
infra/validation-vm.bicep        Private validation desktop
infra/azd/                       azd deployment entry point
infra/bootstrap/                 Resource-group bootstrap
infra/environments/              Bicep parameters
infra/modules/                   Reusable Bicep modules
infra/tests/                     Bicep validation
```

Use the [Bicep deployment instructions](../README.md#deployment-instructions)
for that environment. `azure.yaml` selects the Bicep `infra/azd` entry point;
it does not deploy the Terraform configuration.
