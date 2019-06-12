locals {
  values_external_dns = <<VALUES
image:
  tag: ${var.external_dns["version"]}
provider: aws
txtPrefix: "ext-dns-"
rbac:
 create: true
nodeSelector:
  node-role.kubernetes.io/controller: ""
tolerations:
  - operator: Exists
    effect: NoSchedule
    key: "node-role.kubernetes.io/controller"
VALUES
  values_external_dns_kiam = <<VALUES
image:
  tag: ${var.external_dns["version"]}
provider: aws
txtPrefix: "ext-dns-"
rbac:
 create: true
podAnnotations:
  iam.amazonaws.com/role: "${join(",", data.terraform_remote_state.eks.*.external-dns-kiam-role-arn[0])}"
VALUES
}

resource "kubernetes_namespace" "external_dns" {
  count = "${var.external_dns["enabled"] ? 1 : 0 }"

  metadata {
    annotations {
      "iam.amazonaws.com/permitted" = ".*"
    }

    labels {
      name = "${var.external_dns["namespace"]}"
    }

    name = "${var.external_dns["namespace"]}"
  }
}

resource "helm_release" "external_dns" {
  depends_on = [
    "kubernetes_namespace.external_dns"
  ]
  count     = "${var.external_dns["enabled"] ? 1 : 0 }"
  repository = "${data.helm_repository.stable.metadata.0.name}"
  name      = "external-dns"
  chart     = "external-dns"
  version   = "${var.external_dns["chart_version"]}"
  values    = ["${concat(list(var.external_dns["use_kiam"] ? local.values_external_dns_kiam : local.values_external_dns),list(var.external_dns["extra_values"]))}"]
  namespace = "${var.external_dns["namespace"]}"
}

resource "kubernetes_network_policy" "external_dns_default_deny" {
  count     = "${var.external_dns["enabled"] * var.external_dns["default_network_policy"]}"
  metadata {
    name      = "${var.external_dns["namespace"]}-default-deny"
    namespace = "${var.external_dns["namespace"]}"
  }

  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "external_dns_allow_namespace" {
  count     = "${var.external_dns["enabled"] * var.external_dns["default_network_policy"]}"
  metadata {
    name      = "${var.external_dns["namespace"]}-allow-namespace"
    namespace = "${var.external_dns["namespace"]}"
  }

  spec {
    pod_selector {}

    ingress = [
      {
        from = [
          {
            namespace_selector {
              match_labels = {
                name = "${var.external_dns["namespace"]}"
              }
            }
          }
        ]
      }
    ]

    policy_types = ["Ingress"]
  }
}
