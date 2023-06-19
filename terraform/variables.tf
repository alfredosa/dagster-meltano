variable "DagsterOrganization" {
  description = "Enter your organization name as it appears in the dagster.cloud subdomain, e.g. `hooli` corresponding with https://hooli.dagster.cloud/."
  type        = string
}

variable "DagsterDeployment" {
  description = "Enter your deployment name, e.g. `prod` corresponding with https://hooli.dagster.cloud/prod/. Leave empty to only serve branch deployments."
  type        = string
}

variable "EnableBranchDeployments" {
  description = "Whether this agent should serve branch deployments. For more information, see https://docs.dagster.io/dagster-cloud/developing-testing/branch-deployments."
  type        = bool
  default     = false
}

variable "AgentToken" {
  description = "A Dagster agent token, obtained on https://{organization}.dagster.cloud/{deployment}/cloud-settings/tokens/."
  type        = string
}

variable "EnableZeroDowntimeDeploys" {
  description = "Whether to enable zero-downtime deployment for this agent. This means that when updating, the old agent will not spin down until the new agent is ready to serve requests."
  type        = bool
  default     = false
}

variable "NumReplicas" {
  description = "The number of agent replicas to keep active at a given time."
  type        = number
  default     = 1
  minvalue    = 1
  maxvalue    = 5
}
